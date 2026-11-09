#if os(macOS) || os(iOS)
import CryptoKit
import Foundation
import Security

struct ShareSelection: Codable, Equatable, Sendable {
    var timetable = true
    var tasks = true
    var events = false
    var isEmpty: Bool { !timetable && !tasks && !events }
}

struct SharePayload: Codable, Equatable, Sendable {
    let selection: ShareSelection
    let subjects: [Subject]
    let classes: [ClassSlot]
    let tasks: [StudyTask]
    let events: [PlannerEvent]

    init(database: Database, selection: ShareSelection) {
        self.selection = selection
        subjects = selection.timetable ? database.subjects : []
        classes = selection.timetable ? database.classes : []
        tasks = selection.tasks ? database.tasks.map { task in
            var copy = task
            if !selection.timetable { copy.subjectID = nil }
            copy.reminder = nil
            return copy
        } : []
        events = selection.events ? database.events.map { event in
            var copy = event
            if !selection.timetable { copy.subjectID = nil }
            if !selection.tasks { copy.taskID = nil }
            return copy
        } : []
    }
}

struct ShareCredentials: Codable, Equatable, Sendable {
    private static let alphabet = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
    let code: String
    let password: String

    static func generate() throws -> ShareCredentials {
        var random = [UInt8](repeating: 0, count: 18)
        let result = random.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard result == errSecSuccess else { throw CloudSyncError.secureStorage }
        let characters = random.map { alphabet[Int($0) & 31] }
        return ShareCredentials(code: String(characters.prefix(6)), password: String(characters.suffix(12)))
    }

    var workspace: WorkspaceCode {
        let data = Data("StudyFlow/share/v1:\(code):\(password)".utf8)
        return WorkspaceCode(bytes: Data(SHA256.hash(data: data).prefix(16)))
    }
}

struct PublishedShare: Codable, Identifiable, Sendable {
    let credentials: ShareCredentials
    let selection: ShareSelection
    let owner: String
    var termID: UUID?
    var published = false
    var id: String { credentials.workspace.locator }
}

extension CloudTransport {
    private struct ShareWrite: Encodable {
        let p_workspace: String
        let p_owner: String
        let p_ciphertext: String
    }

    private struct ShareRemove: Encodable {
        let p_workspace: String
        let p_owner: String
    }

    func publishShare(_ share: PublishedShare, payload: SharePayload) async throws {
        let workspace = share.credentials.workspace
        let data = try await call("studyflow_share_write",
                                  body: ShareWrite(p_workspace: workspace.locator, p_owner: share.owner,
                                                   p_ciphertext: try workspace.sealValue(payload)))
        guard try JSONDecoder().decode(Bool.self, from: data) else { throw CloudSyncError.alreadyExists }
    }

    func revokeShare(_ share: PublishedShare) async throws {
        _ = try await call("studyflow_share_revoke",
                           body: ShareRemove(p_workspace: share.credentials.workspace.locator, p_owner: share.owner))
    }
}
#endif
