import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("LatestValueSettleGate")
struct LatestValueSettleGateTests {
    @Test("many offers retain one worker and settle only the latest value")
    func manyOffersRetainOneWorkerAndSettleLatestValue() async {
        // Arrange
        let clock = TestPushClock()
        let recorder = SettleValueRecorder<Int>()
        let gate = LatestValueSettleGate<Int>(
            quietWindow: .milliseconds(100),
            clock: clock,
            onSettledValue: recorder.record
        )

        // Act
        #expect(gate.offer(1) == .scheduled)
        await clock.waitForPendingSleepCount(exactly: 1)
        for value in 2...128 {
            #expect(gate.offer(value) == .replacedPending)
        }
        clock.advance(by: .milliseconds(100))
        await recorder.waitForCount(1)

        // Assert
        #expect(recorder.values == [128])
        #expect(clock.scheduledSleepGeneration == 1)
        #expect(gate.diagnostics.workerTaskStartCount == 1)
        #expect(gate.diagnostics.acceptedOfferCount == 128)
        #expect(gate.diagnostics.replacedOfferCount == 127)
        #expect(gate.diagnostics.settledValueCount == 1)
    }

    @Test("equal pending offers do not restart the settle window")
    func equalPendingOffersDoNotRestartSettleWindow() async {
        // Arrange
        let clock = TestPushClock()
        let recorder = SettleValueRecorder<Int>()
        let gate = LatestValueSettleGate<Int>(
            quietWindow: .milliseconds(50),
            clock: clock,
            onSettledValue: recorder.record
        )

        // Act
        #expect(gate.offer(42) == .scheduled)
        #expect(gate.offer(42) == .unchangedPending)
        #expect(gate.offer(42) == .unchangedPending)
        await clock.waitForPendingSleepCount(exactly: 1)
        clock.advance(by: .milliseconds(50))
        await recorder.waitForCount(1)

        // Assert
        #expect(recorder.values == [42])
        #expect(gate.diagnostics.acceptedOfferCount == 1)
        #expect(gate.diagnostics.unchangedOfferCount == 2)
        #expect(gate.diagnostics.workerTaskStartCount == 1)
    }

    @Test("explicit flush consumes the pending value once")
    func explicitFlushConsumesPendingValueOnce() async {
        // Arrange
        let clock = TestPushClock()
        let recorder = SettleValueRecorder<Int>()
        let gate = LatestValueSettleGate<Int>(
            quietWindow: .seconds(1),
            clock: clock,
            onSettledValue: recorder.record
        )
        #expect(gate.offer(7) == .scheduled)
        await clock.waitForPendingSleepCount(exactly: 1)

        // Act
        let firstFlush = gate.flushNow()
        let secondFlush = gate.flushNow()
        await clock.waitForPendingSleepCount(exactly: 0)

        // Assert
        #expect(firstFlush == .flushed)
        #expect(secondFlush == .noPendingValue)
        #expect(recorder.values == [7])
        #expect(gate.diagnostics.settledValueCount == 1)
    }

    @Test("close discards pending custody and rejects later offers")
    func closeDiscardsPendingCustodyAndRejectsLaterOffers() async {
        // Arrange
        let clock = TestPushClock()
        let recorder = SettleValueRecorder<Int>()
        let gate = LatestValueSettleGate<Int>(
            quietWindow: .seconds(1),
            clock: clock,
            onSettledValue: recorder.record
        )
        #expect(gate.offer(3) == .scheduled)
        await clock.waitForPendingSleepCount(exactly: 1)

        // Act
        let firstClose = gate.close()
        let repeatedClose = gate.close()
        let closedOffer = gate.offer(4)
        let closedFlush = gate.flushNow()
        await clock.waitForPendingSleepCount(exactly: 0)
        clock.advance(by: .seconds(3))

        // Assert
        #expect(firstClose == .closedDiscardingPendingValue)
        #expect(repeatedClose == .alreadyClosed)
        #expect(closedOffer == .rejectedClosed)
        #expect(closedFlush == .rejectedClosed)
        #expect(recorder.values.isEmpty)
        #expect(gate.diagnostics.settledValueCount == 0)
    }

    @Test("cancelled worker cannot clear a replacement worker")
    func cancelledWorkerCannotClearReplacementWorker() async {
        // Arrange
        let clock = TestPushClock()
        let recorder = SettleValueRecorder<Int>()
        let gate = LatestValueSettleGate<Int>(
            quietWindow: .milliseconds(25),
            clock: clock,
            onSettledValue: recorder.record
        )
        #expect(gate.offer(1) == .scheduled)
        await clock.waitForPendingSleepGeneration(0)

        // Act
        #expect(gate.flushNow() == .flushed)
        #expect(gate.offer(2) == .scheduled)
        await clock.waitForPendingSleepGeneration(1)
        clock.advance(by: .milliseconds(25))
        await recorder.waitForCount(2)

        // Assert
        #expect(recorder.values == [1, 2])
        #expect(gate.diagnostics.workerTaskStartCount == 2)
        #expect(gate.diagnostics.settledValueCount == 2)
    }

