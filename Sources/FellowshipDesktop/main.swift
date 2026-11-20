import AppKit

let arguments = CommandLine.arguments.dropFirst()

switch arguments.first {
case "hook":
    HookCommand.run(stdin: FileHandle.standardInput.readDataToEndOfFile())
    exit(0)
case "preview":
    guard let path = arguments.dropFirst().first else {
        FileHandle.standardError.write(Data("usage: FellowshipDesktop preview <out.png>\n".utf8))
        exit(2)
    }
    exit(Preview.write(to: URL(fileURLWithPath: path)) ? 0 : 1)
default:
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.delegate = delegate
    app.run()
}
