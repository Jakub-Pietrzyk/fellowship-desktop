import AppKit

/// What the pet looks like at one moment; the view only draws it.
struct PetLook: Equatable {
    var hero: Hero
    var edition: Edition
    var state: PetState
    var bubble: String?
    var scale: CGFloat
}

final class PetView: NSView {
    static let bubbleHeight: CGFloat = 34
    static let hopHeight: CGFloat = 10
    static let width: CGFloat = 240

    var look: PetLook { didSet { if look != oldValue { lookChanged(from: oldValue) } } }
    var onClick: (() -> Void)?
    var onMoved: ((NSPoint) -> Void)?

    private var frameIndex = 0
    private var frameTimer: Timer?
    private var hopStart: Date?
    private var hopTimer: Timer?
    private var dragStart: NSPoint?
    private var windowStart: NSPoint?
    private var dragged = false

    override var isFlipped: Bool { true }

    init(look: PetLook) {
        self.look = look
        super.init(frame: NSRect(origin: .zero, size: PetView.size(scale: look.scale)))
        restartFrames()
    }

    required init?(coder: NSCoder) { fatalError() }

    static func size(scale: CGFloat) -> NSSize {
        NSSize(width: width, height: bubbleHeight + hopHeight + CGFloat(Sprite.gridSize) * scale)
    }

    private var spriteSide: CGFloat { CGFloat(Sprite.gridSize) * look.scale }

    private var spriteRect: NSRect {
        NSRect(x: (bounds.width - spriteSide) / 2, y: bounds.height - spriteSide, width: spriteSide, height: spriteSide)
    }

    private func lookChanged(from old: PetLook) {
        if look.scale != old.scale { setFrameSize(Self.size(scale: look.scale)) }
        if look.state != old.state || look.hero != old.hero || look.edition != old.edition { restartFrames() }
        if look.state != old.state && (look.state == .blocked || look.state == .done) { hop() }
        updateToolTip()
        needsDisplay = true
    }

    private func restartFrames() {
        frameTimer?.invalidate()
        frameIndex = 0
        let pose = Pose.of(hero: look.hero, edition: look.edition, state: look.state)
        guard pose.frames.count > 1 else { return }
        frameTimer = Timer.scheduledTimer(withTimeInterval: pose.frameDuration, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.frameIndex = (self.frameIndex + 1) % pose.frames.count
            self.needsDisplay = true
        }
    }

    private func hop() {
        hopStart = Date()
        hopTimer?.invalidate()
        hopTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self, let start = self.hopStart else { return timer.invalidate() }
            if Date().timeIntervalSince(start) > 0.9 {
                self.hopStart = nil
                timer.invalidate()
            }
            self.needsDisplay = true
        }
    }

    private var hopOffset: CGFloat {
        guard let start = hopStart else { return 0 }
        let t = Date().timeIntervalSince(start)
        return -abs(sin(t * .pi * 2 / 0.45)) * Self.hopHeight
    }

    private func updateToolTip() {
        toolTip = look.edition == .rare ? look.hero.rareName : look.edition == .sax ? "Epic Sax Gandalf" : look.hero.displayName
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        NSGraphicsContext.current?.shouldAntialias = false
        let pose = Pose.of(hero: look.hero, edition: look.edition, state: look.state)
        let name = pose.frames[frameIndex % pose.frames.count]
        let rect = spriteRect.offsetBy(dx: 0, dy: hopOffset)
        SpriteLibrary.shared.sprite(named: name)?.draw(at: rect.origin, scale: look.scale)
        NSGraphicsContext.current?.shouldAntialias = true
        if let bubble = look.bubble { drawBubble(bubble, above: rect) }
    }

    private func drawBubble(_ text: String, above sprite: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor(srgbRed: 0.17, green: 0.12, blue: 0.09, alpha: 1),
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let maxTextWidth = bounds.width - 24
        var textSize = string.boundingRect(with: NSSize(width: maxTextWidth, height: 40), options: .usesLineFragmentOrigin).size
        textSize.width = min(ceil(textSize.width), maxTextWidth)
        textSize.height = ceil(textSize.height)
        let box = NSRect(
            x: (bounds.width - textSize.width) / 2 - 9,
            y: max(0, sprite.minY - textSize.height - 16),
            width: textSize.width + 18,
            height: textSize.height + 8
        )
        let path = NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: bounds.midX - 5, y: box.maxY - 0.5))
        tail.line(to: NSPoint(x: bounds.midX, y: box.maxY + 6))
        tail.line(to: NSPoint(x: bounds.midX + 5, y: box.maxY - 0.5))
        tail.close()
        let parchment = NSColor(srgbRed: 0.97, green: 0.93, blue: 0.82, alpha: 0.97)
        let ink = look.state == .blocked
            ? NSColor(srgbRed: 0.70, green: 0.22, blue: 0.16, alpha: 1)
            : NSColor(srgbRed: 0.33, green: 0.50, blue: 0.24, alpha: 1)
        parchment.setFill()
        path.fill()
        tail.fill()
        ink.setStroke()
        path.lineWidth = 1.5
        path.stroke()
        string.draw(with: NSRect(x: box.minX + 9, y: box.minY + 4, width: textSize.width, height: textSize.height),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    /// Clicks only land on the figure itself; the rest of the window lets them through to what is beneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return spriteRect.insetBy(dx: look.scale * 3, dy: 0).contains(local) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let windowStart, let window else { return }
        let now = NSEvent.mouseLocation
        let delta = NSPoint(x: now.x - dragStart.x, y: now.y - dragStart.y)
        if abs(delta.x) + abs(delta.y) > 3 { dragged = true }
        window.setFrameOrigin(NSPoint(x: windowStart.x + delta.x, y: windowStart.y + delta.y))
    }

    override func mouseUp(with event: NSEvent) {
        if dragged, let origin = window?.frame.origin { onMoved?(origin) } else { onClick?() }
        dragStart = nil
    }

    /// The pet drawn off screen, for the README preview and for checking the art without a display.
    static func snapshot(of look: PetLook) -> NSImage {
        let view = PetView(look: look)
        view.frameTimer?.invalidate()
        return NSImage(size: view.bounds.size, flipped: true) { _ in
            view.draw(view.bounds)
            return true
        }
    }
}
