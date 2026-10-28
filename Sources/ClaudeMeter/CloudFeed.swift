import Darwin
import Foundation

// The cloud sessions list: claude.ai/code sessions, project threads and Remote Control sessions, each
// with the exact `cost_usd` Anthropic reports for it. The weekly % counts that use, but this Mac's
// transcripts never see it, so before v0.9.26 it hid in "Elsewhere" (and in the calibrated cap). Read the
// way Swarm Watch and Claude Dashboard read it (`Bridge.fetch`, `CloudReader`, verified on this Mac): GET
// only, with the Claude Code sign-in already on this Mac, held in memory and never written anywhere.

/// One session as a read listed it, before it is booked.
struct CloudRow {
    var id: String
    var title: String
    /// Nil when the list carries none (Remote Control child rows don't).
    var cost: Double?
    var createdAt: Date?
    var updatedAt: Date?
    var model: String?
    var cwd: String?
    /// Remote Control work that runs on this Mac: its transcripts are here and already priced, so it is
    /// never counted as cloud use.
    var local: Bool
}

/// A session as last read.
struct CloudSession: Codable {
    var id: String
    var title: String
    var cost: Double
    var createdAt: Date?
    var updatedAt: Date?
    var model: String?
    var cwd: String?
    /// When a read last listed it.
    var seenAt: Date
    var local: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, cost = "cost_usd", createdAt = "created_at", updatedAt = "updated_at", model, cwd
        case seenAt = "seen_at", local
    }
}

/// Spend a read saw a session add: a session's whole cost the first time it is listed, then each rise.
struct CloudSpend: Codable {
    /// Dated at the session's `updated_at` when that moved (else when it was read), never after the read.
    var at: Date
    /// Where the span it was spent in starts: the session's creation for a first sighting, else the
    /// read before. A span that starts before a window counts only its share of the time inside it.
    var from: Date
    /// When the read that saw it ran. With the session, what makes an entry unique: a relaunch never
    /// books the same rise twice.
    var seen: Date
    var session: String
    var title: String
    var cost: Double
    var model: String?

    enum CodingKeys: String, CodingKey {
        case at, from, seen, session, title, cost = "delta", model
    }

    /// The part of it spent in [a, b), spread evenly over its span (a point counts whole where it falls).
    func share(from a: Date, to b: Date) -> Double {
        let start = min(from, at)
        guard at > start else { return a <= at && at < b ? cost : 0 }
        let lo = max(start, a), hi = min(at, b)
        guard hi > lo else { return 0 }
        return cost * hi.timeIntervalSince(lo) / at.timeIntervalSince(start)
    }
}

/// `cloud.json`: the sessions as last read and the spend booked from them.
struct CloudStore: Codable {
    var sessions: [String: CloudSession] = [:]
    /// Cloud spend: what the numbers count.
    var ledger: [CloudSpend] = []
    /// Remote Control sessions run on this Mac. Their transcripts already price this work, so it is shown
    /// nowhere; kept only to reconcile the two later.
    var rcChild: [CloudSpend] = []
    /// "ok", "signed_out", "error" or "rate_limited", from the last read.
    var state: String?
    /// The last read that answered, and the last one tried.
    var readAt: Date?
    var triedAt: Date?

