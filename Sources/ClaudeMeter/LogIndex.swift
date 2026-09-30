import Foundation

/// One model response, as Claude Code logged it.
struct Turn: Codable {
    /// message id + request id; a turn is written once per content block
    let key: String
    let at: Date
    let project: String
    let model: String
    let session: String
    let input: Int
    let output: Int
    let cacheRead: Int
    let write5m: Int
    let write1h: Int
    let fast: Bool
    /// API-list-price equivalent. Derived, not stored, so a pricing change reaches cached turns.
    let cost: Double

    var cacheWrite: Int { write5m + write1h }
    var tokens: Int { input + output + cacheRead + cacheWrite }

    init(key: String, at: Date, project: String, model: String, session: String, input: Int,
         output: Int, cacheRead: Int, write5m: Int, write1h: Int, fast: Bool) {
        self.key = key
        self.at = at
        self.project = project
        self.model = model
        self.session = session
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.write5m = write5m
        self.write1h = write1h
        self.fast = fast
        cost = Pricing.cost(model: model, input: input, output: output, cacheRead: cacheRead,
                            write5m: write5m, write1h: write1h, fast: fast)
    }

    /// The same turn with the larger of each count. Copies written mid-stream carry a partial
    /// output count; the later ones carry the final one.
    func merged(with other: Turn) -> Turn {
        Turn(key: key, at: at, project: project, model: model, session: session,
             input: max(input, other.input), output: max(output, other.output),
             cacheRead: max(cacheRead, other.cacheRead), write5m: max(write5m, other.write5m),
             write1h: max(write1h, other.write1h), fast: fast || other.fast)
    }

    func grows(_ other: Turn) -> Bool {
        other.output > output || other.input > input || other.cacheRead > cacheRead
            || other.write5m > write5m || other.write1h > write1h
    }

    private enum CodingKeys: String, CodingKey {
        case key, at, project, model, session, input, output, cacheRead, write5m, write1h, fast
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(key: try c.decode(String.self, forKey: .key),
                  at: try c.decode(Date.self, forKey: .at),
                  project: try c.decode(String.self, forKey: .project),
                  model: try c.decode(String.self, forKey: .model),
                  session: try c.decode(String.self, forKey: .session),
                  input: try c.decode(Int.self, forKey: .input),
                  output: try c.decode(Int.self, forKey: .output),
                  cacheRead: try c.decode(Int.self, forKey: .cacheRead),
                  write5m: try c.decode(Int.self, forKey: .write5m),
                  write1h: try c.decode(Int.self, forKey: .write1h),
                  fast: try c.decode(Bool.self, forKey: .fast))
    }
}

/// Tails the Claude Code transcripts. Keeps a byte offset per file so each refresh reads only
/// what was appended, and caches what it has read so a relaunch starts warm.
/// Only touched from one serial queue.
final class LogIndex: @unchecked Sendable {
    /// Claude Code keeps its config in ~/.claude unless CLAUDE_CONFIG_DIR moves it. Resolved,
    /// because the directory walk returns nothing when the folder itself is a symlink.
    private let root: URL = {
        let base = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        return base.appendingPathComponent("projects").resolvingSymlinksInPath()
    }()
    /// A weekly window never reaches back further than this.
    private let horizon: TimeInterval = 8 * 86400
    private let activeWindow: TimeInterval = 180

    /// How far each file has been read, and which file it was: a transcript replaced in place
    /// has a new inode and is read again from the start.
    private struct Mark: Codable {
        var offset: UInt64
        var inode: UInt64
    }

    private var marks: [String: Mark] = [:]
    /// Where each turn sits in `turns`, by key. A turn is written once per content block, so a
    /// later copy updates the one already held instead of being counted again.
    private var position: [String: Int] = [:]
    private var projectOfCwd: [String: String] = [:]
    private var projectOfSession: [String: String] = [:]
    private var customTitles: [String: String] = [:]
    private var agentNames: [String: String] = [:]
    private var lastSaved = Date.distantPast
    /// Recent transcripts, refound once a minute.
    private var known: [String] = []
    private var lastDiscovery = Date.distantPast
    private static let skipped: Set<String> = ["tool-results", "memory"]
    /// Set when a turn arrives earlier than the one before it (files are read in no set order).
    private var unsorted = false
    private var dirty = false

    private(set) var turns: [Turn] = []
    /// Sessions whose log was written in the last few minutes.
    private(set) var activeSessions: [String] = []

    private static let usageMarker = Data("\"usage\"".utf8)
    private static let assistantMarker = Data("\"assistant\"".utf8)
    private static let titleMarker = Data("\"custom-title\"".utf8)
    private static let agentMarker = Data("\"agent-name\"".utf8)
    private let decoder = JSONDecoder()
    private let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let iso = ISO8601DateFormatter()

    /// What the app calls each session: its title if it has one, else its project.
    var sessionNames: [String: String] {
        var names = projectOfSession
        names.merge(agentNames) { $1 }
        names.merge(customTitles) { $1 }
        return names
    }

