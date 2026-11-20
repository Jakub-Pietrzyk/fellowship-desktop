import Foundation

/// One square drawn around the figure during a trick, in sprite pixels: (0, 0) is the sprite's top-left corner at
/// rest, y grows downwards and the feet stand on y = 24. Positions snap to whole pixels when drawn.
struct Speck: Equatable {
    var x: Double
    var y: Double
    var w: Double = 1
    var h: Double = 1
    var color: UInt32
    var alpha: Double = 1
}

enum TrickPose: Equatable {
    case current, idle, work, blocked, done
}

/// Where the figure is and what is around it at one moment of a trick. The default is the figure at rest.
struct TrickFrame: Equatable {
    var pose: TrickPose = .current
    var dx = 0.0
    var dy = 0.0
    /// Degrees, clockwise, around the sprite's centre.
    var rotation = 0.0
    var flipped = false
    /// Vertical scale around the feet; the width follows the other way, so a squash looks heavier, not smaller.
    var stretch = 1.0
    var alpha = 1.0
    var behind: [Speck] = []
    var front: [Speck] = []
    var bubble: String?
}

/// A short animation played when the figure is clicked while Claude works or rests.
struct Trick {
    let id: String
    let title: String
    let duration: TimeInterval
    let frame: (TimeInterval) -> TrickFrame

    /// The last quarter of a second eases the figure back to rest, so a trick never ends on a jump cut.
    init(id: String, title: String, duration: TimeInterval, frame raw: @escaping (TimeInterval) -> TrickFrame) {
        self.id = id
        self.title = title
        self.duration = duration
        frame = { t in
            var f = raw(t)
            let settle = phase(t, duration - 0.25, duration)
            guard settle > 0 else { return f }
            let keep = 1 - settle
            var turn = f.rotation.truncatingRemainder(dividingBy: 360)
            if turn > 180 { turn -= 360 }
            if turn < -180 { turn += 360 }
            f.dx *= keep
            f.dy *= keep
            f.rotation = turn * keep
            f.stretch = 1 + (f.stretch - 1) * keep
            f.alpha += (1 - f.alpha) * settle
            if settle >= 1 { f.flipped = false }
            return f
        }
    }
}

/// What a trick needs to know about the drawn figure.
struct Stage: Equatable {
    /// The highest row the sprite paints, so props land on the head of a hobbit and of a wizard alike.
    var headTop: Double

    static let standard = Stage(headTop: 2)

    init(headTop: Double) { self.headTop = headTop }

    init(sprite: Sprite?) {
        headTop = Double(sprite?.runs.map(\.y).min() ?? 2)
    }
}

enum Tricks {
    static func all(for hero: Hero, edition: Edition, stage: Stage = .standard) -> [Trick] {
        let s = stage
        switch hero {
        case .gandalf:
            let pipe = edition == .sax ? saxSolo() : smokeRings()
            return [fireworks(), youShallNotPass(), pipe, neverLate(s)]
        case .frodo: return [theRing(s), underhill(), stingGlows(), lorienLeaves()]
        case .sam: return [potatoes(s), gardener(), fryingPan(), carryYou()]
        case .aragorn: return [forFrodo(), anduril(), kingReturns(s), athelas()]
        case .legolas: return [arrows(), shieldSurf(), elfEyes(s), backflip()]
        case .gimli: return [dwarfToss(), axe(), ale(), stomp()]
        case .sauron: return [eyeAflame(), oneRing(), darkness(), wrath()]
        }
    }

    /// Any trick but the one just played, so a second click always shows something new.
    static func pick(for hero: Hero, edition: Edition, stage: Stage = .standard, after previous: String?,
                     random: (Int) -> Int = { Int.random(in: 0..<$0) }) -> Trick {
        let tricks = all(for: hero, edition: edition, stage: stage)
        let fresh = tricks.filter { $0.id != previous }
        let pool = fresh.isEmpty ? tricks : fresh
        return pool[random(pool.count)]
    }

    // MARK: Gandalf

    static func fireworks() -> Trick {
        Trick(id: "fireworks", title: "Fajerwerki", duration: 2.4) { t in
            var f = TrickFrame(pose: .done)
            if t < 0.45 {
                let p = t / 0.45
                f.front = [
                    Speck(x: 18, y: 1 - 9 * p, h: 2, color: Palette.yellow),
                    Speck(x: 18, y: 3 - 9 * p, color: Palette.orange, alpha: 0.7),
                    Speck(x: 18, y: 4 - 9 * p, color: Palette.red, alpha: 0.4),
                ]
            }
            f.front += burst(t, at: 0.45, x: 18, y: -8, count: 14, reach: 6, life: 0.9, colors: [Palette.yellow, Palette.magenta, Palette.white])
            f.front += burst(t, at: 0.8, x: 4, y: -5, count: 12, reach: 5, life: 0.9, colors: [Palette.red, Palette.orange, Palette.yellow])
            f.front += burst(t, at: 1.15, x: 11, y: -10, count: 16, reach: 7, life: 1.0, colors: [Palette.lightBlue, Palette.green, Palette.white])
            f.dy = hop(t, 0.45, 0.75, 1.5) + hop(t, 1.15, 1.45, 1.5)
            if t > 1.6 { f.bubble = "Fajerwerki!" }
            return f
        }
    }

