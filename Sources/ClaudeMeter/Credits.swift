import AppKit
import Foundation
import SwiftUI

// Console API credits: the prepaid balance on platform.claude.com that pays for API calls made with an
// API key (Parlay Builder's research runs on it). No API returns that balance, so the card starts from
// the number you type in from the Console. With a Console key in the keychain, the Admin API's cost
// report (real billed spend in daily UTC buckets, about 5 minutes behind) is taken off it as you spend.
// The key is read with /usr/bin/security, held in memory for one read, and never written anywhere.

/// The balance you typed in, saved in the app's defaults.
struct CreditAnchor: Codable, Equatable {
    /// What the Console showed as left when you typed it.
    var left: Double
    var setAt: Date
    /// The grant's size, for "of $146.88" and the bar.
    var granted: Double?
    /// The last day the credits can be used (a local date; they lapse when it ends).
    var expires: Date?
    /// What the cost report already had in `setAt`'s UTC day at the first read that day, so the rest of
    /// that day still counts. Nil until such a read; with none that day, counting starts the next UTC day.
    var baseline: Double?
}

/// The last cost report read.
struct CreditRead: Codable {
    /// ok, no_key, rejected, forbidden, rate_limited, error
    var state: String
    var triedAt: Date
    var readAt: Date?
    /// Billed spend since the balance was typed in, as of `readAt`.
    var spent: Double?
    /// The average over the last 7 whole UTC days.
    var perDay: Double?
    /// The `setAt` of the balance these numbers count from, so a new balance never shows an old read.
    var anchorAt: Date?
}

/// The card's numbers.
struct CreditsView {
    var left: Double
    var granted: Double?
    var expires: Date?
    var setAt: Date
    /// Spend is counted from the cost report.
    var live = false
    var readAt: Date?
    var spent: Double?
    var perDay: Double?
    /// Why spend isn't counted when a key is there but the read failed.
    var problem: String?
    var expired = false

    /// When the balance hits zero at the 7-day pace; nil without a pace.
    var runsOut: Date? {
        guard live, let perDay, perDay >= 0.01, left > 0, let readAt else { return nil }
        return readAt.addingTimeInterval(left / perDay * 86400)
    }

    /// The moment the credits lapse: the end of the expiry day, local time.
    var lapses: Date? {
        expires.flatMap { Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: $0)) }
    }
}

enum ConsoleCredits {
    static let anchorKey = "consoleCredits"
    static let readKey = "consoleCreditsRead"
    /// The keychain item you add the key under (Help gives the command).
    static let keychainService = "Claude Meter Console key"

    // MARK: Saved state

    static func loadAnchor() -> CreditAnchor? { decode(anchorKey) }
    static func saveAnchor(_ a: CreditAnchor?) { encode(a, anchorKey) }
    static func loadRead() -> CreditRead? { decode(readKey) }
    static func saveRead(_ r: CreditRead?) { encode(r, readKey) }

