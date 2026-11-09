import Foundation
import SwiftUI
#if os(macOS) || os(iOS)
import UserNotifications
#endif

@MainActor final class PlannerStore: ObservableObject {
    @Published private(set) var db: Database
    @Published private(set) var selectedTermID: UUID
    private let preferences: UserDefaults?
    private let legacyTermName: String
    private let previousTermName: String?
    var activeTermID: UUID { activeTermID(in: db) }

    func activeTermID(in database: Database) -> UUID {
        database.terms?.contains { $0.id == selectedTermID } == true ? selectedTermID : AcademicTerm.legacyID
    }
    var termOptions: [AcademicTerm] {
        let terms = db.terms ?? []
        let legacy = terms.first { $0.id == AcademicTerm.legacyID }
            ?? AcademicTerm(id: AcademicTerm.legacyID, name: legacyTermName)
        return [legacy] + terms.filter { $0.id != legacy.id }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    var termDatabase: Database { db.inTerm(activeTermID) }

    func selectTerm(_ id: UUID) {
        guard termOptions.contains(where: { $0.id == id }) else { return }
        selectedTermID = id
        preferences?.set(id.uuidString, forKey: "planner.selectedTerm")
    }

    @discardableResult
    func saveTerm(_ rawName: String, editing id: UUID? = nil) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !termOptions.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else { return false }
        let term = AcademicTerm(id: id ?? UUID(), name: name)
        guard update({ database in
            var terms = database.terms ?? []
            terms.removeAll { $0.id == term.id }
            terms.append(term)
            if let previousTermName, !terms.contains(where: { $0.id == AcademicTerm.legacyID }) {
                let legacy = AcademicTerm(id: AcademicTerm.legacyID, name: previousTermName)
                terms.append(legacy)
                database.record(legacy, entity: "term", id: legacy.id)
            }
            database.terms = terms
            database.record(term, entity: "term", id: term.id)
        }) else { return false }
        selectTerm(term.id)
        return true
    }

    @Published var error: String?
    @Published var notice: String?
    private var storageReadable = true
    let url: URL
    private let remindersEnabled: Bool
    #if os(macOS) || os(iOS)
    @Published private(set) var cloudConfiguration: CloudConfiguration?
    @Published private(set) var cloudStatus = "ยังไม่ได้เชื่อม"
    @Published private(set) var cloudCode: WorkspaceCode?
    @Published private(set) var syncing = false
    @Published private(set) var shares: [PublishedShare] = []
    @Published private(set) var shareStatus = ""
    @Published private(set) var sharing = false
    private var uploadedShares: [String: SharePayload] = [:]
    private let cloudDefaults: UserDefaults?
    private static let cloudKey = "planner.cloudConfiguration"
    private let cloudAccount: String
    private var keychain: CloudKeychain { CloudKeychain(account: cloudAccount) }
    #endif
    init(url: URL? = nil, fallback: @autoclosure () -> Database = .sample(), remindersEnabled: Bool = true, cloudDefaults: UserDefaults? = nil, legacyName: String = "เทอมเดิม") {
        self.remindersEnabled = remindersEnabled
        preferences = cloudDefaults
        selectedTermID = cloudDefaults?.string(forKey: "planner.selectedTerm")
            .flatMap(UUID.init(uuidString:)) ?? AcademicTerm.legacyID
        let previousName = cloudDefaults?.string(forKey: "planner.termName") ?? ""
        previousTermName = previousName.isEmpty ? nil : previousName
        legacyTermName = previousName.isEmpty ? legacyName : previousName
        let dataRoot = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Daylight")
        self.url = url ?? dataRoot.appendingPathComponent("planner.json")
        do { if FileManager.default.fileExists(atPath:self.url.path) { db = try JSONDecoder().decode(Database.self,from:Data(contentsOf:self.url)) } else { db = fallback() } }
        catch { db = Database(); storageReadable = false; self.error = "Could not read saved data. Original file is preserved. \(error.localizedDescription)" }
        #if os(macOS) || os(iOS)
        self.cloudDefaults = cloudDefaults
        #if os(iOS)
        cloudAccount = url == nil ? "studio.daylight.planner.mobile" : self.url.standardizedFileURL.path
        #else
        cloudAccount = self.url.standardizedFileURL.path
        #endif
        if let cloudDefaults {
            if let data = cloudDefaults.data(forKey: Self.cloudKey) {
                cloudConfiguration = try? JSONDecoder().decode(CloudConfiguration.self, from: data)
            }
            cloudConfiguration = cloudConfiguration ?? .bundled()
            if let cloudConfiguration {
                cloudCode = keychain.load()
                if cloudCode != nil { cloudStatus = "รอซิงก์" }
                loadShares(configuration: cloudConfiguration)
            }
        }
        #endif
    }
    @discardableResult func update(_ body: (inout Database)->Void) -> Bool {
        guard storageReadable else { error = "Could not read saved data. Original file is preserved. Restore or repair the saved file before editing."; return false }
        var next = db
        body(&next)
        do {
            if var replica = next.syncReplica {
                let changes = next.queue.dropFirst(db.queue.count)
                try replica.recordLocalChanges(changes, in: &next)
                next.syncReplica = replica
            }
            try persist(next)
            #if os(macOS) || os(iOS)
            if cloudCode != nil { cloudStatus = "รอซิงก์" }
            #endif
            return true
        } catch {
            self.error = "Changes were not saved: \(error.localizedDescription)"
            return false
        }
    }

