import AgentStudioBridge
import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import os

let bridgePaneLinkMembershipLogger = Logger(
    subsystem: "com.agentstudio", category: "BridgePaneLinkMembership"
)

/// Owns ordered link ingress and durable effects for one workspace. The handler
/// supplies raw facts and tickets; this actor owns every rule and wait after admission.
actor BridgePaneLinkMembershipActor: PaneLinkMembershipPort {
    enum Mutation: Sendable {
        case addMember(UUID, BridgeLinkContributor)
        case removeMember(UUID, BridgeLinkContributor)
        case addPullRequest(ForgePullRequestIdentity, BridgeLinkContributor)
        case removePullRequest(ForgePullRequestIdentity, BridgeLinkContributor)
        case removeCatalogMember(UUID, removedRoot: String)
        case admitCurrentCWD(UUID?)
        case idleBarrier
    }

    struct Request: Sendable {
        let id: Int
        let expectsReply: Bool
        let receiver: BridgeReceiver
        let sourcePaneID: UUID
        let admittedTopology: BridgeReceiverTopologySnapshot?
        let generation: Int
        let previousDerivedWorktreeID: UUID?
        let mutation: Mutation
    }

    enum Reply {
        case memberAdd(CheckedContinuation<BridgeMemberAddResult, Error>)
        case memberRemove(CheckedContinuation<BridgeMemberRemoveResult, Error>)
        case pullRequestAdd(CheckedContinuation<BridgePullRequestReferenceAddResult, Error>)
        case pullRequestRemove(CheckedContinuation<BridgePullRequestReferenceRemoveResult, Error>)
        case catalogRemove(CheckedContinuation<Bool, Never>)
        case idle(CheckedContinuation<Void, Never>)

        func fail(_ error: Error) {
            switch self {
            case .memberAdd(let continuation): continuation.resume(throwing: error)
            case .memberRemove(let continuation): continuation.resume(throwing: error)
            case .pullRequestAdd(let continuation): continuation.resume(throwing: error)
            case .pullRequestRemove(let continuation): continuation.resume(throwing: error)
            case .catalogRemove(let continuation): continuation.resume(returning: false)
            case .idle(let continuation): continuation.resume()
            }
        }
    }

    enum PendingOutcome {
        case waiting(CheckedContinuation<BridgePendingMemberRemovalSettlement, Error>?)
        case settled(Result<BridgePendingMemberRemovalSettlement, Error>)
    }

    let workspaceID: UUID
    let handler: BridgeNavigationCommandHandler
    let commitPort: any BridgeLinkCommitPort
    private let ingress: AsyncStream<Request>
    nonisolated private let ingressContinuation: AsyncStream<Request>.Continuation
    private let facts: AsyncStream<BridgeLinkContributionsRemoved>
    let factsContinuation: AsyncStream<BridgeLinkContributionsRemoved>.Continuation

    private var queuedByReceiver: [BridgeReceiver: [Request]] = [:]
    private var drainingReceivers: Set<BridgeReceiver> = []
    private var replies: [Int: Reply] = [:]
    private var dispatchedCommitIDs: Set<Int> = []
    var pendingRemovals: [UUID: (receiver: BridgeReceiver, outcome: PendingOutcome)] = [:]
    private var activePendingIDByReceiver: [BridgeReceiver: UUID] = [:]
    private var pendingRequestIDByOperationID: [UUID: Int] = [:]
    private var nextIdleBarrierID = -1
    private var stopped = false
    private var shutdownWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        workspaceID: UUID,
        handler: BridgeNavigationCommandHandler,
        commitPort: any BridgeLinkCommitPort
    ) {
        self.workspaceID = workspaceID
        self.handler = handler
        self.commitPort = commitPort
        // Human, CWD and bound-agent link edits are low-rate. Dropping one
        // would reorder authorship or lose a removal, so ingress is unbounded.
        let (ingress, ingressContinuation) = AsyncStream.makeStream(
            of: Request.self, bufferingPolicy: .unbounded
        )
        self.ingress = ingress
        self.ingressContinuation = ingressContinuation
        let (facts, factsContinuation) = AsyncStream.makeStream(
            of: BridgeLinkContributionsRemoved.self,
            bufferingPolicy: BridgeLinkMembershipFactBuffering.policy
        )
        self.facts = facts
        self.factsContinuation = factsContinuation
        Task { await consumeIngress() }
    }

    /// Called synchronously by the CWD presentation path after its raw capture
    /// and ticket. `yield` preserves its position before the next UI mutation.
    nonisolated func enqueueAppMemberContribution(
        receiver: BridgeReceiver, worktreeID: UUID?, sourcePaneID: UUID,
        topology: BridgeReceiverTopologySnapshot, generation: Int,
        previousDerivedWorktreeID: UUID?
    ) {
        ingressContinuation.yield(
            Request(
                id: generation, expectsReply: false,
                receiver: receiver, sourcePaneID: sourcePaneID,
                admittedTopology: topology, generation: generation,
                previousDerivedWorktreeID: previousDerivedWorktreeID,
                mutation: .admitCurrentCWD(worktreeID)
            ))
    }

    func membershipFacts() -> AsyncStream<BridgeLinkContributionsRemoved> { facts }

    /// A receiver-scoped ingress barrier, including requests still buffered in
    /// the stream when this call begins. It never observes an arbitrary delay.
    func awaitReceiverIdle(_ receiver: BridgeReceiver) async {
        await withCheckedContinuation { continuation in
            guard !stopped else {
                continuation.resume()
                return
            }
            let id = nextIdleBarrierID
            nextIdleBarrierID -= 1
            replies[id] = .idle(continuation)
            ingressContinuation.yield(
                Request(
                    id: id, expectsReply: true, receiver: receiver,
                    sourcePaneID: receiver.paneId, admittedTopology: nil,
                    generation: 0, previousDerivedWorktreeID: nil, mutation: .idleBarrier
                ))
        }
    }

    func addMember(
        receiver: PaneId, worktree: WorktreeId, contributor: BridgeLinkContributor
    ) async throws -> BridgeMemberAddResult {
        try await addMember(
            receiver: receiver, worktree: worktree, contributor: contributor,
            sourcePaneID: receiver.uuid
        )
    }

    func addMember(
        receiver: PaneId, worktree: WorktreeId, contributor: BridgeLinkContributor,
        sourcePaneID: UUID
    ) async throws -> BridgeMemberAddResult {
        try await submit(
            receiver: receiver, sourcePaneID: sourcePaneID,
            mutation: .addMember(worktree, contributor), reply: Reply.memberAdd
        )
    }

    func removeMember(
        receiver: PaneId, worktree: WorktreeId, contributor: BridgeLinkContributor
    ) async throws -> BridgeMemberRemoveResult {
        try await removeMember(
            receiver: receiver, worktree: worktree, contributor: contributor,
            sourcePaneID: receiver.uuid
        )
    }

    func removeMember(
        receiver: PaneId, worktree: WorktreeId, contributor: BridgeLinkContributor,
        sourcePaneID: UUID
    ) async throws -> BridgeMemberRemoveResult {
        try await submit(
            receiver: receiver, sourcePaneID: sourcePaneID,
            mutation: .removeMember(worktree, contributor), reply: Reply.memberRemove
        )
    }

    func addPullRequestReference(
        receiver: PaneId, reference: ForgePullRequestIdentity, contributor: BridgeLinkContributor
    ) async throws -> BridgePullRequestReferenceAddResult {
        try await addPullRequestReference(
            receiver: receiver, reference: reference, contributor: contributor,
            sourcePaneID: receiver.uuid
        )
    }

    func addPullRequestReference(
        receiver: PaneId, reference: ForgePullRequestIdentity, contributor: BridgeLinkContributor,
        sourcePaneID: UUID
    ) async throws -> BridgePullRequestReferenceAddResult {
        try await submit(
            receiver: receiver, sourcePaneID: sourcePaneID,
            mutation: .addPullRequest(reference, contributor), reply: Reply.pullRequestAdd
        )
    }

    func removePullRequestReference(
        receiver: PaneId, reference: ForgePullRequestIdentity, contributor: BridgeLinkContributor
    ) async throws -> BridgePullRequestReferenceRemoveResult {
        try await removePullRequestReference(
            receiver: receiver, reference: reference, contributor: contributor,
            sourcePaneID: receiver.uuid
        )
    }

    func removePullRequestReference(
        receiver: PaneId, reference: ForgePullRequestIdentity, contributor: BridgeLinkContributor,
        sourcePaneID: UUID
    ) async throws -> BridgePullRequestReferenceRemoveResult {
        try await submit(
            receiver: receiver, sourcePaneID: sourcePaneID,
            mutation: .removePullRequest(reference, contributor), reply: Reply.pullRequestRemove
        )
    }

    func enqueue(
        id: Int? = nil, receiver: PaneId, sourcePaneID: UUID,
        admitted: (topology: BridgeReceiverTopologySnapshot, generation: Int),
        mutation: Mutation, reply: Reply
    ) {
        guard !stopped else {
            reply.fail(BridgeLinkPortFailure.unavailable)
            return
        }
        let requestID = id ?? admitted.generation
        replies[requestID] = reply
        let resolved =
            BridgeReceiverResolution.receiver(
                forCommandPaneId: receiver.uuid,
                companionEntriesBySourceID: admitted.topology.companionEntriesBySourceID,
                paneStatesByID: admitted.topology.paneStatesByID
            ) ?? BridgeReceiver.terminal(receiver.uuid)
        ingressContinuation.yield(
            Request(
                id: requestID, expectsReply: true, receiver: resolved, sourcePaneID: sourcePaneID,
                admittedTopology: admitted.topology, generation: admitted.generation,
                previousDerivedWorktreeID: nil, mutation: mutation
            ))
    }

    private func submit<Output: Sendable>(
        receiver: PaneId, sourcePaneID: UUID, mutation: Mutation,
        reply makeReply: @escaping @Sendable (CheckedContinuation<Output, Error>) -> Reply
    ) async throws -> Output {
        let admitted = await handler.captureLinkIngress(sourcePaneID: sourcePaneID)
        try Task.checkCancellation()
        let requestID = admitted.generation
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                enqueue(
                    id: requestID, receiver: receiver, sourcePaneID: sourcePaneID,
                    admitted: admitted, mutation: mutation, reply: makeReply(continuation)
                )
            }
        } onCancel: {
            Task { await self.cancelBeforeDispatch(requestID) }
        }
    }

    private func cancelBeforeDispatch(_ requestID: Int) {
        guard !dispatchedCommitIDs.contains(requestID) else { return }
        takeReply(requestID)?.fail(CancellationError())
    }

    private func consumeIngress() async {
        for await request in ingress {
            guard !stopped else { continue }
            queuedByReceiver[request.receiver, default: []].append(request)
            if drainingReceivers.insert(request.receiver).inserted {
                Task { await drain(request.receiver) }
            }
        }
    }

    private func drain(_ receiver: BridgeReceiver) async {
        while !stopped, let request = queuedByReceiver[receiver]?.first {
            queuedByReceiver[receiver]?.removeFirst()
            if queuedByReceiver[receiver]?.isEmpty == true { queuedByReceiver.removeValue(forKey: receiver) }
            await process(request)
        }
        drainingReceivers.remove(receiver)
        finishShutdownIfReady()
    }

    private func process(_ request: Request) async {
        if request.expectsReply, replies[request.id] == nil { return }
        if case .idleBarrier = request.mutation {
            if case .idle(let continuation) = takeReply(request.id) { continuation.resume() }
            return
        }
        let topology = await handler.captureLinkTopology(sourcePaneID: request.sourcePaneID)
        switch request.mutation {
        case .addMember(let worktreeID, let contributor):
            await processMemberAddition(request, worktreeID: worktreeID, contributor: contributor, topology: topology)
        case .removeMember(let worktreeID, let contributor):
            await processMemberRemoval(request, worktreeID: worktreeID, contributor: contributor, topology: topology)
        case .addPullRequest(let reference, let contributor):
            await processPullRequestAddition(
                request, reference: reference, contributor: contributor, topology: topology)
        case .removePullRequest(let reference, let contributor):
            await processPullRequestRemoval(request, reference: reference, contributor: contributor, topology: topology)
        case .removeCatalogMember(let worktreeID, let removedRoot):
            await processCatalogRemoval(request, worktreeID: worktreeID, removedRoot: removedRoot, topology: topology)
        case .admitCurrentCWD(let worktreeID):
            await processCWDAdmission(request, worktreeID: worktreeID, topology: topology)
        case .idleBarrier: break
        }
    }

    private func processMemberAddition(
        _ request: Request, worktreeID: UUID, contributor: BridgeLinkContributor,
        topology: BridgeReceiverTopologySnapshot
    ) async {
        guard mayDispatch(request) else { return }
        do {
            let committed = try await commitPort.commitBridgeMemberAddition(
                context: mutationContext(request, topology: topology), worktreeID: worktreeID,
                contributor: contributor, addedAt: Date()
            )
            await publish(committed.record, request: request, topology: topology, removedWorktreeID: nil)
            if case .memberAdd(let continuation) = takeReply(request.id) {
                continuation.resume(returning: committed.result)
            }
            finishDispatchedCommit(request.id)
        } catch { failDispatched(request, error: error) }
    }

    private func processMemberRemoval(
        _ request: Request, worktreeID: UUID, contributor: BridgeLinkContributor,
        topology: BridgeReceiverTopologySnapshot
    ) async {
        do {
            let preview = try await commitPort.previewBridgeMemberRemoval(
                workspaceID: workspaceID, receiver: request.receiver, worktreeID: worktreeID,
                contributor: contributor, topologySnapshot: topology
            )
            if let immediate = Self.immediateRemovalResult(preview.result) {
                if case .memberRemove(let continuation) = takeReply(request.id) {
                    continuation.resume(returning: immediate)
                }
                return
            }
            if request.expectsReply, replies[request.id] == nil { return }
            var pendingID: UUID?
            if preview.requiresDraftBarrier {
                let operationID = UUIDv7.generate()
                pendingID = operationID
                pendingRemovals[operationID] = (request.receiver, .waiting(nil))
                activePendingIDByReceiver[request.receiver] = operationID
                pendingRequestIDByOperationID[operationID] = request.id
                if case .memberRemove(let continuation) = takeReply(request.id) {
                    continuation.resume(returning: .pendingDraftSettlement(operationId: operationID))
                }
                let preparation = await handler.prepareLinkRemovalDraft(for: request.receiver)
                guard !stopped else {
                    settlePending(operationID, .failure(BridgeLinkPortFailure.unavailable))
                    return
                }
                if let preparation {
                    let reason: BridgeDraftKeptReason?
                    switch preparation {
                    case .prepared, .noLivePage: reason = nil
                    case .refused: reason = .refused
                    case .saveFailed: reason = .saveFailed
                    case .saveOutcomeUnknown: reason = .saveOutcomeUnknown
                    }
                    if let reason {
                        settlePending(operationID, .success(.draftKept(reason: reason)))
                        return
                    }
                }
            }
            let effectTopology = await handler.captureLinkTopology(sourcePaneID: request.sourcePaneID)
            guard mayDispatch(request, pendingID: pendingID) else { return }
            let committed = try await commitPort.commitBridgeMemberRemoval(
                context: mutationContext(request, topology: effectTopology), worktreeID: worktreeID,
                contributor: contributor
            )
            await publish(
                committed.record, request: request, topology: effectTopology,
                removedWorktreeID: committed.result.removesEffectiveMember ? worktreeID : nil
            )
            let result = Self.settlement(for: committed.result)
            if case .removed(let removedContributions) = result {
                emitRemovalFact(
                    receiver: request.receiver, item: .worktree(worktreeID),
                    removedContributions: removedContributions, removedBy: contributor,
                    generation: request.generation
                )
            }
            if let pendingID {
                settlePending(pendingID, .success(result))
            } else if case .memberRemove(let continuation) = takeReply(request.id) {
                continuation.resume(returning: Self.immediateResult(for: result))
            }
            finishDispatchedCommit(request.id)
        } catch {
            if let pendingID = activePendingIDByReceiver[request.receiver] {
                let result: Result<BridgePendingMemberRemovalSettlement, Error> =
                    dispatchedCommitIDs.contains(request.id)
                    ? .success(.membershipOutcomeUnknown) : .failure(error)
                settlePending(pendingID, result)
                finishDispatchedCommit(request.id)
            } else {
                failDispatched(request, error: error)
            }
        }
    }

    private func processPullRequestAddition(
        _ request: Request, reference: ForgePullRequestIdentity, contributor: BridgeLinkContributor,
        topology: BridgeReceiverTopologySnapshot
    ) async {
        guard mayDispatch(request) else { return }
        do {
            let committed = try await commitPort.commitBridgePullRequestAddition(
                context: mutationContext(request, topology: topology), identity: reference,
                contributor: contributor, addedAt: Date()
            )
            await publish(committed.record, request: request, topology: topology, removedWorktreeID: nil)
            if case .pullRequestAdd(let continuation) = takeReply(request.id) {
                continuation.resume(returning: committed.result)
            }
            finishDispatchedCommit(request.id)
        } catch { failDispatched(request, error: error) }
    }

    private func processPullRequestRemoval(
        _ request: Request, reference: ForgePullRequestIdentity, contributor: BridgeLinkContributor,
        topology: BridgeReceiverTopologySnapshot
    ) async {
        guard mayDispatch(request) else { return }
        do {
            let committed = try await commitPort.commitBridgePullRequestRemoval(
                context: mutationContext(request, topology: topology), identity: reference,
                contributor: contributor
            )
            await publish(committed.record, request: request, topology: topology, removedWorktreeID: nil)
            let result = Self.pullRequestRemovalResult(committed.result)
            if case .removed(let removedContributions) = result {
                emitRemovalFact(
                    receiver: request.receiver, item: .pullRequest(reference),
                    removedContributions: removedContributions, removedBy: contributor,
                    generation: request.generation
                )
            }
            if case .pullRequestRemove(let continuation) = takeReply(request.id) {
                continuation.resume(returning: result)
            }
            finishDispatchedCommit(request.id)
        } catch { failDispatched(request, error: error) }
    }

    private func processCatalogRemoval(
        _ request: Request, worktreeID: UUID, removedRoot: String,
        topology: BridgeReceiverTopologySnapshot
    ) async {
        do {
            let latest = await handler.latestLinkRecord(for: request.receiver)
            let roots = topology.memberRoots(in: latest.record)
            let preview = try await commitPort.previewBridgeCatalogMemberRemoval(
                workspaceID: workspaceID, receiver: request.receiver, worktreeID: worktreeID,
                removedRoot: removedRoot, memberRootsByWorktreeID: roots
            )
            if case .removed(_, let effect) = preview,
                effect.clearedFilesSelection || effect.reviewFallback != .unchanged
            {
                let preparation = await handler.prepareLinkRemovalDraft(for: request.receiver)
                guard preparation?.allowsContentToLeave ?? true else {
                    if case .catalogRemove(let continuation) = takeReply(request.id) {
                        continuation.resume(returning: false)
                    }
                    return
                }
            }
            let effectTopology = await handler.captureLinkTopology(sourcePaneID: request.sourcePaneID)
            let current = await handler.latestLinkRecord(for: request.receiver)
            guard mayDispatch(request) else { return }
            let committed = try await commitPort.commitBridgeCatalogMemberRemoval(
                workspaceID: workspaceID, receiver: request.receiver, worktreeID: worktreeID,
                generation: request.generation, removedRoot: removedRoot,
                memberRootsByWorktreeID: effectTopology.memberRoots(in: current.record)
            )
            if case .removed = committed.result {
                await publish(
                    committed.record, request: request, topology: effectTopology,
                    removedWorktreeID: worktreeID, removedRoot: removedRoot
                )
                if committed.deletedContributors.contains(where: { $0 != .app }) {
                    emitRemovalFact(
                        receiver: request.receiver, item: .worktree(worktreeID),
                        removedContributions: committed.deletedContributors, removedBy: .app,
                        generation: request.generation
                    )
                }
            }
            if case .catalogRemove(let continuation) = takeReply(request.id) {
                continuation.resume(returning: true)
            }
            finishDispatchedCommit(request.id)
        } catch {
            bridgePaneLinkMembershipLogger.error("Catalog removal failed for receiver \(request.receiver.paneId)")
            if case .catalogRemove(let continuation) = takeReply(request.id) {
                continuation.resume(returning: false)
            }
            finishDispatchedCommit(request.id)
        }
    }

    func mutationContext(
        _ request: Request, topology: BridgeReceiverTopologySnapshot
    ) -> BridgeLinkMutationContext {
        BridgeLinkMutationContext(
            workspaceID: workspaceID, receiver: request.receiver, generation: request.generation,
            topologySnapshot: topology
        )
    }

    func mayDispatch(_ request: Request, pendingID: UUID? = nil) -> Bool {
        if request.expectsReply, pendingID == nil, replies[request.id] == nil { return false }
        guard !stopped else {
            if let pendingID {
                settlePending(pendingID, .failure(BridgeLinkPortFailure.unavailable))
            } else {
                takeReply(request.id)?.fail(BridgeLinkPortFailure.unavailable)
            }
            return false
        }
        dispatchedCommitIDs.insert(request.id)
        return true
    }

    private func takeReply(_ id: Int) -> Reply? {
        replies.removeValue(forKey: id)
    }

    func finishDispatchedCommit(_ id: Int) {
        dispatchedCommitIDs.remove(id)
        finishShutdownIfReady()
    }

    private func failDispatched(_ request: Request, error: Error) {
        let failure: Error =
            dispatchedCommitIDs.contains(request.id)
            ? BridgeLinkPortFailure.outcomeUnknown : error
        finishDispatchedCommit(request.id)
        takeReply(request.id)?.fail(failure)
    }

    private func settlePending(
        _ id: UUID, _ result: Result<BridgePendingMemberRemovalSettlement, Error>
    ) {
        guard let pending = pendingRemovals[id] else { return }
        guard case .waiting(let waiter) = pending.outcome else { return }
        if let waiter {
            pendingRemovals.removeValue(forKey: id)
            waiter.resume(with: result)
        } else {
            pendingRemovals[id] = (pending.receiver, .settled(result))
        }
        activePendingIDByReceiver.removeValue(forKey: pending.receiver)
        pendingRequestIDByOperationID.removeValue(forKey: id)
    }

    /// Stops admission, settles everything that has not reached a durable
    /// commit, then waits only for commits already dispatched to finish.
    func shutdown() async {
        guard !stopped else { return }
        stopped = true
        ingressContinuation.finish()
        queuedByReceiver.removeAll()
        let undispatched = replies.keys.filter { !dispatchedCommitIDs.contains($0) }
        for id in undispatched { takeReply(id)?.fail(BridgeLinkPortFailure.unavailable) }
        let pendingBeforeCommit = pendingRemovals.compactMap { id, pending -> UUID? in
            guard activePendingIDByReceiver[pending.receiver] == id,
                let requestID = pendingRequestIDByOperationID[id],
                !dispatchedCommitIDs.contains(requestID)
            else { return nil }
            return id
        }
        for id in pendingBeforeCommit {
            settlePending(id, .failure(BridgeLinkPortFailure.unavailable))
        }
        pendingRemovals = pendingRemovals.filter { _, pending in
            if case .waiting = pending.outcome { return true }
            return false
        }
        finishShutdownIfReady()
        if !dispatchedCommitIDs.isEmpty {
            await withCheckedContinuation { shutdownWaiters.append($0) }
        }
    }

    private func finishShutdownIfReady() {
        guard stopped, dispatchedCommitIDs.isEmpty else { return }
        pendingRemovals.removeAll()
        factsContinuation.finish()
        let waiters = shutdownWaiters
        shutdownWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

}