    private static func decode<T: Decodable>(_ key: String) -> T? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(T.self, from: d)
    }

    private static func encode<T: Encodable>(_ value: T?, _ key: String) {
        guard let value else { return UserDefaults.standard.removeObject(forKey: key) }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(value) { UserDefaults.standard.set(d, forKey: key) }
    }

    // MARK: The card

    static func view(anchor: CreditAnchor?, read: CreditRead?, now: Date = Date()) -> CreditsView? {
        guard let anchor else { return nil }
        var v = CreditsView(left: anchor.left, granted: anchor.granted, expires: anchor.expires, setAt: anchor.setAt)
        v.expired = v.lapses.map { now >= $0 } ?? false
        guard let read, read.anchorAt == anchor.setAt else { return v }
        switch read.state {
        case "ok":
            break
        case "no_key":
            return v
        case "rejected":
            v.problem = "The Console key in your keychain was turned down, so spend isn't counted."
            return v
        case "forbidden":
            v.problem = "That key can't read costs (an individual account, or a workspace key). See Help."
            return v
        default:
            // A failed read keeps the last good numbers; with none yet, the typed balance stands.
            guard read.readAt != nil else {
                v.problem = "Couldn't reach the cost report. Trying again in 15 minutes."
                return v
            }
        }
        guard let spent = read.spent, let at = read.readAt else { return v }
        v.live = true
        v.readAt = at
        v.spent = spent
        v.perDay = read.perDay
        v.left = anchor.left - spent
        return v
    }

    // MARK: The cost report

    struct Bucket { var start: Date; var amount: Double }

    /// One page: its buckets (dollars) and the next page's token. Nil when it isn't a cost report.
    static func parse(_ json: [String: Any]) -> (buckets: [Bucket], next: String?)? {
        guard let data = json["data"] as? [Any] else { return nil }
        var out: [Bucket] = []
        for case let b as [String: Any] in data {
            guard let start = date(b["starting_at"]) else { continue }
            // Amounts are cents as decimal strings ("123.78912" is $1.24).
            let cents = ((b["results"] as? [Any]) ?? []).reduce(0.0) { sum, r in
                guard let r = r as? [String: Any], (r["currency"] as? String ?? "USD") == "USD" else { return sum }
                let raw = r["amount"]
                let value = (raw as? String).flatMap(Double.init) ?? (raw as? NSNumber)?.doubleValue ?? 0
                return sum + (value.isFinite ? value : 0)
            }
            out.append(Bucket(start: start, amount: cents / 100))
        }
        let more = json["has_more"] as? Bool ?? false
        return (out, more ? json["next_page"] as? String : nil)
    }

    private static func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    private static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Spend since the balance was typed in, the 7-day pace, and the typing day's baseline once known.
    static func tally(_ buckets: [Bucket], anchor: CreditAnchor, now: Date) -> (spent: Double, perDay: Double?, baseline: Double?) {
        let cal = utc
        let typedDay = cal.startOfDay(for: anchor.setAt)
        let today = cal.startOfDay(for: now)
        var byDay: [Date: Double] = [:]
        for b in buckets { byDay[cal.startOfDay(for: b.start), default: 0] += b.amount }
        var baseline = anchor.baseline
        if baseline == nil, today == typedDay { baseline = byDay[typedDay] ?? 0 }
        let from = baseline != nil ? typedDay : typedDay.addingTimeInterval(86400)
        let spent = byDay.filter { $0.key >= from }.values.reduce(0, +) - (baseline ?? 0)
        let weekStart = today.addingTimeInterval(-7 * 86400)
        let week = byDay.filter { $0.key >= weekStart && $0.key < today }
        let perDay = week.isEmpty ? nil : week.values.reduce(0, +) / 7
        return (max(0, spent), perDay, baseline)
    }

    private enum Fetched {
        case success([String: Any])
        case failure(String)
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral // no cookies or cache on disk
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()

    private static func fetch(key: String, from: Date, page: String?) async -> Fetched {
        guard var comps = URLComponents(string: "https://api.anthropic.com/v1/organizations/cost_report") else { return .failure("error") }
        var q = [URLQueryItem(name: "starting_at", value: ISO8601DateFormatter().string(from: from)),
                 URLQueryItem(name: "bucket_width", value: "1d"),
                 URLQueryItem(name: "limit", value: "31")]
        if let page { q.append(URLQueryItem(name: "page", value: page)) }
        comps.queryItems = q
        guard let url = comps.url else { return .failure("error") }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "GET"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        req.setValue("ClaudeMeter/\(version)", forHTTPHeaderField: "User-Agent")
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) } catch { return .failure("error") }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300:
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .failure("error") }
            return .success(json)
        case 401: return .failure("rejected")
        case 403, 404: return .failure("forbidden")
        case 429: return .failure("rate_limited")
        default: return .failure("error")
        }
    }

    /// One read: every page from the earlier of the typing day and a week back.
    static func read(anchor: CreditAnchor, now: Date = Date()) async -> (CreditRead, baseline: Double?) {
        var r = CreditRead(state: "error", triedAt: now, anchorAt: anchor.setAt)
        let key = await withCheckedContinuation { c in
            DispatchQueue.global(qos: .utility).async { c.resume(returning: Credentials.keychainSecret(service: keychainService)) }
        }
        guard let key else {
            r.state = "no_key"
            return (r, nil)
        }
        let cal = utc
        let from = min(cal.startOfDay(for: anchor.setAt), cal.startOfDay(for: now).addingTimeInterval(-7 * 86400))
        var buckets: [Bucket] = []
        var page: String?
        for _ in 0..<12 {
            switch await fetch(key: key, from: from, page: page) {
            case .failure(let state):
                r.state = state
                return (r, nil)
            case .success(let json):
                guard let p = parse(json) else { return (r, nil) }
                buckets += p.buckets
                page = p.next
            }
            if page == nil { break }
        }
        let t = tally(buckets, anchor: anchor, now: now)
        r.state = "ok"
        r.readAt = now
        r.spent = t.spent
        r.perDay = t.perDay
        return (r, t.baseline)
    }

    // MARK: Command line

    static func statusLines(now: Date = Date()) -> [String] {
        guard let a = loadAnchor() else { return ["api credits: not set"] }
        var line = "api credits: \(ConsoleCredits.money(a.left)) typed in \(Fmt.when(a.setAt))"
        if let g = a.granted { line += " of \(ConsoleCredits.money(g))" }
        if let e = a.expires { line += ", expires \(day.string(from: e))" }
        guard let r = loadRead(), r.anchorAt == a.setAt else { return [line, "api credits read: none yet"] }
        let age = Int(max(0, now.timeIntervalSince(r.triedAt)) / 60)
        var read = "api credits read: \(r.state), tried \(age)m ago"
        if let s = r.spent { read += ", spent \(ConsoleCredits.money(s)) since, \(ConsoleCredits.money(a.left - s)) left" }
        if let p = r.perDay { read += ", \(ConsoleCredits.money(p))/day over 7 days" }
        return [line, read]
    }

    /// `--credits-check [sample.json]`: one read, printed, saving nothing. With a file, its cost report
    /// JSON stands in for the network (a check of the parsing and the sums without a key).
    static func check(sample: String?) -> Int32 {
        let now = Date()
        let anchor = loadAnchor() ?? CreditAnchor(left: 100, setAt: now.addingTimeInterval(-3 * 86400))
        if let sample {
            guard let d = FileManager.default.contents(atPath: sample),
                  let json = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                  let p = parse(json) else {
                Swift.print("api credits: \(sample) isn't a cost report")
                return 1
            }
            for b in p.buckets { Swift.print("  \(ISO8601DateFormatter().string(from: b.start))  \(String(format: "$%.4f", b.amount))") }
            let t = tally(p.buckets, anchor: anchor, now: now)
            Swift.print("api credits (sample): \(p.buckets.count) buckets, next page \(p.next ?? "none"), "
                        + "spent \(ConsoleCredits.money(t.spent)) since \(Fmt.when(anchor.setAt)), "
                        + "per day \(t.perDay.map(money) ?? "none"), baseline \(t.baseline.map(Fmt.dollars) ?? "none")")
            return 0
        }
        final class Box: @unchecked Sendable { var value: (CreditRead, baseline: Double?)? }
        let done = DispatchSemaphore(value: 0)
        let box = Box()
        Task.detached {
            box.value = await read(anchor: anchor, now: now)
            done.signal()
        }
        // Long enough to answer a first macOS prompt to allow the keychain read.
        guard done.wait(timeout: .now() + 180) == .success, let (r, _) = box.value else {
            Swift.print("api credits: timed out (a keychain prompt left open?)")
            return 1
        }
        Swift.print("api credits: \(r.state)" + (r.spent.map { ", spent \(ConsoleCredits.money($0)) since \(Fmt.when(anchor.setAt))" } ?? "")
                    + (r.perDay.map { ", \(ConsoleCredits.money($0))/day over 7 days" } ?? "") + " (nothing saved)")
        return r.state == "ok" ? 0 : 1
    }

    /// Always with cents, like the Console: "$146.88", "$1,204.50".
    static func money(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: v)) ?? String(format: "$%.2f", v)
    }

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.timeZone = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()
}

