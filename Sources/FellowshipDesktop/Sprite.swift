import AppKit

/// A 24×24 pixel-art sprite from `Sprites/`: the SVGs are nothing but `<rect>`s, so they are read
/// straight into pixel runs and drawn with crisp edges at any scale.
struct Sprite {
    struct Run {
        let x: Int, y: Int, width: Int, height: Int
        let color: NSColor
    }

    static let gridSize = 24

    let runs: [Run]

    private static let rectPattern = try! NSRegularExpression(
        pattern: ##"<rect x="(\d+)" y="(\d+)" width="(\d+)" height="(\d+)" fill="#([0-9a-fA-F]{6})"/>"##
    )

    init?(svg: String) {
        let range = NSRange(svg.startIndex..., in: svg)
        var runs: [Run] = []
        for match in Sprite.rectPattern.matches(in: svg, range: range) {
            func int(_ i: Int) -> Int { Int(svg[Range(match.range(at: i), in: svg)!])! }
            let hex = UInt32(svg[Range(match.range(at: 5), in: svg)!], radix: 16)!
            runs.append(Run(
                x: int(1), y: int(2), width: int(3), height: int(4),
                color: NSColor(
                    srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                    green: CGFloat((hex >> 8) & 0xff) / 255,
                    blue: CGFloat(hex & 0xff) / 255,
                    alpha: 1
                )
            ))
        }
        guard !runs.isEmpty else { return nil }
        self.runs = runs
    }

    /// Draws into a flipped context with the sprite's top-left corner at `origin`.
    func draw(at origin: CGPoint, scale: CGFloat) {
        for run in runs {
            run.color.setFill()
            NSRect(
                x: origin.x + CGFloat(run.x) * scale,
                y: origin.y + CGFloat(run.y) * scale,
                width: CGFloat(run.width) * scale,
                height: CGFloat(run.height) * scale
            ).fill()
        }
    }
}

final class SpriteLibrary {
    static let shared = SpriteLibrary()

    private var cache: [String: Sprite] = [:]
    let directory: URL?

    init(directory: URL? = SpriteLibrary.locateDirectory()) {
        self.directory = directory
    }

    func sprite(named name: String) -> Sprite? {
        if let cached = cache[name] { return cached }
        guard let url = directory?.appendingPathComponent("\(name).svg"),
              let svg = try? String(contentsOf: url, encoding: .utf8),
              let sprite = Sprite(svg: svg) else { return nil }
        cache[name] = sprite
        return sprite
    }

    /// Inside the .app the sprites sit in Resources; `swift run` from the repo finds `Sprites/`.
    static func locateDirectory() -> URL? {
        let candidates = [
            ProcessInfo.processInfo.environment["FELLOWSHIP_SPRITES"].map { URL(fileURLWithPath: $0) },
            Bundle.main.resourceURL?.appendingPathComponent("sprites"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sprites"),
        ].compactMap { $0 }
        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("gandalf.svg").path) }
    }
}
