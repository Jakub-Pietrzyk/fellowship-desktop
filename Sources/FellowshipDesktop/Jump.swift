import AppKit

/// Bringing the person to where a Claude Code session runs.
enum Jump: Equatable {
    /// An editor reopens the window that has this folder, or brings it forward if it is open already.
    case openFolder(bundleID: String, path: String)
    case focusTerminalTab(bundleID: String, tty: String)
    case activate(bundleID: String)
    case none

    static let editors: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.exafunction.windsurf",
    ]
    static let terminals: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2"]

    static func plan(for record: SessionRecord) -> Jump {
        guard let bundleID = record.hostBundleID else { return .none }
        if editors.contains(bundleID), let cwd = record.cwd, !cwd.isEmpty {
            return .openFolder(bundleID: bundleID, path: cwd)
        }
        if terminals.contains(bundleID), let tty = record.tty {
            return .focusTerminalTab(bundleID: bundleID, tty: tty)
        }
        return .activate(bundleID: bundleID)
    }

    @MainActor
    func perform() {
        switch self {
        case .none:
            return
        case .activate(let bundleID):
            Self.activate(bundleID)
        case .openFolder(let bundleID, let path):
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: app, configuration: configuration)
        case .focusTerminalTab(let bundleID, let tty):
            if !Self.focusTab(bundleID: bundleID, tty: tty) { Self.activate(bundleID) }
        }
    }

    @MainActor
    private static func activate(_ bundleID: String) {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            running.activate()
        } else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Needs the person's OK once (System Settings → Privacy → Automation); without it the app is only brought forward.
    @MainActor
    private static func focusTab(bundleID: String, tty: String) -> Bool {
        guard tty.range(of: #"^/dev/ttys?\d+$"#, options: .regularExpression) != nil else { return false }
        let source = switch bundleID {
        case "com.apple.Terminal": """
            tell application id "com.apple.Terminal"
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is "\(tty)" then
                    set selected of t to true
                    set index of w to 1
                    activate
                    return true
                  end if
                end repeat
              end repeat
            end tell
            return false
            """
        case "com.googlecode.iterm2": """
            tell application id "com.googlecode.iterm2"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with s in sessions of t
                    if tty of s is "\(tty)" then
                      select w
                      select t
                      select s
                      activate
                      return true
                    end if
                  end repeat
                end repeat
              end repeat
            end tell
            return false
            """
        default: ""
        }
        guard !source.isEmpty, let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        return script.executeAndReturnError(&error).booleanValue
    }
}
