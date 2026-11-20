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

    static func run(
        stdin: Data,
        store: StatusStore = .default,
        now: Date = Date(),
        host: SessionHost = .current()
    ) {
        guard let input = (try? JSONSerialization.jsonObject(with: stdin)) as? [String: Any],
              let sessionID = input["session_id"] as? String else { return }
        switch action(for: input) {
        case .ignore:
            return
        case .remove:
            store.remove(sessionID: sessionID)
        case .set(let state):
            let previous = store.read(sessionID: sessionID)
            let record = SessionRecord(
                state: state,
                cwd: input["cwd"] as? String ?? previous?.cwd,
                updated: now,
                hostBundleID: host.bundleID ?? previous?.hostBundleID,
                entrypoint: host.entrypoint ?? previous?.entrypoint,
                tty: host.tty ?? previous?.tty
            )
            try? store.write(sessionID: sessionID, record: record)
        }
    }
}

/// Where the Claude Code process that ran the hook lives: the app that launched it and its terminal, if any.
/// Hooks inherit Claude Code's environment, and macOS puts the launching app's bundle id in `__CFBundleIdentifier`.
struct SessionHost: Equatable {
    var bundleID: String?
    var entrypoint: String?
    var tty: String?

    static func current(environment: [String: String] = ProcessInfo.processInfo.environment) -> SessionHost {
        SessionHost(
            bundleID: environment["__CFBundleIdentifier"].flatMap { $0.isEmpty ? nil : $0 },
            entrypoint: environment["CLAUDE_CODE_ENTRYPOINT"].flatMap { $0.isEmpty ? nil : $0 },
            tty: controllingTerminal()
        )
    }

    private static func controllingTerminal() -> String? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let device = info.kp_eproc.e_tdev
        guard device != -1, let name = devname(device, S_IFCHR) else { return nil }
        let tty = String(cString: name)
        return tty.hasPrefix("tty") ? "/dev/\(tty)" : nil
    }
}
