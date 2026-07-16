import Foundation

enum LatestValueSettleOfferResult: Equatable, Sendable {
    case scheduled
    case replacedPending
    case unchangedPending
    case rejectedClosed
}

enum LatestValueSettleFlushResult: Equatable, Sendable {
    case flushed
    case noPendingValue
    case rejectedClosed
}

enum LatestValueSettleCloseResult: Equatable, Sendable {
    case closedDiscardingPendingValue
    case closedWithoutPendingValue
    case alreadyClosed
}

struct LatestValueSettleGateDiagnostics: Equatable, Sendable {
    let acceptedOfferCount: UInt64
    let replacedOfferCount: UInt64
    let unchangedOfferCount: UInt64
    let workerTaskStartCount: UInt64
    let settledValueCount: UInt64
    let delayFailureCount: UInt64
}

/// MainActor-local latest-value admission for checkpointed UI memory.
///
/// Offers overwrite one pending value in O(1). One worker task remains active
/// while values continue arriving; a new task is not allocated per offer. The
/// gate owns timing only. Domain decisions and persistence remain in the
/// settled callback's owner.
@MainActor
final class LatestValueSettleGate<Value: Equatable & Sendable> {
    private let delay: AsyncDelay
    private let elapsedTime: @Sendable () -> Duration
    private let quietWindow: Duration
    private let onSettledValue: @MainActor (Value) -> Void

    private var pendingValue: Value?
    private var pendingDeadline: Duration?
    private var workerGeneration: UInt64 = 0
    private var workerTask: Task<Void, Never>?
    private var isClosed = false

    private var acceptedOfferCount: UInt64 = 0
    private var replacedOfferCount: UInt64 = 0
    private var unchangedOfferCount: UInt64 = 0
    private var workerTaskStartCount: UInt64 = 0
    private var settledValueCount: UInt64 = 0
    private var delayFailureCount: UInt64 = 0

    convenience init(
        quietWindow: Duration,
        onSettledValue: @escaping @MainActor (Value) -> Void
    ) {
        self.init(
            quietWindow: quietWindow,
            clock: ContinuousClock(),
            onSettledValue: onSettledValue
        )
    }

    init<SettleClock: Clock & Sendable>(
        quietWindow: Duration,
        clock: SettleClock,
        onSettledValue: @escaping @MainActor (Value) -> Void
    ) where SettleClock.Duration == Duration {
        precondition(quietWindow > .zero, "latest-value settle window must be positive")
        let origin = clock.now
        delay = SettleClock.self == ContinuousClock.self ? .taskSleep : .clock(clock)
        elapsedTime = { origin.duration(to: clock.now) }
        self.quietWindow = quietWindow
        self.onSettledValue = onSettledValue
    }

    isolated deinit {
        workerTask?.cancel()
    }

    var diagnostics: LatestValueSettleGateDiagnostics {
        LatestValueSettleGateDiagnostics(
            acceptedOfferCount: acceptedOfferCount,
            replacedOfferCount: replacedOfferCount,
            unchangedOfferCount: unchangedOfferCount,
            workerTaskStartCount: workerTaskStartCount,
            settledValueCount: settledValueCount,
            delayFailureCount: delayFailureCount
        )
    }

    func offer(_ value: Value) -> LatestValueSettleOfferResult {
        guard !isClosed else { return .rejectedClosed }

        if pendingValue == value {
            unchangedOfferCount &+= 1
            return .unchangedPending
        }

        let replacedPendingValue = pendingValue != nil
        pendingValue = value
        pendingDeadline = elapsedTime() + quietWindow
        acceptedOfferCount &+= 1
        if replacedPendingValue {
            replacedOfferCount &+= 1
        }

        guard workerTask == nil else {
            return .replacedPending
        }

        workerGeneration &+= 1
        let scheduledWorkerGeneration = workerGeneration
        workerTaskStartCount &+= 1
        workerTask = Task { @MainActor [weak self] in
            await self?.runSettleLoop(workerGeneration: scheduledWorkerGeneration)
        }
        return .scheduled
    }

    func flushNow() -> LatestValueSettleFlushResult {
        guard !isClosed else { return .rejectedClosed }
        guard let pendingValue else { return .noPendingValue }

        invalidateWorker()
        self.pendingValue = nil
        settledValueCount &+= 1
        onSettledValue(pendingValue)
        return .flushed
    }

    func close() -> LatestValueSettleCloseResult {
        guard !isClosed else { return .alreadyClosed }
        let discardedPendingValue = pendingValue != nil
        isClosed = true
        pendingValue = nil
        pendingDeadline = nil
        invalidateWorker()
        return discardedPendingValue ? .closedDiscardingPendingValue : .closedWithoutPendingValue
    }

    private func runSettleLoop(workerGeneration: UInt64) async {
        while isCurrentWorker(workerGeneration) {
            guard let pendingDeadline else {
                workerTask = nil
                return
            }
            let remainingDuration = max(.zero, pendingDeadline - elapsedTime())
            do {
                try await delay.wait(remainingDuration)
            } catch is CancellationError {
                return
            } catch {
                settleAfterDelayFailure(workerGeneration: workerGeneration)
                return
            }

            guard isCurrentWorker(workerGeneration) else { return }
            guard let currentDeadline = self.pendingDeadline else {
                workerTask = nil
                return
            }
            guard elapsedTime() >= currentDeadline else { continue }
            guard let settledValue = pendingValue else {
                workerTask = nil
                return
            }

            pendingValue = nil
            self.pendingDeadline = nil
            workerTask = nil
            settledValueCount &+= 1
            onSettledValue(settledValue)
            return
        }
    }

    private func invalidateWorker() {
        workerGeneration &+= 1
        let task = workerTask
        workerTask = nil
        task?.cancel()
    }

    private func settleAfterDelayFailure(workerGeneration: UInt64) {
        guard isCurrentWorker(workerGeneration) else { return }
        guard let settledValue = pendingValue else {
            workerTask = nil
            return
        }
        pendingValue = nil
        pendingDeadline = nil
        workerTask = nil
        delayFailureCount &+= 1
        settledValueCount &+= 1
        onSettledValue(settledValue)
    }

    private func isCurrentWorker(_ generation: UInt64) -> Bool {
        !isClosed && workerTask != nil && workerGeneration == generation
    }
}
