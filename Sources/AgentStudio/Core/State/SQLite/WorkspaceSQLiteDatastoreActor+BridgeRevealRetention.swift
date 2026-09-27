import Foundation

extension WorkspaceSQLiteDatastoreActor {
    package func previewAgentReveal(
        workspaceID: UUID, receiver: BridgeReceiver,
        target: BridgeRevealFileTarget,
        topologySnapshot: BridgeReceiverTopologySnapshot
    ) throws -> BridgeRevealAdmissionPreflight {
        try preparedLocalRepository(workspaceId: workspaceID).previewAgentReveal(
            receiver: receiver, target: target, topologySnapshot: topologySnapshot)
    }

    package func retainAgentReveal(
        context: BridgeLinkMutationContext, target: BridgeRevealFileTarget,
        requestedBy: BridgeLinkContributor, retainedAt: Date
    ) throws -> BridgeRevealRetentionReceipt {
        let repository = try preparedLocalRepository(workspaceId: context.workspaceID)
        let (record, result) = try repository.retainAgentReveal(
            receiver: context.receiver, target: target, requestedBy: requestedBy,
            generation: context.generation, retainedAt: retainedAt,
            topologySnapshot: context.topologySnapshot)
        bridgeCommitSequence += 1
        return BridgeRevealRetentionReceipt(
            record: record, result: result, commitSequence: bridgeCommitSequence,
            generationFloor: try repository.latestBridgeGeneration())
    }

    package func clearRetainedOpenViewItem(
        context: BridgeLinkMutationContext, location: BridgeDocumentLocation
    ) throws -> BridgeRevealRetentionReceipt {
        let repository = try preparedLocalRepository(workspaceId: context.workspaceID)
        let (record, result) = try repository.clearRetainedOpenViewItem(
            receiver: context.receiver, location: location,
            generation: context.generation, topologySnapshot: context.topologySnapshot)
        bridgeCommitSequence += 1
        return BridgeRevealRetentionReceipt(
            record: record, result: result, commitSequence: bridgeCommitSequence,
            generationFloor: try repository.latestBridgeGeneration())
    }

    package func retainedOpenViewItems(
        workspaceID: UUID, receiver: BridgeReceiver
    ) throws -> [BridgeRetainedOpenViewItem] {
        try preparedLocalRepository(workspaceId: workspaceID).retainedOpenViewItems(receiver: receiver)
    }
}
