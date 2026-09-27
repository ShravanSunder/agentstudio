import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import os

private let bridgePaneRevealLogger = Logger(subsystem: "com.agentstudio", category: "BridgePaneReveal")

/// Read-only admission fact. A mounted controller alone does not prove either
/// effective visibility or freedom from an unfinished draft.
enum BridgeAgentRevealEligibilityState: Equatable, Sendable {
    case waitingInOpenView
    case visibleAndDraftFree
}

/// The activation owner repeats the visibility and draft check at its effect
/// point and reports success only after the requested line is confirmed.
enum BridgeAgentRevealActivationResult: Sendable {
    case shownAtRequestedLine
    case becameIneligible
    case unavailable
}

protocol BridgeAgentRevealEligibility: Sendable {
    func readOnlyState(
        receiver: BridgeReceiver, target: BridgeRevealFileTarget
    ) async -> BridgeAgentRevealEligibilityState

    func showIfStillEligible(
        receiver: BridgeReceiver, target: BridgeRevealFileTarget
    ) async -> BridgeAgentRevealActivationResult
}

/// Controls the gap between an off-main decision and its revision-guarded
/// publication. Production has no delay; tests can place a close at this seam.
protocol BridgeRevealPublicationInterlock: Sendable {
    func beforeApply(receiver: BridgeReceiver, location: BridgeDocumentLocation) async
    func afterAdmissionTicket(receiver: BridgeReceiver, location: BridgeDocumentLocation) async
}

extension BridgeRevealPublicationInterlock {
    func afterAdmissionTicket(receiver _: BridgeReceiver, location _: BridgeDocumentLocation) async {}
}

struct BridgeImmediateRevealPublicationInterlock: BridgeRevealPublicationInterlock {
    func beforeApply(receiver _: BridgeReceiver, location _: BridgeDocumentLocation) async {}
}

/// Until PR1 supplies a read-only visibility/draft fact and line-confirmed
/// installation receipt, production always retains the request in Open view.
struct BridgeFailClosedAgentRevealEligibility: BridgeAgentRevealEligibility {
    func readOnlyState(
        receiver _: BridgeReceiver, target _: BridgeRevealFileTarget
    ) async -> BridgeAgentRevealEligibilityState { .waitingInOpenView }

    func showIfStillEligible(
        receiver _: BridgeReceiver, target _: BridgeRevealFileTarget
    ) async -> BridgeAgentRevealActivationResult { .becameIneligible }
}

