import AgentStudioBridge
import AgentStudioCore
import Foundation

@MainActor
extension BridgeNavigationCommandHandler {
    /// Copy existing write-owner facts. Resolution and validation are performed
    /// by the membership actor and datastore actor after this read-only hop.
    func captureLinkTopology(sourcePaneID: UUID) -> BridgeReceiverTopologySnapshot {
        BridgeReceiverTopologySnapshot(
            sourcePaneId: sourcePaneID,
            paneStatesByID: paneAtom?.captureBridgeLinkPaneFacts() ?? [:],
            companionEntriesBySourceID: panePresentationAtom?.zoomCompanionsBySourcePaneId ?? [:],
            repositoryTopology: repositoryTopologyAtom.captureReadSnapshot()
        )
    }

    func captureLinkIngress(
        sourcePaneID: UUID
    ) -> (topology: BridgeReceiverTopologySnapshot, generation: Int) {
        (captureLinkTopology(sourcePaneID: sourcePaneID), writeSequencer.nextTicket().value)
    }

    func prepareLinkRemovalDraft(for receiver: BridgeReceiver) async -> BridgeEditorPreparationOutcome? {
        await presentationPorts?.mountedPresentation(receiver)?.prepareActiveEditorsForNavigation()
    }

    func latestLinkRecord(
        for receiver: BridgeReceiver
    ) -> (record: BridgeNavigationRecord, revision: Int) {
        (navigationAtom.record(for: receiver) ?? .empty, navigationAtom.acceptedRevision)
    }

    /// All rules and reconciliation have completed off-main. This hop only
    /// applies a prepared record and the existing mounted presentation calls.
    func applyCommittedLinkApplication(
        _ application: BridgeCommittedLinkApplication,
        for receiver: BridgeReceiver,
        ifRevision revision: Int,
        reviewSurface: BridgeProductSurface?
    ) -> Bool {
        guard navigationAtom.acceptedRevision == revision else { return false }
        guard navigationAtom.setRecord(application.record, for: receiver) else { return true }
        presentationPorts?.refreshFilesSource(receiver)
        if let reviewSurface {
            _ = presentationPorts?.replaceReviewSource(receiver, reviewSurface)
        }
        return true
    }

    /// The CWD callback makes this O(1) ingress in the same MainActor turn;
    /// the actor's single stream preserves it before a later removal.
    func enqueueAppMemberContribution(
        _ worktreeID: UUID?, previousDerivedWorktreeID: UUID?, for receiver: BridgeReceiver
    ) {
        guard let linkMembershipActor else { return }
        let admitted = captureLinkIngress(sourcePaneID: receiver.paneId)
        linkMembershipActor.enqueueAppMemberContribution(
            receiver: receiver, worktreeID: worktreeID, sourcePaneID: receiver.paneId,
            topology: admitted.topology, generation: admitted.generation,
            previousDerivedWorktreeID: previousDerivedWorktreeID
        )
    }

    func addMemberLink(
        _ worktreeID: UUID,
        to receiver: BridgeReceiver,
        sourcePaneID: UUID,
        contributor: BridgeLinkContributor
    ) async throws -> BridgeMemberAddResult {
        guard let linkMembershipActor else { throw BridgeLinkPortFailure.unavailable }
        return try await linkMembershipActor.addMember(
            receiver: PaneId(existingUUID: receiver.paneId), worktree: worktreeID,
            contributor: contributor, sourcePaneID: sourcePaneID
        )
    }

    func removeMemberLink(
        _ worktreeID: UUID,
        from receiver: BridgeReceiver,
        sourcePaneID: UUID,
        contributor: BridgeLinkContributor
    ) async throws -> BridgePendingMemberRemovalSettlement {
        guard let linkMembershipActor else { throw BridgeLinkPortFailure.unavailable }
        return try await linkMembershipActor.removeMemberAndAwait(
            receiver: PaneId(existingUUID: receiver.paneId), worktree: worktreeID,
            contributor: contributor, sourcePaneID: sourcePaneID
        )
    }
}
