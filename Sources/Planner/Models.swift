import Foundation

struct AcademicTerm: Identifiable, Codable, Equatable {
    static let legacyID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    var id = UUID()
    var name: String
}

struct Subject: Identifiable, Codable, Equatable {
    var id = UUID(); var name: String; var code: String; var teacher: String; var color: Int
    var termID: UUID?
}
struct ClassSlot: Identifiable, Codable, Equatable {
    var id = UUID(); var subjectID: UUID; var weekday: Int; var start: Int; var end: Int; var room: String
    var kind: ClassKind?
    var building: String?

    var location: String { [building ?? "", room].filter { !$0.isEmpty }.joined(separator: " ") }
}
enum ClassKind: String, Codable, CaseIterable { case lecture = "LEC", lab = "LAB" }
enum Priority: String, Codable, CaseIterable { case low = "Low", medium = "Medium", high = "High" }
enum WorkStatus: String, Codable, CaseIterable { case todo = "To do", active = "In progress", done = "Done" }
struct Subtask: Identifiable, Codable, Equatable { var id = UUID(); var title: String; var done = false }
struct StudyTask: Identifiable, Codable, Equatable {
    var id = UUID(); var title: String; var subjectID: UUID?; var assigned: Date; var due: Date
    var priority: Priority = .medium; var status: WorkStatus = .todo; var subtasks: [Subtask] = []
    var reminder: Date?; var notes = ""
    var color: Int?
    var termID: UUID?
    var progress: Double { status == .done ? 1 : (subtasks.isEmpty ? 0 : Double(subtasks.filter(\.done).count) / Double(subtasks.count)) }
}
struct PlannerEvent: Identifiable, Codable, Equatable {
    var id = UUID(); var title: String; var subjectID: UUID?; var taskID: UUID?; var start: Date; var end: Date; var location = ""
    var termID: UUID?
}
struct Change: Identifiable, Codable, Equatable, Sendable {
    var id = UUID(); var entity: String; var entityID: UUID; var operation: String; var baseVersion: Int; var version: Int; var changedAt = Date(); var payload: Data?
}
struct SyncConflict: Identifiable, Codable, Equatable { var id = UUID(); var local: Change; var incoming: Change }
struct Database: Codable, Equatable {
    var schemaVersion = 1
    var syncReplica: PlannerReplica?
    var syncWorkspace: String?
    var terms: [AcademicTerm]?
    var subjects: [Subject] = []; var classes: [ClassSlot] = []; var tasks: [StudyTask] = []; var events: [PlannerEvent] = []
    var versions: [String: Int] = [:]; var queue: [Change] = []; var conflicts: [SyncConflict] = []
    func inTerm(_ id: UUID) -> Database {
        var result = Database()
        result.subjects = subjects.filter { ($0.termID ?? AcademicTerm.legacyID) == id }
        let knownSubjects = Set(subjects.map(\.id))
        let termSubjects = Set(result.subjects.map(\.id))
        result.classes = classes.filter {
            termSubjects.contains($0.subjectID) || (id == AcademicTerm.legacyID && !knownSubjects.contains($0.subjectID))
        }
        result.tasks = tasks.filter { ($0.termID ?? AcademicTerm.legacyID) == id }
        result.events = events.filter { ($0.termID ?? AcademicTerm.legacyID) == id }
        return result
    }

