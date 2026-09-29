import AgentStudioCore
import Foundation

/// Handler sequencing tests use this contract stand-in. The real repository
/// transaction is proved separately in the storage integration suite.
actor BridgePaneLinkCommitTestPort: BridgeLinkCommitPort {
    func prepareBridgeCommittedLinkApplication(
        committedRecord: BridgeNavigationRecord, latestUIRecord: BridgeNavigationRecord,
        topologySnapshot: BridgeReceiverTopologySnapshot, removedWorktreeID: UUID?,
        removedRoot: String?
    ) async -> BridgeCommittedLinkApplication {
        var roots = memberRoots(latestUIRecord, topologySnapshot: topologySnapshot)
        if let removedWorktreeID, let removedRoot {
            roots[removedWorktreeID] =
                DarwinFSEventPathCanonicalizer.canonicalURL(
                    URL(fileURLWithPath: removedRoot)
                ).path
        } else if let removedWorktreeID, roots[removedWorktreeID] == nil,
            let worktree = topologySnapshot.repositoryTopology.worktree(removedWorktreeID)
        {
            roots[removedWorktreeID] = DarwinFSEventPathCanonicalizer.canonicalURL(worktree.path).path
        }
        let reconciled = BridgeNavigationRules.reconcilingCommittedLinks(
            committedRecord, with: latestUIRecord, removedWorktreeId: removedWorktreeID,
            memberRootsByWorktreeId: roots
        )
        return BridgeCommittedLinkApplication(
            record: reconciled,
            openedDocumentUpdates: BridgeOpenedDocumentAtomUpdate.difference(
                from: latestUIRecord, to: reconciled),
            memberRoots: roots,
            reviewReplacement: reconciled.reviewSelection == latestUIRecord.reviewSelection
                ? nil : reconciled.surface
        )
    }

    private let navigationAtom: BridgeNavigationAtom
    private var sequence: UInt64 = 0
    private(set) var commitCount = 0
    private var failNextCommit = false

    init(navigationAtom: BridgeNavigationAtom, failInitialCommit: Bool = false) {
        self.navigationAtom = navigationAtom
        self.failNextCommit = failInitialCommit
    }

    private func record(for receiver: BridgeReceiver) async -> BridgeNavigationRecord {
        await MainActor.run { navigationAtom.record(for: receiver) ?? .empty }
    }

    private func nextSequence() -> UInt64 {
        sequence += 1
        commitCount += 1
        return sequence
    }

    private func receipt<Outcome: Sendable>(
        _ record: BridgeNavigationRecord, _ result: Outcome, generation: Int
    ) -> BridgeLinkCommitReceipt<Outcome> {
        BridgeLinkCommitReceipt(
            record: record, result: result, commitSequence: nextSequence(),
            generationFloor: generation
        )
    }

    func failFollowingCommit() { failNextCommit = true }

    private func requireCommitAvailable() throws {
        guard !failNextCommit else {
            failNextCommit = false
            throw BridgeLinkPortFailure.unavailable
        }
    }

    func previewBridgeCatalogMemberRemoval(
        workspaceID _: UUID, receiver: BridgeReceiver, worktreeID: UUID,
        removedRoot: String, memberRootsByWorktreeID: [UUID: String]
    ) async throws -> BridgeMemberRemovalOutcome {
        var roots = memberRootsByWorktreeID
        roots[worktreeID] = removedRoot
        return BridgeNavigationRules.removingMember(
            worktreeID, from: await record(for: receiver), reason: .catalogUnregistration,
            memberRootsByWorktreeId: roots
        )
    }

    func commitBridgeCatalogMemberRemoval(
        workspaceID: UUID, receiver: BridgeReceiver, worktreeID: UUID, generation: Int,
        removedRoot: String, memberRootsByWorktreeID: [UUID: String]
    ) async throws -> BridgeCatalogMemberRemovalReceipt {
        let current = await record(for: receiver)
        let result = try await previewBridgeCatalogMemberRemoval(
            workspaceID: workspaceID, receiver: receiver, worktreeID: worktreeID,
            removedRoot: removedRoot, memberRootsByWorktreeID: memberRootsByWorktreeID
        )
        let updated: BridgeNavigationRecord
        let deletedContributors: [BridgeLinkContributor]
        if case .removed(let value, _) = result {
            updated = value
            deletedContributors =
                current.committedMemberLinks.first(where: { $0.worktreeId == worktreeID })?
                .contributions.map(\.addedBy) ?? []
        } else {
            updated = current
            deletedContributors = []
        }
        return BridgeCatalogMemberRemovalReceipt(
            record: updated, result: result, commitSequence: nextSequence(),
            generationFloor: generation, deletedContributors: deletedContributors
        )
    }

    func previewBridgeMemberRemoval(
        workspaceID _: UUID, receiver: BridgeReceiver, worktreeID: UUID,
        contributor: BridgeLinkContributor, topologySnapshot: BridgeReceiverTopologySnapshot
    ) async throws -> BridgeMemberRemovalPreview {
        guard let resolved = resolvedReceiver(in: topologySnapshot) else {
            return BridgeMemberRemovalPreview(result: .staleReceiver, requiresDraftBarrier: false)
        }
        guard resolved == receiver else {
            return BridgeMemberRemovalPreview(result: .staleOwner, requiresDraftBarrier: false)
        }
        let current = await record(for: receiver)
        let result = BridgeNavigationRules.removingMemberContribution(
            worktreeID, contributor: contributor, from: current,
            protectedWorktreeId: protectedWorktreeID(receiver: receiver, topologySnapshot: topologySnapshot),
            memberRootsByWorktreeId: memberRoots(current, topologySnapshot: topologySnapshot)
        )
        let requiresDraftBarrier: Bool
        if case .removed(_, let effect?, _) = result {
            requiresDraftBarrier = effect.clearedFilesSelection || effect.reviewFallback != .unchanged
        } else {
            requiresDraftBarrier = false
        }
        return BridgeMemberRemovalPreview(result: result, requiresDraftBarrier: requiresDraftBarrier)
    }

    func commitBridgeMemberAddition(
        context: BridgeLinkMutationContext, worktreeID: UUID,
        contributor: BridgeLinkContributor, addedAt: Date
    ) async throws -> BridgeLinkCommitReceipt<BridgeMemberAddResult> {
        try requireCommitAvailable()
        let receiver = context.receiver
        let topologySnapshot = context.topologySnapshot
        let generation = context.generation
        guard let resolved = resolvedReceiver(in: topologySnapshot) else {
            return receipt(await record(for: receiver), .staleReceiver, generation: generation)
        }
        guard resolved == receiver else {
            return receipt(await record(for: receiver), .staleOwner, generation: generation)
        }
        guard let worktree = topologySnapshot.repositoryTopology.worktree(worktreeID),
            topologySnapshot.repositoryTopology.validatedAssociation(
                repoId: worktree.repoId, worktreeId: worktreeID
            ) != nil
        else {
            return receipt(await record(for: receiver), .refusedUnknownWorktree, generation: generation)
        }
        let (updated, result) = BridgeNavigationRules.addingMemberContribution(
            worktreeID, contributor: contributor, addedAt: addedAt, to: await record(for: receiver)
        )
        return receipt(updated, result, generation: generation)
    }

    func commitBridgeMemberRemoval(
        context: BridgeLinkMutationContext, worktreeID: UUID,
        contributor: BridgeLinkContributor
    ) async throws -> BridgeLinkCommitReceipt<BridgeMemberContributionRemoval> {
        try requireCommitAvailable()
        let receiver = context.receiver
        let topologySnapshot = context.topologySnapshot
        let generation = context.generation
        let current = await record(for: receiver)
        guard let resolved = resolvedReceiver(in: topologySnapshot) else {
            return receipt(current, .staleReceiver, generation: generation)
        }
        guard resolved == receiver else {
            return receipt(current, .staleOwner, generation: generation)
        }
        let result = BridgeNavigationRules.removingMemberContribution(
            worktreeID, contributor: contributor, from: current,
            protectedWorktreeId: protectedWorktreeID(receiver: receiver, topologySnapshot: topologySnapshot),
            memberRootsByWorktreeId: memberRoots(current, topologySnapshot: topologySnapshot)
        )
        let updated: BridgeNavigationRecord
        if case .removed(let value, _, _) = result { updated = value } else { updated = current }
        return receipt(updated, result, generation: generation)
    }

    func commitBridgePullRequestAddition(
        context: BridgeLinkMutationContext, identity: ForgePullRequestIdentity,
        contributor: BridgeLinkContributor, addedAt: Date
    ) async throws -> BridgeLinkCommitReceipt<BridgePullRequestReferenceAddResult> {
        try requireCommitAvailable()
        let receiver = context.receiver
        let topologySnapshot = context.topologySnapshot
        let generation = context.generation
        guard let resolved = resolvedReceiver(in: topologySnapshot) else {
            return receipt(await record(for: receiver), .staleReceiver, generation: generation)
        }
        guard resolved == receiver else {
            return receipt(await record(for: receiver), .staleOwner, generation: generation)
        }
        let (updated, result) = BridgeNavigationRules.addingPullRequestContribution(
            identity, contributor: contributor, addedAt: addedAt, to: await record(for: receiver)
        )
        return receipt(updated, result, generation: generation)
    }

    func commitBridgePullRequestRemoval(
        context: BridgeLinkMutationContext, identity: ForgePullRequestIdentity,
        contributor: BridgeLinkContributor
    ) async throws -> BridgeLinkCommitReceipt<BridgePullRequestContributionRemoval> {
        try requireCommitAvailable()
        let receiver = context.receiver
        let topologySnapshot = context.topologySnapshot
        let generation = context.generation
        let current = await record(for: receiver)
        guard let resolved = resolvedReceiver(in: topologySnapshot) else {
            return receipt(current, .staleReceiver, generation: generation)
        }
        guard resolved == receiver else {
            return receipt(current, .staleOwner, generation: generation)
        }
        let result = BridgeNavigationRules.removingPullRequestContribution(
            identity, contributor: contributor, from: current
        )
        let updated: BridgeNavigationRecord
        if case .removed(let value, _) = result { updated = value } else { updated = current }
        return receipt(updated, result, generation: generation)
    }

    private func resolvedReceiver(in snapshot: BridgeReceiverTopologySnapshot) -> BridgeReceiver? {
        BridgeReceiverResolution.receiver(
            forCommandPaneId: snapshot.sourcePaneId,
            companionEntriesBySourceID: snapshot.companionEntriesBySourceID,
            paneStatesByID: snapshot.paneStatesByID
        )
    }

    private func protectedWorktreeID(
        receiver: BridgeReceiver, topologySnapshot: BridgeReceiverTopologySnapshot
    ) -> UUID? {
        guard receiver.kind == .terminalAssociated,
            let paneState = topologySnapshot.paneStatesByID[receiver.paneId]
        else { return nil }
        let facets = paneState.durableContextFacets
        return topologySnapshot.repositoryTopology.validatedAssociation(
            repoId: facets.repoId, worktreeId: facets.worktreeId
        )?.worktree.id
    }

    private func memberRoots(
        _ record: BridgeNavigationRecord, topologySnapshot: BridgeReceiverTopologySnapshot
    ) -> [UUID: String] {
        Dictionary(
            uniqueKeysWithValues: record.effectiveMemberWorktreeIds.compactMap { worktreeID in
                topologySnapshot.repositoryTopology.worktree(worktreeID).map {
                    (worktreeID, DarwinFSEventPathCanonicalizer.canonicalURL($0.path).path)
                }
            })
    }
}
