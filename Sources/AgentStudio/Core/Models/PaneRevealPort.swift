import Foundation

/// Reveal admission and settlement are separate. Agent admission can settle
/// without a mounted page; human Open uses the later draft barrier.
/// Implementations perform validation, scheduling and page work off MainActor.
package protocol PaneRevealPort: Sendable {
    func admitAgentReveal(
        receiver: PaneId, target: BridgeRevealFileTarget, requestedBy: BridgeLinkContributor
    ) async throws -> BridgeRevealAdmissionResult

    func awaitAgentRevealSettlement(
        receiver: PaneId, operationId: UUID
    ) async throws -> BridgeAgentRevealSettlement

    func openRetainedViewItem(
        receiver: PaneId, target: BridgeRevealFileTarget
    ) async throws -> BridgeHumanOpenSettlement

    func retainedOpenViewItems(receiver: PaneId) async -> [BridgeRetainedOpenViewItem]
}