/// App owner of agent reveal admission and per-receiver durable retention.
/// It never invokes the editor barrier or the existing page activation API.
actor BridgePaneRevealActor: PaneRevealPort {
    struct DocumentKey: Hashable, Sendable {
        let receiver: BridgeReceiver
        let location: BridgeDocumentLocation
    }

    struct Request: Sendable {
        let operationID: UUID
        let receiver: BridgeReceiver
        let sourcePaneID: UUID
        let location: BridgeDocumentLocation
        let target: BridgeRevealFileTarget
        let requestedBy: BridgeLinkContributor
        let generation: Int
        let retainedAt: Date
    }

    private struct Operation {
        let key: DocumentKey
        var stage: Stage
        var waiter: CheckedContinuation<BridgeAgentRevealSettlement, Error>?
    }

    private enum Stage {
        case admitting
        case queued
        case dispatched
        case settled(BridgeAgentRevealSettlement)
    }

    private enum Ingress: Sendable {
        case reveal(Request)
        case closed(DocumentKey, ticket: Int)
        case barrier(CheckedContinuation<Void, Never>)
    }

    private let workspaceID: UUID
    let handler: BridgeNavigationCommandHandler
    private let commitPort: any BridgeRevealRetentionPort
    private let eligibility: any BridgeAgentRevealEligibility
    let publicationInterlock: any BridgeRevealPublicationInterlock
    private let ingress: AsyncStream<Ingress>
    nonisolated private let ingressContinuation: AsyncStream<Ingress>.Continuation
    private var queuedByReceiver: [BridgeReceiver: [Request]] = [:]
    private var drainingReceivers: Set<BridgeReceiver> = []
    private var operations: [UUID: Operation] = [:]
    private var inFlightByDocument: [DocumentKey: Set<UUID>] = [:]
    private var closeFloorByDocument: [DocumentKey: Int] = [:]
    private var dispatchedIDs: Set<UUID> = []
    private var stopped = false
    private var shutdownWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        workspaceID: UUID, handler: BridgeNavigationCommandHandler,
        commitPort: any BridgeRevealRetentionPort,
        eligibility: any BridgeAgentRevealEligibility = BridgeFailClosedAgentRevealEligibility(),
        publicationInterlock: any BridgeRevealPublicationInterlock = BridgeImmediateRevealPublicationInterlock()
    ) {
        self.workspaceID = workspaceID
        self.handler = handler
        self.commitPort = commitPort
        self.eligibility = eligibility
        self.publicationInterlock = publicationInterlock
        // Human and bound-agent reveals are low-rate. Dropping one would leak
        // its operation ID, so this single ordered ingress is unbounded.
        let (stream, continuation) = AsyncStream.makeStream(
            of: Ingress.self, bufferingPolicy: .unbounded
        )
        ingress = stream
        ingressContinuation = continuation
        Task { await consumeIngress() }
    }

    func admitAgentReveal(
        receiver: PaneId, target: BridgeRevealFileTarget, requestedBy: BridgeLinkContributor
    ) async throws -> BridgeRevealAdmissionResult {
        guard case .agent = requestedBy else { throw BridgeLinkPortFailure.unavailable }
        let topology = await handler.captureLinkTopology(sourcePaneID: receiver.uuid)
        try Task.checkCancellation()
        let resolved =
            BridgeReceiverResolution.receiver(
                forCommandPaneId: receiver.uuid,
                companionEntriesBySourceID: topology.companionEntriesBySourceID,
                paneStatesByID: topology.paneStatesByID
            ) ?? .terminal(receiver.uuid)
        let preview = try await commitPort.previewAgentReveal(
            workspaceID: workspaceID, receiver: resolved, target: target,
            topologySnapshot: topology
        )
        try Task.checkCancellation()
        switch preview {
        case .unsupportedTarget: return .unsupportedTarget
        case .staleOwner: return .staleOwner
        case .staleReceiver: return .staleReceiver
        case .eligible(let location):
            guard !stopped else { throw BridgeLinkPortFailure.unavailable }
            let operationID = UUIDv7.generate()
            let key = DocumentKey(receiver: resolved, location: location)
            operations[operationID] = Operation(key: key, stage: .admitting, waiter: nil)
            inFlightByDocument[key, default: []].insert(operationID)
            let generation = await handler.nextRevealAdmissionTicket()
            await publicationInterlock.afterAdmissionTicket(receiver: resolved, location: location)
            if Task.isCancelled {
                discardProvisionalAdmission(operationID)
                throw CancellationError()
            }
            guard !stopped, operations[operationID] != nil else {
                discardProvisionalAdmission(operationID)
                throw BridgeLinkPortFailure.unavailable
            }
            operations[operationID]?.stage = .queued
            ingressContinuation.yield(
                .reveal(
                    Request(
                        operationID: operationID, receiver: resolved, sourcePaneID: receiver.uuid,
                        location: location, target: target, requestedBy: requestedBy,
                        generation: generation, retainedAt: Date()
                    )))
            return .admitted(operationId: operationID)
        }
    }

    func awaitAgentRevealSettlement(
        receiver: PaneId, operationId: UUID
    ) async throws -> BridgeAgentRevealSettlement {
        guard let operation = operations[operationId], operation.key.receiver.paneId == receiver.uuid else {
            throw BridgeLinkPortFailure.unavailable
        }
        switch operation.stage {
        case .settled(let result):
            operations.removeValue(forKey: operationId)
            return result
        case .admitting, .queued, .dispatched:
            guard operation.waiter == nil else { throw BridgeLinkPortFailure.unavailable }
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    guard var current = operations[operationId], current.waiter == nil else {
                        continuation.resume(throwing: BridgeLinkPortFailure.unavailable)
                        return
                    }
                    current.waiter = continuation
                    operations[operationId] = current
                }
            } onCancel: {
                Task { await self.cancelBeforeDispatch(operationId) }
            }
        }
    }

    /// Human Open is integrated with the PR1 draft barrier and INST receipt.
    /// This native agent-preparation slice cannot truthfully report `shown`.
    func openRetainedViewItem(
        receiver _: PaneId, target _: BridgeRevealFileTarget
    ) async throws -> BridgeHumanOpenSettlement {
        throw BridgeLinkPortFailure.unavailable
    }

    func retainedOpenViewItems(receiver: PaneId) async -> [BridgeRetainedOpenViewItem] {
        do {
            let topology = await handler.captureLinkTopology(sourcePaneID: receiver.uuid)
            let resolved =
                BridgeReceiverResolution.receiver(
                    forCommandPaneId: receiver.uuid,
                    companionEntriesBySourceID: topology.companionEntriesBySourceID,
                    paneStatesByID: topology.paneStatesByID
                ) ?? .terminal(receiver.uuid)
            return try await commitPort.retainedOpenViewItems(
                workspaceID: workspaceID, receiver: resolved
            )
        } catch {
            bridgePaneRevealLogger.error("Bridge retained Open view read failed")
            return []
        }
    }

    /// Called in the same MainActor turn as a successful atom-first close.
    nonisolated func documentClosed(
        _ location: BridgeDocumentLocation, in receiver: BridgeReceiver, ticket: Int
    ) {
        ingressContinuation.yield(.closed(DocumentKey(receiver: receiver, location: location), ticket: ticket))
    }

    private func consumeIngress() async {
        for await event in ingress {
            switch event {
            case .reveal(let request):
                guard !stopped, operations[request.operationID] != nil else { continue }
                queuedByReceiver[request.receiver, default: []].append(request)
                if drainingReceivers.insert(request.receiver).inserted {
                    Task { await drain(request.receiver) }
                }
            case .closed(let key, let ticket):
                guard inFlightByDocument[key] != nil else { continue }
                closeFloorByDocument[key] = max(closeFloorByDocument[key] ?? 0, ticket)
            case .barrier(let continuation):
                continuation.resume()
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
        guard let operation = operations[request.operationID] else { return }
        guard case .queued = operation.stage else { return }
        let topology = await handler.captureLinkTopology(sourcePaneID: request.sourcePaneID)
        guard !stopped, operations[request.operationID] != nil else { return }
        dispatchedIDs.insert(request.operationID)
        operations[request.operationID]?.stage = .dispatched
        do {
            let receipt = try await commitPort.retainAgentReveal(
                context: BridgeLinkMutationContext(
                    workspaceID: workspaceID, receiver: request.receiver,
                    generation: request.generation, topologySnapshot: topology
                ),
                target: request.target, requestedBy: request.requestedBy, retainedAt: request.retainedAt
            )
            let settlement = await settleReceipt(receipt, request: request)
            settle(request.operationID, with: settlement)
        } catch {
            settle(request.operationID, with: .outcomeUnknown)
        }
        dispatchedIDs.remove(request.operationID)
        finishShutdownIfReady()
    }

    private func settleReceipt(
        _ receipt: BridgeRevealRetentionReceipt, request: Request
    ) async -> BridgeAgentRevealSettlement {
        switch receipt.result {
        case .retained(let item):
            switch await publishRetained(receipt.record, item: item, request: request) {
            case .applied: break
            case .superseded: return .superseded
            case .inconsistent: return .outcomeUnknown
            }
            let eligibilityState = await eligibility.readOnlyState(
                receiver: request.receiver, target: request.target
            )
            await awaitIngressBarrier()
            if let closeTicket = closeTicket(for: request), closeTicket > request.generation {
                return .superseded
            }
            guard eligibilityState == .visibleAndDraftFree else { return .waitingInOpenView }
            switch await eligibility.showIfStillEligible(receiver: request.receiver, target: request.target) {
            case .shownAtRequestedLine: return .shown
            case .becameIneligible: return .waitingInOpenView
            case .unavailable: return .unavailable
            }
        case .unsupportedTarget, .staleReceiver: return .unavailable
        case .staleOwner: return .staleOwner
        case .superseded: return .superseded
        case .cleared, .alreadyAbsent: return .unavailable
        }
    }

    private func cancelBeforeDispatch(_ operationID: UUID) {
        guard let operation = operations[operationID], case .queued = operation.stage else { return }
        settle(operationID, with: .cancelled)
    }

    private func discardProvisionalAdmission(_ operationID: UUID) {
        guard let operation = operations.removeValue(forKey: operationID) else { return }
        let key = operation.key
        inFlightByDocument[key]?.remove(operationID)
        if inFlightByDocument[key]?.isEmpty == true {
            inFlightByDocument.removeValue(forKey: key)
            closeFloorByDocument.removeValue(forKey: key)
        }
    }

    func closeTicket(for request: Request) -> Int? {
        closeFloorByDocument[DocumentKey(receiver: request.receiver, location: request.location)]
    }

    func closeFloorEntryCount() -> Int { closeFloorByDocument.count }

    func awaitIngressBarrier() async {
        guard !stopped else { return }
        await withCheckedContinuation { continuation in
            ingressContinuation.yield(.barrier(continuation))
        }
    }

    private func settle(_ operationID: UUID, with result: BridgeAgentRevealSettlement) {
        guard var operation = operations[operationID] else { return }
        guard case .settled = operation.stage else {
            let key = operation.key
            inFlightByDocument[key]?.remove(operationID)
            if inFlightByDocument[key]?.isEmpty == true {
                inFlightByDocument.removeValue(forKey: key)
                closeFloorByDocument.removeValue(forKey: key)
            }
            if let waiter = operation.waiter {
                operations.removeValue(forKey: operationID)
                waiter.resume(returning: result)
            } else {
                operation.stage = .settled(result)
                operations[operationID] = operation
            }
            return
        }
    }

    func shutdown() async {
        if stopped {
            if !dispatchedIDs.isEmpty {
                await withCheckedContinuation { shutdownWaiters.append($0) }
            }
            return
        }
        stopped = true
        ingressContinuation.finish()
        queuedByReceiver.removeAll()
        let beforeDispatch = operations.compactMap { id, operation -> UUID? in
            if case .queued = operation.stage { return id }
            return nil
        }
        for id in beforeDispatch { settle(id, with: .unavailable) }
        let provisional = operations.compactMap { id, operation -> UUID? in
            if case .admitting = operation.stage { return id }
            return nil
        }
        for id in provisional { discardProvisionalAdmission(id) }
        finishShutdownIfReady()
        if !dispatchedIDs.isEmpty {
            await withCheckedContinuation { shutdownWaiters.append($0) }
        }
    }

    private func finishShutdownIfReady() {
        guard stopped, dispatchedIDs.isEmpty else { return }
        let waiters = shutdownWaiters
        shutdownWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}
