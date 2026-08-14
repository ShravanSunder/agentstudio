import AgentStudioInfrastructure
import Foundation

/// Defers keyed background facts into bounded MainActor drain turns.
final class BackgroundFactApplyGovernor<Key: Hashable & Sendable, Fact: Sendable>: @unchecked Sendable {
    enum AcknowledgementResult: Equatable, Sendable {
        case applied
        case superseded
    }

    struct Acknowledgement: Sendable {
        fileprivate let resultStream: AsyncStream<AcknowledgementResult>

        func result() async -> AcknowledgementResult {
            for await result in resultStream { return result }
            preconditionFailure("Apply acknowledgement ended without a result")
        }
    }

    private struct PendingFact: Sendable {
        let key: Key
        let fact: Fact
        let acknowledgement: AsyncStream<AcknowledgementResult>.Continuation
    }

    private struct State: Sendable {
        var pendingByKey: [Key: PendingFact] = [:]
        var pendingOrder: [Key] = []
        var supersededSinceLastDrain = 0
        var isTickScheduled = false
        var isClosed = false
        var drainTask: Task<Void, Never>?
    }

    private struct DrainSnapshot: Sendable {
        let pendingFacts: [PendingFact]
        let supersededCount: Int
    }

    private struct DrainResult: Sendable {
        let carriedFacts: [PendingFact]
        let elapsed: Duration
    }

    private let lock = NSLock()
    private var state = State()
    private let tickCadence: Duration
    private let drainBudget: Duration
    private let delay: AsyncDelay
    private let elapsedSinceOrigin: @Sendable () -> Duration
    private let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    private let mergeFacts: @Sendable (Fact, Fact) -> Fact
    private let applyFact: @MainActor @Sendable (Key, Fact) -> Void
    private let tickStream: AsyncStream<Void>
    private let tickContinuation: AsyncStream<Void>.Continuation

    convenience init(
        tickCadence: Duration,
        drainBudget: Duration,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil,
        mergeFacts: @escaping @Sendable (Fact, Fact) -> Fact = { _, newerFact in newerFact },
        apply: @escaping @MainActor @Sendable (Key, Fact) -> Void
    ) {
        self.init(
            tickCadence: tickCadence,
            drainBudget: drainBudget,
            clock: ContinuousClock(),
            performanceTraceRecorder: performanceTraceRecorder,
            mergeFacts: mergeFacts,
            apply: apply
        )
    }