    static let keepSpend: TimeInterval = 14 * 86400
    /// Sessions outlive their spend: one that drops off the list and comes back after its record went
    /// would be booked whole again.
    static let keepSessions: TimeInterval = 60 * 86400

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessions = try c.decodeIfPresent([String: CloudSession].self, forKey: .sessions) ?? [:]
        ledger = try c.decodeIfPresent([CloudSpend].self, forKey: .ledger) ?? []
        rcChild = try c.decodeIfPresent([CloudSpend].self, forKey: .rcChild) ?? []
        state = try c.decodeIfPresent(String.self, forKey: .state)
        readAt = try c.decodeIfPresent(Date.self, forKey: .readAt)
        triedAt = try c.decodeIfPresent(Date.self, forKey: .triedAt)
    }

    /// Books what a read found. A session seen for the first time is booked whole, dated at its last
    /// update (not now), so a launch mid-week doesn't pile old spend onto today; after that, each rise
    /// is booked at the update that carried it. A cost that fell is taken as the new base, booking nothing.
    mutating func take(_ rows: [CloudRow], now: Date) {
        for row in rows {
            guard let cost = row.cost, cost.isFinite, cost >= 0 else { continue }
            let updated = row.updatedAt.map { min($0, now) }
            if var s = sessions[row.id] {
                let delta = cost - s.cost
                if delta > 0 {
                    let moved = updated.map { $0 > (s.updatedAt ?? .distantPast) } ?? false
                    let at = moved ? (updated ?? now) : now
                    book(CloudSpend(at: at, from: min(s.seenAt, at), seen: now, session: row.id, title: row.title,
                                    cost: delta, model: row.model ?? s.model), local: row.local || s.local)
                }
                s.cost = cost
                s.title = row.title
                s.createdAt = row.createdAt ?? s.createdAt
                s.updatedAt = row.updatedAt ?? s.updatedAt
                s.model = row.model ?? s.model
                s.cwd = row.cwd ?? s.cwd
                s.seenAt = now
                s.local = s.local || row.local
                sessions[row.id] = s
            } else {
                if cost > 0 {
                    let at = updated ?? now
                    book(CloudSpend(at: at, from: min(row.createdAt ?? at, at), seen: now, session: row.id,
                                    title: row.title, cost: cost, model: row.model), local: row.local)
                }
                sessions[row.id] = CloudSession(id: row.id, title: row.title, cost: cost, createdAt: row.createdAt,
                                                updatedAt: row.updatedAt, model: row.model, cwd: row.cwd,
                                                seenAt: now, local: row.local)
            }
        }
        prune(now: now)
    }

    private mutating func book(_ spend: CloudSpend, local: Bool) {
        let held = local ? rcChild : ledger
        guard !held.contains(where: { $0.session == spend.session && $0.seen == spend.seen }) else { return }
        if local { rcChild.append(spend) } else { ledger.append(spend) }
    }

    mutating func prune(now: Date) {
        let spendCutoff = now.addingTimeInterval(-Self.keepSpend)
        ledger.removeAll { $0.at < spendCutoff }
        rcChild.removeAll { $0.at < spendCutoff }
        let sessionCutoff = now.addingTimeInterval(-Self.keepSessions)
        sessions = sessions.filter { $0.value.seenAt >= sessionCutoff }
    }

    /// Cloud spend in [from, to), and the same by session title.
    func spent(from: Date, to: Date) -> (total: Double, byTitle: [String: Double]) {
        var total = 0.0
        var byTitle: [String: Double] = [:]
        for e in ledger {
            let part = e.share(from: from, to: to)
            guard part > 0 else { continue }
            total += part
            byTitle[e.title, default: 0] += part
        }
        return (total, byTitle)
    }
}

/// Reading and saving the list, off the main thread. Nothing here touches the meter.
enum CloudSessions {
    static var file: URL { Paths.cloud }
    /// The setting (right-click → Cloud sessions); on unless turned off.
    static let settingKey = "cloudSessions"