/// Reads the cost report while a balance is set: soon after launch or a new balance, then every 15 minutes.
@MainActor
final class CreditsFeed {
    static let pollSeconds: TimeInterval = 900
    private(set) var anchor = ConsoleCredits.loadAnchor()
    private(set) var read = ConsoleCredits.loadRead()
    /// claude.ai usage credits, read with the Claude Code sign-in whether or not a Console balance is set.
    private(set) var plan = PlanCredits.load()
    var onChange: (@MainActor () -> Void)?
    private var running = false
    private var nextPoll = Date().addingTimeInterval(15)
    private var planRunning = false
    private var nextPlanPoll = Date().addingTimeInterval(25)

    func set(_ a: CreditAnchor?) {
        anchor = a
        ConsoleCredits.saveAnchor(a)
        if a == nil {
            read = nil
            ConsoleCredits.saveRead(nil)
        }
        nextPoll = .distantPast
        onChange?()
        tick()
    }

    func tick(now: Date = Date()) {
        tickPlan(now: now)
        guard let anchor, !running, now >= nextPoll else { return }
        running = true
        Task { [weak self] in
            let result = await ConsoleCredits.read(anchor: anchor, now: now)
            self?.finish(result, for: anchor)
        }
    }

    private func tickPlan(now: Date) {
        guard !planRunning, now >= nextPlanPoll else { return }
        planRunning = true
        Task { [weak self] in
            let r = await PlanCredits.read(now: now)
            guard let self else { return }
            self.planRunning = false
            self.nextPlanPoll = Date().addingTimeInterval(Self.pollSeconds)
            // A failed read keeps the last one, which the card dates.
            guard let r else { return }
            self.plan = r
            PlanCredits.save(r)
            self.onChange?()
        }
    }