    static func youShallNotPass() -> Trick {
        Trick(id: "shall-not-pass", title: "Nie przejdziesz!", duration: 2.2) { t in
            var f = TrickFrame(pose: .blocked)
            if t < 0.35 {
                f.dy = -2 * phase(t, 0, 0.35)
                f.stretch = 1 + 0.08 * phase(t, 0, 0.35)
            } else {
                f.dx = wobble(t, t < 0.8 ? 0.8 : 0)
                let crack = 12 * easeOut(phase(t, 0.35, 0.7))
                let fade = 1 - phase(t, 1.6, 2.2)
                for i in stride(from: 0.0, to: crack, by: 1) {
                    let zig = Int(i) % 3 == 0 ? 1.0 : 0
                    f.behind.append(Speck(x: 12 + i, y: 23 - zig, color: Palette.ink, alpha: fade))
                    f.behind.append(Speck(x: 11 - i, y: 23 - zig, color: Palette.ink, alpha: fade))
                }
                f.front += burst(t, at: 0.35, x: 12, y: 18, count: 16, reach: 9, life: 0.7, colors: [Palette.white, Palette.lightBlue], gravity: 0)
                    .filter { $0.y <= 23.5 }
                f.bubble = "Nie przejdziesz!"
            }
            return f
        }
    }

    static func smokeRings() -> Trick {
        Trick(id: "smoke-rings", title: "Kółka z dymu", duration: 2.6) { t in
            var f = TrickFrame(pose: .idle)
            for start in [0.0, 0.45, 0.9] {
                let p = (t - start) / 1.5
                guard p >= 0, p < 1 else { continue }
                let size = 2 + 4 * p
                let x = 4 - 6 * p - size / 2
                let y = 10 - 16 * p - size / 2
                f.front += hollowSquare(x: x, y: y, size: size, color: Palette.smoke, alpha: 1 - p)
            }
            f.stretch = 1 + 0.03 * sin(t * 6)
            if t > 1.5 { f.bubble = "Pyk, pyk…" }
            return f
        }
    }

    static func saxSolo() -> Trick {
        Trick(id: "sax-solo", title: "Epic Sax", duration: 2.4) { t in
            var f = TrickFrame(pose: .work)
            f.dy = -abs(sin(t * .pi * 4)) * 1.5
            f.rotation = sin(t * .pi * 4) * 6
            for (i, start) in [0.0, 0.35, 0.7, 1.05, 1.4].enumerated() {
                let p = (t - start) / 1.0
                guard p >= 0, p < 1 else { continue }
                let x = (i.isMultiple(of: 2) ? 20 : 2) + sin(p * 6) * 2
                f.front += shape(Art.note, x: x, y: 10 - 14 * p, alpha: 1 - p * p)
            }
            if t > 1.2 { f.bubble = "Epic sax!" }
            return f
        }
    }

    static func neverLate(_ stage: Stage) -> Trick {
        Trick(id: "never-late", title: "Czarodziej się nie spóźnia", duration: 2.6) { t in
            var f = TrickFrame(pose: .done)
            if t < 0.72 { f.flipped = Int(t / 0.12).isMultiple(of: 2) == false }
            f.dy = hop(t, 0.72, 1.12, 5)
            f.stretch = t > 1.12 && t < 1.3 ? 0.88 : 1
            f.front += sparkles(t, at: 1.12, around: stage, life: 0.8)
            if t > 1.0 { f.bubble = "Czarodziej nigdy się nie spóźnia." }
            return f
        }
    }

    // MARK: Frodo

    static func theRing(_ stage: Stage) -> Trick {
        Trick(id: "the-ring", title: "Pierścień", duration: 3.0) { t in
            var f = TrickFrame(pose: .idle)
            if t < 0.6 {
                let p = t / 0.6
                f.front = shape(Art.ring, x: 10, y: 14 - 22 * p * (1 - p) * 2 - 4 * p, alpha: 1)
            }
            let vanish = phase(t, 0.6, 0.85) - phase(t, 2.1, 2.4)
            f.alpha = 1 - 0.88 * vanish
            if t > 0.85 && t < 2.1 {
                let pulse = 0.6 + 0.4 * sin(t * 10)
                f.front += shape(Art.eye, x: 8.5, y: stage.headTop - 8, alpha: pulse * phase(t, 0.85, 1.1))
            }
            if t > 2.3 { f.bubble = "Lepiej go zdejmę…" }
            return f
        }
    }

