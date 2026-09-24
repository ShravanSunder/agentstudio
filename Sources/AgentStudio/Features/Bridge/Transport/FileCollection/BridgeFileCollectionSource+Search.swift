import AgentStudioCore
import Foundation

/// The collection state a search answer must still match to be trusted: the
/// live source generation and the membership revision whose groups attributed
/// the matches.
struct BridgeFileCollectionSearchFence: Equatable, Sendable {
    let source: BridgeProductNavigationFileSource
    let membershipRevision: Int
    /// Members whose source failed; their files are absent from any result.
    let unavailableMemberWorktreeIds: [UUID]
}

extension BridgeFileCollectionSource {
    /// The fence for the live, announced subscription; nil when the page has
    /// no accepted Files source to search.
    func searchFence() -> BridgeFileCollectionSearchFence? {
        guard
            let context = contextBySubscriptionId.values.first(where: \.collectionSourceAccepted)
        else { return nil }
        return BridgeFileCollectionSearchFence(
            source: BridgeProductNavigationFileSource(
                sourceId: context.productSource.sourceId,
                subscriptionGeneration: context.productSource.subscriptionGeneration
            ),
            membershipRevision: membershipRevision,
            unavailableMemberWorktreeIds: context.memberAvailability
                .filter { $0.value == .failed }
                .map(\.key)
                .sorted { $0.uuidString < $1.uuidString }
        )
    }
}
