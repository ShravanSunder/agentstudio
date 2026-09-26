import Foundation

/// An ordered fact after a durable removal that deleted another author's
/// contribution. The producer, not this contract, owns commit and emission.
package struct BridgeLinkContributionsRemoved: Hashable, Sendable, Codable {
    package let receiver: PaneId
    package let item: BridgeLinkItem
    package let removedContributions: [BridgeLinkContributor]
    package let removedBy: BridgeLinkContributor
    package let generation: Int

    package init(
        receiver: PaneId,
        item: BridgeLinkItem,
        removedContributions: [BridgeLinkContributor],
        removedBy: BridgeLinkContributor,
        generation: Int
    ) throws {
        guard removedContributions.contains(where: { $0 != removedBy }), generation > 0 else {
            throw BridgeLinkIdentityError.invalidEncoding
        }
        self.receiver = receiver
        self.item = item
        self.removedContributions = removedContributions
        self.removedBy = removedBy
        self.generation = generation
    }

    package init(from decoder: Decoder) throws {
        let container = try BridgeContractWire.decodeFields(
            decoder,
            required: ["receiver", "item", "removedContributions", "removedBy", "generation"]
        )
        try self.init(
            receiver: container.decode(PaneId.self, forKey: .receiver),
            item: container.decode(BridgeLinkItem.self, forKey: .item),
            removedContributions: container.decode(
                [BridgeLinkContributor].self, forKey: .removedContributions
            ),
            removedBy: container.decode(BridgeLinkContributor.self, forKey: .removedBy),
            generation: container.decode(Int.self, forKey: .generation)
        )
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: BridgeContractWire.Key.self)
        try container.encode(receiver, forKey: .receiver)
        try container.encode(item, forKey: .item)
        try container.encode(removedContributions, forKey: .removedContributions)
        try container.encode(removedBy, forKey: .removedBy)
        try container.encode(generation, forKey: .generation)
    }
}