    static func underhill() -> Trick {
        Trick(id: "underhill", title: "Nazywam się Underhill", duration: 2.2) { t in
            var f = TrickFrame(pose: .work)
            let beat = 0.45
            f.dy = hop(t.truncatingRemainder(dividingBy: beat), 0, beat, 3) * (t < 1.8 ? 1 : 0)
            f.flipped = Int(t / beat).isMultiple(of: 2) == false && t < 1.8
            for (i, start) in [0.1, 0.55, 1.0].enumerated() {
                let p = (t - start) / 1.1
                guard p >= 0, p < 1 else { continue }
                f.front += shape(Art.note, x: i == 1 ? 21 : 0, y: 8 - 12 * p, alpha: 1 - p)
            }
            f.bubble = "Nazywam się Underhill!"
            return f
        }
    }

    static func stingGlows() -> Trick {
        Trick(id: "sting", title: "Żądło świeci", duration: 2.4) { t in
            var f = TrickFrame(pose: .blocked)
            f.dx = wobble(t, 0.4, 7)
            let glow = 0.55 + 0.45 * sin(t * 9)
            for i in 0..<14 {
                let angle = Double(i) / 14 * 2 * .pi + t * 1.5
                let radius = 13 + sin(t * 5 + Double(i)) * 1.5
                f.behind.append(Speck(x: 12 + cos(angle) * radius, y: 11 + sin(angle) * radius * 0.75,
                                      color: i.isMultiple(of: 3) ? Palette.white : Palette.lightBlue, alpha: glow * phase(t, 0, 0.3)))
            }
            f.bubble = "Żądło świeci… orkowie!"
            return f
        }
    }

    static func lorienLeaves() -> Trick {
        Trick(id: "lorien", title: "Liście Lórien", duration: 2.8) { t in
            var f = TrickFrame(pose: .idle)
            let leaves: [(x: Double, start: Double)] = [(-2, 0), (8, 0.25), (19, 0.1), (26, 0.5), (3, 0.8), (14, 0.95), (22, 1.2)]
            for leaf in leaves {
                let p = (t - leaf.start) / 1.5
                guard p >= 0, p < 1 else { continue }
                let x = leaf.x + sin(p * 9 + leaf.x) * 2.5
                f.front += shape(Art.leaf, x: x, y: -10 + 31 * p, alpha: 1 - phase(p, 0.8, 1))
            }
            f.stretch = 1 + 0.03 * sin(t * 4)
            if t > 1.2 { f.bubble = "Liście Lórien…" }
            return f
        }
    }

    // MARK: Sam

    static func potatoes(_ stage: Stage) -> Trick {
        Trick(id: "potatoes", title: "Ziemniaki", duration: 2.6) { t in
            var f = TrickFrame(pose: .done)
            let period = 0.9
            for i in 0..<3 {
                let local = t - Double(i) * period / 3
                guard local >= 0, t < 2.2 else { continue }
                let p = local.truncatingRemainder(dividingBy: period) / period
                let leftToRight = Int(local / period).isMultiple(of: 2)
                let x = leftToRight ? 4 + 14 * p : 18 - 14 * p
                let top = stage.headTop - 5
                let y = 12 - (12 - top) * 4 * p * (1 - p)
                f.front += shape(Art.potato, x: x, y: y, alpha: 1)
            }
            f.dy = -abs(sin(t * .pi / 0.45)) * 0.8
            if t > 2.2 { f.bubble = "Ziem-nia-ki!" }
            return f
        }
    }

    static func gardener() -> Trick {
        Trick(id: "gardener", title: "Ogrodnik", duration: 2.8) { t in
            var f = TrickFrame(pose: .idle)
            let flowers: [(x: Double, start: Double, head: [String])] = [
                (-3, 0.1, Art.flowerPink), (0, 0.5, Art.flowerYellow), (24, 0.3, Art.flowerYellow), (27, 0.8, Art.flowerPink),
            ]
            for flower in flowers {
                let grow = easeOut(phase(t, flower.start, flower.start + 0.7))
                guard grow > 0 else { continue }
                let height = 2 + 5 * grow
                f.behind.append(Speck(x: flower.x + 1, y: 24 - height, h: height, color: Palette.darkGreen))
                f.behind.append(Speck(x: flower.x + 2, y: 23 - height * 0.5, color: Palette.green))
                if grow > 0.6 { f.behind += shape(flower.head, x: flower.x, y: 22 - height, alpha: phase(grow, 0.6, 1)) }
            }
            f.stretch = 1 - 0.05 * abs(sin(t * 6))
            if t > 1.0 { f.bubble = "Trochę ziemi z Shire." }
            return f
        }
    }

