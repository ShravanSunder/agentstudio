import AgentStudioBridge
import AgentStudioCore
import Foundation

/// Maps durable contribution effects to the fixed immediate and terminal unions.
extension BridgePaneLinkMembershipActor {
    func processCWDAdmission(
        _ request: Request, worktreeID: UUID?, topology: BridgeReceiverTopologySnapshot
    ) async {
        if let worktreeID {
            guard mayDispatch(request) else { return }
            do {
                let committed = try await commitPort.commitBridgeMemberAddition(
                    context: mutationContext(request, topology: topology), worktreeID: worktreeID,
                    contributor: .app, addedAt: Date()
                )
                await publish(
                    committed.record, request: request, topology: topology,
                    removedWorktreeID: nil,
                    previousDerivedWorktreeID: request.previousDerivedWorktreeID
                )
                finishDispatchedCommit(request.id)
                return
            } catch {
                bridgePaneLinkMembershipLogger.error(
                    "App contribution commit failed for receiver \(request.receiver.paneId)"
                )
                finishDispatchedCommit(request.id)
            }
        }
        await publishDerivedDeparture(request: request, topology: topology)
    }

    func publish(
        _ committed: BridgeNavigationRecord, request: Request,
        topology: BridgeReceiverTopologySnapshot, removedWorktreeID: UUID?, removedRoot: String? = nil,
        previousDerivedWorktreeID: UUID? = nil
    ) async {
        while true {
            let latest = await handler.latestLinkRecord(for: request.receiver)
            let reconciledLatest = reconcileDepartedDerivedCWD(
                in: latest.record, previousDerivedWorktreeID: previousDerivedWorktreeID,
                topology: topology
            )
            let prepared = await commitPort.prepareBridgeCommittedLinkApplication(
                committedRecord: committed, latestUIRecord: reconciledLatest,
                topologySnapshot: topology, removedWorktreeID: removedWorktreeID,
                removedRoot: removedRoot
            )
            let application = BridgeCommittedLinkApplication(
                record: prepared.record,
                openedDocumentUpdates: BridgeOpenedDocumentAtomUpdate.difference(
                    from: latest.record, to: prepared.record),
                memberRoots: prepared.memberRoots,
                reviewReplacement: prepared.reviewReplacement
                    ?? (prepared.record.reviewSelection == latest.record.reviewSelection
                        ? nil : prepared.record.surface)
            )
            let reviewSurface: BridgeProductSurface?
            switch application.reviewReplacement {
            case .files: reviewSurface = .file
            case .review: reviewSurface = .review
            case nil: reviewSurface = nil
            }
            if await handler.applyCommittedLinkApplication(
                application, for: request.receiver, ifRevision: latest.revision,
                reviewSurface: reviewSurface
            ) {
                return
            }
        }
    }

    /// A failed or absent new CWD contribution still removes a departed
    /// derived-only member from the live projection without a durable write.
    func publishDerivedDeparture(request: Request, topology: BridgeReceiverTopologySnapshot) async {
        guard request.previousDerivedWorktreeID != nil else { return }
        while true {
            let latest = await handler.latestLinkRecord(for: request.receiver)
            let reconciled = reconcileDepartedDerivedCWD(
                in: latest.record, previousDerivedWorktreeID: request.previousDerivedWorktreeID,
                topology: topology
            )
            let reviewSurface: BridgeProductSurface?
            if reconciled.reviewSelection != latest.record.reviewSelection {
                switch reconciled.surface {
                case .files: reviewSurface = .file
                case .review: reviewSurface = .review
                }
            } else {
                reviewSurface = nil
            }
            let application = BridgeCommittedLinkApplication(
                record: reconciled,
                openedDocumentUpdates: BridgeOpenedDocumentAtomUpdate.difference(
                    from: latest.record, to: reconciled),
                memberRoots: topology.effectiveMemberRoots(in: reconciled),
                reviewReplacement: reconciled.reviewSelection == latest.record.reviewSelection
                    ? nil : reconciled.surface
            )
            if await handler.applyCommittedLinkApplication(
                application, for: request.receiver, ifRevision: latest.revision,
                reviewSurface: reviewSurface
            ) {
                return
            }
        }
    }

    private func reconcileDepartedDerivedCWD(
        in latest: BridgeNavigationRecord, previousDerivedWorktreeID: UUID?,
        topology: BridgeReceiverTopologySnapshot
    ) -> BridgeNavigationRecord {
        guard let previousDerivedWorktreeID else { return latest }
        var previousContext = latest
        previousContext.derivedCurrentCWDWorktreeId = previousDerivedWorktreeID
        return BridgeNavigationRules.reconcilingDepartedDerivedCWD(
            previousDerivedWorktreeID: previousDerivedWorktreeID, in: latest,
            memberRootsByWorktreeId: topology.effectiveMemberRoots(in: previousContext)
        )
    }

