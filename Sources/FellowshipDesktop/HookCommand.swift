import Foundation

/// `FellowshipDesktop hook`: Claude Code pipes each hook's JSON to stdin; the session's new state lands in the
/// status store. It never prints: stdout of some hooks (SessionStart, UserPromptSubmit) goes into Claude's context.
enum HookCommand {
    enum Action: Equatable {
        case set(PetState)
        case remove
        case ignore
    }

    static func action(for input: [String: Any]) -> Action {
        switch input["hook_event_name"] as? String {
        case "SessionStart":
            return .set(.idle)
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionDenied":
            return .set(.working)
        case "PermissionRequest":
            return .set(.blocked)
        case "Notification":
            return notificationAction(input)
        case "Stop", "StopFailure":
            return .set(.done)
        case "SessionEnd":
            return .remove
        default:
            return .ignore
        }
    }

    private static func notificationAction(_ input: [String: Any]) -> Action {
        switch input["notification_type"] as? String {
        case "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input":
            return .set(.blocked)
        case .some:
            return .ignore
        case nil:
            let message = (input["message"] as? String ?? "").lowercased()
            return message.contains("permission") ? .set(.blocked) : .ignore
        }
    }

    static func run(stdin: Data, store: StatusStore = .default, now: Date = Date()) {
        guard let input = (try? JSONSerialization.jsonObject(with: stdin)) as? [String: Any],
              let sessionID = input["session_id"] as? String else { return }
        switch action(for: input) {
        case .ignore:
            return
        case .remove:
            store.remove(sessionID: sessionID)
        case .set(let state):
            let cwd = input["cwd"] as? String ?? store.read(sessionID: sessionID)?.cwd
            try? store.write(sessionID: sessionID, record: SessionRecord(state: state, cwd: cwd, updated: now))
        }
    }
}