    private func finish(_ result: (CreditRead, baseline: Double?), for a: CreditAnchor) {
        running = false
        nextPoll = Date().addingTimeInterval(Self.pollSeconds)
        guard anchor?.setAt == a.setAt else { return } // a new balance was typed in while it read
        var r = result.0
        // A failed read keeps the last good spend, marked with the failure.
        if r.state != "ok", r.state != "no_key", let last = read, last.anchorAt == a.setAt, last.readAt != nil {
            r.readAt = last.readAt
            r.spent = last.spent
            r.perDay = last.perDay
        }
        read = r
        ConsoleCredits.saveRead(r)
        if anchor?.baseline == nil, let b = result.baseline {
            anchor?.baseline = b
            ConsoleCredits.saveAnchor(anchor)
        }
        onChange?()
    }
}

// MARK: - The dropdown's card

struct CreditsCard: View {
    let c: CreditsView
    var edit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("API credits").font(Theme.title).accessibilityAddTraits(.isHeader)
                Chip(text: c.live ? "Console" : "Typed in")
                Spacer(minLength: 4)
                if c.live, let at = c.readAt, !c.expired {
                    Text("checked \(Fmt.ago(at))").font(Theme.meta).foregroundStyle(.secondary)
                } else {
                    Button(action: edit) {
                        HStack(spacing: 2) {
                            Text("Update")
                            Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .font(Theme.row)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Update API credits")
                }
            }
            if c.expired {
                Text("Expired \(c.expires.map { ConsoleCredits.day.string(from: $0) } ?? "")")
                    .font(Theme.heroUnit).foregroundStyle(.secondary)
                Text("Type in your new balance from the Console.").font(Theme.row).foregroundStyle(.secondary)
            } else {
                hero
                if let g = c.granted, g > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.track)
                            Capsule().fill(c.live ? Color.primary.opacity(0.62) : Theme.quiet)
                                .frame(width: geo.size.width * min(1, max(0, c.left / g)))
                        }
                    }
                    .frame(height: 5)
                    .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if c.live, let s = c.spent {
                        Text("Spent \(ConsoleCredits.money(s)) since \(ConsoleCredits.day.string(from: c.setAt))"
                             + (c.perDay.map { " · \(ConsoleCredits.money($0))/day this week" } ?? ""))
                    } else {
                        Text("Typed in \(Fmt.when(c.setAt)). Spend since isn't counted.")
                    }
                }
                .font(Theme.row)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                footer
            }
        }
        .monospacedDigit()
    }

    private var hero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(ConsoleCredits.money(max(0, c.left))).font(Theme.hero)
            Text("left").font(Theme.heroUnit)
            if let g = c.granted, g > 0 {
                Text("of \(ConsoleCredits.money(g))").font(Theme.row).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            // On the hero's line, so the card stays a line shorter in a tall dropdown.
            if let e = c.expires {
                Text("expires \(ConsoleCredits.day.string(from: e)) · \(daysLeft(e))")
                    .font(Theme.meta).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The pace, a problem, or how to count spend: one line under a hairline. Red only when the
    /// credits run out early.
    @ViewBuilder private var footer: some View {
        if let text = footerText {
            Text(text.words)
                .font(Theme.row)
                .fontWeight(text.alarm ? .medium : .regular)
                .foregroundStyle(text.alarm ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 5)
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
        }
    }

    private var footerText: (words: String, alarm: Bool)? {
        if let p = c.problem { return (p, false) }
        if c.left <= 0 { return ("Used up. API calls on this key will fail until more credits land.", true) }
        guard c.live else { return ("Add a Console key to count spend as it happens. See Help.", false) }
        guard let out = c.runsOut else { return c.perDay == nil ? nil : ("No spend this week.", false) }
        if let lapse = c.lapses {
            if out < lapse {
                let early = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: out),
                                                            to: Calendar.current.startOfDay(for: lapse)).day ?? 0
                return ("Runs out about \(ConsoleCredits.day.string(from: out))"
                        + (early > 1 ? ", \(early - 1) days before it expires." : ", just before it expires."), true)
            }
            let leftAtLapse = c.left - (c.perDay ?? 0) * lapse.timeIntervalSince(c.readAt ?? Date()) / 86400
            return ("At this pace, about \(Fmt.dollars(max(0, leftAtLapse).rounded())) is still left when it expires.", false)
        }
        return ("Lasts until about \(ConsoleCredits.day.string(from: out)) at this pace.", false)
    }

    private func daysLeft(_ expires: Date) -> String {
        let n = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                to: Calendar.current.startOfDay(for: expires)).day ?? 0
        return n == 0 ? "today" : n == 1 ? "tomorrow" : "\(n)d"
    }
}

