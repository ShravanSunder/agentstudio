import Foundation
import Testing

@testable import AgentStudio

@Suite
struct PerformanceRunEvidenceLedgerTests {
    @Test
    func accountsForRecordedLostGapsMissingStagesAndDrainState() {
        let ledger = PerformanceRunEvidenceLedger(
            requiredStages: [.mainActorWork, .mainActorHeartbeat, .quiescence]
        )
        let emptySink = PerformanceProbeSink(capacity: 1)
        let first = requireEnvelope(ledger.offer(stage: .mainActorWork))
        let second = requireEnvelope(ledger.offer(stage: .mainActorHeartbeat))
        let third = requireEnvelope(ledger.offer(stage: .quiescence))

        #expect(ledger.settle(first, as: .recorded) == nil)
        #expect(ledger.settle(second, as: .lost) == nil)
        #expect(ledger.settle(third, as: .recorded) == nil)
        #expect(ledger.settle(first, as: .recorded) == .duplicateSettlement)
        let drainToken = requireDrainToken(ledger.beginDrain(sink: emptySink))
        #expect(ledger.summary().drainState == .draining)
        #expect(
            ledger.reconcileDrain(emptySink.drain(maximumCount: 1, using: drainToken))
                == .finished
        )

        let summary = ledger.summary()
        #expect(summary.offeredCount == 3)
        #expect(summary.recordedCount == 2)
        #expect(summary.lostCount == 1)
        #expect(summary.gaps == [.init(after: 1, before: 3)])
        #expect(summary.missingStages == [.mainActorHeartbeat])
        #expect(summary.drainState == .finished)
    }

    @Test
    func rejectsForeignAndExhaustedSequences() {
        let ledger = PerformanceRunEvidenceLedger(requiredStages: [], initialSequence: UInt64.max)
        #expect(ledger.offer(stage: .quiescence) == .rejected(.sequenceExhausted))

        let first = PerformanceRunEvidenceLedger(requiredStages: [])
        let second = PerformanceRunEvidenceLedger(requiredStages: [])
        let envelope = requireEnvelope(first.offer(stage: .quiescence))
        #expect(second.settle(envelope, as: .recorded) == .foreignRun)
    }

    @Test
    func sinkOfferAtomicallyAccountsForRecordedAndLostEvidence() {
        let ledger = PerformanceRunEvidenceLedger(requiredStages: [.mainActorWork, .mainActorHeartbeat])
        let sink = PerformanceProbeSink(capacity: 1)

        guard case .recorded = ledger.offer(stage: .mainActorWork, to: sink) else {
            Issue.record("expected recorded offer")
            return
        }
        guard case .lost(_, .capacity) = ledger.offer(stage: .mainActorHeartbeat, to: sink) else {
            Issue.record("expected capacity loss")
            return
        }

        let summary = ledger.summary()
        #expect(summary.offeredCount == 2)
        #expect(summary.recordedCount == 1)
        #expect(summary.lostCount == 1)
        #expect(summary.missingStages == [.mainActorHeartbeat])

        let drainToken = requireDrainToken(ledger.beginDrain(sink: sink))
        let incompleteReceipt = sink.drain(maximumCount: 0, using: drainToken)
        #expect(ledger.reconcileDrain(incompleteReceipt) == .incomplete(remainingCount: 1))
        #expect(ledger.offer(stage: .quiescence) == .rejected(.drainInProgress))
        #expect(
            ledger.reconcileDrain(sink.drain(maximumCount: 1, using: drainToken)) == .finished
        )
        #expect(ledger.offer(stage: .quiescence) == .rejected(.drainFinished))
    }

    @Test
    func rejectsDrainReceiptFromForeignSink() {
        let ledger = PerformanceRunEvidenceLedger(requiredStages: [.mainActorWork])
        let boundSink = PerformanceProbeSink(capacity: 1)
        let foreignSink = PerformanceProbeSink(capacity: 1)

        guard case .recorded = ledger.offer(stage: .mainActorWork, to: boundSink) else {
            Issue.record("expected recorded offer")
            return
        }
        let drainToken = requireDrainToken(ledger.beginDrain(sink: boundSink))
        let foreignToken = PerformanceProbeDrainToken.make(sinkID: foreignSink.sinkID)
        #expect(foreignSink.beginDrain(using: foreignToken) == .began(foreignToken))

        #expect(
            ledger.reconcileDrain(foreignSink.drain(maximumCount: 1, using: foreignToken))
                == .foreignSink
        )
        #expect(ledger.summary().drainState == .draining)
        #expect(
            ledger.reconcileDrain(boundSink.drain(maximumCount: 1, using: drainToken)) == .finished
        )
    }

    @Test
    func cannotFinishWhileManualSettlementRemainsPending() {
        let ledger = PerformanceRunEvidenceLedger(requiredStages: [.mainActorWork])
        let sink = PerformanceProbeSink(capacity: 1)
        let envelope = requireEnvelope(ledger.offer(stage: .mainActorWork))

        let drainToken = requireDrainToken(ledger.beginDrain(sink: sink))
        let emptyReceipt = sink.drain(maximumCount: 1, using: drainToken)
        #expect(ledger.reconcileDrain(emptyReceipt) == .pendingSettlements(count: 1))
        #expect(ledger.settle(envelope, as: .recorded) == nil)
        #expect(ledger.reconcileDrain(emptyReceipt) == .finished)
    }

    @Test
    func inFlightOfferRejectsDrainWithoutBlockingAndReentrantSinkCannotDeadlock() async {
        let ledger = PerformanceRunEvidenceLedger(requiredStages: [.mainActorWork])
        let sink = BarrierPerformanceProbeSink(onOffer: { _ = ledger.summary() })

        // Blocking barrier work must not inherit the async test's cooperative executor.
        // swiftlint:disable:next no_task_detached
        let offerTask = Task.detached {
            ledger.offer(stage: .mainActorWork, to: sink)
        }
        // Blocking barrier work must not inherit the async test's cooperative executor.
        // swiftlint:disable:next no_task_detached
        await Task.detached {
            sink.waitUntilOfferEntered()
        }.value

        #expect(ledger.beginDrain(sink: sink) == .offersInFlight(count: 1))

        sink.releaseOffer()
        guard case .recorded = await offerTask.value else {
            Issue.record("expected recorded offer")
            return
        }
        let drainToken = requireDrainToken(ledger.beginDrain(sink: sink))
        #expect(ledger.summary().offeredCount == 1)
        #expect(ledger.summary().recordedCount == 1)
        #expect(ledger.summary().lostCount == 0)
        #expect(ledger.reconcileDrain(sink.drain(using: drainToken)) == .finished)
    }

    @Test
    func staleSameSinkReceiptCannotFinishCurrentDrainAndAdmissionClosesAtomically() {
        let ledger = PerformanceRunEvidenceLedger(requiredStages: [.mainActorWork])
        let sink = PerformanceProbeSink(capacity: 4)

        #expect(sink.offer(.contraction(stage: .source, count: 1)) == .accepted)
        guard case .recorded = ledger.offer(stage: .mainActorWork, to: sink) else {
            Issue.record("expected recorded offer")
            return
        }

        let drainToken = requireDrainToken(ledger.beginDrain(sink: sink))
        let staleToken = PerformanceProbeDrainToken.make(sinkID: sink.sinkID)
        let staleReceipt = PerformanceProbeDrainReceipt(
            token: staleToken,
            records: [],
            acceptedTotal: 0,
            lostTotal: 0,
            remainingCount: 0,
            state: .shutdown
        )
        #expect(ledger.reconcileDrain(staleReceipt) == .staleDrain)
        #expect(sink.offer(.contraction(stage: .fact, count: 1)) == .lost(.shutdown))

        let receipt = sink.drain(maximumCount: 4, using: drainToken)
        #expect(receipt.records.count == 2)
        #expect(ledger.reconcileDrain(receipt) == .finished)
    }

    private func requireEnvelope(_ result: PerformanceRunOfferResult) -> PerformanceRunProbeEnvelope {
        guard case .offered(let envelope) = result else {
            preconditionFailure("expected envelope")
        }
        return envelope
    }

    private func requireDrainToken(
        _ result: PerformanceRunBeginDrainResult
    ) -> PerformanceProbeDrainToken {
        guard case .began(let token) = result else {
            preconditionFailure("expected drain token")
        }
        return token
    }
}

