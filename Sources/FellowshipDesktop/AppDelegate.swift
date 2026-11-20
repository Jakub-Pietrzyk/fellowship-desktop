import AppKit
import ServiceManagement

private enum Key {
    static let hero = "hero"
    static let edition = "edition"
    static let scale = "scale"
    static let sound = "sound"
    static let hidden = "hidden"
    static let originX = "originX"
    static let originY = "originY"
}

/// `edition` in the defaults: "random" draws a fresh edition at every launch, like a new agent in Herdr.
private let randomEdition = "random"

private final class SessionBox: NSObject {
    let record: SessionRecord
    init(_ record: SessionRecord) { self.record = record }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let defaults = UserDefaults.standard
    private let store = StatusStore.default
    private var window: NSPanel!
    private var petView: PetView!
    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?
    private var summary = Summary.empty
    private var drawnEdition: Edition = .normal

    private var hero: Hero {
        get { Hero(rawValue: defaults.string(forKey: Key.hero) ?? "") ?? .gandalf }
        set { defaults.set(newValue.rawValue, forKey: Key.hero) }
    }

    private var editionSetting: String {
        get { defaults.string(forKey: Key.edition) ?? randomEdition }
        set { defaults.set(newValue, forKey: Key.edition) }
    }

    private var edition: Edition {
        if editionSetting == randomEdition { return drawnEdition }
        let chosen = Edition(rawValue: editionSetting) ?? .normal
        return chosen.isAvailable(for: hero) ? chosen : .normal
    }

