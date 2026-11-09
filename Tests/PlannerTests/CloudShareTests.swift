#if os(macOS)
import XCTest
@testable import Planner

final class CloudShareTests: XCTestCase {
    func testTasksOnlyKeepsRelatedPrivateDataOutOfThePayload() throws {
        let original = Database.sample()
        let selection = ShareSelection(timetable: false, tasks: true, events: false)
        let payload = SharePayload(database: original, selection: selection)
        XCTAssertTrue(payload.subjects.isEmpty)
        XCTAssertTrue(payload.classes.isEmpty)
        XCTAssertTrue(payload.events.isEmpty)
        XCTAssertEqual(payload.tasks.map(\.id), original.tasks.map(\.id))
        XCTAssertTrue(payload.tasks.allSatisfy { $0.subjectID == nil && $0.reminder == nil })
        XCTAssertEqual(payload.tasks.first?.notes, original.tasks.first?.notes)
        let events = SharePayload(database: original, selection: .init(timetable: false, tasks: false, events: true))
        XCTAssertTrue(events.events.allSatisfy { $0.subjectID == nil && $0.taskID == nil })
        XCTAssertTrue(events.tasks.isEmpty)
    }

    func testWebAndMacAgreeOnCodePasswordAndEncryptedPayload() throws {
        let credentials = ShareCredentials(code: "ABCD23", password: "EFGHJKLMNP45")
        XCTAssertEqual(credentials.workspace.locator, "90132e8aa0e05edc1eac25b0072b145db558d09b21a9b9ba2e4701eebfa41e6d")
        let payload = try credentials.workspace.openValue("M43mvull0W8NL5oNCgnztSt1qc6GUM2A5fp7PE0e1Bs8cHJ07cX9z5bJFxyFcdyKBJVnzegWVDMX8vikLhGPzFqCFLTwZMYQNoxkq91JMYZFSfXrm2lERH1xSjdq906rPA/cvnTFF3rnsev+OtUN1VMpXj1IqfNqoORiScwk492kv6L8JpcwmCk+wA==", as: SharePayload.self)
        XCTAssertEqual(payload.selection, ShareSelection(timetable: false, tasks: true, events: false))
        let wrong = ShareCredentials(code: "ABCD23", password: "EFGHJKLMNP46")
        XCTAssertThrowsError(try wrong.workspace.openValue(credentials.workspace.sealValue(payload), as: SharePayload.self))
        let generated = try ShareCredentials.generate()
        XCTAssertEqual(generated.code.count, 6)
        XCTAssertEqual(generated.password.count, 12)
    }
}
#endif