private func waitForDispatchSignal(
    _ semaphore: DispatchSemaphore,
    timeout: DispatchTime
) -> DispatchTimeoutResult {
    semaphore.wait(timeout: timeout)
}

private final class BarrierPerformanceProbeSink: PerformanceProbeDrainableSink, @unchecked Sendable {
    let sinkID = PerformanceProbeSinkID.make()
    private let onOffer: @Sendable () -> Void
    private let offerEntered = DispatchSemaphore(value: 0)
    private let offerRelease = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var acceptedTotal: UInt64 = 0
    private var drainToken: PerformanceProbeDrainToken?
    private var storedRecord: PerformanceProbeRecord?

    init(onOffer: @escaping @Sendable () -> Void = {}) {
        self.onOffer = onOffer
    }

    func offer(_ record: PerformanceProbeRecord) -> PerformanceProbeOfferOutcome {
        onOffer()
        offerEntered.signal()
        offerRelease.wait()
        lock.withLock {
            acceptedTotal += 1
            storedRecord = record
        }
        return .accepted
    }

    func waitUntilOfferEntered() {
        offerEntered.wait()
    }

    func releaseOffer() {
        offerRelease.signal()
    }

    func beginDrain(using token: PerformanceProbeDrainToken) -> PerformanceProbeDrainStartResult {
        lock.withLock {
            guard token.sinkID == sinkID else { return .rejected(.sinkMismatch) }
            if let drainToken {
                return drainToken == token
                    ? .alreadyStarted(drainToken)
                    : .rejected(.tokenMismatch(current: drainToken))
            }
            drainToken = token
            return .began(token)
        }
    }

    func drain(
        maximumCount: Int = .max,
        using token: PerformanceProbeDrainToken
    ) -> PerformanceProbeDrainReceipt {
        let snapshot = lock.withLock { () -> (UInt64, PerformanceProbeRecord?) in
            precondition(drainToken == token)
            return (acceptedTotal, storedRecord)
        }
        return PerformanceProbeDrainReceipt(
            token: token,
            records: maximumCount == 0 ? [] : snapshot.1.map { [$0] } ?? [],
            acceptedTotal: snapshot.0,
            lostTotal: 0,
            remainingCount: 0,
            state: .shutdown
        )
    }
}
