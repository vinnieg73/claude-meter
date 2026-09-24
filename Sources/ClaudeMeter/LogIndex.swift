import Foundation

/// One model response, as Claude Code logged it.
struct Turn {
    let at: Date
    let project: String
    let model: String
    let session: String
    let cost: Double
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheWrite: Int

    var tokens: Int { input + output + cacheRead + cacheWrite }
}

/// Tails ~/.claude/projects/**/*.jsonl. Keeps a byte offset per file so each refresh
/// reads only what was appended. Only touched from one serial queue.
final class LogIndex: @unchecked Sendable {
    private let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")
    /// A weekly window never reaches back further than this.
    private let horizon: TimeInterval = 8 * 86400
    private let activeWindow: TimeInterval = 180

    private var offsets: [String: UInt64] = [:]
    /// Claude Code writes a turn once per content block, each copy carrying the same usage.
    private var seen: Set<String> = []
    private var projectOfCwd: [String: String] = [:]
    private var projectOfSession: [String: String] = [:]

    private(set) var turns: [Turn] = []
    /// One entry per session whose log was written in the last few minutes.
    private(set) var activeProjects: [String] = []

    private static let usageMarker = Data("\"usage\"".utf8)
    private static let assistantMarker = Data("\"assistant\"".utf8)
    private let decoder = JSONDecoder()
    private let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let iso = ISO8601DateFormatter()

    /// Reads whatever was appended since the last call. Returns true if new turns arrived.
    @discardableResult
    func refresh() -> Bool {
        let now = Date()
        let cutoff = now.addingTimeInterval(-horizon)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else {
            return false
        }
        var added = false
        var activeSessions: Set<String> = []

        for case let url as URL in files where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let mtime = values.contentModificationDate, mtime > cutoff,
                  let size = values.fileSize else { continue }
            let path = url.path
            if now.timeIntervalSince(mtime) < activeWindow {
                activeSessions.insert(Self.session(of: url))
            }
            var start = offsets[path] ?? 0
            if UInt64(size) < start { start = 0 } // rewritten; `seen` absorbs the repeats
            guard UInt64(size) > start else { continue }
            if read(url, from: start, cutoff: cutoff) { added = true }
        }

        if added {
            turns.removeAll { $0.at < cutoff }
            turns.sort { $0.at < $1.at }
        }
        activeProjects = activeSessions.map { projectOfSession[$0] ?? "…" }.sorted()
        return added
    }

    private func read(_ url: URL, from start: UInt64, cutoff: Date) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: start)) != nil else { return false }

        // Chunked, so the first scan of a few hundred MB of logs never sits in memory at once.
        var added = false
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
                guard line.range(of: Self.usageMarker) != nil,
                      line.range(of: Self.assistantMarker) != nil else { continue }
                autoreleasepool {
                    if let turn = parse(Data(line)), turn.at >= cutoff {
                        turns.append(turn)
                        added = true
                    }
                }
            }
            offset += UInt64(lineStart - pending.startIndex)
            pending = Data(pending[lineStart...])
        }
        // A partial last line is left for the next pass.
        offsets[url.path] = offset
        return added
    }

    private func parse(_ line: Data) -> Turn? {
        guard let entry = try? decoder.decode(LogLine.self, from: line),
              entry.type == "assistant",
              let message = entry.message, let usage = message.usage,
              let model = message.model, model != "<synthetic>",
              let stamp = entry.timestamp,
              let at = isoFrac.date(from: stamp) ?? iso.date(from: stamp) else { return nil }

        let key = (message.id ?? UUID().uuidString) + "|" + (entry.requestId ?? "")
        guard seen.insert(key).inserted else { return nil }

        let project = project(for: entry.cwd ?? "")
        let session = entry.sessionId ?? "?"
        projectOfSession[session] = project

        let write1h = usage.cache_creation?.ephemeral_1h_input_tokens ?? 0
        let writeAll = usage.cache_creation_input_tokens ?? 0
        let write5m = usage.cache_creation?.ephemeral_5m_input_tokens ?? max(0, writeAll - write1h)
        let input = usage.input_tokens ?? 0
        let output = usage.output_tokens ?? 0
        let cacheRead = usage.cache_read_input_tokens ?? 0

        return Turn(
            at: at, project: project, model: model, session: session,
            cost: Pricing.cost(model: model, input: input, output: output, cacheRead: cacheRead,
                               write5m: write5m, write1h: write1h, fast: usage.speed == "fast"),
            input: input, output: output, cacheRead: cacheRead, cacheWrite: write5m + write1h
        )
    }

    /// Names a working directory by its repo, so `Surge/web/src` counts as Surge.
    private func project(for cwd: String) -> String {
        if let known = projectOfCwd[cwd] { return known }
        guard !cwd.isEmpty else { return "unknown" }
        var path = cwd
        if let r = path.range(of: "/.claude/worktrees/") { path = String(path[..<r.lowerBound]) }
        var dir = URL(fileURLWithPath: path)
        var name = dir.lastPathComponent
        while dir.path != "/" && dir.path != NSHomeDirectory() {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                name = dir.lastPathComponent
                break
            }
            dir.deleteLastPathComponent()
        }
        projectOfCwd[cwd] = name
        return name
    }

    /// `<session>.jsonl`, or `<session>/subagents/agent-x.jsonl` for a subagent.
    private static func session(of url: URL) -> String {
        let parent = url.deletingLastPathComponent()
        if parent.lastPathComponent == "subagents" {
            return parent.deletingLastPathComponent().lastPathComponent
        }
        return url.deletingPathExtension().lastPathComponent
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
