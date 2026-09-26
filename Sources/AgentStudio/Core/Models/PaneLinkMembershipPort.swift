import Foundation

/// Receiver link authority. App composition supplies `contributor` from the
/// authenticated caller binding; request parameters never nominate an author.
/// Implementations run admission and durable effects off MainActor.
package protocol PaneLinkMembershipPort: Sendable {
    func addMember(
        receiver: PaneId, item: BridgeLinkItem, contributor: BridgeLinkContributor
    ) async throws -> BridgeMemberAddResult

    func removeMember(
        receiver: PaneId, item: BridgeLinkItem, contributor: BridgeLinkContributor
    ) async throws -> BridgeMemberRemoveResult

    func awaitPendingMemberRemoval(
        receiver: PaneId, operationId: UUID
    ) async throws -> BridgePendingMemberRemovalSettlement

    func addPullRequestReference(
        receiver: PaneId, item: BridgeLinkItem, contributor: BridgeLinkContributor
    ) async throws -> BridgePullRequestReferenceAddResult

    func removePullRequestReference(
        receiver: PaneId, item: BridgeLinkItem, contributor: BridgeLinkContributor
    ) async throws -> BridgePullRequestReferenceRemoveResult

    /// The producer uses `BridgeLinkMembershipFactBuffering.policy`. Facts are
    /// post-commit, ordered and emitted only for another author's removal.
    func membershipFacts() async -> AsyncStream<BridgeLinkContributionsRemoved>
}

package enum BridgeLinkMembershipFactBuffering {
    /// Removal facts are low-rate and cannot silently drop an owner change.
    package static let policy: AsyncStream<BridgeLinkContributionsRemoved>.Continuation.BufferingPolicy = .unbounded
}