    /// Reads whatever was appended since the last call. Returns true if turns were added or
    /// updated. Checks only the recent transcripts it knows about; the full tree is walked
    /// once a minute to find new ones, since walking it is most of what a refresh would cost.
    @discardableResult
    func refresh() -> Bool {
        let now = Date()
        let cutoff = now.addingTimeInterval(-horizon)
        if now.timeIntervalSince(lastDiscovery) > 60 {
            discover(cutoff: cutoff)
            lastDiscovery = now
        }
        var changed = false
        var active: Set<String> = []

        for path in known {
            var info = stat()
            guard stat(path, &info) == 0 else { continue }
            let mtime = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
            guard mtime > cutoff else { continue }
            let url = URL(fileURLWithPath: path)
            if now.timeIntervalSince(mtime) < activeWindow {
                active.insert(Self.session(of: url))
            }
            let size = UInt64(info.st_size)
            let inode = UInt64(info.st_ino)
            var mark = marks[path] ?? Mark(offset: 0, inode: inode)
            // Replaced (new inode) or rewritten shorter: read it again; `position` absorbs repeats.
            if mark.inode != inode || size < mark.offset { mark = Mark(offset: 0, inode: inode) }
            guard size > mark.offset else {
                marks[path] = mark
                continue
            }
            if read(url, from: mark.offset, inode: inode, cutoff: cutoff) { changed = true }
        }

        if changed {
            let before = turns.count
            turns.removeAll { $0.at < cutoff }
            let reorder = unsorted || turns.count < before
            if unsorted {
                turns.sort { $0.at < $1.at }
                unsorted = false
            }
            if reorder { reindex() }
            dirty = true
        }
        activeSessions = active.sorted()
        return changed
    }

    private func reindex() {
        position = Dictionary(turns.enumerated().map { ($1.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Transcripts touched within the horizon. Tool-result dumps and memory folders hold
    /// no transcripts and are most of the tree, so they are skipped whole. Also drops what
    /// no longer matters: marks for files gone quiet, names for sessions no longer held.
    private func discover(cutoff: Date) {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return }
        var found: [String] = []
        for case let url as URL in files {
            if Self.skipped.contains(url.lastPathComponent) {
                files.skipDescendants()
                continue
            }
            guard url.pathExtension == "jsonl",
                  let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  mtime > cutoff else { continue }
            found.append(url.path)
        }
        known = found

        let live = Set(found)
        let sessions = Set(turns.map(\.session)).union(found.map { Self.session(of: URL(fileURLWithPath: $0)) })
        let before = marks.count + projectOfSession.count + customTitles.count + agentNames.count
        marks = marks.filter { live.contains($0.key) }
        projectOfSession = projectOfSession.filter { sessions.contains($0.key) }
        customTitles = customTitles.filter { sessions.contains($0.key) }
        agentNames = agentNames.filter { sessions.contains($0.key) }
        if marks.count + projectOfSession.count + customTitles.count + agentNames.count < before { dirty = true }
        // Repos come and go (a git init, a deleted checkout); look them up afresh now and then.
        projectOfCwd.removeAll(keepingCapacity: true)
    }

    private func read(_ url: URL, from start: UInt64, inode: UInt64, cutoff: Date) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: start)) != nil else { return false }

        // Chunked, so the first scan of a few hundred MB of logs never sits in memory at once.
        var changed = false
        var offset = start
        var pending = Data()
        while true {
            let chunk: Data? = autoreleasepool { try? handle.read(upToCount: 4 << 20) }
            guard let chunk, !chunk.isEmpty else { break }
            pending.append(chunk)
            var lineStart = pending.startIndex
            while let newline = pending[lineStart...].firstIndex(of: 0x0A) {
                let line = pending[lineStart..<newline]
                lineStart = newline + 1
                if line.range(of: Self.usageMarker) != nil, line.range(of: Self.assistantMarker) != nil {
                    autoreleasepool {
                        if let turn = parseTurn(Data(line)), turn.at >= cutoff, keep(turn) { changed = true }
                    }
                } else if line.count < 4096,
                          line.range(of: Self.titleMarker) != nil || line.range(of: Self.agentMarker) != nil {
                    parseTitle(Data(line))
                }
            }
            offset += UInt64(lineStart - pending.startIndex)
            pending = Data(pending[lineStart...])
        }
        // A partial last line is left for the next pass.
        marks[url.path] = Mark(offset: offset, inode: inode)
        return changed
    }

    /// Adds a new turn, or folds a later copy into the one already held. True if anything changed.
    private func keep(_ turn: Turn) -> Bool {
        if let i = position[turn.key], i < turns.count, turns[i].key == turn.key {
            guard turns[i].grows(turn) else { return false }
            turns[i] = turns[i].merged(with: turn)
            return true
        }
        if let last = turns.last, turn.at < last.at { unsorted = true }
        position[turn.key] = turns.count
        turns.append(turn)
        return true
    }