    mutating func record<T: Encodable>(_ item: T, entity: String, id: UUID, deleted: Bool = false) {
        let key = "\(entity):\(id)"; let base = versions[key, default: 0]; versions[key] = base + 1
        queue.append(Change(entity: entity, entityID: id, operation: deleted ? "delete" : "upsert", baseVersion: base, version: base + 1, payload: deleted ? nil : try? JSONEncoder().encode(item)))
    }
    // Remote adapter must call this before applying an incoming row. Never silently overwrite a pending local edit.
    mutating func accepts(_ incoming: Change) -> Bool {
        if let local = queue.last(where: { $0.entity == incoming.entity && $0.entityID == incoming.entityID }) {
            conflicts.append(SyncConflict(local: local, incoming: incoming)); return false
        }
        return incoming.version > versions["\(incoming.entity):\(incoming.entityID)", default: 0]
    }
    static func sample(now: Date = Date()) -> Database {
        var db = Database()
        db.subjects = [
            Subject(name: "IE Project 2", code: "301493", teacher: "", color: 1),
            Subject(name: "Simulation", code: "301494", teacher: "", color: 5),
            Subject(name: "Quality Engineering", code: "301495", teacher: "", color: 6),
            Subject(name: "Production Planning", code: "301492", teacher: "", color: 1),
            Subject(name: "Industrial Engineering Lab", code: "301421", teacher: "", color: 7),
            Subject(name: "Engineering Mathematics III", code: "MATH 260", teacher: "", color: 6),
            Subject(name: "Data Analytics for IE", code: "301233", teacher: "", color: 2),
            Subject(name: "Technology and Society", code: "GEN 101", teacher: "", color: 1),
            Subject(name: "Quality Engineering", code: "IE 315", teacher: "", color: 5)
        ]
        let slots: [(day: Int, subject: Int, start: Int, end: Int, kind: ClassKind, building: String?, room: String)] = [
            (0, 0, 480, 710, .lecture, "EN", "505"), (0, 1, 780, 890, .lecture, "EN", "405"),
            (0, 2, 900, 1070, .lecture, "EN", "407"), (1, 3, 540, 710, .lecture, "EN", "408"),
            (1, 4, 780, 960, .lab, nil, "Lab 2"), (2, 5, 540, 710, .lecture, "SC", "301"),
            (2, 6, 840, 1010, .lecture, "EN", "406"), (3, 1, 540, 710, .lab, "EN", "405"),
            (3, 0, 780, 950, .lecture, "EN", "410"), (4, 7, 540, 710, .lecture, "HU", "201"),
            (4, 8, 840, 1010, .lab, "EN", "407")
        ]
        db.classes = slots.map { slot in
            ClassSlot(subjectID: db.subjects[slot.subject].id, weekday: slot.day,
                      start: slot.start, end: slot.end, room: slot.room, kind: slot.kind, building: slot.building)
        }
        let calendar = Calendar.current
        let weekday = (calendar.component(.weekday, from: now) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -weekday, to: calendar.startOfDay(for: now))!
        func due(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: offset, to: monday)!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        db.tasks = [
            StudyTask(title: "รายงาน Simulation", subjectID: db.subjects[1].id, assigned: monday, due: due(4, 17),
                      priority: .high, status: .active, subtasks: [
                        Subtask(title: "รวบรวมผลทดลอง", done: true), Subtask(title: "ทำกราฟ", done: true),
                        Subtask(title: "ตรวจรายงานก่อนส่ง")
                      ], notes: "ใส่กราฟและอธิบายผลการจำลองท้ายรายงาน"),
            StudyTask(title: "Homework 3", subjectID: db.subjects[5].id, assigned: monday, due: due(5, 23, 59)),
            StudyTask(title: "Lab Report 2", subjectID: db.subjects[4].id, assigned: monday, due: due(6, 23, 59), priority: .low),
            StudyTask(title: "ทบทวนสไลด์สัปดาห์นี้", subjectID: db.subjects[6].id, assigned: monday, due: due(1, 18), status: .done),
            StudyTask(title: "ส่งหัวข้อโปรเจกต์", subjectID: db.subjects[0].id, assigned: monday, due: due(2, 18), status: .done)
        ]
        db.events = [
            PlannerEvent(title: "เตรียมรายงาน Simulation", subjectID: db.subjects[1].id, taskID: db.tasks[0].id,
                         start: due(3, 16), end: due(3, 17), location: "ห้องสมุด")
        ]
        return db
    }
}
struct WeeklyTaskProgress {
    let tasks: [StudyTask]
    var done: Int { tasks.filter { $0.status == .done }.count }
    var total: Int { tasks.count }
    var remaining: Int { total - done }
    var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

struct AgendaItem: Identifiable { var id: String; var title: String; var start: Date; var end: Date; var subjectID: UUID?; var detail: String; var taskID: UUID?; var eventID: UUID? }
extension Database {
    func weeklyTaskProgress(from start: Date, to end: Date) -> WeeklyTaskProgress {
        WeeklyTaskProgress(tasks: tasks.filter { $0.due >= start && $0.due < end }.sorted { $0.due < $1.due })
    }

    func subject(_ id: UUID?) -> Subject? { subjects.first { $0.id == id } }
    func agenda(on day: Date) -> [AgendaItem] {
        let cal = Calendar.current; let wd = (cal.component(.weekday, from:day) + 5) % 7
        let midnight = cal.startOfDay(for:day)
        var items = classes.filter { $0.weekday == wd }.map { slot in
            AgendaItem(id:slot.id.uuidString, title:subject(slot.subjectID)?.name ?? "Class", start:cal.date(byAdding:.minute,value:slot.start,to:midnight)!, end:cal.date(byAdding:.minute,value:slot.end,to:midnight)!, subjectID:slot.subjectID,detail:slot.location,taskID:nil,eventID:nil)
        }
        items += events.filter { $0.start < cal.date(byAdding:.day,value:1,to:midnight)! && $0.end > midnight }.map { event in AgendaItem(id:event.id.uuidString,title:event.title,start:event.start,end:event.end,subjectID:event.subjectID ?? tasks.first(where:{$0.id == event.taskID})?.subjectID,detail:event.location,taskID:event.taskID,eventID:event.id) }
        items += tasks.filter { cal.isDate($0.due,inSameDayAs:day) && $0.status != .done }.map { AgendaItem(id:$0.id.uuidString,title:$0.title,start:$0.due,end:$0.due,subjectID:$0.subjectID,detail:"Assignment due",taskID:$0.id,eventID:nil) }
        return items.sorted { $0.start < $1.start }
    }
}
func clock(_ minutes: Int) -> String { String(format:"%02d:%02d", minutes / 60, minutes % 60) }
let dayNames = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]

// Shared wall-clock projection for both weekly calendar orientations.
// Clip overnight sessions at each day's boundary; deadlines get a visible marker.
extension AgendaItem {
    func minuteRange(on day: Date, calendar: Calendar = .current) -> Range<Double> {
        let midnight = calendar.startOfDay(for: day)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: midnight)!
        func minute(_ date: Date) -> Double {
            if date <= midnight { return 0 }
            if date >= tomorrow { return 1440 }
            return Double(calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date))
        }
        let lower = min(1439, max(0, minute(start)))
        return lower..<min(1440, max(lower + 1, minute(end)))
    }
}