// MARK: - Typing it in

/// A small dialog for the balance: what's left, the grant and its expiry. Opened from Settings or the
/// card's Update button only, never on its own.
@MainActor
enum CreditsEditor {
    enum Result { case save(CreditAnchor), remove, cancel }

    static func run(current: CreditAnchor?, shownLeft: Double?) -> Result {
        let left = field(shownLeft.map { String(format: "%.2f", $0) } ?? "", placeholder: "137.27")
        let granted = field(current?.granted.map { String(format: "%.2f", $0) } ?? "", placeholder: "Optional, e.g. 146.88")
        let hasExpiry = NSButton(checkboxWithTitle: "Expires on", target: nil, action: nil)
        hasExpiry.state = current?.expires != nil || current == nil ? .on : .off
        let picker = NSDatePicker()
        picker.datePickerElements = .yearMonthDay
        picker.datePickerStyle = .textFieldAndStepper
        picker.dateValue = current?.expires ?? Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        let grid = NSGridView(views: [
            [label("Left now ($)"), left],
            [label("Granted ($)"), granted],
            [hasExpiry, picker],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.frame = NSRect(x: 0, y: 0, width: 300, height: 86)

        var problem: String?
        while true {
            let alert = NSAlert()
            alert.messageText = "API credits"
            alert.informativeText = problem
                ?? "Copy the balance from the Console's Billing page (platform.claude.com/settings/billing): the total left across your credit grants."
            alert.accessoryView = grid
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            if current != nil { alert.addButton(withTitle: "Remove") }
            alert.window.initialFirstResponder = left
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                guard let l = amount(left.stringValue), l >= 0 else {
                    problem = "Type the amount left as a number, like 137.27."
                    continue
                }
                let g = amount(granted.stringValue)
                if !granted.stringValue.trimmingCharacters(in: .whitespaces).isEmpty, g == nil {
                    problem = "The grant should be a number, like 146.88, or left empty."
                    continue
                }
                return .save(CreditAnchor(left: l, setAt: Date(), granted: g.flatMap { $0 > 0 ? $0 : nil },
                                          expires: hasExpiry.state == .on ? Calendar.current.startOfDay(for: picker.dateValue) : nil))
            case .alertThirdButtonReturn:
                return .remove
            default:
                return .cancel
            }
        }
    }

    /// "$1,234.50" or "137.27" as dollars.
    static func amount(_ s: String) -> Double? {
        let cleaned = s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let v = Double(cleaned), v.isFinite else { return nil }
        return v
    }

    private static func field(_ value: String, placeholder: String) -> NSTextField {
        let f = NSTextField(string: value)
        f.placeholderString = placeholder
        f.widthAnchor.constraint(equalToConstant: 170).isActive = true
        return f
    }

    private static func label(_ s: String) -> NSTextField { NSTextField(labelWithString: s) }
}

// MARK: - claude.ai usage credits

/// Your Claude plan's usage credits (claude.ai › Settings › Usage): the prepaid balance that extra usage
/// draws on once a limit is reached, and this month's extra-usage spend against its monthly limit. Read
/// the way Claude Code's /usage reads them, GET only, with Claude Code's sign-in on this Mac (held in
/// memory, as for the cloud sessions list).
enum PlanCredits {
    struct Reading: Codable {
        var at: Date
        /// Prepaid balance in dollars; nil when the account has none to report.
        var balance: Double?
        var autoReload: Bool?
        /// Extra usage was ever turned on: without it (and no balance) there is nothing to show.
        var everOn = false
        var extraOn: Bool?
        var usedThisMonth: Double?
        var monthlyLimit: Double?
        var limitReached = false
    }

