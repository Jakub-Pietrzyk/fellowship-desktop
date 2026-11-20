import Foundation

enum Hero: String, CaseIterable {
    case gandalf, frodo, sam, aragorn, legolas, gimli, sauron

    var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    var rareName: String {
        switch self {
        case .gandalf: "Gandalf the White"
        case .aragorn: "King Elessar"
        case .frodo: "Frodo Elf-friend"
        case .sam: "Samwise the Gardener"
        case .legolas: "Prince Legolas"
        case .gimli: "Gimli of Helm's Deep"
        case .sauron: "Annatar"
        }
    }
}

enum Edition: String, CaseIterable {
    case normal, rare, sax

    func isAvailable(for hero: Hero) -> Bool { self != .sax || hero == .gandalf }

    /// Same odds as the Herdr layout: 1% Epic Sax Gandalf, otherwise 10% rare.
    static func draw(for hero: Hero, random: () -> Double = { Double.random(in: 0..<1) }) -> Edition {
        if hero == .gandalf && random() < 0.01 { return .sax }
        return random() < 0.1 ? .rare : .normal
    }
}

enum PetState: String, Codable, Comparable {
    case idle, done, working, blocked

    /// The most urgent session wins what the pet shows: blocked > working > done > idle.
    private var urgency: Int {
        switch self {
        case .idle: 0
        case .done: 1
        case .working: 2
        case .blocked: 3
        }
    }

    static func < (lhs: PetState, rhs: PetState) -> Bool { lhs.urgency < rhs.urgency }
}

struct Pose: Equatable {
    let frames: [String]
    let frameDuration: TimeInterval

    /// Mirrors the Herdr layout's timing: two frames swap every 400 ms on the road, every 900 ms at rest.
    static func of(hero: Hero, edition: Edition, state: PetState) -> Pose {
        let base = edition == .normal || !edition.isAvailable(for: hero) ? hero.rawValue : "\(hero.rawValue)-\(edition.rawValue)"
        switch state {
        case .working: return Pose(frames: ["\(base)-work", "\(base)-2"], frameDuration: 0.4)
        case .idle: return Pose(frames: ["\(base)-idle", "\(base)-idle-2"], frameDuration: 0.9)
        case .blocked: return Pose(frames: ["\(base)-blocked"], frameDuration: 1)
        case .done: return Pose(frames: ["\(base)-done"], frameDuration: 1)
        }
    }
}
