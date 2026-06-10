import Foundation

struct BridgeReviewGeneration: Codable, Comparable, Equatable, ExpressibleByIntegerLiteral, Hashable, Sendable {
    let rawValue: Int

    init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    init(integerLiteral value: Int) {
        self.rawValue = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(Int.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    func next() -> Self {
        Self(rawValue + 1)
    }
}