    static func fryingPan() -> Trick {
        Trick(id: "frying-pan", title: "Patelnia", duration: 2.0) { t in
            var f = TrickFrame(pose: .blocked)
            let swing = easeIn(phase(t, 0.15, 0.55))
            let angle = -.pi * 0.9 + swing * .pi * 0.9
            if t < 1.1 {
                f.front = shape(Art.pan, x: 13 + cos(angle) * 9 - 4, y: 12 + sin(angle) * 11 - 2, alpha: 1)
            }
            f.front += burst(t, at: 0.55, x: 22, y: 12, count: 8, reach: 5, life: 0.5, colors: [Palette.yellow, Palette.white], gravity: 0)
            if t > 0.55 && t < 0.9 { f.dx = wobble(t, 0.8) }
            f.rotation = 8 * swing * (1 - phase(t, 0.6, 1.0))
            f.bubble = t < 0.55 ? nil : t < 1.2 ? "BONK!" : "Coraz lepiej mi idzie!"
            return f
        }
    }

    static func carryYou() -> Trick {
        Trick(id: "carry-you", title: "Mogę Cię nieść", duration: 2.6) { t in
            var f = TrickFrame(pose: .idle)
            f.stretch = 0.9 + 0.04 * sin(t * 8)
            f.dx = sin(t * .pi / 2.6 * 2) * 4
            f.flipped = cos(t * .pi / 2.6 * 2) < 0
            for start in [0.3, 1.0, 1.7] {
                let p = (t - start) / 0.6
                guard p >= 0, p < 1 else { continue }
                f.front += shape(Art.drop, x: 4 + f.dx + start * 4, y: 4 + 6 * p, alpha: 1 - p)
            }
            f.bubble = "Ciebie mogę nieść!"
            return f
        }
    }

    // MARK: Aragorn

    static func forFrodo() -> Trick {
        Trick(id: "for-frodo", title: "Za Frodo!", duration: 2.0) { t in
            var f = TrickFrame(pose: .work)
            let out = easeInOut(phase(t, 0.1, 0.8))
            let back = easeInOut(phase(t, 1.0, 1.7))
            f.dx = 9 * out - 9 * back
            f.flipped = t > 0.9 && t < 1.75
            f.dy = -abs(sin(t * .pi / 0.2)) * (t < 1.75 ? 1 : 0)
            for i in 0..<4 {
                let p = ((t + Double(i) * 0.12).truncatingRemainder(dividingBy: 0.5)) / 0.5
                guard t < 1.75 else { break }
                let behindX = f.flipped ? f.dx + 18 + p * 4 : f.dx + 6 - p * 4
                f.behind.append(Speck(x: behindX, y: 23 - p * 2, color: Palette.dust, alpha: 1 - p))
            }
            f.bubble = "Za Frodo!"
            return f
        }
    }

    static func anduril() -> Trick {
        Trick(id: "anduril", title: "Andúril", duration: 2.2) { t in
            var f = TrickFrame(pose: .done)
            let sweep = phase(t, 0.2, 0.55)
            if sweep > 0 && sweep < 1 {
                for i in 0..<7 {
                    let k = Double(i)
                    let angle = .pi * (0.95 - sweep * 0.9) + k * 0.09
                    f.front.append(Speck(x: 12 + cos(angle) * 14, y: 14 - sin(angle) * 14, w: 2, h: 2,
                                         color: i < 2 ? Palette.white : Palette.lightBlue, alpha: 1 - k * 0.13))
                }
            }
            f.front += burst(t, at: 0.55, x: 24, y: 10, count: 10, reach: 4, life: 0.6, colors: [Palette.white, Palette.yellow], gravity: 0)
            f.dy = hop(t, 0.5, 0.8, 1.5)
            if t > 0.6 { f.bubble = "Andúril, Płomień Zachodu!" }
            return f
        }
    }

    static func kingReturns(_ stage: Stage) -> Trick {
        Trick(id: "king-returns", title: "Król powraca", duration: 2.8) { t in
            var f = TrickFrame(pose: .idle)
            let rest = stage.headTop - 4
            let drop = easeOut(phase(t, 0.1, 1.0))
            let fade = 1 - phase(t, 2.4, 2.8)
            f.front = shape(Art.crown, x: 9.5, y: rest - 10 * (1 - drop), alpha: fade)
            f.front += sparkles(t, at: 1.0, around: stage, life: 0.9)
            f.stretch = t > 1.0 && t < 1.15 ? 0.95 : 1
            if t > 1.1 { f.bubble = "Król powraca." }
            return f
        }
    }

