import Foundation

struct PerformanceMonotonicInstant: Comparable, Equatable, Sendable {
    let uptimeNanoseconds: UInt64

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.uptimeNanoseconds < rhs.uptimeNanoseconds
    }
}

protocol PerformanceMonotonicClock: Sendable {
    func now() -> PerformanceMonotonicInstant
}

struct SystemPerformanceMonotonicClock: PerformanceMonotonicClock {
    func now() -> PerformanceMonotonicInstant {
        PerformanceMonotonicInstant(uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds)
    }
}

struct OpaquePerformanceWorkID: Equatable, Hashable, Sendable {
    let rawValue: UUID

    static func make() -> Self { Self(rawValue: UUIDv7.generate()) }
}

struct OpaquePerformanceRunToken: Equatable, Hashable, Sendable {
    let rawValue: UUID

    static func make() -> Self { Self(rawValue: UUIDv7.generate()) }
}

enum MainActorWorkRecordVersion: String, Sendable {
    case v1
}

enum MainActorWorkDomain: String, CaseIterable, Sendable {
    case bridge
    case diagnostics
    case persistence
    case runtimeFact = "runtime_fact"
    case terminal
    case topology
}

enum MainActorWorkOperation: String, CaseIterable, Sendable {
    case bridgeCapture = "bridge_capture"
    case ghosttyAppTick = "ghostty_app_tick"
    case heartbeatObservation = "heartbeat_observation"
    case persistencePageCapture = "persistence_page_capture"
    case runtimeFactApply = "runtime_fact_apply"
    case topologyApply = "topology_apply"
    case webKitSend = "webkit_send"
}

enum MainActorWorkOutcome: String, CaseIterable, Sendable {
    case cancelled
    case failed
    case succeeded
}

enum MainActorWorkParent: Equatable, Sendable {
    case root
    case work(OpaquePerformanceWorkID)
}

enum MainActorWorkRun: Equatable, Sendable {
    case unscoped
    case run(OpaquePerformanceRunToken)
}

enum MainActorWorkRevision: Equatable, Sendable {
    case unversioned
    case value(UInt64)
}

struct MainActorWorkCounts: Equatable, Sendable {
    let input: UInt64
    let changedKey: UInt64
}

struct MainActorWorkTicket: Equatable, Sendable {
    fileprivate let ledgerID: UUID
    let workID: OpaquePerformanceWorkID
    let sequence: UInt64
}

struct MainActorWorkRecord: Equatable, Sendable {
    let version: MainActorWorkRecordVersion
    let workID: OpaquePerformanceWorkID
    let parent: MainActorWorkParent
    let run: MainActorWorkRun
    let domain: MainActorWorkDomain
    let operation: MainActorWorkOperation
    let revision: MainActorWorkRevision
    let sequence: UInt64
    let queueAgeNanoseconds: UInt64
    let synchronousServiceNanoseconds: UInt64
    let counts: MainActorWorkCounts
    let outcome: MainActorWorkOutcome
}

enum MainActorWorkInvalidity: Equatable, Sendable {
    case clockReversal(MainActorWorkClockPhase)
    case duplicateSettlement
    case foreignTicket
    case sequenceExhausted
}

enum MainActorWorkClockPhase: Equatable, Sendable {
    case enqueueToStart
    case startToSynchronousEnd
}

enum MainActorWorkEnqueueResult: Equatable, Sendable {
    case enqueued(MainActorWorkTicket)
    case rejected(MainActorWorkInvalidity)
}

enum MainActorWorkExecution<Value> {
    case completed(value: Value, record: MainActorWorkRecord)
    case rejected(MainActorWorkInvalidity)
}

final class MainActorWorkLedger: @unchecked Sendable {
    private struct PendingWork {
        let workID: OpaquePerformanceWorkID
        let parent: MainActorWorkParent
        let run: MainActorWorkRun
        let domain: MainActorWorkDomain
        let operation: MainActorWorkOperation
        let revision: MainActorWorkRevision
        let sequence: UInt64
        let enqueuedAt: PerformanceMonotonicInstant
        let counts: MainActorWorkCounts
    }

    private enum StartResult {
        case pending(PendingWork)
        case rejected(MainActorWorkInvalidity)
    }

    private let ledgerID = UUIDv7.generate()
    private let clock: any PerformanceMonotonicClock
    private let lock = NSLock()
    private var nextSequence: UInt64
    private var pendingByWorkID: [OpaquePerformanceWorkID: PendingWork] = [:]

    init(
        clock: any PerformanceMonotonicClock = SystemPerformanceMonotonicClock(),
        initialSequence: UInt64 = 0
    ) {
        self.clock = clock
        self.nextSequence = initialSequence
    }

    func enqueue(
        domain: MainActorWorkDomain,
        operation: MainActorWorkOperation,
        parent: MainActorWorkParent = .root,
        run: MainActorWorkRun = .unscoped,
        revision: MainActorWorkRevision = .unversioned,
        counts: MainActorWorkCounts = .init(input: 0, changedKey: 0)
    ) -> MainActorWorkEnqueueResult {
        lock.withLock {
            guard nextSequence < UInt64.max else { return .rejected(.sequenceExhausted) }
            nextSequence += 1
            let workID = OpaquePerformanceWorkID.make()
            let pending = PendingWork(
                workID: workID,
                parent: parent,
                run: run,
                domain: domain,
                operation: operation,
                revision: revision,
                sequence: nextSequence,
                enqueuedAt: clock.now(),
                counts: counts
            )
            pendingByWorkID[workID] = pending
            return .enqueued(MainActorWorkTicket(ledgerID: ledgerID, workID: workID, sequence: nextSequence))
        }
    }

    @MainActor
    func withMainActorWork<Value>(
        ticket: MainActorWorkTicket,
        outcome: MainActorWorkOutcome,
        body: () -> Value
    ) -> MainActorWorkExecution<Value> {
        let startResult: StartResult = lock.withLock {
            guard ticket.ledgerID == ledgerID else { return .rejected(.foreignTicket) }
            guard let pending = pendingByWorkID.removeValue(forKey: ticket.workID) else {
                return .rejected(.duplicateSettlement)
            }
            return .pending(pending)
        }
        guard case .pending(let pending) = startResult else {
            guard case .rejected(let invalidity) = startResult else { preconditionFailure() }
            return .rejected(invalidity)
        }

        let startedAt = clock.now()
        guard startedAt >= pending.enqueuedAt else {
            return .rejected(.clockReversal(.enqueueToStart))
        }
        let value = body()
        let endedAt = clock.now()
        guard endedAt >= startedAt else {
            return .rejected(.clockReversal(.startToSynchronousEnd))
        }
        return .completed(
            value: value,
            record: MainActorWorkRecord(
                version: .v1,
                workID: pending.workID,
                parent: pending.parent,
                run: pending.run,
                domain: pending.domain,
                operation: pending.operation,
                revision: pending.revision,
                sequence: pending.sequence,
                queueAgeNanoseconds: startedAt.uptimeNanoseconds - pending.enqueuedAt.uptimeNanoseconds,
                synchronousServiceNanoseconds: endedAt.uptimeNanoseconds - startedAt.uptimeNanoseconds,
                counts: pending.counts,
                outcome: outcome
            )
        )
    }
}
