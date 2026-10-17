import Foundation

/// The Claude desktop app's title for each Claude Code session it runs ("Claude Meter workbench"),
/// by transcript session id. Read from the app's own session records, which aren't a documented
/// format: if they move or change, this finds nothing and sessions are named as before.
///
/// A Remote Control session the app never named keeps the placeholder "Remote Control session
/// (from a project)"; its thread's title lives only on Claude's servers. Those count as untitled,
/// and the app's one-line summary of the session's latest turn names them instead, when it has one.
final class DesktopTitles {
    struct Names {
        /// Titles the app or the user gave.
        var titles: [String: String] = [:]
        /// The app's summary of what each untitled session last did.
        var summaries: [String: String] = [:]
    }

    private static let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Claude/claude-code-sessions")

    private struct Record: Decodable {
        let cliSessionId: String?
        let title: String?
        let postTurnSummary: Summary?

        struct Summary: Decodable {
            let status_detail: String?
        }
    }

    private typealias Entry = (mtime: Date, id: String?, title: String?, summary: String?)

    /// Each record read, by path, with the modification date it was read at.
    private var read: [String: Entry] = [:]
    private let decoder = JSONDecoder()

    /// Names by session id. Only records changed since the last call are read again.
    func refresh() -> Names {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = FileManager.default.enumerator(at: Self.root, includingPropertiesForKeys: keys) else {
            read = [:]
            return Names()
        }
        var next: [String: Entry] = [:]
        for case let url as URL in files where url.pathExtension == "json" && url.lastPathComponent.hasPrefix("local_") {
            let mtime = (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            if let old = read[url.path], old.mtime == mtime {
                next[url.path] = old
                continue
            }
            let record = (try? Data(contentsOf: url)).flatMap { try? decoder.decode(Record.self, from: $0) }
            next[url.path] = (mtime, record?.cliSessionId, record?.title, record?.postTurnSummary?.status_detail)
        }
        read = next
        // Oldest first, so where two records share a session id the newer title wins, the same every time
        // (records written in the same instant go by path, not by the dictionary's order).
        var names = Names()
        let ordered = read.sorted { $0.value.mtime != $1.value.mtime ? $0.value.mtime < $1.value.mtime : $0.key < $1.key }
        for r in ordered.map(\.value) {
            guard let id = r.id, let title = Self.clean(r.title) else { continue }
            if !title.hasPrefix(Self.placeholder) {
                names.titles[id] = title
            } else if let summary = Self.clean(r.summary) {
                names.summaries[id] = Self.capitalized(summary)
            }
        }
        return names
    }

    /// "removed leftover worktrees" reads as a name once it starts with a capital; "v0.9.17 mascots"
    /// and "fetch.py install" would read wrong with one, so only a plain lowercase word gets it.
    private static func capitalized(_ text: String) -> String {
        let first = text.prefix { $0 != " " }
        guard first.allSatisfy({ $0.isLetter && $0.isLowercase }) else { return text }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// What the app calls a Remote Control session it has no title for.
    private static let placeholder = "Remote Control session"

    /// One line, trimmed, or nil if empty.
    private static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let line = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        return line.isEmpty ? nil : line
    }
}