    static func athelas() -> Trick {
        Trick(id: "athelas", title: "Athelas", duration: 2.6) { t in
            var f = TrickFrame(pose: .done)
            for (i, start) in [0.0, 0.3, 0.6, 0.9, 1.2].enumerated() {
                let p = (t - start) / 1.2
                guard p >= 0, p < 1 else { continue }
                let x = 6 + Double(i * 3) + sin(p * 7 + Double(i)) * 2
                f.front += shape(Art.herb, x: x, y: 16 - 18 * p, alpha: 1 - p * p)
            }
            let glow = (1 - phase(t, 2.0, 2.6)) * phase(t, 0, 0.4)
            for i in 0..<10 {
                let angle = Double(i) / 10 * 2 * .pi + t * 0.8
                f.behind.append(Speck(x: 12 + cos(angle) * 13, y: 13 + sin(angle) * 11,
                                      color: i.isMultiple(of: 2) ? Palette.green : Palette.foam, alpha: glow * (0.5 + 0.5 * sin(t * 6 + Double(i)))))
            }
            if t > 0.8 { f.bubble = "Athelas, ziele królów." }
            return f
        }
    }

    // MARK: Legolas

    static func arrows() -> Trick {
        Trick(id: "arrows", title: "Strzały", duration: 2.2) { t in
            var f = TrickFrame(pose: .done)
            for start in [0.15, 0.5, 0.85] {
                let p = (t - start) / 0.45
                guard p >= 0, p < 1 else { continue }
                f.front += shape(Art.arrow, x: 16 + p * 26, y: 11 - p * 3, alpha: 1)
                if p < 0.3 { f.dx = -0.7 }
            }
            if t > 1.3 { f.bubble = "Mam już czterdzieści dwa!" }
            return f
        }
    }

    static func shieldSurf() -> Trick {
        Trick(id: "shield-surf", title: "Na tarczy", duration: 2.2) { t in
            var f = TrickFrame(pose: .blocked)
            let ride = phase(t, 0.1, 1.9)
            let lift = t > 0.1 && t < 1.9 ? 2.0 : 0
            f.dx = -9 + 18 * ride
            if t < 0.1 || t > 1.9 { f.dx = 0 }
            f.dy = -lift + sin(t * 14) * 0.6 * (lift > 0 ? 1 : 0)
            f.rotation = lift > 0 ? -12 + sin(t * 14) * 3 : 0
            if lift > 0 {
                f.front = shape(Art.shield, x: f.dx + 7, y: 22 + f.dy * 0.2, alpha: 1)
                for i in 0..<5 {
                    let k = Double(i)
                    f.behind.append(Speck(x: f.dx + 6 - k * 2, y: 23 - k * 0.6, color: Palette.dust, alpha: 0.8 - k * 0.15))
                }
            }
            f.bubble = "Juhuu!"
            return f
        }
    }

    static func elfEyes(_ stage: Stage) -> Trick {
        Trick(id: "elf-eyes", title: "Elfi wzrok", duration: 2.6) { t in
            var f = TrickFrame(pose: .idle)
            f.flipped = t > 0.5 && t < 1.2
            f.stretch = t > 0.2 && t < 1.8 ? 1.04 : 1
            let twinkle = t > 1.3 && t < 1.8
            if twinkle { f.front = shape(Art.sparkle, x: 13, y: stage.headTop + 5, alpha: 1 - phase(t, 1.3, 1.8)) }
            if t > 0.6 { f.bubble = "Widzę jeźdźców Rohanu!" }
            return f
        }
    }

    static func backflip() -> Trick {
        Trick(id: "backflip", title: "Salto", duration: 1.9) { t in
            var f = TrickFrame(pose: .done)
            let air = phase(t, 0.2, 0.9)
            f.dy = hop(t, 0.2, 0.9, 9)
            f.rotation = -360 * easeInOut(air)
            f.stretch = t < 0.2 ? 1 - 0.12 * phase(t, 0, 0.2) : t > 0.9 && t < 1.05 ? 0.9 : 1
            f.front = burst(t, at: 0.9, x: 12, y: 23, count: 6, reach: 4, life: 0.4, colors: [Palette.dust], gravity: 0)
                .filter { $0.y <= 23.5 }
            if t > 1.0 { f.bubble = "Elfie salto!" }
            return f
        }
    }

    // MARK: Gimli

