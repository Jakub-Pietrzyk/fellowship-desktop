import Foundation

/// One file per Claude Code session, written by `FellowshipDesktop hook` and read by the app.
struct SessionRecord: Codable, Equatable {
    var state: PetState
    var cwd: String?
    var updated: Date

    var project: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}

struct Summary: Equatable {
    let state: PetState
    /// Sessions in `state`, most recently updated first.
    let sessions: [SessionRecord]
    let total: Int

    static let empty = Summary(state: .idle, sessions: [], total: 0)
}

struct StatusStore {
    let directory: URL

    /// A session that stopped reporting is assumed gone: a long tool call can be quiet for a while, a closed
    /// terminal is quiet forever.
    static let workingTimeout: TimeInterval = 30 * 60
    static let blockedTimeout: TimeInterval = 60 * 60
    static let doneTimeout: TimeInterval = 10 * 60
    static let forgetAfter: TimeInterval = 12 * 60 * 60

    static let `default` = StatusStore(
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FellowshipDesktop/sessions", isDirectory: true)
    )

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    private func url(for sessionID: String) -> URL {
        let safe = sessionID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return directory.appendingPathComponent("\(safe.isEmpty ? "unknown" : safe).json")
    }

    func write(sessionID: String, record: SessionRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(record).write(to: url(for: sessionID), options: .atomic)
    }

    func read(sessionID: String) -> SessionRecord? {
        guard let data = try? Data(contentsOf: url(for: sessionID)) else { return nil }
        return try? Self.decoder.decode(SessionRecord.self, from: data)
    }

    func remove(sessionID: String) {
        try? FileManager.default.removeItem(at: url(for: sessionID))
    }

    func all() -> [String: SessionRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var records: [String: SessionRecord] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let record = try? Self.decoder.decode(SessionRecord.self, from: data) else { continue }
            records[file.deletingPathExtension().lastPathComponent] = record
        }
        return records
    }

    /// Reads every session, forgets the long-dead ones and folds the rest into what the pet shows.
    func summary(now: Date = Date()) -> Summary {
        var live: [SessionRecord] = []
        for (id, record) in all() {
            if now.timeIntervalSince(record.updated) > Self.forgetAfter {
                remove(sessionID: id)
                continue
            }
            live.append(Self.effective(record, now: now))
        }
        return Self.fold(live)
    }

    static func effective(_ record: SessionRecord, now: Date) -> SessionRecord {
        let age = now.timeIntervalSince(record.updated)
        let expired = switch record.state {
        case .working: age > workingTimeout
        case .blocked: age > blockedTimeout
        case .done: age > doneTimeout
        case .idle: false
        }
        var copy = record
        if expired { copy.state = .idle }
        return copy
    }

    static func fold(_ records: [SessionRecord]) -> Summary {
        guard let top = records.map(\.state).max() else { return .empty }
        let matching = records.filter { $0.state == top }.sorted { $0.updated > $1.updated }
        return Summary(state: top, sessions: matching, total: records.count)
    }

    /// The person has seen the pet celebrate: every finished session goes back to rest.
    func acknowledgeDone(now: Date = Date()) {
        for (id, record) in all() where record.state == .done {
            var copy = record
            copy.state = .idle
            copy.updated = now
            try? write(sessionID: id, record: copy)
        }
    }
}
