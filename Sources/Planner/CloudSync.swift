#if os(macOS) || os(iOS)
import CryptoKit
import Foundation
import Security

struct CloudConfiguration: Codable, Equatable, Sendable {
    let url: URL
    let publishableKey: String

    static func bundled() -> Self? {
        guard let url = Bundle.main.url(forResource: "CloudDeployment", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let values = try? PropertyListDecoder().decode([String: String].self, from: data),
              let address = values["ProjectURL"], let key = values["PublishableKey"] else { return nil }
        return try? Self(address: address, key: key)
    }

    init(address: String, key: String) throws {
        let raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: raw), let url = parts.url,
              parts.scheme == "https", parts.host?.hasSuffix(".supabase.co") == true,
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil, ["", "/"].contains(parts.path) else {
            throw CloudSyncError.configuration
        }
        let publicKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard publicKey.hasPrefix("sb_publishable_"), !publicKey.contains(where: \.isWhitespace) else {
            throw CloudSyncError.configuration
        }
        self.url = url
        self.publishableKey = publicKey
    }
}

struct WorkspaceCode: Sendable {
    private let bytes: Data

    init(_ code: String) throws {
        let text = code.filter { $0 != "-" && !$0.isWhitespace }
        guard text.utf8.count == 32, text.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { throw CloudSyncError.code }
        let characters = Array(text.utf8)
        var data = Data()
        for index in stride(from: 0, to: characters.count, by: 2) {
            guard let byte = UInt8(String(decoding: characters[index...index + 1], as: UTF8.self), radix: 16) else {
                throw CloudSyncError.code
            }
            data.append(byte)
        }
        guard data.count == 16 else { throw CloudSyncError.code }
        bytes = data
    }

    init(bytes: Data) { self.bytes = bytes }

    static func generate() throws -> WorkspaceCode {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw CloudSyncError.secureStorage }
        return WorkspaceCode(bytes: Data(bytes))
    }

    var display: String {
        stride(from: 0, to: bytes.count, by: 2).map { index in
            String(format: "%02X%02X", bytes[index], bytes[index + 1])
        }.joined(separator: "-")
    }

    private func digest(_ domain: String) -> SHA256.Digest {
        SHA256.hash(data: Data(domain.utf8) + bytes)
    }

    var locator: String { digest("StudyFlow/workspace/v1:").map { String(format: "%02x", $0) }.joined() }
    private var key: SymmetricKey { SymmetricKey(data: Data(digest("StudyFlow/encryption/v1:"))) }

    func seal(_ replica: PlannerReplica) throws -> String {
        try sealValue(replica)
    }

    func sealValue<Value: Encodable>(_ value: Value) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let combined = try AES.GCM.seal(data, using: key).combined else { throw CloudSyncError.invalidData }
        return combined.base64EncodedString()
    }

    func open(_ ciphertext: String) throws -> PlannerReplica {
        try openValue(ciphertext, as: PlannerReplica.self)
    }

    func openValue<Value: Decodable>(_ ciphertext: String, as type: Value.Type) throws -> Value {
        guard let data = Data(base64Encoded: ciphertext) else { throw CloudSyncError.invalidData }
        do {
            let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
            return try JSONDecoder().decode(type, from: plain)
        } catch { throw CloudSyncError.invalidData }
    }
}

enum CloudSyncError: LocalizedError {
    case configuration, code, missing, alreadyExists, differentWorkspace, invalidData, secureStorage, busy, service

    var errorDescription: String? {
        switch self {
        case .configuration: return "ตรวจ Project URL และ Publishable Key ของ Supabase"
        case .code: return "โค้ดซิงก์ต้องมีเลขหรือ A–F รวม 32 ตัว"
        case .missing: return "ยังไม่พบชุดข้อมูลของโค้ดนี้ ลองตรวจโค้ดหรือรอให้เครื่องแรกซิงก์ก่อน"
        case .alreadyExists: return "สร้างชุดข้อมูลไม่สำเร็จ กรุณาลองสร้างโค้ดใหม่"
        case .differentWorkspace: return "ข้อมูลในเครื่องนี้เคยเชื่อมกับอีกชุด กรุณาใช้โค้ดชุดเดิม"
        case .invalidData: return "เปิดข้อมูลที่เข้ารหัสไม่ได้"
        case .secureStorage: return "เข้าถึงกุญแจใน Keychain ไม่สำเร็จ"
        case .busy: return "อีกเครื่องกำลังอัปเดต ลองใหม่อีกครั้ง"
        case .service: return "ติดต่อคลาวด์ไม่สำเร็จ ข้อมูลยังเก็บในเครื่อง"
        }
    }
}

struct CloudTransport: Sendable {
    struct Snapshot: Decodable, Sendable {
        let revision: Int
        let ciphertext: String
    }

    private struct Lookup: Encodable { let p_workspace: String }
    private struct Save: Encodable {
        let p_workspace: String
        let p_expected: Int
        let p_ciphertext: String
    }

    let configuration: CloudConfiguration

    func read(_ code: WorkspaceCode) async throws -> Snapshot? {
        let data = try await call("studyflow_read", body: Lookup(p_workspace: code.locator))
        return try JSONDecoder().decode([Snapshot].self, from: data).first
    }

    func write(_ replica: PlannerReplica, code: WorkspaceCode, expecting revision: Int) async throws -> Bool {
        let data = try await call("studyflow_write", body: Save(p_workspace: code.locator, p_expected: revision,
                                                              p_ciphertext: try code.seal(replica)))
        return try JSONDecoder().decode(Bool.self, from: data)
    }

    func call<Body: Encodable>(_ function: String, body: Body) async throws -> Data {
        let url = configuration.url.appendingPathComponent("rest/v1/rpc").appendingPathComponent(function)
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CloudSyncError.service
        }
        return data
    }
}

struct CloudKeychain {
    let account: String
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "StudyFlow Sync Code",
         kSecAttrAccount as String: account]
    }

    func load() -> WorkspaceCode? {
        guard let data = loadData(), let text = String(data: data, encoding: .utf8) else { return nil }
        return try? WorkspaceCode(text)
    }

    func loadData() -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    func save(_ code: WorkspaceCode) throws {
        try saveData(Data(code.display.utf8))
    }

    func saveData(_ value: Data) throws {
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw CloudSyncError.secureStorage }
        var entry = query
        entry[kSecValueData as String] = value
        guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw CloudSyncError.secureStorage }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CloudSyncError.secureStorage }
    }
}
#endif
