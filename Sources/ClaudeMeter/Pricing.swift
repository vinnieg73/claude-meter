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
    /// Longest matching prefix wins, so "claude-opus-4-8" beats "claude-opus-4".
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
        ("claude-opus-4", Price(input: 15, output: 75, cacheRead: 1.50)),
        ("claude-sonnet-5", Price(input: 2, output: 10, cacheRead: 0.20)),
        ("claude-sonnet-4", Price(input: 3, output: 15, cacheRead: 0.30)),
        ("claude-haiku-4-5", Price(input: 1, output: 5, cacheRead: 0.10)),
    ]

    static func price(for model: String) -> Price? {
        table.filter { model.hasPrefix($0.prefix) }
            .max { $0.prefix.count < $1.prefix.count }?
            .price
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