    static func dwarfToss() -> Trick {
        Trick(id: "dwarf-toss", title: "Rzut krasnoludem", duration: 2.4) { t in
            var f = TrickFrame(pose: .blocked)
            f.dy = hop(t, 0.15, 1.05, 11)
            f.rotation = 720 * easeInOut(phase(t, 0.15, 1.05))
            if t > 1.05 && t < 1.4 {
                f.dx = wobble(t, 0.8)
                f.stretch = 0.85
            }
            f.front = burst(t, at: 1.05, x: 12, y: 23, count: 8, reach: 6, life: 0.5, colors: [Palette.dust], gravity: 0)
                .filter { $0.y <= 23.5 }
            if t > 1.1 { f.bubble = "Nikt nie rzuca krasnoludem!" }
            return f
        }
    }

    static func axe() -> Trick {
        Trick(id: "axe", title: "Topór", duration: 2.0) { t in
            var f = TrickFrame(pose: .blocked)
            for strike in [0.4, 1.0] {
                let wind = phase(t, strike - 0.3, strike)
                if t < strike && t >= strike - 0.3 { f.stretch = 1 + 0.1 * wind }
                if t >= strike && t < strike + 0.15 {
                    f.stretch = 0.85
                    f.dx = wobble(t, 0.7)
                }
                f.front += burst(t, at: strike, x: 18, y: 21, count: 7, reach: 5, life: 0.6,
                                 colors: [Palette.wood, Palette.leafDark, Palette.dust])
                    .filter { $0.y <= 23.5 }
            }
            f.bubble = t < 0.4 ? nil : t < 1.3 ? "Ha!" : "I jeszcze raz!"
            return f
        }
    }

    static func ale() -> Trick {
        Trick(id: "ale", title: "Kufel", duration: 2.8) { t in
            var f = TrickFrame(pose: .idle)
            let raise = easeOut(phase(t, 0.1, 0.5)) - phase(t, 1.6, 1.9)
            if raise > 0 { f.front = shape(Art.mug, x: 15, y: 14 - raise * 6, alpha: 1) }
            if t > 0.5 && t < 1.6 {
                f.rotation = -6
                for (i, start) in [0.5, 0.75, 1.0, 1.25].enumerated() {
                    let p = (t - start) / 0.5
                    guard p >= 0, p < 1 else { continue }
                    f.front.append(Speck(x: 16 + Double(i % 3), y: 6 - 5 * p, color: Palette.foam, alpha: 1 - p))
                }
            }
            f.dy = hop(t, 2.0, 2.25, 2)
            if t > 1.6 { f.bubble = "Krasnoluda nie przepijesz!" }
            return f
        }
    }

    static func stomp() -> Trick {
        Trick(id: "stomp", title: "Tupanie", duration: 2.2) { t in
            var f = TrickFrame(pose: .work)
            let beat = 0.4
            let local = t.truncatingRemainder(dividingBy: beat)
            let dancing = t < 1.6
            f.dy = dancing ? hop(local, 0, beat, 2.5) : 0
            f.flipped = dancing && Int(t / beat).isMultiple(of: 2) == false
            f.stretch = dancing && local < 0.06 ? 0.88 : 1
            for landing in stride(from: beat, through: 1.6, by: beat) {
                f.front += burst(t, at: landing, x: 12, y: 23, count: 6, reach: 5, life: 0.35, colors: [Palette.dust], gravity: 0)
                    .filter { $0.y <= 23.5 }
            }
            if t > 0.4 { f.bubble = "Groźni na krótkich dystansach!" }
            return f
        }
    }

    // MARK: Sauron

    static func eyeAflame() -> Trick {
        Trick(id: "eye-aflame", title: "Płonące Oko", duration: 2.4) { t in
            var f = TrickFrame(pose: .blocked)
            let strength = phase(t, 0, 0.3) * (1 - phase(t, 1.9, 2.4))
            for i in 0..<26 {
                let k = Double(i)
                let life = 0.6 + (k.truncatingRemainder(dividingBy: 3)) * 0.15
                let p = ((t + k * 0.13).truncatingRemainder(dividingBy: life)) / life
                let x = -5 + k * 1.3 + sin(t * 8 + k) * 0.8
                let colors = [Palette.yellow, Palette.orange, Palette.red]
                let size = p < 0.5 ? 2.0 : 1.0
                f.behind.append(Speck(x: x, y: 23 - p * 18, w: size, h: size, color: colors[Int(p * 3) % 3], alpha: strength * (1 - p)))
            }
            f.stretch = 1 + 0.03 * sin(t * 12)
            if t > 0.4 { f.bubble = "Widzę Cię." }
            return f
        }
    }

    static func oneRing() -> Trick {
        Trick(id: "one-ring", title: "Jedyny Pierścień", duration: 2.8) { t in
            var f = TrickFrame(pose: .idle)
            let presence = phase(t, 0, 0.3) * (1 - phase(t, 2.4, 2.8))
            let angle = t * 2 * .pi / 1.2
            let ring = shape(Art.ring, x: 10 + cos(angle) * 14, y: 10 + sin(angle) * 4, alpha: presence)
            if sin(angle) > 0 { f.front = ring } else { f.behind = ring }
            if t > 0.5 { f.bubble = "Jeden, by wszystkimi rządzić." }
            return f
        }
    }

