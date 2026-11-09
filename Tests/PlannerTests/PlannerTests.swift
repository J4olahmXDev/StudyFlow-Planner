import XCTest
@testable import Planner

final class PlannerTests: XCTestCase {
    func testOvernightSessionIsClippedAcrossBothDays() {
        var cal = Calendar(identifier:.gregorian)
        cal.timeZone = TimeZone(secondsFromGMT:0)!
        let day = cal.date(from:DateComponents(year:2026,month:11,day:8))!
        let next = cal.date(byAdding:.day,value:1,to:day)!
        let event = PlannerEvent(title:"Late study",start:day.addingTimeInterval(23*3600),end:next.addingTimeInterval(2*3600))
        let item = AgendaItem(id:"test",title:event.title,start:event.start,end:event.end,detail:"")
        XCTAssertEqual(item.minuteRange(on:day,calendar:cal),1380..<1440)
        XCTAssertEqual(item.minuteRange(on:next,calendar:cal),0..<120)
    }

    @MainActor func testSaveReloadAndCorruptionProtection() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url = folder.appendingPathComponent("planner.json")
        let store = PlannerStore(url:url)
        let subject = Subject(name:"Test subject",code:"T1",teacher:"Teacher",color:2)
        store.save(subject)
        XCTAssertEqual(PlannerStore(url:url).db.subject(subject.id),subject)
        let broken = Data("invalid database".utf8)
        try broken.write(to:url)
        let damaged = PlannerStore(url:url)
        XCTAssertNotNil(damaged.error)
        damaged.error = nil // Dismissing an alert must not unlock writes.
        XCTAssertFalse(damaged.update { $0.subjects.append(subject) })
        XCTAssertEqual(try Data(contentsOf:url),broken)
    }

    func testTaskRelationshipsAndProgressSurviveRoundTrip() throws {
        var db = Database.sample()
        db.tasks[0].reminder = Date(timeIntervalSince1970:123456)
        let saved = try JSONDecoder().decode(Database.self,from:JSONEncoder().encode(db))
        XCTAssertEqual(saved,db)
        XCTAssertEqual(saved.tasks[0].progress,2.0/3.0,accuracy:0.001)
        XCTAssertEqual(saved.events[0].taskID,saved.tasks[0].id)
    }

    @MainActor func testLegacyDataKeepsRelationshipsWhenEditingNewFields() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = folder.appendingPathComponent("planner.json")
        var legacy = Database.sample()
        legacy.classes[0].kind = nil
        legacy.classes[0].building = nil
        try JSONEncoder().encode(legacy).write(to: url)
        let store = PlannerStore(url: url)
        var slot = try XCTUnwrap(store.db.classes.first)
        var task = try XCTUnwrap(store.db.tasks.first)
        var subject = try XCTUnwrap(store.db.subject(task.subjectID))
        XCTAssertNil(slot.kind)
        XCTAssertNil(slot.building)
        XCTAssertNil(task.color)

        slot.kind = .lab
        slot.building = "EN"
        task.color = 5
        subject.color = 7
        store.save(slot)
        store.save(task)
        store.toggle(task)
        store.save(subject)

        let reloaded = PlannerStore(url: url).db
        XCTAssertEqual(reloaded.classes.first(where: { $0.id == slot.id }), slot)
        let persistedTask = try XCTUnwrap(reloaded.tasks.first(where: { $0.id == task.id }))
        XCTAssertEqual(persistedTask.status, .done)
        XCTAssertEqual(persistedTask.color, 5)
        XCTAssertEqual(persistedTask.subjectID, subject.id)
        XCTAssertEqual(reloaded.events, legacy.events)
    }

    @MainActor func testClearingPreviewPreservesPersonalWorkspace() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let personalURL = folder.appendingPathComponent("planner.json")
        let previewURL = folder.appendingPathComponent("preview.json")
        let personal = PlannerStore(url: personalURL, fallback: Database())
        let preview = PlannerStore(url: previewURL, remindersEnabled: false)

        XCTAssertTrue(personal.db.classes.isEmpty)
        XCTAssertEqual(preview.db.classes.count, 11)
        XCTAssertEqual(preview.db.tasks.filter { $0.status == .done }.count, 2)
        let subject = Subject(name: "Personal subject", code: "P1", teacher: "", color: 0)
        personal.save(subject)
        let before = try Data(contentsOf: personalURL)
        preview.toggle(try XCTUnwrap(preview.db.tasks.first))
        XCTAssertEqual(PlannerStore(url: previewURL).db.tasks.filter { $0.status == .done }.count, 3)
        XCTAssertTrue(preview.update { $0 = Database() })

        XCTAssertTrue(PlannerStore(url: previewURL).db.subjects.isEmpty)
        XCTAssertEqual(try Data(contentsOf: personalURL), before)
        XCTAssertEqual(PlannerStore(url: personalURL).db.subject(subject.id), subject)
    }

    @MainActor func testTaskCompletionUpdatesWeekAndCalendarWithoutOverwritingNewEdits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("planner.json")
        let store = PlannerStore(url: url, fallback: Database())
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let end = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: start))
        let stale = StudyTask(title: "Original title", assigned: start, due: start)
        let outside = StudyTask(title: "Next week", assigned: start, due: end)
        store.save(stale)
        store.save(outside)
        var edited = stale
        edited.title = "Updated title"
        store.save(edited)
        let linked = PlannerEvent(title: "Study block", taskID: stale.id, start: start,
                                  end: start.addingTimeInterval(1800))
        store.save(linked)

        XCTAssertEqual(store.db.weeklyTaskProgress(from: start, to: end).tasks.map(\.id), [stale.id])
        XCTAssertTrue(store.db.agenda(on: start).contains { $0.id == stale.id.uuidString })
        store.toggle(stale)
        let result = PlannerStore(url: url).db
        let progress = result.weeklyTaskProgress(from: start, to: end)
        XCTAssertEqual(progress.done, 1)
        XCTAssertEqual(progress.remaining, 0)
        XCTAssertEqual(progress.fraction, 1)
        XCTAssertEqual(progress.tasks.first?.title, "Updated title")
        XCTAssertFalse(result.agenda(on: start).contains { $0.id == stale.id.uuidString })
        XCTAssertTrue(result.agenda(on: start).contains { $0.eventID == linked.id && $0.taskID == stale.id })

        store.toggle(stale)
        XCTAssertEqual(store.db.weeklyTaskProgress(from: start, to: end).remaining, 1)
        XCTAssertTrue(store.db.agenda(on: start).contains { $0.id == stale.id.uuidString })
        store.deleteTask(stale.id)
        store.toggle(stale)
        XCTAssertFalse(store.db.tasks.contains { $0.id == stale.id })
        XCTAssertNil(store.db.events.first(where: { $0.id == linked.id })?.taskID)
    }

    @MainActor func testMovingClassUpdatesAgendaAndSurvivesReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("planner.json")
        let store = PlannerStore(url: url, fallback: Database())
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: .now)
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))
        let weekday = (calendar.component(.weekday, from: day) + 5) % 7
        let subject = Subject(name: "QA class", code: "QA100", teacher: "", color: 1)
        var slot = ClassSlot(subjectID: subject.id, weekday: weekday, start: 540, end: 600, room: "101")
        store.save(subject)
        store.save(slot)
        XCTAssertTrue(store.db.agenda(on: day).contains { $0.id == slot.id.uuidString })

        slot.weekday = (weekday + 1) % 7
        slot.start = 660
        slot.end = 720
        slot.room = "202"
        store.save(slot)
        let result = PlannerStore(url: url).db
        XCTAssertEqual(result.classes.first, slot)
        XCTAssertFalse(result.agenda(on: day).contains { $0.id == slot.id.uuidString })
        let moved = try XCTUnwrap(result.agenda(on: nextDay).first { $0.id == slot.id.uuidString })
        XCTAssertEqual(moved.title, subject.name)
        XCTAssertEqual(moved.detail, "202")
        XCTAssertEqual(moved.minuteRange(on: nextDay), 660..<720)
    }
}