    static func load() -> CloudStore? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONCoding.decoder().decode(CloudStore.self, from: data)
    }

    /// Titles, costs and times only (never the sign-in), readable by you alone.
    static func save(_ store: CloudStore) {
        guard let data = try? JSONCoding.encoder(pretty: true).encode(store) else { return }
        Paths.makeSupport()
        try? data.write(to: file, options: .atomic)
        _ = chmod(file.path, 0o600)
    }

    /// What one read came to: the rows, or why there are none.
    struct Read {
        var state: String
        var rows: [CloudRow]?
        /// Rows the listings held, a cost or not.
        var listed = 0
    }

    /// The three listings Swarm Watch reads: the default one, project threads, and Remote Control
    /// children. A sign-out or a 429 stops the read (the next listing would get the same); any other
    /// failure keeps what the other listings answered, since a row missing from one read books nothing.
    static func read() async -> Read {
        var found: [String: CloudRow] = [:]
        var order: [String] = []
        var failed: String?
        var answered = 0
        var listed = 0
        let bridged = await offMain { bridgedSessionIDs() }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for tags in [[], ["hearth-thread"], ["rc-child"]] as [[String]] {
            var query = [URLQueryItem(name: "limit", value: "50")]
            query += tags.map { URLQueryItem(name: "tags", value: $0) }
            switch await fetch(query) {
            case .success(let json):
                answered += 1
                for case let raw as [String: Any] in (json["data"] as? [Any]) ?? [] {
                    guard let row = parse(raw, bridged: bridged, home: home) else { continue }
                    if found[row.id] == nil {
                        order.append(row.id)
                        listed += 1
                    }
                    found[row.id] = row
                }
            case .failure(let state):
                if state == "signed_out" || state == "rate_limited" { return Read(state: state, rows: nil) }
                failed = failed ?? state
            }
        }
        guard answered > 0 else { return Read(state: failed ?? "error", rows: nil) }
        return Read(state: failed ?? "ok", rows: order.compactMap { found[$0] }, listed: listed)
    }

    /// Blocking work (the keychain, which can wait on a macOS prompt; the file system) on a utility thread.
    private static func offMain<T>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: work()) }
        }
    }

    private static let base = URL(string: "https://api.anthropic.com/v1/sessions")
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral // no cookies or cache on disk
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()

    private enum Fetched {
        case success([String: Any])
        case failure(String)
    }

    /// One GET. On 401/403 the sign-in is read once more (Claude Code may have refreshed it) and tried again.
    private static func fetch(_ query: [URLQueryItem], retried: Bool = false) async -> Fetched {
        guard let creds = await offMain({ Credentials.current(forceReload: retried) }) else { return .failure("signed_out") }
        guard let root = Self.base, var comps = URLComponents(url: root, resolvingAgainstBaseURL: false) else { return .failure("error") }
        comps.queryItems = query
        guard let url = comps.url else { return .failure("error") }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "GET"
        req.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("ccr-byoc-2025-07-29", forHTTPHeaderField: "anthropic-beta")
        if let org = creds.org { req.setValue(org, forHTTPHeaderField: "x-organization-uuid") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) } catch { return .failure("error") }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300:
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .failure("error") }
            return .success(json)
        case 401, 403:
            if retried { return .failure("signed_out") }
            return await fetch(query, retried: true)
        case 429:
            return .failure("rate_limited")
        default:
            return .failure("error")
        }
    }

    /// The fields kept from a row; nil for one without an id.
    private static func parse(_ r: [String: Any], bridged: Set<String>, home: String) -> CloudRow? {
        guard let id = r["id"] as? String, !id.isEmpty else { return nil }
        let meta = r["external_metadata"] as? [String: Any] ?? [:]
        let context = r["session_context"] as? [String: Any] ?? [:]
        let tags = (r["tags"] as? [Any])?.compactMap { $0 as? String } ?? []
        let cost = ((meta["usage"] as? [String: Any])?["cost_usd"] as? NSNumber)?.doubleValue
        let cwd = (context["cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let model = (meta["last_served_model"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return CloudRow(id: id, title: title(r["title"]), cost: cost.flatMap { $0.isFinite ? $0 : nil },
                        createdAt: date(r["created_at"]), updatedAt: date(r["updated_at"]), model: model, cwd: cwd,
                        local: isLocal(id: id, tags: tags, cwd: cwd, bridged: bridged, home: home))
    }

    /// One line, at most 80 characters.
    private static func title(_ value: Any?) -> String {
        let words = (value as? String ?? "").split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        guard !words.isEmpty else { return "Untitled session" }
        return words.count > 80 ? String(words.prefix(79)) + "…" : words
    }

    private static func date(_ value: Any?) -> Date? {
        if let s = value as? String { return JSONCoding.parseDate(s.trimmingCharacters(in: .whitespaces)) }
        if let n = (value as? NSNumber)?.doubleValue, n.isFinite, n > 0 {
            return Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n)
        }
        return nil
    }

    /// Remote Control work run on this Mac: a Remote Control row (tag `rc-child`, or `remote-control-sdk`,
    /// the desktop app's own), one a Claude Code process here bridged (`~/.claude/sessions/*.json`), or
    /// one whose folder is in your home folder here. Cloud sessions run in /home/user on Anthropic's machines.
    static func isLocal(id: String, tags: [String], cwd: String?, bridged: Set<String>, home: String) -> Bool {
        if tags.contains("rc-child") || tags.contains("remote-control-sdk") || bridged.contains(id) { return true }
        guard let cwd, cwd.hasPrefix(home + "/") else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: cwd, isDirectory: &isDir) && isDir.boolValue
    }

    /// Cloud ids that Claude Code processes on this Mac bridged (Remote Control), from their session files.
    private static func bridgedSessionIDs() -> Set<String> {
        let config = ShellEnv.claudeConfigDir.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        let dir = config.appendingPathComponent("sessions")
        var ids: Set<String> = []
        for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        where f.pathExtension == "json" {
            guard let d = try? Data(contentsOf: f),
                  let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                  let bridge = o["bridgeSessionId"] as? String, !bridge.isEmpty else { continue }
            ids.insert(bridge)
        }
        return ids
    }

    // MARK: Terminal

    /// Where this week counts from, by the last reading's weekly window (its early reset, if it had one);
    /// the last 7 days when no week is known.
    private static func weekBegin(_ state: PersistedState, now: Date) -> Date {
        if let w = state.lastExact?.weekly, now < w.resetsAt {
            return max(w.resetsAt.addingTimeInterval(-7 * 86400), w.restartedAt ?? .distantPast)
        }
        return now.addingTimeInterval(-7 * 86400)
    }

    /// For `--status`: the setting, the last read, and this week's cloud spend as booked.
    static func statusLines(state: PersistedState, now: Date = Date()) -> [String] {
        let on = UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
        guard on else { return ["cloud sessions: off"] }
        guard let store = load() else { return ["cloud sessions: on, not read yet"] }
        func age(_ d: Date?) -> String { d.map { "\(Int(max(0, now.timeIntervalSince($0)) / 60))m ago" } ?? "never" }
        let begin = weekBegin(state, now: now)
        let week = store.spent(from: begin, to: now)
        let cloud = store.sessions.values.filter { !$0.local }.count
        return [
            "cloud sessions: \(store.state ?? "not read yet"), last read \(age(store.readAt)), last tried \(age(store.triedAt))",
            "cloud this week: \(Fmt.dollars(week.total)) across \(week.byTitle.count) titles since \(Fmt.when(begin)) "
                + "(\(cloud) cloud sessions known, \(store.ledger.count) spend entries, \(store.rcChild.count) Remote Control entries not counted)",
        ]
    }

    /// `--cloud-check`: one read, printed, without touching cloud.json. Exits 0 when the read answered.
    static func check() -> Int32 {
        final class Box: @unchecked Sendable { var value = CloudSessions.Read(state: "error", rows: nil) }
        let done = DispatchSemaphore(value: 0)
        let box = Box()
        let started = Date()
        Task.detached {
            box.value = await CloudSessions.read()
            done.signal()
        }
        // Long enough to answer a first macOS prompt to allow the keychain read.
        guard done.wait(timeout: .now() + 180) == .success else {
            Swift.print("cloud sessions: timed out (a keychain prompt left open?)")
            return 1
        }
        let result = box.value
        let now = Date()
        Swift.print("cloud sessions: \(result.state) (read in \(String(format: "%.1f", now.timeIntervalSince(started))) s; cloud.json not touched)")
        guard let rows = result.rows else { return 1 }
        let local = rows.filter(\.local)
        let cloud = rows.filter { !$0.local && $0.cost != nil }
        Swift.print("listed: \(result.listed) sessions (\(cloud.count) cloud with a cost, \(local.count) Remote Control on this Mac, "
                    + "\(rows.count - cloud.count - local.count) cloud without a cost)")
        // As the app would book them on a first read: each session's whole cost, spread over its life.
        let begin = weekBegin(StateStore().state, now: now)
        var store = CloudStore()
        store.take(rows, now: now)
        let week = store.spent(from: begin, to: now)
        let lifetime = cloud.reduce(0) { $0 + ($1.cost ?? 0) }
        Swift.print("cloud this week since \(Fmt.when(begin)): \(Fmt.dollars(week.total)) across \(week.byTitle.count) titles "
                    + "(listed sessions' whole cost \(Fmt.dollars(lifetime)))")
        for (title, cost) in week.byTitle.sorted(by: { $0.value > $1.value }).prefix(5) {
            Swift.print("  \(Fmt.dollars(cost))  \(title)")
        }
        return result.state == "ok" ? 0 : 1
    }
}

