import Foundation

/// The Claude desktop app's title for each Claude Code session it runs ("Claude Meter workbench"),
/// by transcript session id. Read from the app's own session records, which aren't a documented
/// format: if they move or change, this finds nothing and sessions are named as before.
final class DesktopTitles {
    private static let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Claude/claude-code-sessions")

    private struct Record: Decodable {
        let cliSessionId: String?
        let title: String?
    }

    /// Each record read, by path, with the modification date it was read at.
    private var read: [String: (mtime: Date, id: String?, title: String?)] = [:]
    private let decoder = JSONDecoder()

    /// Titles by session id. Only records changed since the last call are read again.
    func refresh() -> [String: String] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = FileManager.default.enumerator(at: Self.root, includingPropertiesForKeys: keys) else {
            read = [:]
            return [:]
        }
        var next: [String: (mtime: Date, id: String?, title: String?)] = [:]
        for case let url as URL in files where url.pathExtension == "json" && url.lastPathComponent.hasPrefix("local_") {
            let mtime = (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            if let old = read[url.path], old.mtime == mtime {
                next[url.path] = old
                continue
            }
            let record = (try? Data(contentsOf: url)).flatMap { try? decoder.decode(Record.self, from: $0) }
            next[url.path] = (mtime, record?.cliSessionId, record?.title)
        }
        read = next
        // Oldest first, so where two records share a session id the newer title wins, the same every time.
        var titles: [String: String] = [:]
        for r in read.values.sorted(by: { $0.mtime < $1.mtime }) {
            guard let id = r.id, let title = r.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { continue }
            titles[id] = title
        }
        return titles
    }
}