    func emitRemovalFact(
        receiver: BridgeReceiver, item: BridgeLinkItem,
        removedContributions: [BridgeLinkContributor], removedBy: BridgeLinkContributor,
        generation: Int
    ) {
        guard
            let fact = try? BridgeLinkContributionsRemoved(
                receiver: PaneId(existingUUID: receiver.paneId), item: item,
                removedContributions: removedContributions, removedBy: removedBy,
                generation: generation
            )
        else { return }
        factsContinuation.yield(fact)
    }

    func removeCatalogMember(
        receiver: BridgeReceiver, worktreeID: UUID, removedRoot: String, sourcePaneID: UUID
    ) async -> Bool {
        let admitted = await handler.captureLinkIngress(sourcePaneID: sourcePaneID)
        return await withCheckedContinuation { continuation in
            enqueue(
                receiver: PaneId(existingUUID: receiver.paneId), sourcePaneID: sourcePaneID,
                admitted: admitted, mutation: .removeCatalogMember(worktreeID, removedRoot: removedRoot),
                reply: .catalogRemove(continuation)
            )
        }
    }

    func awaitPendingMemberRemoval(
        receiver: PaneId, operationId: UUID
    ) async throws -> BridgePendingMemberRemovalSettlement {
        guard let pending = pendingRemovals[operationId], pending.receiver.paneId == receiver.uuid else {
            throw BridgeLinkPortFailure.unavailable
        }
        switch pending.outcome {
        case .settled(let result):
            pendingRemovals.removeValue(forKey: operationId)
            return try result.get()
        case .waiting(let existingWaiter):
            guard existingWaiter == nil else { throw BridgeLinkPortFailure.unavailable }
            return try await withCheckedThrowingContinuation { continuation in
                guard let pending = pendingRemovals[operationId] else {
                    continuation.resume(throwing: BridgeLinkPortFailure.unavailable)
                    return
                }
                if case .waiting(nil) = pending.outcome {
                    pendingRemovals[operationId] = (pending.receiver, .waiting(continuation))
                } else {
                    continuation.resume(throwing: BridgeLinkPortFailure.unavailable)
                }
            }
        }
    }

    /// Human navigation still needs the terminal answer. IPC callers may use
    /// the immediate result and settle the returned operation separately.
    func removeMemberAndAwait(
        receiver: PaneId, worktree: WorktreeId, contributor: BridgeLinkContributor,
        sourcePaneID: UUID
    ) async throws -> BridgePendingMemberRemovalSettlement {
        let immediate = try await removeMember(
            receiver: receiver, worktree: worktree, contributor: contributor,
            sourcePaneID: sourcePaneID
        )
        switch immediate {
        case .removed(let contributions): return .removed(removedContributions: contributions)
        case .alreadyAbsent: return .alreadyAbsent
        case .refusedProtectedCurrentDirectory: return .refusedProtectedCurrentDirectory
        case .refusedNotAuthor: return .refusedNotAuthor
        case .staleOwner: return .staleOwner
        case .staleReceiver: return .staleReceiver
        case .pendingDraftSettlement(let operationID):
            return try await awaitPendingMemberRemoval(receiver: receiver, operationId: operationID)
        }
    }

    static func immediateRemovalResult(
        _ result: BridgeMemberContributionRemoval
    ) -> BridgeMemberRemoveResult? {
        switch result {
        case .removed: nil
        case .alreadyAbsent: .alreadyAbsent
        case .refusedProtectedCurrentDirectory: .refusedProtectedCurrentDirectory
        case .refusedNotAuthor: .refusedNotAuthor
        case .staleOwner: .staleOwner
        case .staleReceiver: .staleReceiver
        }
    }

    static func settlement(
        for result: BridgeMemberContributionRemoval
    ) -> BridgePendingMemberRemovalSettlement {
        switch result {
        case .removed(_, _, let removedContributions): .removed(removedContributions: removedContributions)
        case .alreadyAbsent: .alreadyAbsent
        case .refusedProtectedCurrentDirectory: .refusedProtectedCurrentDirectory
        case .refusedNotAuthor: .refusedNotAuthor
        case .staleOwner: .staleOwner
        case .staleReceiver: .staleReceiver
        }
    }

    static func immediateResult(
        for result: BridgePendingMemberRemovalSettlement
    ) -> BridgeMemberRemoveResult {
        switch result {
        case .removed(let contributions): .removed(removedContributions: contributions)
        case .alreadyAbsent: .alreadyAbsent
        case .refusedProtectedCurrentDirectory: .refusedProtectedCurrentDirectory
        case .refusedNotAuthor: .refusedNotAuthor
        case .staleOwner: .staleOwner
        case .staleReceiver: .staleReceiver
        case .draftKept, .membershipOutcomeUnknown:
            preconditionFailure("A removal without a draft wait cannot produce an asynchronous settlement")
        }
    }

    static func pullRequestRemovalResult(
        _ result: BridgePullRequestContributionRemoval
    ) -> BridgePullRequestReferenceRemoveResult {
        switch result {
        case .removed(_, let contributions): .removed(removedContributions: contributions)
        case .alreadyAbsent: .alreadyAbsent
        case .refusedNotAuthor: .refusedNotAuthor
        case .staleOwner: .staleOwner
        case .staleReceiver: .staleReceiver
        }
    }
}