/// Polls the list while the app runs and the setting is on: about 20 seconds after launch, then every
/// 5 minutes (15 after a 429). Each read is booked into `cloud.json`.
@MainActor
final class CloudFeed {
    static let cloudPollSeconds: TimeInterval = 300
    static let firstPollAfter: TimeInterval = 20
    static let rateLimitedWait: TimeInterval = 900

    private(set) var store: CloudStore
    /// After each read is booked.
    var onChange: (@MainActor () -> Void)?
    private var enabled = false
    private var running = false
    private var nextPoll = Date.distantFuture

    init() {
        store = CloudSessions.load() ?? CloudStore()
    }

    func setEnabled(_ on: Bool, now: Date = Date()) {
        guard on != enabled else { return }
        enabled = on
        if on {
            nextPoll = now.addingTimeInterval(Self.firstPollAfter)
        } else {
            Credentials.forget()
        }
    }

    /// From the meter's 10-second tick.
    func tick(now: Date = Date()) {
        guard enabled, !running, now >= nextPoll else { return }
        running = true
        Task { [weak self] in
            let read = await CloudSessions.read()
            self?.finish(read)
        }
    }

    private func finish(_ read: CloudSessions.Read) {
        let now = Date()
        running = false
        nextPoll = now.addingTimeInterval(read.state == "rate_limited" ? Self.rateLimitedWait : Self.cloudPollSeconds)
        guard enabled else { return } // turned off while it read
        store.state = read.state
        store.triedAt = now
        if let rows = read.rows {
            store.take(rows, now: now)
            store.readAt = now
        }
        CloudSessions.save(store)
        onChange?()
    }
}

