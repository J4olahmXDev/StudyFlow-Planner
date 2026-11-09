#if os(macOS)
import XCTest
@testable import Planner

final class CloudSyncTests: XCTestCase {
    func testBrowserAndMacShareEncryptedFormat() throws {
        let code = try WorkspaceCode("0011-2233-4455-6677-8899-AABB-CCDD-EEFF")
        XCTAssertEqual(code.locator, "01eeb89cedcd96406c131ffe10027e7f90f42e7e8eff563a038b1095ac094604")
        let browserCiphertext = "8xkTXqamTbR7mDtV+klk287ZTfVuQBS7aM+wlVQ8uHyqpsyF2TJKenufV/+b90CQ2aSUr57ardILj8wX8JvpKwCsmdMpHPMRWHuGayxj2wo03O96xfuwdqPH+W+aA/2DvnqBHjRp"
        let replica = try code.open(browserCiphertext)
        XCTAssertEqual(replica.clock, 0)
        XCTAssertEqual(replica.deviceID.uuidString, "BB6F56BD-8BC4-4DBD-AFAE-0D83DDC92495")
        XCTAssertEqual(try code.open(code.seal(replica)), replica)
        XCTAssertThrowsError(try WorkspaceCode.generate().open(browserCiphertext))
        XCTAssertThrowsError(try WorkspaceCode("é000000000000000000000000000000"))
    }

    @MainActor func testAcademicTermsKeepLegacyAndNewDataSeparateAcrossReloadAndSync() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("planner.json")
        let old = Database.sample()
        let store = PlannerStore(url: file, fallback: old, remindersEnabled: false)
        XCTAssertEqual(store.termDatabase.tasks, old.tasks)
        XCTAssertTrue(store.saveTerm("  เทอม 2 / 2569  "))
        let newID = store.activeTermID
        XCTAssertTrue(store.termDatabase.subjects.isEmpty)
        XCTAssertFalse(store.saveTerm("เทอม 2 / 2569"))

        let subject = Subject(name: "New subject", code: "NEW", teacher: "", color: 0)
        store.save(subject)
        store.save(ClassSlot(subjectID: subject.id, weekday: 0, start: 540, end: 600, room: "A"))
        store.save(StudyTask(title: "New assignment", subjectID: subject.id, assigned: .now, due: .now))
        store.save(PlannerEvent(title: "New event", taskID: store.termDatabase.tasks.first?.id, start: .now, end: .now))
        XCTAssertTrue(store.saveTerm("เทอม 2", editing: newID))

        let reloaded = PlannerStore(url: file, remindersEnabled: false)
        XCTAssertEqual(reloaded.termDatabase.tasks, old.tasks)
        XCTAssertEqual(reloaded.termDatabase.classes, old.classes)
        reloaded.selectTerm(newID)
        XCTAssertEqual(reloaded.termDatabase.subjects.map(\.id), [subject.id])
        XCTAssertEqual(reloaded.termDatabase.classes.count, 1)
        XCTAssertEqual(reloaded.termDatabase.tasks.map(\.title), ["New assignment"])
        XCTAssertEqual(reloaded.termDatabase.events.map(\.title), ["New event"])
        XCTAssertEqual(reloaded.termOptions.last?.name, "เทอม 2")

        let source = try PlannerReplica(database: reloaded.db)
        var remoteDB = Database()
        var remote = try PlannerReplica(database: remoteDB)
        try remote.merge([source], into: &remoteDB)
        XCTAssertEqual(remoteDB.inTerm(newID), reloaded.termDatabase)
        let share = SharePayload(database: remoteDB.inTerm(AcademicTerm.legacyID), selection: ShareSelection())
        XCTAssertEqual(Set(share.tasks.map(\.id)), Set(old.tasks.map(\.id)))
        XCTAssertFalse(share.subjects.contains { $0.id == subject.id })
    }

    func testMergePreservesSeparateEditsAndDeletions() throws {
        var first = Database()
        let task = StudyTask(title: "Brief", assigned: .now, due: .now)
        first.tasks = [task]
        var left = try PlannerReplica(database: first)
        var second = Database()
        var right = try PlannerReplica(database: second)
        try right.merge([left], into: &second)

        let event = PlannerEvent(title: "Focus", taskID: task.id, start: .now, end: .now)
        second.events.append(event)
        second.record(event, entity: "event", id: event.id)
        try right.recordLocalChanges(second.queue[...], in: &second)

        first.tasks.removeAll()
        first.record(task, entity: "task", id: task.id, deleted: true)
        try left.recordLocalChanges(first.queue[...], in: &first)

        try left.merge([right], into: &first)
        try right.merge([left], into: &second)
        XCTAssertEqual(left.records, right.records)
        XCTAssertEqual(first.events, second.events)
        XCTAssertEqual(second.events.first?.id, event.id)
        XCTAssertNil(second.events.first?.taskID)
        XCTAssertTrue(second.tasks.isEmpty)
    }
}
#endif
