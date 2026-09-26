import Foundation

/// Strict tagged-object decoding shared by the standalone pane-link contract.
/// A case accepts exactly its documented keys, including associated values.
enum BridgeContractWire {
    struct Key: CodingKey, Hashable {
        let stringValue: String
        let intValue: Int?

        init(_ stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }

        static let kind = Self("kind")
        static let effect = Self("effect")
        static let operationId = Self("operationId")
        static let removedContributions = Self("removedContributions")
        static let reason = Self("reason")
        static let provider = Self("provider")
        static let sessionRef = Self("sessionRef")
        static let worktreeId = Self("worktreeId")
        static let worktree = Self("worktree")
        static let pullRequest = Self("pullRequest")
        static let host = Self("host")
        static let owner = Self("owner")
        static let repository = Self("repository")
        static let number = Self("number")
        static let relativePath = Self("relativePath")
        static let line = Self("line")
        static let target = Self("target")
        static let requestedBy = Self("requestedBy")
        static let retainedAt = Self("retainedAt")
        static let receiver = Self("receiver")
        static let item = Self("item")
        static let removedBy = Self("removedBy")
        static let generation = Self("generation")
    }

    static func decode(
        _ decoder: Decoder,
        fieldsByKind: [String: Set<String>]
    ) throws -> KeyedDecodingContainer<Key> {
        let container = try decoder.container(keyedBy: Key.self)
        let kind = try container.decode(String.self, forKey: .kind)
        guard let fields = fieldsByKind[kind] else { throw invalidKind(decoder) }
        let actual = Set(container.allKeys.map(\.stringValue))
        let expected = fields.union(["kind"])
        guard actual == expected else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "\(kind) requires exactly \(expected.sorted())"
                ))
        }
        return container
    }

    static func decodeFields(
        _ decoder: Decoder,
        required: Set<String>,
        optional: Set<String> = []
    ) throws -> KeyedDecodingContainer<Key> {
        let container = try decoder.container(keyedBy: Key.self)
        let actual = Set(container.allKeys.map(\.stringValue))
        guard required.isSubset(of: actual), actual.isSubset(of: required.union(optional)) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Object requires \(required.sorted()), optional \(optional.sorted())"
                ))
        }
        return container
    }

    static func invalidKind(_ decoder: Decoder) -> DecodingError {
        .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown contract kind"))
    }
}
