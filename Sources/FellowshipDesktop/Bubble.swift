import Foundation

enum Bubble {
    static func text(for summary: Summary) -> String? {
        switch summary.state {
        case .blocked:
            if summary.sessions.count > 1 { return "\(sessions(summary.sessions.count)) czeka na Ciebie" }
            return prefixed(summary.sessions.first, "czekam na Twoją zgodę")
        case .done:
            if summary.sessions.count > 1 { return "\(sessions(summary.sessions.count)) skończyło" }
            return prefixed(summary.sessions.first, "gotowe!")
        case .working, .idle:
            return nil
        }
    }

    static func menuLine(for summary: Summary) -> String {
        guard summary.total > 0 else { return "Claude Code: brak aktywnych sesji" }
        let state = switch summary.state {
        case .blocked: "czeka na Ciebie"
        case .working: "pracuje"
        case .done: "skończył"
        case .idle: "odpoczywa"
        }
        return "Claude Code: \(sessions(summary.total)), \(state)"
    }

    /// Polish plural: 1 sesja, 2-4 sesje, 5+ sesji (12-14 sesji).
    static func sessions(_ n: Int) -> String {
        if n == 1 { return "1 sesja" }
        let tens = n % 100
        let ones = n % 10
        let few = (2...4).contains(ones) && !(12...14).contains(tens)
        return "\(n) \(few ? "sesje" : "sesji")"
    }

    private static func prefixed(_ record: SessionRecord?, _ text: String) -> String {
        guard let project = record?.project else { return text.prefix(1).uppercased() + text.dropFirst() }
        return "\(project): \(text)"
    }
}