    static let readKey = "planCreditsRead"
    static func load() -> Reading? {
        guard let d = UserDefaults.standard.data(forKey: readKey) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Reading.self, from: d)
    }
    static func save(_ r: Reading) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(r) { UserDefaults.standard.set(d, forKey: readKey) }
    }

    /// Both reads. Nil when the usage report didn't answer; a failed balance read leaves `balance` nil.
    static func read(now: Date = Date()) async -> Reading? {
        guard let usage = await get("/api/oauth/usage").json else { return nil }
        let prepaid = await get("/api/oauth/organizations/:org/prepaid/credits").json
        return parse(usage: usage, prepaid: prepaid, at: now)
    }

    static func parse(usage: [String: Any], prepaid: [String: Any]?, at: Date) -> Reading {
        var r = Reading(at: at)
        if let x = usage["extra_usage"] as? [String: Any] {
            // Minor units: cents at the usual 2 decimal places.
            let scale = pow(10, (x["decimal_places"] as? NSNumber)?.doubleValue ?? 2)
            r.everOn = x["credits_ever_enabled"] as? Bool ?? false
            r.extraOn = x["is_enabled"] as? Bool
            r.usedThisMonth = (x["used_credits"] as? NSNumber).map { $0.doubleValue / scale }
            r.monthlyLimit = (x["monthly_limit"] as? NSNumber).map { $0.doubleValue / scale }
            r.limitReached = x["spend_limit_reached"] as? Bool ?? false
        }
        if let p = prepaid, let cents = (p["amount"] as? NSNumber)?.doubleValue {
            r.balance = cents / 100
            r.autoReload = (p["auto_reload_settings"] as? [String: Any])?["enabled"] as? Bool
        }
        return r
    }

    static func statusLines(now: Date = Date()) -> [String] {
        guard let r = load() else { return ["usage credits: not read yet"] }
        let age = Int(max(0, now.timeIntervalSince(r.at)) / 60)
        var line = "usage credits: read \(age)m ago"
        if let u = r.usedThisMonth, let l = r.monthlyLimit { line += ", extra usage \(ConsoleCredits.money(u)) of \(ConsoleCredits.money(l)) this month" }
        if r.limitReached { line += " (limit reached)" }
        if let on = r.extraOn { line += on ? ", on" : ", off" }
        if let b = r.balance { line += ", prepaid balance \(ConsoleCredits.money(b))" }
        return [line]
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()

    /// One GET with the Claude Code sign-in; the JSON, or the HTTP status as a word.
    static func get(_ path: String) async -> (json: [String: Any]?, state: String) {
        let creds = await withCheckedContinuation { c in
            DispatchQueue.global(qos: .utility).async { c.resume(returning: Credentials.current()) }
        }
        guard let creds else { return (nil, "signed_out") }
        let resolved = path.replacingOccurrences(of: ":org", with: creds.org ?? "")
        guard !(path.contains(":org") && creds.org == nil), let url = URL(string: "https://api.anthropic.com" + resolved) else {
            return (nil, "no_org")
        }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "GET"
        req.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) } catch { return (nil, "error") }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { return (nil, "http_\(code)") }
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any], "ok")
    }

    /// `--extra-check`: both reads, printed (amounts only, never the sign-in), saving nothing.
    static func check() -> Int32 {
        final class Box: @unchecked Sendable { var lines: [String] = [] }
        let done = DispatchSemaphore(value: 0)
        let box = Box()
        Task.detached {
            for path in ["/api/oauth/usage", "/api/oauth/organizations/:org/prepaid/credits"] {
                let r = await get(path)
                var line = "\(path): \(r.state)"
                if let j = r.json {
                    let keep = path.hasSuffix("usage") ? (j["extra_usage"] ?? NSNull()) : j as Any
                    if let d = try? JSONSerialization.data(withJSONObject: keep, options: [.sortedKeys, .fragmentsAllowed]) {
                        line += " " + String(decoding: d, as: UTF8.self)
                    }
                    if path.hasSuffix("usage") { line += " (top-level keys: \(j.keys.sorted().joined(separator: ", ")))" }
                }
                box.lines.append(line)
            }
            done.signal()
        }
        guard done.wait(timeout: .now() + 180) == .success else {
            Swift.print("usage credits: timed out (a keychain prompt left open?)")
            return 1
        }
        box.lines.forEach { Swift.print($0) }
        return 0
    }
}