/// Claude Code's saved sign-in on this Mac, from the keychain item Claude Code keeps (Swarm Watch's
/// `Credentials`). Held in memory only: never written, logged or refreshed here.
enum Credentials {
    struct Value { let token: String; let org: String?; let expires: Date? }
    nonisolated(unsafe) private static var cached: Value?
    nonisolated(unsafe) private static var loadedAt = Date.distantPast
    private static let lock = NSLock()
    private static let minReload: TimeInterval = 15

    static func current(forceReload: Bool = false) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        if !forceReload, let c = cached, (c.expires ?? .distantFuture) > Date().addingTimeInterval(60) { return c }
        // Each read runs /usr/bin/security; while the saved sign-in stays expired, at most every 15 s.
        if Date().timeIntervalSince(loadedAt) < minReload { return cached }
        loadedAt = Date()
        cached = load()
        return cached
    }

    /// Drops the in-memory copy (the setting was turned off).
    static func forget() {
        lock.lock()
        defer { lock.unlock() }
        cached = nil
        loadedAt = .distantPast
    }

    private static func load() -> Value? {
        guard let raw = keychainSecret(service: "Claude Code-credentials"),
              let obj = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        let expires = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return Value(token: token, org: organization(), expires: expires)
    }

    /// `security` asks macOS for the item; the first time, macOS may ask you to allow it.
    static func keychainSecret(service: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", service, "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// The organization the sign-in belongs to, from Claude Code's `.claude.json`.
    private static func organization() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var places = [home.appendingPathComponent(".claude.json"), home.appendingPathComponent(".claude/.claude.json")]
        if let dir = ShellEnv.claudeConfigDir {
            places.insert(URL(fileURLWithPath: (dir as NSString).expandingTildeInPath).appendingPathComponent(".claude.json"), at: 0)
        }
        for url in places {
            if let d = try? Data(contentsOf: url),
               let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
               let account = obj["oauthAccount"] as? [String: Any],
               let org = account["organizationUuid"] as? String { return org }
        }
        return nil
    }
}
