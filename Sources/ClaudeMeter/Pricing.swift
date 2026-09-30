import Foundation

/// API list prices in $ per million tokens. Used to weight turns so a limit can be
/// estimated from spend; subscription limits are not published in tokens.
/// Cache writes are 1.25x input (5m TTL) and 2x input (1h TTL). Fast mode is 2x.
struct Price {
    let input: Double
    let output: Double
    let cacheRead: Double
}

enum Pricing {
    /// A prefix covers the model and its dated snapshots ("claude-opus-4" covers
    /// "claude-opus-4-20250514"), never another version ("claude-opus-4-1" is its own row).
    static let table: [(prefix: String, price: Price)] = [
        ("claude-fable-5-1", Price(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-mythos-5-1", Price(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-fable-5", Price(input: 10, output: 50, cacheRead: 1.0)),
        ("claude-mythos-5", Price(input: 10, output: 50, cacheRead: 1.0)),
        ("claude-opus-5-5", Price(input: 4, output: 20, cacheRead: 0.20)),
        ("claude-opus-5", Price(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-8", Price(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-7", Price(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-6", Price(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-5", Price(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-1", Price(input: 15, output: 75, cacheRead: 1.50)),
        ("claude-opus-4", Price(input: 15, output: 75, cacheRead: 1.50)),
        ("claude-sonnet-5-5", Price(input: 2, output: 10, cacheRead: 0.20)),
        ("claude-sonnet-5", Price(input: 2, output: 10, cacheRead: 0.20)),
        ("claude-sonnet-4-6", Price(input: 3, output: 15, cacheRead: 0.30)),
        ("claude-sonnet-4-5", Price(input: 3, output: 15, cacheRead: 0.30)),
        ("claude-sonnet-4", Price(input: 3, output: 15, cacheRead: 0.30)),
        ("claude-haiku-4-5", Price(input: 1, output: 5, cacheRead: 0.10)),
    ]

    /// The newest price in each family, for a model the table doesn't know yet: a release
    /// after this was written shouldn't count as free, or as its predecessor's price.
    static let families: [(word: String, price: Price)] = [
        ("fable", Price(input: 10, output: 50, cacheRead: 0.25)),
        ("mythos", Price(input: 10, output: 50, cacheRead: 0.25)),
        ("opus", Price(input: 4, output: 20, cacheRead: 0.20)),
        ("sonnet", Price(input: 2, output: 10, cacheRead: 0.20)),
        ("haiku", Price(input: 1, output: 5, cacheRead: 0.10)),
    ]

    static func price(for model: String) -> Price? {
        if let row = table.filter({ covers($0.prefix, model) }).max(by: { $0.prefix.count < $1.prefix.count }) {
            return row.price
        }
        return families.first { model.contains($0.word) }?.price
    }

    /// True when `model` is `prefix` itself or one of its snapshots: what follows is nothing,
    /// a date, or a suffix like "[1m]", but not another version number.
    private static func covers(_ prefix: String, _ model: String) -> Bool {
        guard model.hasPrefix(prefix) else { return false }
        let rest = model.dropFirst(prefix.count)
        guard let first = rest.first else { return true }
        guard first == "-" else { return first == "[" || first == "@" }
        let next = rest.dropFirst().prefix { $0 != "-" }
        return !(next.count <= 2 && Int(next) != nil)
    }

    static func cost(model: String, input: Int, output: Int, cacheRead: Int,
                     write5m: Int, write1h: Int, fast: Bool) -> Double {
        guard let p = price(for: model) else { return 0 }
        let dollars = Double(input) * p.input
            + Double(output) * p.output
            + Double(cacheRead) * p.cacheRead
            + Double(write5m) * p.input * 1.25
            + Double(write1h) * p.input * 2
        return dollars / 1_000_000 * (fast ? 2 : 1)
    }
}