/// The claude.ai usage credits card: this month's extra usage against its limit, and the prepaid balance.
struct UsageCreditsCard: View {
    let r: PlanCredits.Reading

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Usage credits").font(Theme.title).accessibilityAddTraits(.isHeader)
                Chip(text: "claude.ai")
                Spacer(minLength: 4)
                Text("checked \(Fmt.ago(r.at))").font(Theme.meta).foregroundStyle(.secondary)
            }
            if let used = r.usedThisMonth, let limit = r.monthlyLimit, limit > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(ConsoleCredits.money(used)).font(Theme.heroUnit)
                    Text("of \(ConsoleCredits.money(limit)) this month").font(Theme.row).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if let b = r.balance {
                        Text("balance \(ConsoleCredits.money(b))").font(Theme.meta).foregroundStyle(.secondary).fixedSize()
                    }
                }
                .accessibilityElement(children: .combine)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule().fill(r.limitReached ? Color.red : Color.primary.opacity(0.62))
                            .frame(width: geo.size.width * min(1, max(0, used / limit)))
                    }
                }
                .frame(height: 5)
                .accessibilityHidden(true)
            } else if let b = r.balance {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(ConsoleCredits.money(b)).font(Theme.heroUnit)
                    Text("prepaid balance").font(Theme.row).foregroundStyle(.secondary)
                }
            }
            if let line = status {
                Text(line.words)
                    .font(Theme.row)
                    .fontWeight(line.alarm ? .medium : .regular)
                    .foregroundStyle(line.alarm ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .monospacedDigit()
    }

    /// Red only when the monthly limit stops extra usage.
    private var status: (words: String, alarm: Bool)? {
        if r.limitReached { return ("Monthly limit reached. Extra usage is off.", true) }
        if r.extraOn == false { return ("Extra usage is off.", false) }
        if r.extraOn == true { return ("Extra usage is on.", false) }
        return nil
    }
}