    init<ApplyClock: Clock & Sendable>(
        tickCadence: Duration,
        drainBudget: Duration,
        clock: ApplyClock,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil,
        mergeFacts: @escaping @Sendable (Fact, Fact) -> Fact = { _, newerFact in newerFact },
        apply: @escaping @MainActor @Sendable (Key, Fact) -> Void
    ) where ApplyClock.Duration == Duration {
        precondition(tickCadence >= .zero)
        precondition(drainBudget > .zero)
        let clockOrigin = clock.now
        self.tickCadence = tickCadence
        self.drainBudget = drainBudget
        self.delay = .clock(clock)
        self.elapsedSinceOrigin = { clockOrigin.duration(to: clock.now) }
        self.performanceTraceRecorder = performanceTraceRecorder
        self.mergeFacts = mergeFacts
        self.applyFact = apply
        let (tickStream, tickContinuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.tickStream = tickStream
        self.tickContinuation = tickContinuation
    }

    deinit {
        tickContinuation.finish()
    }

    func start() {
        lock.withLock {
            guard state.drainTask == nil, !state.isClosed else { return }
            state.drainTask = Task { [weak self] in
                await self?.runDrainLoop()
            }
        }
    }

    func enqueue(_ fact: Fact, for key: Key) -> Acknowledgement {
        let (resultStream, resultContinuation) = AsyncStream.makeStream(
            of: AcknowledgementResult.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        var supersededContinuation: AsyncStream<AcknowledgementResult>.Continuation?
        var shouldScheduleTick = false
        lock.withLock {
            precondition(!state.isClosed, "Cannot enqueue a fact after governor shutdown")
            let pendingFact: Fact
            if let pending = state.pendingByKey[key] {
                supersededContinuation = pending.acknowledgement
                state.supersededSinceLastDrain += 1
                pendingFact = mergeFacts(pending.fact, fact)
            } else {
                state.pendingOrder.append(key)
                pendingFact = fact
            }
            state.pendingByKey[key] = PendingFact(
                key: key,
                fact: pendingFact,
                acknowledgement: resultContinuation
            )
            if !state.isTickScheduled {
                state.isTickScheduled = true
                shouldScheduleTick = true
            }
        }
        supersededContinuation?.yield(.superseded)
        supersededContinuation?.finish()
        if shouldScheduleTick { tickContinuation.yield(()) }
        return Acknowledgement(resultStream: resultStream)
    }

    func shutdown() async {
        let drainTask: Task<Void, Never>? = lock.withLock {
            guard !state.isClosed else { return state.drainTask }
            state.isClosed = true
            let task = state.drainTask
            state.drainTask = nil
            return task
        }
        tickContinuation.finish()
        drainTask?.cancel()
        await drainTask?.value
        await flushAllPendingFacts()
    }

    func flushPending() async {
        guard let snapshot = takeDrainSnapshot() else { return }
        await applyAllFacts(in: snapshot)
        scheduleNextTickIfNeeded()
    }

    private func runDrainLoop() async {
        for await _ in tickStream {
            if Task.isCancelled { break }
            do {
                if tickCadence > .zero {
                    try await delay.wait(tickCadence)
                } else {
                    await Task.yield()
                }
            } catch {
                if Task.isCancelled { break }
                continue
            }
            if Task.isCancelled { break }
            await drainOneTick()
            scheduleNextTickIfNeeded()
        }
    }

    private func drainOneTick() async {
        guard let snapshot = takeDrainSnapshot() else { return }
        let drainResult = await MainActor.run { [applyFact, drainBudget, elapsedSinceOrigin] in
            let drainStart = elapsedSinceOrigin()
            var appliedCount = 0
            for pending in snapshot.pendingFacts {
                applyFact(pending.key, pending.fact)
                pending.acknowledgement.yield(.applied)
                pending.acknowledgement.finish()
                appliedCount += 1
                if appliedCount < snapshot.pendingFacts.count,
                    elapsedSinceOrigin() - drainStart >= drainBudget
                {
                    break
                }
            }
            return DrainResult(
                carriedFacts: Array(snapshot.pendingFacts.dropFirst(appliedCount)),
                elapsed: elapsedSinceOrigin() - drainStart
            )
        }
        let carriedOverCount = requeueCarriedFacts(drainResult.carriedFacts)
        performanceTraceRecorder?.recordDuration(
            .applyGovernorDrain,
            duration: drainResult.elapsed,
            attributes: [
                "agentstudio.performance.apply_governor.batch.count": .int(snapshot.pendingFacts.count),
                "agentstudio.performance.apply_governor.superseded.count": .int(snapshot.supersededCount),
                "agentstudio.performance.apply_governor.carried_over.count": .int(carriedOverCount),
            ]
        )
    }

    private func takeDrainSnapshot() -> DrainSnapshot? {
        lock.withLock {
            let pendingFacts = state.pendingOrder.compactMap { state.pendingByKey[$0] }
            let supersededCount = state.supersededSinceLastDrain
            state.pendingByKey.removeAll(keepingCapacity: true)
            state.pendingOrder.removeAll(keepingCapacity: true)
            state.supersededSinceLastDrain = 0
            guard !pendingFacts.isEmpty else { return nil }
            return DrainSnapshot(pendingFacts: pendingFacts, supersededCount: supersededCount)
        }
    }

    private func requeueCarriedFacts(_ carriedFacts: [PendingFact]) -> Int {
        var supersededContinuations: [AsyncStream<AcknowledgementResult>.Continuation] = []
        let carriedOverCount = lock.withLock {
            var carriedKeys: [Key] = []
            for pending in carriedFacts {
                if state.pendingByKey[pending.key] != nil {
                    supersededContinuations.append(pending.acknowledgement)
                    state.supersededSinceLastDrain += 1
                } else {
                    state.pendingByKey[pending.key] = pending
                    carriedKeys.append(pending.key)
                }
            }
            state.pendingOrder = carriedKeys + state.pendingOrder
            return carriedKeys.count
        }
        for continuation in supersededContinuations {
            continuation.yield(.superseded)
            continuation.finish()
        }
        return carriedOverCount
    }

    private func scheduleNextTickIfNeeded() {
        let shouldScheduleTick = lock.withLock {
            state.isTickScheduled = false
            guard !state.isClosed, !state.pendingByKey.isEmpty else { return false }
            state.isTickScheduled = true
            return true
        }
        if shouldScheduleTick { tickContinuation.yield(()) }
    }

    private func flushAllPendingFacts() async {
        guard let snapshot = takeDrainSnapshot() else { return }
        await applyAllFacts(in: snapshot)
    }

    private func applyAllFacts(in snapshot: DrainSnapshot) async {
        let flushStart = elapsedSinceOrigin()
        await MainActor.run { [applyFact] in
            for pending in snapshot.pendingFacts {
                applyFact(pending.key, pending.fact)
                pending.acknowledgement.yield(.applied)
                pending.acknowledgement.finish()
            }
        }
        performanceTraceRecorder?.recordDuration(
            .applyGovernorDrain,
            duration: elapsedSinceOrigin() - flushStart,
            attributes: [
                "agentstudio.performance.apply_governor.batch.count": .int(snapshot.pendingFacts.count),
                "agentstudio.performance.apply_governor.superseded.count": .int(snapshot.supersededCount),
                "agentstudio.performance.apply_governor.carried_over.count": .int(0),
            ]
        )
    }
}