    private var scale: CGFloat {
        get { CGFloat(defaults.object(forKey: Key.scale) as? Double ?? 5) }
        set { defaults.set(Double(newValue), forKey: Key.scale) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        drawnEdition = Edition.draw(for: hero)
        petView = PetView(look: currentLook())
        petView.onClick = { [weak self] in self?.petClicked() }
        petView.onMoved = { [weak self] origin in
            self?.defaults.set(Double(origin.x), forKey: Key.originX)
            self?.defaults.set(Double(origin.y), forKey: Key.originY)
        }
        makeWindow()
        makeStatusItem()
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func makeWindow() {
        window = NSPanel(
            contentRect: NSRect(origin: savedOrigin() ?? defaultOrigin(), size: petView.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.contentView = petView
        if !defaults.bool(forKey: Key.hidden) { window.orderFrontRegardless() }
    }

    private func savedOrigin() -> NSPoint? {
        guard defaults.object(forKey: Key.originX) != nil else { return nil }
        let origin = NSPoint(x: defaults.double(forKey: Key.originX), y: defaults.double(forKey: Key.originY))
        let onScreen = NSScreen.screens.contains { $0.frame.insetBy(dx: -40, dy: -40).contains(origin) }
        return onScreen ? origin : nil
    }

    private func defaultOrigin() -> NSPoint {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: visible.maxX - PetView.width - 24, y: visible.minY + 24)
    }

    private func currentLook() -> PetLook {
        PetLook(hero: hero, edition: edition, state: summary.state, bubble: Bubble.text(for: summary), scale: scale)
    }

    private func refresh() {
        let next = store.summary()
        let previous = summary.state
        summary = next
        if next.state != previous && defaults.bool(forKey: Key.sound) {
            switch next.state {
            case .blocked: NSSound(named: "Funk")?.play()
            case .done: NSSound(named: "Glass")?.play()
            case .working, .idle: break
            }
        }
        applyLook()
    }

    private func applyLook() {
        let look = currentLook()
        petView.look = look
        if window.frame.size != petView.frame.size {
            window.setContentSize(petView.frame.size)
        }
        statusItem.button?.image = menuBarImage()
    }

    /// Waiting or finished: the click takes the person to that session (the latest one, if several); finished
    /// sessions then go back to rest.
    private func petClicked() {
        guard summary.state == .done || summary.state == .blocked else { return }
        if let session = summary.sessions.first { Jump.plan(for: session).perform() }
        if summary.state == .done {
            store.acknowledgeDone()
            refresh()
        }
    }

    // MARK: - Menu bar

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = menuBarImage()
        statusItem.button?.toolTip = "Fellowship Desktop"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func menuBarImage() -> NSImage {
        let pose = Pose.of(hero: hero, edition: edition, state: summary.state)
        let sprite = SpriteLibrary.shared.sprite(named: pose.frames[0])
        let side: CGFloat = 18
        return NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            NSGraphicsContext.current?.shouldAntialias = false
            sprite?.draw(at: .zero, scale: side / CGFloat(Sprite.gridSize))
            return true
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: Bubble.menuLine(for: summary), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        for session in summary.all.prefix(8) {
            let line = NSMenuItem(title: "   \(Bubble.menuEntry(for: session))", action: #selector(jumpToSession(_:)), keyEquivalent: "")
            line.target = self
            line.representedObject = SessionBox(session)
            if Jump.plan(for: session) == .none { line.action = nil }
            menu.addItem(line)
        }
        menu.addItem(.separator())

        let heroMenu = NSMenu()
        for candidate in Hero.allCases {
            let item = NSMenuItem(title: candidate.displayName, action: #selector(pickHero(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = candidate.rawValue
            item.state = candidate == hero ? .on : .off
            heroMenu.addItem(item)
        }
        menu.addItem(submenu("Postać", heroMenu))

        let editionMenu = NSMenu()
        let editions: [(String, String)] = [
            (randomEdition, "Losowa przy starcie (10% rzadka)"),
            (Edition.normal.rawValue, "Zwykła"),
            (Edition.rare.rawValue, "Rzadka: \(hero.rareName)"),
            (Edition.sax.rawValue, "Epic Sax Gandalf"),
        ]
        for (value, title) in editions {
            let item = NSMenuItem(title: title, action: #selector(pickEdition(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = value == editionSetting ? .on : .off
            if value == Edition.sax.rawValue && hero != .gandalf { item.action = nil }
            editionMenu.addItem(item)
        }
        menu.addItem(submenu("Edycja", editionMenu))

        let sizeMenu = NSMenu()
        for (value, title) in [(3.0, "Mała"), (5.0, "Średnia"), (7.0, "Duża")] {
            let item = NSMenuItem(title: title, action: #selector(pickScale(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = CGFloat(value) == scale ? .on : .off
            sizeMenu.addItem(item)
        }
        menu.addItem(submenu("Rozmiar", sizeMenu))

        menu.addItem(toggle("Dźwięk, gdy czeka lub skończy", on: defaults.bool(forKey: Key.sound), action: #selector(toggleSound)))
        menu.addItem(toggle("Uruchamiaj przy logowaniu", on: SMAppService.mainApp.status == .enabled, action: #selector(toggleLoginItem)))
        menu.addItem(.separator())

        let visibility = NSMenuItem(title: window.isVisible ? "Ukryj postać" : "Pokaż postać", action: #selector(toggleVisible), keyEquivalent: "h")
        visibility.target = self
        menu.addItem(visibility)
        let reset = NSMenuItem(title: "Przywróć w prawy dolny róg", action: #selector(resetPosition), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Zakończ", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func toggle(_ title: String, on: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    @objc private func jumpToSession(_ sender: NSMenuItem) {
        guard let session = (sender.representedObject as? SessionBox)?.record else { return }
        Jump.plan(for: session).perform()
    }

    @objc private func pickHero(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let picked = Hero(rawValue: raw) else { return }
        hero = picked
        drawnEdition = Edition.draw(for: picked)
        applyLook()
    }

    @objc private func pickEdition(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        editionSetting = value
        if value == randomEdition { drawnEdition = Edition.draw(for: hero) }
        applyLook()
    }

    @objc private func pickScale(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        let oldTop = window.frame.maxY
        scale = CGFloat(value)
        applyLook()
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: oldTop - window.frame.height))
    }

    @objc private func toggleSound() {
        defaults.set(!defaults.bool(forKey: Key.sound), forKey: Key.sound)
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Nie udało się zmienić uruchamiania przy logowaniu"
            alert.informativeText = "\(error.localizedDescription)\n\nMożesz dodać aplikację ręcznie: Ustawienia systemowe → Ogólne → Rzeczy otwierane podczas logowania."
            alert.runModal()
        }
    }

    @objc private func toggleVisible() {
        if window.isVisible {
            window.orderOut(nil)
            defaults.set(true, forKey: Key.hidden)
        } else {
            window.orderFrontRegardless()
            defaults.set(false, forKey: Key.hidden)
        }
    }

    @objc private func resetPosition() {
        window.setFrameOrigin(defaultOrigin())
        defaults.removeObject(forKey: Key.originX)
        defaults.removeObject(forKey: Key.originY)
        if !window.isVisible { toggleVisible() }
    }
}