    static func darkness() -> Trick {
        Trick(id: "darkness", title: "Ciemność", duration: 2.8) { t in
            var f = TrickFrame(pose: .blocked)
            let dusk = phase(t, 0.1, 0.8) * (1 - phase(t, 2.0, 2.6))
            for i in 0..<28 {
                let angle = Double(i) / 28 * 2 * .pi + t * 0.7
                let r = 18 - 6 * easeOut(phase(t, 0.1, 1.2)) + sin(t * 3 + Double(i)) * 1.5
                f.behind.append(Speck(x: 12 + cos(angle) * r, y: 12 + sin(angle) * r * 0.9, w: 2, h: 2,
                                      color: Palette.shadow, alpha: 0.75 * dusk))
            }
            f.behind = f.behind.filter { $0.y <= 22.5 }
            if dusk > 0.5 {
                f.front = burst(t, at: 0.9, x: 12, y: 6, count: 10, reach: 8, life: 0.8, colors: [Palette.red, Palette.orange], gravity: 0)
                f.stretch = 1 + 0.05 * sin(t * 10)
            }
            if t > 0.6 { f.bubble = "Ciemność nadchodzi…" }
            return f
        }
    }

    static func wrath() -> Trick {
        Trick(id: "wrath", title: "Gniew", duration: 2.2) { t in
            var f = TrickFrame(pose: .blocked)
            f.dx = t < 1.4 ? wobble(t, 1.0, 14) : 0
            f.stretch = 1 + 0.06 * phase(t, 0, 0.3) * (1 - phase(t, 1.3, 1.6))
            for (strike, x) in [(0.25, -4.0), (0.65, 27.0), (1.0, -1.0)] {
                let p = (t - strike) / 0.3
                guard p >= 0, p < 1 else { continue }
                f.behind += bolt(x: x, alpha: 1 - p)
            }
            if t > 0.3 { f.bubble = "Gdzie jest Pierścień?!" }
            return f
        }
    }

    // MARK: Building blocks

    static func burst(_ t: Double, at start: Double, x: Double, y: Double, count: Int, reach: Double, life: Double,
                      colors: [UInt32], gravity: Double = 3) -> [Speck] {
        let p = (t - start) / life
        guard p >= 0, p < 1 else { return [] }
        let r = reach * easeOut(p)
        return (0..<count).map { i in
            let angle = Double(i) / Double(count) * 2 * .pi + 0.4
            return Speck(x: x + cos(angle) * r, y: y + sin(angle) * r + gravity * p * p,
                         color: colors[i % colors.count], alpha: 1 - p * p)
        }
    }

    static func sparkles(_ t: Double, at start: Double, around stage: Stage, life: Double) -> [Speck] {
        let p = (t - start) / life
        guard p >= 0, p < 1 else { return [] }
        let spots: [(Double, Double)] = [(-1, stage.headTop + 2), (21, stage.headTop), (-2, 14), (23, 12)]
        return spots.enumerated().flatMap { i, spot in
            shape(Art.sparkle, x: spot.0, y: spot.1 - p * 2, alpha: (1 - p) * (i.isMultiple(of: 2) ? 1 : 0.8))
        }
    }

    static func hollowSquare(x: Double, y: Double, size: Double, color: UInt32, alpha: Double) -> [Speck] {
        let side = max(1, size.rounded())
        return [
            Speck(x: x + 1, y: y, w: side - 2, h: 1, color: color, alpha: alpha),
            Speck(x: x + 1, y: y + side - 1, w: side - 2, h: 1, color: color, alpha: alpha),
            Speck(x: x, y: y + 1, w: 1, h: side - 2, color: color, alpha: alpha),
            Speck(x: x + side - 1, y: y + 1, w: 1, h: side - 2, color: color, alpha: alpha),
        ]
    }

    static func bolt(x: Double, alpha: Double) -> [Speck] {
        let path: [(Double, Double)] = [(0, -14), (1, -11), (-1, -8), (1, -5), (0, -2), (2, 1), (0, 4), (1, 7), (-1, 10), (0, 13), (1, 16), (0, 19), (0, 22)]
        return path.flatMap { dx, dy in
            [Speck(x: x + dx, y: dy, w: 1, h: 3, color: Palette.yellow, alpha: alpha),
             Speck(x: x + dx + 1, y: dy, w: 1, h: 3, color: Palette.white, alpha: alpha * 0.8)]
        }
    }

