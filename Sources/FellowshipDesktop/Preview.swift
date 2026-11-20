import AppKit

/// `FellowshipDesktop preview <out.png>`: the whole cast and Gandalf's states on one sheet.
enum Preview {
    static func write(to url: URL) -> Bool {
        let scale: CGFloat = 4
        let cast = Hero.allCases.map { PetLook(hero: $0, edition: .normal, state: .idle, bubble: nil, scale: scale) }
        let states: [PetLook] = [
            PetLook(hero: .gandalf, edition: .normal, state: .working, bubble: nil, scale: scale),
            PetLook(hero: .gandalf, edition: .normal, state: .blocked, bubble: "bodyvibes_mobile: czekam na Twoją zgodę", scale: scale),
            PetLook(hero: .gandalf, edition: .normal, state: .done, bubble: "bodyvibes_mobile: gotowe!", scale: scale),
            PetLook(hero: .gandalf, edition: .rare, state: .idle, bubble: nil, scale: scale),
            PetLook(hero: .gandalf, edition: .sax, state: .idle, bubble: nil, scale: scale),
        ]
        let rows = [cast, states].map { $0.map { PetView.snapshot(of: $0) } }
        return write(rows: rows, cell: PetView.size(scale: scale), cropTop: PetView.trickRoom, to: url)
    }

    /// `FellowshipDesktop tricks <dir>`: one sheet per hero, a row per trick, the trick at five moments.
    static func writeTricks(to directory: URL) -> Bool {
        let scale: CGFloat = 5
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var ok = true
        for hero in Hero.allCases {
            let editions: [Edition] = hero == .gandalf ? [.normal, .sax] : [.normal]
            var rows: [[NSImage]] = []
            for edition in editions {
                let look = PetLook(hero: hero, edition: edition, state: .idle, bubble: nil, scale: scale)
                let stage = Stage(sprite: SpriteLibrary.shared.sprite(named: Pose.of(hero: hero, edition: edition, state: .idle).frames[0]))
                for trick in Tricks.all(for: hero, edition: edition, stage: stage) where edition == .normal || trick.id == "sax-solo" {
                    rows.append([0.1, 0.3, 0.5, 0.7, 0.9].map { PetView.snapshot(of: look, trick: trick, at: trick.duration * $0) })
                }
            }
            ok = write(rows: rows, cell: PetView.size(scale: scale), cropTop: 0, to: directory.appendingPathComponent("\(hero.rawValue).png")) && ok
        }
        return ok
    }

    private static func write(rows: [[NSImage]], cell: NSSize, cropTop: CGFloat, to url: URL) -> Bool {
        let columnWidth = cell.width
        let columns = CGFloat(rows.map(\.count).max() ?? 1)
        let rowHeight = cell.height - cropTop
        let size = NSSize(width: columnWidth * columns + 40, height: rowHeight * CGFloat(rows.count) + 40)

        let pixelScale = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width) * pixelScale, pixelsHigh: Int(size.height) * pixelScale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return false }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixelScale), y: CGFloat(pixelScale))
        NSColor(srgbRed: 0.95, green: 0.91, blue: 0.82, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        for (r, row) in rows.enumerated() {
            for (c, image) in row.enumerated() {
                let x = 20 + CGFloat(c) * columnWidth
                let y = size.height - 20 - CGFloat(r + 1) * rowHeight
                image.draw(in: NSRect(x: x, y: y, width: cell.width, height: rowHeight),
                           from: NSRect(x: 0, y: 0, width: cell.width, height: rowHeight), operation: .sourceOver, fraction: 1)
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }
}
