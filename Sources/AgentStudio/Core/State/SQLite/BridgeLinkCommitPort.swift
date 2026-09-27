import Foundation

package struct BridgeLinkMutationContext: Sendable {
    package let workspaceID: UUID
    package let receiver: BridgeReceiver
    package let generation: Int
    package let topologySnapshot: BridgeReceiverTopologySnapshot

    package init(
        workspaceID: UUID, receiver: BridgeReceiver, generation: Int,
        topologySnapshot: BridgeReceiverTopologySnapshot
    ) {
        self.workspaceID = workspaceID
        self.receiver = receiver
        self.generation = generation
        self.topologySnapshot = topologySnapshot
    }
}

package struct BridgeLinkCommitReceipt<Outcome: Sendable>: Sendable {
    package let record: BridgeNavigationRecord
    package let result: Outcome
    package let commitSequence: UInt64
    package let generationFloor: Int

    package init(record: BridgeNavigationRecord, result: Outcome, commitSequence: UInt64, generationFloor: Int) {
        self.record = record
        self.result = result
        self.commitSequence = commitSequence
        self.generationFloor = generationFloor
    }
}

package struct BridgeCatalogMemberRemovalReceipt: Sendable {
    package let record: BridgeNavigationRecord
    package let result: BridgeMemberRemovalOutcome
    package let commitSequence: UInt64
    package let generationFloor: Int
    package let deletedContributors: [BridgeLinkContributor]

    package init(
        record: BridgeNavigationRecord, result: BridgeMemberRemovalOutcome,
        commitSequence: UInt64, generationFloor: Int,
        deletedContributors: [BridgeLinkContributor]
    ) {
        self.record = record
        self.result = result
        self.commitSequence = commitSequence
        self.generationFloor = generationFloor
        self.deletedContributors = deletedContributors
    }
}

/// Commit-first link boundary. The App handler publishes only an acknowledged
/// record, and its in-process commit sequence fences out-of-order callbacks.
package protocol BridgeLinkCommitPort: Sendable {
    func prepareBridgeCommittedLinkApplication(
        committedRecord: BridgeNavigationRecord, latestUIRecord: BridgeNavigationRecord,
        topologySnapshot: BridgeReceiverTopologySnapshot, removedWorktreeID: UUID?,
        removedRoot: String?
    ) async -> BridgeCommittedLinkApplication

    func previewBridgeCatalogMemberRemoval(
        workspaceID: UUID, receiver: BridgeReceiver, worktreeID: UUID,
        removedRoot: String, memberRootsByWorktreeID: [UUID: String]
    ) async throws -> BridgeMemberRemovalOutcome

    func commitBridgeCatalogMemberRemoval(
        workspaceID: UUID, receiver: BridgeReceiver, worktreeID: UUID, generation: Int,
        removedRoot: String, memberRootsByWorktreeID: [UUID: String]
    ) async throws -> BridgeCatalogMemberRemovalReceipt

    func previewBridgeMemberRemoval(
        workspaceID: UUID, receiver: BridgeReceiver, worktreeID: UUID,
        contributor: BridgeLinkContributor, topologySnapshot: BridgeReceiverTopologySnapshot
    ) async throws -> BridgeMemberRemovalPreview

    func commitBridgeMemberAddition(
        context: BridgeLinkMutationContext, worktreeID: UUID,
        contributor: BridgeLinkContributor, addedAt: Date
    ) async throws -> BridgeLinkCommitReceipt<BridgeMemberAddResult>

    func commitBridgeMemberRemoval(
        context: BridgeLinkMutationContext, worktreeID: UUID,
        contributor: BridgeLinkContributor
    ) async throws -> BridgeLinkCommitReceipt<BridgeMemberContributionRemoval>

    func commitBridgePullRequestAddition(
        context: BridgeLinkMutationContext, identity: ForgePullRequestIdentity,
        contributor: BridgeLinkContributor, addedAt: Date
    ) async throws -> BridgeLinkCommitReceipt<BridgePullRequestReferenceAddResult>

    func commitBridgePullRequestRemoval(
        context: BridgeLinkMutationContext, identity: ForgePullRequestIdentity,
        contributor: BridgeLinkContributor
    ) async throws -> BridgeLinkCommitReceipt<BridgePullRequestContributionRemoval>
}

extension WorkspaceSQLiteDatastoreActor: BridgeLinkCommitPort {}