    /// Pixel art written as text: every letter is a colour from `Palette.byLetter`, a dot is empty.
    static func shape(_ art: [String], x: Double, y: Double, alpha: Double) -> [Speck] {
        guard alpha > 0 else { return [] }
        var specks: [Speck] = []
        for (row, line) in art.enumerated() {
            for (column, letter) in line.enumerated() {
                guard let color = Palette.byLetter[letter] else { continue }
                specks.append(Speck(x: x + Double(column), y: y + Double(row), color: color, alpha: alpha))
            }
        }
        return specks
    }
}

enum Palette {
    static let ink: UInt32 = 0x2a1e18
    static let white: UInt32 = 0xffffff
    static let silver: UInt32 = 0xc4c4c8
    static let wood: UInt32 = 0x7a5230
    static let potato: UInt32 = 0x9c6b3a
    static let potatoDark: UInt32 = 0x6b4423
    static let green: UInt32 = 0x6aa84f
    static let darkGreen: UInt32 = 0x3d7a2a
    static let leaf: UInt32 = 0xe0a530
    static let leafDark: UInt32 = 0xc27c1e
    static let red: UInt32 = 0xd23a1e
    static let orange: UInt32 = 0xff8c1a
    static let yellow: UInt32 = 0xf2c94c
    static let gold: UInt32 = 0xb8860b
    static let lightBlue: UInt32 = 0x7fd4ff
    static let blue: UInt32 = 0x3a8fd9
    static let magenta: UInt32 = 0xd86bd0
    static let pink: UInt32 = 0xf08cb4
    static let foam: UInt32 = 0xf7f2e0
    static let smoke: UInt32 = 0xb9b6ae
    static let dust: UInt32 = 0xa89a80
    static let shadow: UInt32 = 0x1c1420
    static let iron: UInt32 = 0x55565c

    static let byLetter: [Character: UInt32] = [
        "k": ink, "w": white, "s": silver, "b": wood, "p": potato, "P": potatoDark, "g": green, "G": darkGreen,
        "l": leaf, "L": leafDark, "r": red, "o": orange, "y": yellow, "Y": gold, "c": lightBlue, "C": blue,
        "m": magenta, "i": pink, "f": foam, "d": iron, "K": 0x000000,
    ]
}

private enum Art {
    static let ring = [
        ".yY.",
        "y..Y",
        "Y..Y",
        ".YY.",
    ]
    static let eye = [
        "..rrr..",
        ".royor.",
        "royKyor",
        ".royor.",
        "..rrr..",
    ]
    static let note = [
        "..kk",
        "..k.",
        "..k.",
        "kkk.",
        "kk..",
    ]
    static let leaf = [
        ".l",
        "lL",
        "L.",
    ]
    static let potato = [
        ".pp.",
        "pPpp",
        "ppPp",
        ".pp.",
    ]
    static let flowerPink = [
        ".i.",
        "iyi",
        ".i.",
    ]
    static let flowerYellow = [
        ".y.",
        "yoy",
        ".y.",
    ]
    static let pan = [
        ".kkk.....",
        "kdddk....",
        "kdddkbbbb",
        "kdddk....",
        ".kkk.....",
    ]
    static let drop = [
        ".c",
        "cC",
    ]
    static let crown = [
        "y.y.y",
        "yYyYy",
        "yrycy",
        "YYYYY",
    ]
    static let herb = [
        "g.g",
        ".G.",
    ]
    static let arrow = [
        "w.......",
        "wbbbbbss",
        "w.......",
    ]
    static let shield = [
        ".dddddddd.",
        "dbbbYYbbbd",
        ".dddddddd.",
    ]
    static let mug = [
        "ffff.",
        "yyyyY",
        "yYyy.Y",
        "yyyyY",
        "YYYY.",
    ]
    static let sparkle = [
        ".w.",
        "wyw",
        ".w.",
    ]
}

private func clamp01(_ value: Double) -> Double { min(1, max(0, value)) }

/// 0 before `start`, 1 after `end`, linear in between.
func phase(_ t: Double, _ start: Double, _ end: Double) -> Double { clamp01((t - start) / (end - start)) }

/// A jump of `height` sprite pixels between `start` and `end`; negative is up.
func hop(_ t: Double, _ start: Double, _ end: Double, _ height: Double) -> Double {
    guard t >= start, t < end else { return 0 }
    let p = phase(t, start, end)
    return -4 * height * p * (1 - p)
}

func wobble(_ t: Double, _ amplitude: Double, _ hertz: Double = 18) -> Double { amplitude * sin(2 * .pi * hertz * t) }

func easeOut(_ p: Double) -> Double { 1 - (1 - p) * (1 - p) }

func easeIn(_ p: Double) -> Double { p * p }

func easeInOut(_ p: Double) -> Double { p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2 }
