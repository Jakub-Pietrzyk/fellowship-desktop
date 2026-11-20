import XCTest
@testable import FellowshipDesktop

final class SpriteTests: XCTestCase {
    private let library = SpriteLibrary(directory: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sprites"))

    func testEveryPoseOfEveryHeroHasItsFrames() {
        for hero in Hero.allCases {
            for edition in Edition.allCases where edition.isAvailable(for: hero) {
                for state in [PetState.idle, .working, .blocked, .done] {
                    for frame in Pose.of(hero: hero, edition: edition, state: state).frames {
                        XCTAssertNotNil(library.sprite(named: frame), "missing sprite \(frame)")
                    }
                }
            }
        }
    }

    func testRunsStayInsideTheGrid() throws {
        let sprite = try XCTUnwrap(library.sprite(named: "gandalf"))
        for run in sprite.runs {
            XCTAssertLessThanOrEqual(run.x + run.width, Sprite.gridSize)
            XCTAssertLessThanOrEqual(run.y + run.height, Sprite.gridSize)
        }
    }

    func testMalformedSvgIsRejected() {
        XCTAssertNil(Sprite(svg: "<svg></svg>"))
    }

    func testSaxFallsBackToNormalForHeroesOtherThanGandalf() {
        XCTAssertEqual(Pose.of(hero: .frodo, edition: .sax, state: .idle), Pose.of(hero: .frodo, edition: .normal, state: .idle))
        XCTAssertEqual(Pose.of(hero: .gandalf, edition: .sax, state: .done).frames, ["gandalf-sax-done"])
    }

    func testEditionDraw() {
        XCTAssertEqual(Edition.draw(for: .gandalf, random: { 0.005 }), .sax)
        XCTAssertEqual(Edition.draw(for: .frodo, random: { 0.005 }), .rare)
        XCTAssertEqual(Edition.draw(for: .frodo, random: { 0.5 }), .normal)
    }
}

final class HookCommandTests: XCTestCase {
    private func action(_ event: String, _ extra: [String: Any] = [:]) -> HookCommand.Action {
        HookCommand.action(for: ["hook_event_name": event].merging(extra) { $1 })
    }

    func testEventsMapToStates() {
        XCTAssertEqual(action("SessionStart"), .set(.idle))
        XCTAssertEqual(action("UserPromptSubmit"), .set(.working))
        XCTAssertEqual(action("PreToolUse"), .set(.working))
        XCTAssertEqual(action("PostToolUse"), .set(.working))
        XCTAssertEqual(action("PermissionRequest"), .set(.blocked))
        XCTAssertEqual(action("Stop"), .set(.done))
        XCTAssertEqual(action("SessionEnd"), .remove)
        XCTAssertEqual(action("SubagentStop"), .ignore)
    }

    func testNotificationsOnlyBlockForPermissionsAndQuestions() {
        XCTAssertEqual(action("Notification", ["notification_type": "permission_prompt"]), .set(.blocked))
        XCTAssertEqual(action("Notification", ["notification_type": "elicitation_dialog"]), .set(.blocked))
        XCTAssertEqual(action("Notification", ["notification_type": "idle_prompt"]), .ignore)
        XCTAssertEqual(action("Notification", ["message": "Claude needs your permission to use Bash"]), .set(.blocked))
        XCTAssertEqual(action("Notification", ["message": "Claude is waiting for your input"]), .ignore)
    }

