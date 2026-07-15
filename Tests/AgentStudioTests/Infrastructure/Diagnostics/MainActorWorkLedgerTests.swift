import Foundation
import Testing

@testable import AgentStudio

@Suite
struct MainActorWorkLedgerTests {
    @MainActor
    @Test
    func separatesQueueAgeFromSynchronousServiceAndExecutesBodyOnce() {
        let clock = ScriptedPerformanceClock([100, 140, 155])
        let ledger = MainActorWorkLedger(clock: clock)
        let ticket = requireTicket(
            ledger.enqueue(
                domain: .topology,
                operation: .topologyApply,
                counts: .init(input: 8, changedKey: 2)
            ))
        var bodyCount = 0

        let execution = ledger.withMainActorWork(ticket: ticket, outcome: .succeeded) {
            bodyCount += 1
            return 42
        }

        guard case .completed(let value, let record) = execution else {
            Issue.record("expected completed work")
            return
        }
        #expect(value == 42)
        #expect(bodyCount == 1)
        #expect(record.queueAgeNanoseconds == 40)
        #expect(record.synchronousServiceNanoseconds == 15)
        #expect(record.counts == .init(input: 8, changedKey: 2))
        #expect(UUIDv7.isV7(record.workID.rawValue))
    }

    @MainActor
    @Test
    func rejectsDuplicateAndForeignTicketsWithoutExecutingBody() {
        let firstLedger = MainActorWorkLedger(clock: ScriptedPerformanceClock([1, 2, 3]))
        let secondLedger = MainActorWorkLedger(clock: ScriptedPerformanceClock([1]))
        let ticket = requireTicket(firstLedger.enqueue(domain: .terminal, operation: .ghosttyAppTick))
        let cancelled = firstLedger.withMainActorWork(ticket: ticket, outcome: .cancelled) { () }
        guard case .completed(_, let cancelledRecord) = cancelled else {
            Issue.record("expected cancelled settlement record")
            return
        }
        #expect(cancelledRecord.outcome == .cancelled)
        var bodyCount = 0

        let duplicate = firstLedger.withMainActorWork(ticket: ticket, outcome: .succeeded) { bodyCount += 1 }
        let foreign = secondLedger.withMainActorWork(ticket: ticket, outcome: .succeeded) { bodyCount += 1 }

        guard case .rejected(.duplicateSettlement) = duplicate else {
            Issue.record("expected duplicate rejection")
            return
        }
        guard case .rejected(.foreignTicket) = foreign else {
            Issue.record("expected foreign rejection")
            return
        }
        #expect(bodyCount == 0)
    }

    @MainActor
    @Test
    func reportsClockReversalAndSequenceExhaustion() {
        let ledger = MainActorWorkLedger(clock: ScriptedPerformanceClock([20, 10]))
        let ticket = requireTicket(ledger.enqueue(domain: .bridge, operation: .bridgeCapture))
        let execution = ledger.withMainActorWork(ticket: ticket, outcome: .failed) { 1 }
        guard case .rejected(.clockReversal(.enqueueToStart)) = execution else {
            Issue.record("expected clock reversal")
            return
        }

        let exhausted = MainActorWorkLedger(initialSequence: UInt64.max)
        #expect(
            exhausted.enqueue(domain: .persistence, operation: .persistencePageCapture)
                == .rejected(.sequenceExhausted))
    }

    @MainActor
    @Test
    func serviceClockReversalSettlesTicketAfterExecutingBodyExactlyOnce() {
        let ledger = MainActorWorkLedger(clock: ScriptedPerformanceClock([10, 20, 15]))
        let ticket = requireTicket(ledger.enqueue(domain: .bridge, operation: .webKitSend))
        var bodyCount = 0

        let execution = ledger.withMainActorWork(ticket: ticket, outcome: .failed) {
            bodyCount += 1
        }

        guard case .rejected(.clockReversal(.startToSynchronousEnd)) = execution else {
            Issue.record("expected synchronous-end clock reversal")
            return
        }
        #expect(bodyCount == 1)
        let duplicate = ledger.withMainActorWork(ticket: ticket, outcome: .succeeded) { bodyCount += 1 }
        guard case .rejected(.duplicateSettlement) = duplicate else {
            Issue.record("expected settled ticket rejection")
            return
        }
        #expect(bodyCount == 1)
    }

    private func requireTicket(_ result: MainActorWorkEnqueueResult) -> MainActorWorkTicket {
        guard case .enqueued(let ticket) = result else {
            preconditionFailure("expected ticket")
        }
        return ticket
    }
}

final class ScriptedPerformanceClock: PerformanceMonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var instants: [UInt64]

    init(_ instants: [UInt64]) {
        self.instants = instants
    }

    func now() -> PerformanceMonotonicInstant {
        lock.withLock {
            precondition(!instants.isEmpty)
            return PerformanceMonotonicInstant(uptimeNanoseconds: instants.removeFirst())
        }
    }
}