    private func parseTurn(_ line: Data) -> Turn? {
        guard let entry = try? decoder.decode(LogLine.self, from: line),
              entry.type == "assistant",
              let message = entry.message, let usage = message.usage,
              let model = message.model, model != "<synthetic>",
              let stamp = entry.timestamp,
              let at = isoFrac.date(from: stamp) ?? iso.date(from: stamp) else { return nil }

        let key = (message.id ?? UUID().uuidString) + "|" + (entry.requestId ?? "")
        let project = project(for: entry.cwd ?? "")
        let session = entry.sessionId ?? "?"
        projectOfSession[session] = project

        let write1h = usage.cache_creation?.ephemeral_1h_input_tokens ?? 0
        let writeAll = usage.cache_creation_input_tokens ?? 0
        let write5m = usage.cache_creation?.ephemeral_5m_input_tokens ?? max(0, writeAll - write1h)
        return Turn(key: key, at: at, project: project, model: model, session: session,
                    input: usage.input_tokens ?? 0, output: usage.output_tokens ?? 0,
                    cacheRead: usage.cache_read_input_tokens ?? 0, write5m: write5m,
                    write1h: write1h, fast: usage.speed == "fast")
    }

    private func parseTitle(_ line: Data) {
        guard let entry = try? decoder.decode(TitleLine.self, from: line),
              let session = entry.sessionId else { return }
        if entry.type == "custom-title", let title = entry.customTitle, !title.isEmpty {
            customTitles[session] = title
        } else if entry.type == "agent-name", let name = entry.agentName, !name.isEmpty {
            agentNames[session] = name
        }
    }

    /// Names a working directory by its repo, so `Surge/web/src` counts as Surge.
    private func project(for cwd: String) -> String {
        if let known = projectOfCwd[cwd] { return known }
        guard !cwd.isEmpty, cwd != "/" else { return "unknown" }
        var path = cwd
        if let r = path.range(of: "/.claude/worktrees/") { path = String(path[..<r.lowerBound]) }
        var dir = URL(fileURLWithPath: path)
        var name = dir.lastPathComponent
        // Checking for .git on an unreachable network volume can hang the scan; name it by folder.
        let remote = path.hasPrefix("/Volumes/") || path.hasPrefix("/net/")
        while !remote && dir.path != "/" && dir.path != NSHomeDirectory() {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                name = dir.lastPathComponent
                break
            }
            dir.deleteLastPathComponent()
        }
        projectOfCwd[cwd] = name
        return name
    }

    /// `<session>.jsonl`, or anything under `<session>/subagents/`: a subagent, or a workflow's
    /// agents at `<session>/subagents/workflows/wf_…/agent-x.jsonl`.
    private static func session(of url: URL) -> String {
        let parts = url.pathComponents
        if let i = parts.lastIndex(of: "subagents"), i > 0 { return parts[i - 1] }
        return url.deletingPathExtension().lastPathComponent
    }

    // MARK: Cache

    private struct IndexCache: Codable {
        /// 2: turns keep their largest copy; files are tracked by inode.
        static let version = 2
        var version = IndexCache.version
        var marks: [String: Mark]
        var turns: [Turn]
        var projectOfSession: [String: String]
        var customTitles: [String: String]
        var agentNames: [String: String]
    }

    private static let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeMeter")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("index.plist")
    }()

    /// Picks up where the last run stopped. A missing or older cache just means a full scan.
    func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let cache = try? PropertyListDecoder().decode(IndexCache.self, from: data),
              cache.version == IndexCache.version else { return }
        let cutoff = Date().addingTimeInterval(-horizon)
        marks = cache.marks
        turns = cache.turns.filter { $0.at >= cutoff }.sorted { $0.at < $1.at }
        reindex()
        projectOfSession = cache.projectOfSession
        customTitles = cache.customTitles
        agentNames = cache.agentNames
        lastSaved = Date()
    }

    /// Writes at most every five minutes unless forced (on quit).
    func saveCache(force: Bool = false) {
        guard dirty || force, force || Date().timeIntervalSince(lastSaved) > 300 else { return }
        let cache = IndexCache(marks: marks, turns: turns, projectOfSession: projectOfSession,
                               customTitles: customTitles, agentNames: agentNames)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        if let data = try? encoder.encode(cache) {
            try? data.write(to: Self.cacheURL, options: .atomic)
            lastSaved = Date()
            dirty = false
        }
    }
}

/// The few fields of a transcript line this app reads.
private struct LogLine: Decodable {
    let type: String?
    let timestamp: String?
    let requestId: String?
    let sessionId: String?
    let cwd: String?
    let message: Message?

    struct Message: Decodable {
        let id: String?
        let model: String?
        let usage: Usage?
    }

    struct Usage: Decodable {
        let input_tokens: Int?
        let output_tokens: Int?
        let cache_read_input_tokens: Int?
        let cache_creation_input_tokens: Int?
        let cache_creation: CacheCreation?
        let speed: String?
    }

    struct CacheCreation: Decodable {
        let ephemeral_5m_input_tokens: Int?
        let ephemeral_1h_input_tokens: Int?
    }
}

/// A session's title, as the desktop app or the user set it.
private struct TitleLine: Decodable {
    let type: String?
    let sessionId: String?
    let customTitle: String?
    let agentName: String?
}
