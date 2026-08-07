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

    package private(set) var value: Value?
    package private(set) var freshness: Freshness = .idle
    package private(set) var revision = 0

    @ObservationIgnored private let revocationEpoch = Mutex<UInt64>(0)
    @ObservationIgnored private let requestIdentity: @Sendable (Request) -> RequestIdentity
    @ObservationIgnored private let isValueEqual: @Sendable (Value, Value) -> Bool
    @ObservationIgnored private let project: @Sendable (Request) throws(CancellationError) -> Value
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var admittedIdentity: RequestIdentity?
    @ObservationIgnored private var admittedEpoch: UInt64?
    @ObservationIgnored private var retainedTask: Task<Void, Never>?
    @ObservationIgnored private var hasStopped = false

    package init(
        requestIdentity: @escaping @Sendable (Request) -> RequestIdentity,
        isValueEqual: @escaping @Sendable (Value, Value) -> Bool,
        project: @escaping @Sendable (Request) throws(CancellationError) -> Value
    ) {
        self.requestIdentity = requestIdentity
        self.isValueEqual = isValueEqual
        self.project = project
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
        let admittedGeneration = generation
        retainedTask?.cancel()
        admittedIdentity = identity
        admittedEpoch = epoch
        freshness = .running(identity)

        let previousValue = value
        let isValueEqual = self.isValueEqual
        let project = self.project
        // Detached execution is the primitive's off-MainActor projection guarantee.
        // swiftlint:disable:next no_task_detached
        retainedTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let candidate = try project(request)
                let isEqualToPrevious =
                    previousValue.map {
                        isValueEqual($0, candidate)
                    } ?? false
                let wasCancelled = Task.isCancelled
                await self?.acceptCompletion(
                    candidate,
                    isEqualToPrevious: isEqualToPrevious,
                    wasCancelled: wasCancelled,
                    generation: admittedGeneration,
                    identity: identity,
                    epoch: epoch
                )
            } catch {
                await self?.finishCancelledProjection(generation: admittedGeneration)
            }
        }
    }

    package func stop() {
        guard !hasStopped else { return }
        hasStopped = true
        generation &+= 1
        retainedTask?.cancel()
        retainedTask = nil
        admittedIdentity = nil
        admittedEpoch = nil
        freshness = .stopped
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
        guard !hasStopped,
            !wasCancelled,
            generation == completedGeneration,
            admittedIdentity == completedIdentity,
            admittedEpoch == completedEpoch,
            revocationEpoch.withLock({ $0 }) == completedEpoch
        else {
            return
        }

        retainedTask = nil
        freshness = .current(completedIdentity)
        guard !isEqualToPrevious else { return }

        if value != nil {
            revision += 1
        }
        value = candidate
    }

    private func finishCancelledProjection(generation completedGeneration: UInt64) {
        guard generation == completedGeneration else { return }
        retainedTask = nil
    }
}
