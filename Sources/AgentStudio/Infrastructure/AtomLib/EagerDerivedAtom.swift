import Observation
import Synchronization

@MainActor
@Observable
package final class EagerDerivedAtom<
    Request: Sendable,
    RequestIdentity: Equatable & Sendable,
    Value: Sendable
> {
    package enum Freshness: Equatable, Sendable {
        case idle
        case running(RequestIdentity)
        case invalidated(RequestIdentity)
        case current(RequestIdentity)
        case stopped
    }

    package enum ProjectionCompletion: Equatable, Sendable {
        case published(RequestIdentity)
        case equal(RequestIdentity)
        case superseded(RequestIdentity)
        case cancelled(RequestIdentity)
    }

    package private(set) var value: Value?
    package private(set) var freshness: Freshness = .idle
    package private(set) var revision = 0
    @ObservationIgnored package private(set) var latestAcceptedValue: Value?

    @ObservationIgnored private let revocationEpoch = Mutex<UInt64>(0)
    @ObservationIgnored private let requestIdentity: @Sendable (Request) -> RequestIdentity
    @ObservationIgnored private let combinePendingRequests: @Sendable (Request, Request) -> Request
    @ObservationIgnored private let isValueEqual: @Sendable (Value, Value) -> Bool
    @ObservationIgnored private let project: @Sendable (Request) throws(CancellationError) -> Value
    @ObservationIgnored private let onProjectionCompletion: @MainActor @Sendable (ProjectionCompletion) -> Void
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var admittedIdentity: RequestIdentity?
    @ObservationIgnored private var admittedEpoch: UInt64?
    @ObservationIgnored private var activeRequest: AcceptedRequest?
    @ObservationIgnored private var pendingRequest: AcceptedRequest?
    @ObservationIgnored private var retainedTask: Task<Void, Never>?
    @ObservationIgnored private var unsettledProjectionTaskCount = 0
    @ObservationIgnored private var hasStopped = false

    private struct AcceptedRequest {
        let request: Request
        let identity: RequestIdentity
        let generation: UInt64
        let epoch: UInt64
    }

    package init(
        requestIdentity: @escaping @Sendable (Request) -> RequestIdentity,
        combinePendingRequests: @escaping @Sendable (Request, Request) -> Request,
        isValueEqual: @escaping @Sendable (Value, Value) -> Bool,
        project: @escaping @Sendable (Request) throws(CancellationError) -> Value,
        onProjectionCompletion: @escaping @MainActor @Sendable (ProjectionCompletion) -> Void = { _ in }
    ) {
        self.requestIdentity = requestIdentity
        self.combinePendingRequests = combinePendingRequests
        self.isValueEqual = isValueEqual
        self.project = project
        self.onProjectionCompletion = onProjectionCompletion
    }

    package nonisolated func sourceDidInvalidate() {
        revocationEpoch.withLock { epoch in
            epoch &+= 1
        }
        Task { @MainActor [weak self] in
            self?.mirrorInvalidatedFreshnessIfNeeded()
        }
    }

    package func admit(_ request: Request) {
        guard !hasStopped else { return }

        let identity = requestIdentity(request)
        let epoch = revocationEpoch.withLock { $0 }
        if admittedIdentity == identity, admittedEpoch == epoch {
            return
        }

        generation &+= 1
        admittedIdentity = identity
        admittedEpoch = epoch
        freshness = .running(identity)

        let acceptedRequest = AcceptedRequest(
            request: request,
            identity: identity,
            generation: generation,
            epoch: epoch
        )
        guard let activeRequest else {
            start(acceptedRequest)
            return
        }

        let requestToCombine = pendingRequest?.request ?? activeRequest.request
        let combinedRequest = combinePendingRequests(requestToCombine, request)
        precondition(
            requestIdentity(combinedRequest) == identity,
            "The combined pending request must retain the latest admitted identity"
        )
        let replacedPendingRequest = pendingRequest
        pendingRequest = AcceptedRequest(
            request: combinedRequest,
            identity: identity,
            generation: generation,
            epoch: epoch
        )
        retainedTask?.cancel()
        if let replacedPendingRequest,
            replacedPendingRequest.identity != identity
        {
            onProjectionCompletion(.superseded(replacedPendingRequest.identity))
        }
    }

    private func start(_ acceptedRequest: AcceptedRequest) {
        guard !hasStopped else { return }
        activeRequest = acceptedRequest

        let previousValue = value
        let isValueEqual = self.isValueEqual
        let project = self.project
        unsettledProjectionTaskCount += 1
        // Detached execution is the primitive's off-MainActor projection guarantee.
        // swiftlint:disable:next no_task_detached
        retainedTask = Task.detached(priority: .userInitiated) { [self] in
            do {
                let candidate = try project(acceptedRequest.request)
                let isEqualToPrevious =
                    previousValue.map {
                        isValueEqual($0, candidate)
                    } ?? false
                let wasCancelled = Task.isCancelled
                await acceptCompletion(
                    candidate,
                    isEqualToPrevious: isEqualToPrevious,
                    wasCancelled: wasCancelled,
                    generation: acceptedRequest.generation,
                    identity: acceptedRequest.identity,
                    epoch: acceptedRequest.epoch
                )
            } catch {
                await finishCancelledProjection(
                    generation: acceptedRequest.generation,
                    identity: acceptedRequest.identity,
                    epoch: acceptedRequest.epoch
                )
            }
        }
    }

    package func isCurrent(_ identity: RequestIdentity) -> Bool {
        guard !hasStopped,
            admittedIdentity == identity,
            admittedEpoch == revocationEpoch.withLock({ $0 }),
            freshness == .current(identity)
        else {
            return false
        }
        return true
    }

    package var hasUnsettledProjectionTasks: Bool {
        unsettledProjectionTaskCount > 0
    }

    package func stop() {
        guard !hasStopped else { return }
        hasStopped = true
        generation &+= 1
        retainedTask?.cancel()
        let cancelledPendingRequest = pendingRequest
        pendingRequest = nil
        admittedIdentity = nil
        admittedEpoch = nil
        freshness = .stopped
        if let cancelledPendingRequest {
            onProjectionCompletion(.cancelled(cancelledPendingRequest.identity))
        }
    }

    private func mirrorInvalidatedFreshnessIfNeeded() {
        guard !hasStopped,
            let admittedIdentity,
            let admittedEpoch,
            admittedEpoch != revocationEpoch.withLock({ $0 })
        else {
            return
        }
        freshness = .invalidated(admittedIdentity)
    }

    private func acceptCompletion(
        _ candidate: Value,
        isEqualToPrevious: Bool,
        wasCancelled: Bool,
        generation completedGeneration: UInt64,
        identity completedIdentity: RequestIdentity,
        epoch completedEpoch: UInt64
    ) {
        projectionTaskDidSettle()
        let completion: ProjectionCompletion
        if hasStopped {
            completion = .cancelled(completedIdentity)
        } else if !wasCancelled,
            generation == completedGeneration,
            admittedIdentity == completedIdentity,
            admittedEpoch == completedEpoch,
            revocationEpoch.withLock({ $0 }) == completedEpoch
        {
            freshness = .current(completedIdentity)
            latestAcceptedValue = candidate
            if isEqualToPrevious {
                completion = .equal(completedIdentity)
            } else {
                if value != nil {
                    revision += 1
                }
                value = candidate
                completion = .published(completedIdentity)
            }
        } else {
            completion = .superseded(completedIdentity)
        }
        finishActiveRequest(completedGeneration, completion: completion)
    }

    private func finishCancelledProjection(
        generation completedGeneration: UInt64,
        identity completedIdentity: RequestIdentity,
        epoch completedEpoch: UInt64
    ) {
        projectionTaskDidSettle()
        let completion: ProjectionCompletion
        if hasStopped {
            completion = .cancelled(completedIdentity)
        } else if generation == completedGeneration,
            admittedIdentity == completedIdentity,
            admittedEpoch == completedEpoch,
            revocationEpoch.withLock({ $0 }) == completedEpoch
        {
            completion = .cancelled(completedIdentity)
        } else {
            completion = .superseded(completedIdentity)
        }
        finishActiveRequest(completedGeneration, completion: completion)
    }

    private func finishActiveRequest(
        _ completedGeneration: UInt64,
        completion: ProjectionCompletion
    ) {
        onProjectionCompletion(completion)
        guard activeRequest?.generation == completedGeneration else { return }
        activeRequest = nil
        retainedTask = nil
        guard !hasStopped, let pendingRequest else { return }
        self.pendingRequest = nil
        guard pendingRequest.epoch == revocationEpoch.withLock({ $0 }) else {
            onProjectionCompletion(.superseded(pendingRequest.identity))
            return
        }
        start(pendingRequest)
    }

    private func projectionTaskDidSettle() {
        precondition(unsettledProjectionTaskCount > 0)
        unsettledProjectionTaskCount -= 1
    }
}
