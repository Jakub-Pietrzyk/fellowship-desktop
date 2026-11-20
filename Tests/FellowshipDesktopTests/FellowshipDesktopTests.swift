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

final class JumpTests: XCTestCase {
    private func record(host: String?, cwd: String? = "/Users/kuba/Desktop/BodyVibes/bodyvibes_mobile", tty: String? = nil) -> SessionRecord {
        SessionRecord(state: .done, cwd: cwd, updated: Date(), hostBundleID: host, tty: tty)
    }

    func testEditorsReopenTheProjectWindow() {
        XCTAssertEqual(Jump.plan(for: record(host: "com.microsoft.VSCode")),
                       .openFolder(bundleID: "com.microsoft.VSCode", path: "/Users/kuba/Desktop/BodyVibes/bodyvibes_mobile"))
    }

    func testEditorWithoutFolderIsOnlyBroughtForward() {
        XCTAssertEqual(Jump.plan(for: record(host: "com.microsoft.VSCode", cwd: nil)), .activate(bundleID: "com.microsoft.VSCode"))
    }

    func testTerminalsGoToTheTab() {
        XCTAssertEqual(Jump.plan(for: record(host: "com.apple.Terminal", tty: "/dev/ttys004")),
                       .focusTerminalTab(bundleID: "com.apple.Terminal", tty: "/dev/ttys004"))
        XCTAssertEqual(Jump.plan(for: record(host: "com.googlecode.iterm2")), .activate(bundleID: "com.googlecode.iterm2"))
    }

    func testOtherAppsAreBroughtForward() {
        XCTAssertEqual(Jump.plan(for: record(host: "com.anthropic.claudefordesktop")), .activate(bundleID: "com.anthropic.claudefordesktop"))
    }

    func testUnknownHostDoesNothing() {
        XCTAssertEqual(Jump.plan(for: record(host: nil)), .none)
    }
}

final class SessionHostTests: XCTestCase {
    func testHostComesFromTheEnvironment() {
        let host = SessionHost.current(environment: ["__CFBundleIdentifier": "com.microsoft.VSCode", "CLAUDE_CODE_ENTRYPOINT": "claude-vscode"])
        XCTAssertEqual(host.bundleID, "com.microsoft.VSCode")
        XCTAssertEqual(host.entrypoint, "claude-vscode")
    }

    func testEmptyValuesAreIgnored() {
        XCTAssertNil(SessionHost.current(environment: ["__CFBundleIdentifier": ""]).bundleID)
    }

