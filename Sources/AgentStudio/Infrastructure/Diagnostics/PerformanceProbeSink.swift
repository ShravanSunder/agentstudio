import Foundation

enum PerformanceAgePrecision: String, CaseIterable, Sendable {
    case exact
    case pressureConservative = "pressure_conservative"
}

enum PerformanceContractionStage: String, CaseIterable, Sendable {
    case admitted
    case coalesced
    case delivered
    case fact
    case mainActorApply = "mainactor_apply"
    case rendered
    case source
}

enum PerformanceProbeRecord: Equatable, Sendable {
    case contraction(stage: PerformanceContractionStage, count: UInt64)
    case heartbeat(MainActorHeartbeatRecord)
    case mainActorWork(MainActorWorkRecord, agePrecision: PerformanceAgePrecision)
    case runStage(PerformanceRunProbeEnvelope)
}

enum PerformanceProbeOfferOutcome: Equatable, Sendable {
    case accepted
    case lost(PerformanceProbeLossReason)
}

enum PerformanceProbeLossReason: Equatable, Sendable {
    case capacity
    case shutdown
}

enum PerformanceProbeDrainState: Equatable, Sendable {
    case open
    case shutdown
}

enum PerformanceProbeDrainStartResult: Equatable, Sendable {
    case alreadyStarted(PerformanceProbeDrainToken)
    case began(PerformanceProbeDrainToken)
    case rejected(PerformanceProbeDrainStartRejection)
}

enum PerformanceProbeDrainStartRejection: Equatable, Sendable {
    case sinkMismatch
    case tokenMismatch(current: PerformanceProbeDrainToken)
}

struct PerformanceProbeSinkID: Equatable, Hashable, Sendable {
    let rawValue: UUID

    static func make() -> Self { Self(rawValue: UUIDv7.generate()) }
}

struct PerformanceProbeDrainToken: Equatable, Hashable, Sendable {
    let sinkID: PerformanceProbeSinkID
    let operationID: UUID

    static func make(sinkID: PerformanceProbeSinkID) -> Self {
        Self(sinkID: sinkID, operationID: UUIDv7.generate())
    }
}

protocol PerformanceProbeRecordingSink: Sendable {
    var sinkID: PerformanceProbeSinkID { get }
    func offer(_ record: PerformanceProbeRecord) -> PerformanceProbeOfferOutcome
}

protocol PerformanceProbeDrainableSink: PerformanceProbeRecordingSink {
    func beginDrain(using token: PerformanceProbeDrainToken) -> PerformanceProbeDrainStartResult
    func drain(
        maximumCount: Int,
        using token: PerformanceProbeDrainToken
    ) -> PerformanceProbeDrainReceipt
}

struct PerformanceProbeDrainReceipt: Equatable, Sendable {
    let token: PerformanceProbeDrainToken
    let records: [PerformanceProbeRecord]
    let acceptedTotal: UInt64
    let lostTotal: UInt64
    let remainingCount: Int
    let state: PerformanceProbeDrainState
}

private enum PerformanceProbeSinkLifecycle: Equatable, Sendable {
    case draining(PerformanceProbeDrainToken)
    case open

    var publicState: PerformanceProbeDrainState {
        switch self {
        case .draining:
            return .shutdown
        case .open:
            return .open
        }
    }
}

final class PerformanceProbeSink: PerformanceProbeDrainableSink, @unchecked Sendable {
    let sinkID = PerformanceProbeSinkID.make()
    private let capacity: Int
    private let lock = NSLock()
    private var storage: [PerformanceProbeRecord?]
    private var readIndex = 0
    private var writeIndex = 0
    private var count = 0
    private var acceptedTotal: UInt64 = 0
    private var lostTotal: UInt64 = 0
    private var lifecycle: PerformanceProbeSinkLifecycle = .open

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    func offer(_ record: PerformanceProbeRecord) -> PerformanceProbeOfferOutcome {
        lock.withLock {
            guard lifecycle == .open else {
                lostTotal = min(lostTotal + 1, UInt64.max)
                return .lost(.shutdown)
            }
            guard count < capacity else {
                lostTotal = min(lostTotal + 1, UInt64.max)
                return .lost(.capacity)
            }
            storage[writeIndex] = record
            writeIndex = (writeIndex + 1) % capacity
            count += 1
            acceptedTotal = min(acceptedTotal + 1, UInt64.max)
            return .accepted
        }
    }

    func beginDrain(using token: PerformanceProbeDrainToken) -> PerformanceProbeDrainStartResult {
        guard token.sinkID == sinkID else { return .rejected(.sinkMismatch) }
        return lock.withLock {
            switch lifecycle {
            case .open:
                lifecycle = .draining(token)
                return .began(token)
            case .draining(let current) where current == token:
                return .alreadyStarted(current)
            case .draining(let current):
                return .rejected(.tokenMismatch(current: current))
            }
        }
    }

    func drain(
        maximumCount: Int,
        using token: PerformanceProbeDrainToken
    ) -> PerformanceProbeDrainReceipt {
        precondition(maximumCount >= 0)
        return lock.withLock {
            guard case .draining(let current) = lifecycle, current == token else {
                preconditionFailure("drain requires the exact active token")
            }
            var records: [PerformanceProbeRecord] = []
            records.reserveCapacity(min(maximumCount, count))
            while records.count < maximumCount, count >= 1 {
                guard let record = storage[readIndex] else { preconditionFailure("probe ring invariant") }
                storage[readIndex] = nil
                readIndex = (readIndex + 1) % capacity
                count -= 1
                records.append(record)
            }
            return PerformanceProbeDrainReceipt(
                token: token,
                records: records,
                acceptedTotal: acceptedTotal,
                lostTotal: lostTotal,
                remainingCount: count,
                state: lifecycle.publicState
            )
        }
    }
}