    func testRunWritesTheSessionAndKeepsItsFolder() throws {
        let store = StatusStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let now = Date(timeIntervalSince1970: 1_000)
        HookCommand.run(stdin: Data(#"{"session_id":"abc","hook_event_name":"UserPromptSubmit","cwd":"/x/bodyvibes_mobile"}"#.utf8), store: store, now: now)
        HookCommand.run(stdin: Data(#"{"session_id":"abc","hook_event_name":"Stop"}"#.utf8), store: store, now: now)
        let record = try XCTUnwrap(store.read(sessionID: "abc"))
        XCTAssertEqual(record.state, .done)
        XCTAssertEqual(record.project, "bodyvibes_mobile")

        HookCommand.run(stdin: Data(#"{"session_id":"abc","hook_event_name":"SessionEnd"}"#.utf8), store: store, now: now)
        XCTAssertNil(store.read(sessionID: "abc"))
    }

    func testGarbageOnStdinWritesNothing() {
        let store = StatusStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        HookCommand.run(stdin: Data("not json".utf8), store: store)
        XCTAssertTrue(store.all().isEmpty)
    }
}

final class StatusStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100_000)

    private func record(_ state: PetState, ageMinutes: Double, cwd: String = "/p") -> SessionRecord {
        SessionRecord(state: state, cwd: cwd, updated: now.addingTimeInterval(-ageMinutes * 60))
    }

    func testMostUrgentSessionWins() {
        let summary = StatusStore.fold([record(.done, ageMinutes: 1), record(.blocked, ageMinutes: 2), record(.working, ageMinutes: 1)])
        XCTAssertEqual(summary.state, .blocked)
        XCTAssertEqual(summary.sessions.count, 1)
        XCTAssertEqual(summary.total, 3)
    }

    func testNoSessionsIsIdle() {
        XCTAssertEqual(StatusStore.fold([]), .empty)
    }

    func testQuietSessionsFallBackToIdle() {
        XCTAssertEqual(StatusStore.effective(record(.working, ageMinutes: 29), now: now).state, .working)
        XCTAssertEqual(StatusStore.effective(record(.working, ageMinutes: 31), now: now).state, .idle)
        XCTAssertEqual(StatusStore.effective(record(.done, ageMinutes: 11), now: now).state, .idle)
        XCTAssertEqual(StatusStore.effective(record(.blocked, ageMinutes: 59), now: now).state, .blocked)
    }

    func testAcknowledgeDoneRestsOnlyFinishedSessions() throws {
        let store = StatusStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try store.write(sessionID: "a", record: record(.done, ageMinutes: 1))
        try store.write(sessionID: "b", record: record(.working, ageMinutes: 1))
        store.acknowledgeDone(now: now)
        XCTAssertEqual(store.read(sessionID: "a")?.state, .idle)
        XCTAssertEqual(store.read(sessionID: "b")?.state, .working)
    }

    func testLongDeadSessionsAreForgotten() throws {
        let store = StatusStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try store.write(sessionID: "old", record: record(.working, ageMinutes: 13 * 60))
        XCTAssertEqual(store.summary(now: now), .empty)
        XCTAssertNil(store.read(sessionID: "old"))
    }

    func testSessionIdCannotEscapeTheDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = StatusStore(directory: directory)
        try store.write(sessionID: "../../evil", record: record(.idle, ageMinutes: 0))
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files, ["evil.json"])
    }
}

final class BubbleTests: XCTestCase {
    private let now = Date()

    func testPolishPlurals() {
        XCTAssertEqual(Bubble.sessions(1), "1 sesja")
        XCTAssertEqual(Bubble.sessions(3), "3 sesje")
        XCTAssertEqual(Bubble.sessions(5), "5 sesji")
        XCTAssertEqual(Bubble.sessions(12), "12 sesji")
        XCTAssertEqual(Bubble.sessions(22), "22 sesje")
    }

    func testBubbleNamesTheProject() {
        let one = Summary(state: .blocked, sessions: [SessionRecord(state: .blocked, cwd: "/a/bodyvibes_mobile", updated: now)], total: 1)
        XCTAssertEqual(Bubble.text(for: one), "bodyvibes_mobile: czekam na Twoją zgodę")
        let two = Summary(state: .done, sessions: [
            SessionRecord(state: .done, cwd: "/a", updated: now),
            SessionRecord(state: .done, cwd: "/b", updated: now),
        ], total: 2)
        XCTAssertEqual(Bubble.text(for: two), "2 sesje skończyło")
        XCTAssertNil(Bubble.text(for: Summary(state: .working, sessions: [], total: 1)))
    }
}