    func testHookKeepsTheHostWhenALaterEventLacksIt() throws {
        let store = StatusStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let vscode = SessionHost(bundleID: "com.microsoft.VSCode", entrypoint: "claude-vscode", tty: nil)
        HookCommand.run(stdin: Data(#"{"session_id":"s","hook_event_name":"UserPromptSubmit","cwd":"/p"}"#.utf8), store: store, host: vscode)
        HookCommand.run(stdin: Data(#"{"session_id":"s","hook_event_name":"Stop"}"#.utf8), store: store, host: SessionHost())
        let record = try XCTUnwrap(store.read(sessionID: "s"))
        XCTAssertEqual(record.hostBundleID, "com.microsoft.VSCode")
        XCTAssertEqual(record.entrypoint, "claude-vscode")
        XCTAssertEqual(record.state, .done)
    }

    func testOldRecordsWithoutHostStillDecode() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"state":"done","cwd":"/p","updated":1000}"#.utf8).write(to: directory.appendingPathComponent("old.json"))
        XCTAssertEqual(StatusStore(directory: directory).read(sessionID: "old")?.state, .done)
    }

    func testMenuEntryNamesProjectStateAndApp() {
        let record = SessionRecord(state: .blocked, cwd: "/x/bodyvibes_supabase", updated: Date(), hostBundleID: "com.anthropic.claudefordesktop")
        XCTAssertEqual(Bubble.menuEntry(for: record), "bodyvibes_supabase: czeka na Ciebie · aplikacja Claude")
    }

    func testAllSessionsAreSortedByUrgencyThenRecency() {
        let now = Date()
        let summary = StatusStore.fold([
            SessionRecord(state: .idle, cwd: "/a", updated: now),
            SessionRecord(state: .done, cwd: "/b", updated: now.addingTimeInterval(-60)),
            SessionRecord(state: .done, cwd: "/c", updated: now),
            SessionRecord(state: .blocked, cwd: "/d", updated: now.addingTimeInterval(-300)),
        ])
        XCTAssertEqual(summary.all.map(\.project), ["d", "c", "b", "a"])
    }
}

final class TrickTests: XCTestCase {
    private let library = SpriteLibrary(directory: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sprites"))

    private func everyTrick() -> [(Hero, Edition, Trick)] {
        Hero.allCases.flatMap { hero in
            Edition.allCases.filter { $0.isAvailable(for: hero) }.flatMap { edition in
                Tricks.all(for: hero, edition: edition).map { (hero, edition, $0) }
            }
        }
    }

    func testEveryHeroHasThreeToFiveDistinctTricks() {
        for hero in Hero.allCases {
            for edition in Edition.allCases where edition.isAvailable(for: hero) {
                let tricks = Tricks.all(for: hero, edition: edition)
                XCTAssertTrue((3...5).contains(tricks.count), "\(hero) \(edition)")
                XCTAssertEqual(Set(tricks.map(\.id)).count, tricks.count, "duplicate trick id for \(hero)")
            }
        }
    }

    func testSaxGandalfPlaysTheSaxInsteadOfSmokingThePipe() {
        let ids = Tricks.all(for: .gandalf, edition: .sax).map(\.id)
        XCTAssertTrue(ids.contains("sax-solo"))
        XCTAssertFalse(ids.contains("smoke-rings"))
    }

    func testTricksEndWithTheFigureBackAtRest() {
        for (hero, _, trick) in everyTrick() {
            let end = trick.frame(trick.duration)
            XCTAssertEqual(end.dx, 0, accuracy: 0.01, "\(hero) \(trick.id)")
            XCTAssertEqual(end.dy, 0, accuracy: 0.01, "\(hero) \(trick.id)")
            XCTAssertEqual(end.rotation.truncatingRemainder(dividingBy: 360), 0, accuracy: 0.5, "\(hero) \(trick.id)")
            XCTAssertEqual(end.stretch, 1, accuracy: 0.01, "\(hero) \(trick.id)")
            XCTAssertEqual(end.alpha, 1, accuracy: 0.01, "\(hero) \(trick.id)")
            XCTAssertFalse(end.flipped, "\(hero) \(trick.id)")
        }
    }

    func testEveryFrameIsFiniteAndStaysNearTheFigure() {
        for (hero, _, trick) in everyTrick() {
            XCTAssertTrue((1...3.5).contains(trick.duration), "\(trick.id) lasts \(trick.duration)s")
            for step in 0...60 {
                let frame = trick.frame(trick.duration * Double(step) / 60)
                for value in [frame.dx, frame.dy, frame.rotation, frame.stretch, frame.alpha] {
                    XCTAssertTrue(value.isFinite, "\(hero) \(trick.id)")
                }
                XCTAssertTrue((0...1).contains(frame.alpha), "\(hero) \(trick.id)")
                for speck in frame.behind + frame.front {
                    XCTAssertTrue(speck.x.isFinite && speck.y.isFinite, "\(hero) \(trick.id)")
                    XCTAssertTrue((-20...50).contains(speck.x) && (-25...24).contains(speck.y),
                                  "\(hero) \(trick.id) speck at \(speck.x), \(speck.y)")
                }
            }
        }
    }

    func testPosesUsedByTricksExistForEveryEdition() {
        let states: [TrickPose: PetState] = [.idle: .idle, .work: .working, .blocked: .blocked, .done: .done]
        for (hero, edition, trick) in everyTrick() {
            for step in 0...20 {
                guard let state = states[trick.frame(trick.duration * Double(step) / 20).pose] else { continue }
                for name in Pose.of(hero: hero, edition: edition, state: state).frames {
                    XCTAssertNotNil(library.sprite(named: name), "\(trick.id) needs \(name)")
                }
            }
        }
    }

    func testPickNeverRepeatsTheTrickJustPlayed() {
        let ids = Tricks.all(for: .gimli, edition: .normal).map(\.id)
        for previous in ids {
            for roll in 0..<ids.count - 1 {
                let picked = Tricks.pick(for: .gimli, edition: .normal, after: previous, random: { _ in roll })
                XCTAssertNotEqual(picked.id, previous)
            }
        }
    }

    func testStageFindsTheTopOfTheHead() {
        let sprite = Sprite(svg: ##"<rect x="3" y="5" width="2" height="1" fill="#000000"/><rect x="3" y="9" width="2" height="1" fill="#000000"/>"##)
        XCTAssertEqual(Stage(sprite: sprite).headTop, 5)
        XCTAssertEqual(Stage(sprite: nil).headTop, 2)
    }
}
