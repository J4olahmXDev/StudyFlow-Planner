import Foundation

struct PlannerReplica: Codable, Equatable, Sendable {
    let deviceID: UUID
    var clock = 0
    private(set) var records: [String: Change] = [:]

    init(database: Database, deviceID: UUID = UUID()) throws {
        self.deviceID = deviceID
        let history = Dictionary(database.queue.map { ($0.syncKey, $0) }, uniquingKeysWith: { _, newest in newest })
        for term in database.terms ?? [] { try seed(term, entity: "term", history: history) }
        for subject in database.subjects { try seed(subject, entity: "subject", history: history) }
        for slot in database.classes { try seed(slot, entity: "class", history: history) }
        for task in database.tasks { try seed(task, entity: "task", history: history) }
        for event in database.events { try seed(event, entity: "event", history: history) }
        for entry in database.queue where entry.operation == "delete" && records[entry.syncKey] == nil {
            var deletion = entry
            deletion.version = 0
            records[entry.syncKey] = deletion
        }
    }

    private mutating func seed<Value: Encodable & Identifiable>(_ value: Value, entity: String,
                                                               history: [String: Change]) throws where Value.ID == UUID {
        var record = Change(entity: entity, entityID: value.id, operation: "upsert",
                            baseVersion: 0, version: 0, payload: try JSONEncoder().encode(value))
        if let previous = history[record.syncKey], previous.operation == "upsert" {
            record.id = previous.id
            record.changedAt = previous.changedAt
        } else {
            record.changedAt = .distantPast
        }
        records[record.syncKey] = record
    }

    mutating func recordLocalChanges(_ changes: ArraySlice<Change>, in database: inout Database) throws {
        for var change in changes {
            let key = change.syncKey
            if records[key]?.operation == "delete" {
                // Saved IDs cannot be reused, including by a form left open during sync.
                try records[key]?.apply(to: &database)
                continue
            }
            guard clock < Int.max else { throw PlannerSyncError.invalidReplica }
            change.baseVersion = records[key]?.version ?? 0
            clock += 1
            change.version = clock
            records[key] = change
        }
    }

    mutating func merge(_ replicas: [PlannerReplica], into database: inout Database) throws {
        for remote in replicas {
            guard remote.clock >= 0 else { throw PlannerSyncError.invalidReplica }
            clock = max(clock, remote.clock)
            for (key, record) in remote.records {
                guard key == record.syncKey, record.version >= 0, record.version <= remote.clock else {
                    throw PlannerSyncError.invalidReplica
                }
                if let current = records[key], !record.wins(over: current) { continue }
                try record.apply(to: &database)
                records[key] = record
            }
        }

        // An event edited offline can still refer to a task deleted on another Mac.
        for index in database.events.indices {
            guard let taskID = database.events[index].taskID,
                  records["task:\(taskID)"]?.operation == "delete" else { continue }
            database.events[index].taskID = nil
        }
    }
}

private extension Change {
    var syncKey: String { "\(entity):\(entityID)" }

    func wins(over current: Change) -> Bool {
        let deleting = operation == "delete"
        if deleting != (current.operation == "delete") { return deleting }
        if version != current.version { return version > current.version }
        if version == 0, changedAt != current.changedAt { return changedAt > current.changedAt }
        return id.uuidString > current.id.uuidString
    }

    func apply(to database: inout Database) throws {
        switch entity {
        case "term":
            var terms = database.terms ?? []
            try apply(to: &terms)
            database.terms = terms
        case "subject": try apply(to: &database.subjects)
        case "class": try apply(to: &database.classes)
        case "task": try apply(to: &database.tasks)
        case "event": try apply(to: &database.events)
        default: throw PlannerSyncError.invalidReplica
        }
    }

    private func apply<Value: Decodable & Identifiable>(to values: inout [Value]) throws where Value.ID == UUID {
        if operation == "delete" {
            guard payload == nil else { throw PlannerSyncError.invalidReplica }
            values.removeAll { $0.id == entityID }
            return
        }
        guard operation == "upsert", let payload else { throw PlannerSyncError.invalidReplica }
        let value = try JSONDecoder().decode(Value.self, from: payload)
        guard value.id == entityID else { throw PlannerSyncError.invalidReplica }
        if let index = values.firstIndex(where: { $0.id == entityID }) {
            values[index] = value
        } else {
            values.append(value)
        }
    }
}

enum PlannerSyncError: LocalizedError {
    case invalidReplica

    var errorDescription: String? {
        switch self {
        case .invalidReplica: return "ข้อมูลซิงก์ใช้รูปแบบที่แอปอ่านไม่ได้"
        }
    }
}