    @Test("replacement moves the deadline without starting another worker")
    func replacementMovesDeadlineWithoutStartingAnotherWorker() async {
        // Arrange
        let clock = TestPushClock()
        let recorder = SettleValueRecorder<Int>()
        let gate = LatestValueSettleGate<Int>(
            quietWindow: .milliseconds(100),
            clock: clock,
            onSettledValue: recorder.record
        )
        #expect(gate.offer(1) == .scheduled)
        await clock.waitForPendingSleepCount(exactly: 1)

        // Act
        clock.advance(by: .milliseconds(90))
        #expect(gate.offer(2) == .replacedPending)
        clock.advance(by: .milliseconds(10))
        await clock.waitForPendingSleepGeneration(1)
        #expect(recorder.values.isEmpty)
        clock.advance(by: .milliseconds(90))
        await recorder.waitForCount(1)

        // Assert
        #expect(recorder.values == [2])
        #expect(clock.scheduledSleepGeneration == 2)
        #expect(gate.diagnostics.workerTaskStartCount == 1)
    }

    @Test("unexpected delay failure settles custody and permits later reuse")
    func unexpectedDelayFailureSettlesCustodyAndPermitsLaterReuse() async {
        // Arrange
        let baseClock = TestPushClock()
        let clock = FailingOnceSettleClock(base: baseClock)
        let recorder = SettleValueRecorder<Int>()
        let gate = LatestValueSettleGate<Int>(
            quietWindow: .milliseconds(20),
            clock: clock,
            onSettledValue: recorder.record
        )

        // Act
        #expect(gate.offer(1) == .scheduled)
        await recorder.waitForCount(1)
        #expect(gate.offer(2) == .scheduled)
        await baseClock.waitForPendingSleepCount(exactly: 1)
        baseClock.advance(by: .milliseconds(20))
        await recorder.waitForCount(2)

        // Assert
        #expect(recorder.values == [1, 2])
        #expect(gate.diagnostics.delayFailureCount == 1)
        #expect(gate.diagnostics.workerTaskStartCount == 2)
    }

    @Test("natural settlement permits a new independent worker")
    func naturalSettlementPermitsNewIndependentWorker() async {
        // Arrange
        let clock = TestPushClock()
        let recorder = SettleValueRecorder<Int>()
        let gate = LatestValueSettleGate<Int>(
            quietWindow: .milliseconds(10),
            clock: clock,
            onSettledValue: recorder.record
        )

        // Act
        #expect(gate.offer(1) == .scheduled)
        await clock.waitForPendingSleepGeneration(0)
        clock.advance(by: .milliseconds(10))
        await recorder.waitForCount(1)
        #expect(gate.offer(2) == .scheduled)
        await clock.waitForPendingSleepGeneration(1)
        clock.advance(by: .milliseconds(10))
        await recorder.waitForCount(2)

        // Assert
        #expect(recorder.values == [1, 2])
        #expect(gate.diagnostics.workerTaskStartCount == 2)
    }
}

@MainActor
private final class SettleValueRecorder<Value: Equatable> {
    private(set) var values: [Value] = []
    private var countWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func record(_ value: Value) {
        values.append(value)
        let readyWaiters = countWaiters.filter { values.count >= $0.count }
        countWaiters.removeAll { values.count >= $0.count }
        for waiter in readyWaiters {
            waiter.continuation.resume()
        }
    }

    func waitForCount(_ count: Int) async {
        guard values.count < count else { return }
        await withCheckedContinuation { continuation in
            countWaiters.append((count: count, continuation: continuation))
        }
    }
}

private struct FailingOnceSettleClock: Clock {
    typealias Duration = Swift.Duration
    typealias Instant = TestPushClock.Instant

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var shouldFail = true

        func consumeFailure() -> Bool {
            lock.withLock {
                defer { shouldFail = false }
                return shouldFail
            }
        }
    }

    let base: TestPushClock
    private let state = State()

    var now: Instant { base.now }
    var minimumResolution: Duration { base.minimumResolution }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        if state.consumeFailure() {
            throw FailingOnceSettleClockError.expectedFailure
        }
        try await base.sleep(until: deadline, tolerance: tolerance)
    }
}

private enum FailingOnceSettleClockError: Error {
    case expectedFailure
}