    private func persist(_ next: Database) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(next).write(to: url, options: .atomic)
        db = next
    }

    #if os(macOS) || os(iOS)
    func configureCloud(address: String, key: String) {
        guard let cloudDefaults, cloudCode == nil, !syncing, !sharing else { return }
        do {
            let configuration = try CloudConfiguration(address: address, key: key)
            cloudDefaults.set(try JSONEncoder().encode(configuration), forKey: Self.cloudKey)
            cloudConfiguration = configuration
            loadShares(configuration: configuration)
            cloudStatus = "ตั้งค่าคลาวด์แล้ว"
        } catch { cloudStatus = error.localizedDescription }
    }

    private func shareKeychain(_ configuration: CloudConfiguration) -> CloudKeychain {
        CloudKeychain(account: "\(cloudAccount):shares:\(configuration.url.host ?? "")")
    }

    private func loadShares(configuration: CloudConfiguration) {
        let data = shareKeychain(configuration).loadData()
        shares = data.flatMap { try? JSONDecoder().decode([PublishedShare].self, from: $0) } ?? []
        uploadedShares = [:]
        shareStatus = ""
    }

    private func saveShares(_ entries: [PublishedShare], configuration: CloudConfiguration) throws {
        try shareKeychain(configuration).saveData(JSONEncoder().encode(entries))
        shares = entries
    }

    func createShare(selection: ShareSelection) async {
        guard let configuration = cloudConfiguration, !sharing, storageReadable, !selection.isEmpty else { return }
        sharing = true
        defer { sharing = false }
        do {
            let credentials = try ShareCredentials.generate()
            let owner = try (WorkspaceCode.generate().display + WorkspaceCode.generate().display)
                .replacingOccurrences(of: "-", with: "").lowercased()
            let share = PublishedShare(credentials: credentials, selection: selection, owner: owner, termID: activeTermID)
            try saveShares(shares + [share], configuration: configuration)
            try await publishShare(share, using: CloudTransport(configuration: configuration))
            shareStatus = "แชร์แล้ว"
        } catch { showShareError(error) }
    }

    func refreshShares() async {
        guard let configuration = cloudConfiguration, !sharing, storageReadable, !shares.isEmpty else { return }
        let pending = shares.filter { uploadedShares[$0.id] != SharePayload(database: db.inTerm($0.termID ?? AcademicTerm.legacyID), selection: $0.selection) }
        guard !pending.isEmpty else { return }
        sharing = true
        defer { sharing = false }
        let transport = CloudTransport(configuration: configuration)
        var failure: Error?
        for share in pending {
            do { try await publishShare(share, using: transport) }
            catch { failure = error }
        }
        if let failure { showShareError(failure) }
        else { shareStatus = "แชร์แล้ว" }
    }

    func revokeShare(_ share: PublishedShare) async {
        guard let configuration = cloudConfiguration, !sharing else { return }
        sharing = true
        defer { sharing = false }
        do {
            try await CloudTransport(configuration: configuration).revokeShare(share)
            try saveShares(shares.filter { $0.id != share.id }, configuration: configuration)
            uploadedShares.removeValue(forKey: share.id)
            shareStatus = "หยุดแชร์แล้ว"
        } catch { showShareError(error) }
    }

    private func publishShare(_ share: PublishedShare, using transport: CloudTransport) async throws {
        let payload = SharePayload(database: db.inTerm(share.termID ?? AcademicTerm.legacyID), selection: share.selection)
        try await transport.publishShare(share, payload: payload)
        if !share.published, let index = shares.firstIndex(where: { $0.id == share.id }) {
            var entries = shares
            entries[index].published = true
            try saveShares(entries, configuration: transport.configuration)
        }
        uploadedShares[share.id] = payload
    }

    private func showShareError(_ error: Error) {
        shareStatus = (error as? LocalizedError)?.errorDescription ?? CloudSyncError.service.localizedDescription
    }

    func connectCloud(enteredCode: String?) async {
        guard cloudCode == nil, let configuration = cloudConfiguration, !syncing, storageReadable else { return }
        syncing = true
        defer { syncing = false }
        do {
            let code = try enteredCode.map(WorkspaceCode.init) ?? WorkspaceCode.generate()
            try validateWorkspace(configuration, code: code)
            try keychain.save(code)
            do {
                try await exchange(configuration, code: code, creating: enteredCode == nil)
            } catch {
                // Retain a successfully bound code so an interrupted upload can retry.
                if db.syncWorkspace == workspaceID(configuration, code: code) {
                    cloudCode = code
                } else {
                    try keychain.clear()
                }
                throw error
            }
            cloudCode = code
        } catch { showCloudError(error) }
    }

    func disconnectCloud() {
        guard !syncing else { return }
        do {
            try keychain.clear()
            cloudCode = nil
            cloudStatus = "ยกเลิกการเชื่อมแล้ว"
        } catch { showCloudError(error) }
    }

    func syncNow() async {
        guard let cloudCode, let configuration = cloudConfiguration, !syncing, storageReadable else { return }
        syncing = true
        defer { syncing = false }
        do {
            try validateWorkspace(configuration, code: cloudCode)
            try await exchange(configuration, code: cloudCode, creating: false)
        } catch { showCloudError(error) }
    }

    private func workspaceID(_ configuration: CloudConfiguration, code: WorkspaceCode) -> String {
        "\(configuration.url.host ?? ""):\(code.locator)"
    }

    private func validateWorkspace(_ configuration: CloudConfiguration, code: WorkspaceCode) throws {
        if let bound = db.syncWorkspace, bound != workspaceID(configuration, code: code) {
            throw CloudSyncError.differentWorkspace
        }
    }

    private func exchange(_ configuration: CloudConfiguration, code: WorkspaceCode, creating: Bool) async throws {
        let transport = CloudTransport(configuration: configuration)
        let workspace = workspaceID(configuration, code: code)
        for _ in 0..<3 {
            let remote = try await transport.read(code)
            if creating && remote != nil { throw CloudSyncError.alreadyExists }
            if !creating && remote == nil { throw CloudSyncError.missing }
            let before = db
            var next = before
            var replica = try before.syncReplica ?? PlannerReplica(database: before)
            let incoming = try remote.map { try code.open($0.ciphertext) }
            if let incoming { try replica.merge([incoming], into: &next) }
            next.syncReplica = replica
            next.syncWorkspace = workspace

            if remote != nil, next != before {
                try persist(next)
                if next.tasks != before.tasks { reconcileReminders(before: before.tasks, after: next.tasks) }
            }
            if incoming?.records != replica.records || incoming?.clock != replica.clock {
                if try await !transport.write(replica, code: code, expecting: remote?.revision ?? 0) {
                    if creating { throw CloudSyncError.alreadyExists }
                    continue
                }
            }
            if creating {
                // Local edits may arrive while the first encrypted snapshot is in flight.
                let latest = db
                var initialized = latest
                let edits = latest.queue.dropFirst(before.queue.count)
                try replica.recordLocalChanges(edits, in: &initialized)
                initialized.syncWorkspace = workspace
                initialized.syncReplica = replica
                try persist(initialized)
                if !edits.isEmpty {
                    cloudStatus = "รอซิงก์"
                    return
                }
            }
            cloudStatus = db.syncReplica == replica ? "ซิงก์แล้ว" : "รอซิงก์"
            return
        }
        throw CloudSyncError.busy
    }

    private func reconcileReminders(before: [StudyTask], after: [StudyTask]) {
        guard supportsNotifications else { return }
        let previous = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let currentIDs = Set(after.map(\.id))
        let removed = before.filter { $0.reminder != nil && !currentIDs.contains($0.id) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: removed.map { $0.id.uuidString })
        for task in after {
            let old = previous[task.id]
            if (task.reminder != nil || old?.reminder != nil) && task != old { scheduleReminder(task) }
        }
    }

    private func showCloudError(_ error: Error) {
        cloudStatus = (error as? LocalizedError)?.errorDescription ?? CloudSyncError.service.localizedDescription
    }
    #endif

    func save(_ subject: Subject) {
        var value = subject
        let termID = db.subject(subject.id).map { $0.termID ?? AcademicTerm.legacyID } ?? activeTermID
        value.termID = termID == AcademicTerm.legacyID ? nil : termID
        update { d in d.subjects.removeAll { $0.id == value.id }; d.subjects.append(value); d.record(value, entity: "subject", id: value.id) }
    }
    func save(_ s: ClassSlot) { update { d in d.classes.removeAll{$0.id == s.id}; d.classes.append(s); d.record(s,entity:"class",id:s.id) } }
    func save(_ task: StudyTask) {
        var value = task
        let termID = db.tasks.first { $0.id == task.id }.map { $0.termID ?? AcademicTerm.legacyID } ?? activeTermID
        value.termID = termID == AcademicTerm.legacyID ? nil : termID
        if let subject = db.subject(value.subjectID), (subject.termID ?? AcademicTerm.legacyID) != termID {
            value.subjectID = nil
        }
        if update({ d in d.tasks.removeAll { $0.id == value.id }; d.tasks.append(value); d.record(value, entity: "task", id: value.id) }),
           let saved = db.tasks.first(where: { $0.id == value.id }) {
            scheduleReminder(saved)
        }
    }
    func save(_ event: PlannerEvent) {
        var value = event
        let termID = db.events.first { $0.id == event.id }.map { $0.termID ?? AcademicTerm.legacyID } ?? activeTermID
        value.termID = termID == AcademicTerm.legacyID ? nil : termID
        if let subject = db.subject(value.subjectID), (subject.termID ?? AcademicTerm.legacyID) != termID { value.subjectID = nil }
        if let linked = db.tasks.first(where: { $0.id == value.taskID }), (linked.termID ?? AcademicTerm.legacyID) != termID { value.taskID = nil }
        update { d in d.events.removeAll { $0.id == value.id }; d.events.append(value); d.record(value, entity: "event", id: value.id) }
    }
    func toggle(_ task: StudyTask) {
        guard var current = db.tasks.first(where: { $0.id == task.id }) else { return }
        current.status = current.status == .done ? .todo : .done
        save(current)
    }
    func deleteClass(_ id: UUID) { update { d in if let s=d.classes.first(where:{$0.id == id}) { d.classes.removeAll{$0.id == id}; d.record(s,entity:"class",id:id,deleted:true) } } }
    func deleteEvent(_ id: UUID) { update { d in if let e=d.events.first(where:{$0.id == id}) { d.events.removeAll{$0.id == id}; d.record(e,entity:"event",id:id,deleted:true) } } }
    func deleteTask(_ id: UUID) {
        update { d in
            if let t=d.tasks.first(where:{$0.id == id}) { d.tasks.removeAll{$0.id == id}; d.record(t,entity:"task",id:id,deleted:true) }
            for i in d.events.indices where d.events[i].taskID == id { d.events[i].taskID=nil; d.record(d.events[i],entity:"event",id:d.events[i].id) }
        }
        #if os(macOS) || os(iOS)
        if supportsNotifications { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers:[id.uuidString]) }
        #endif
    }
    #if os(macOS) || os(iOS)
    private var supportsNotifications: Bool {
        remindersEnabled && Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }
    #endif

    func scheduleReminder(_ t: StudyTask) {
        #if os(macOS) || os(iOS)
        guard supportsNotifications else { return }
        let center=UNUserNotificationCenter.current(); center.removePendingNotificationRequests(withIdentifiers:[t.id.uuidString])
        guard let date=t.reminder, date > Date(), t.status != .done else { return }
        center.requestAuthorization(options:[.alert,.sound]) { allowed, err in
            guard allowed else { Task { @MainActor in self.notice = "Notifications are disabled. Reminder dates remain visible in Tasks." }; return }
            let content=UNMutableNotificationContent(); content.title=t.title; content.body="StudyFlow Planner"; content.sound = .default
            let trigger=UNTimeIntervalNotificationTrigger(timeInterval:max(1,date.timeIntervalSinceNow),repeats:false)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:t.id.uuidString,content:content,trigger:trigger)) { error in if let error { Task { @MainActor in self.notice=error.localizedDescription } } }
        }
        #endif
    }
}
