import Foundation

enum OrderedFactJournalLifecycle: Sendable {
    case open, sealed, invalidated
}

enum OrderedFactProductGapState: Sendable {
    case noGap
    case pendingTransfer(FactGap, firstRetainedAt: Duration)
    case transferred(FactGap, firstRetainedAt: Duration)
}

enum OrderedFactDrainLeasePayload<Fact: Sendable>: Sendable {
    case facts(OrderedFactHistoryLease<Fact>)
    case gap(FactGap, firstRetainedAt: Duration)
}

enum OrderedFactDrainLeaseState<Fact: Sendable>: Sendable {
    case noLease
    case awaitingPresentation(AdmissionDrainToken, OrderedFactDrainLeasePayload<Fact>)
    case presented(AdmissionDrainToken, OrderedFactDrainLeasePayload<Fact>)
}

struct OrderedFactOfferContext<Fact: Sendable, Snapshot: Sendable>: Sendable {
    let offeredGeneration: AdmissionGeneration
    let fact: Fact
    let estimatedFactBytes: Int
    let snapshotReplacement: OrderedFactSnapshotReplacement<Snapshot>?
    let retainedAt: Duration

    var incomingRelease: OrderedFactIncomingOfferRelease<Fact, Snapshot> {
        if let snapshotReplacement {
            .factAndSnapshot(fact, snapshotReplacement)
        } else {
            .fact(fact)
        }
    }
}

struct OrderedFactExistingGapOfferContext: Sendable {
    let gap: FactGap
    let firstRetainedAt: Duration
}

struct OrderedFactSnapshotLimits: Sendable, Equatable {
    let maximumSnapshotBytes: Int
    let maximumPhysicalSnapshotCount: Int
    let maximumPhysicalSnapshotBytes: Int
}

struct OrderedFactDrainQuantum: Sendable, Equatable {
    let maximumFacts: Int
}

struct OrderedFactSnapshotReplacement<Snapshot: Sendable>: Sendable {
    let snapshot: Snapshot
    let estimatedBytes: Int
}

enum OrderedFactJournalConfigurationError: Error, Sendable, Equatable {
    case initialSnapshotInvalidSize
    case initialSnapshotTooLarge
    case invalidSnapshotLimits
    case invalidCleanupQuantum
}

struct OrderedFactJournalAuthoritySeeds: Sendable, Equatable {
    let bindingSequence: UInt64
    let nextLeaseSequence: UInt64
    let nextGapRevision: UInt64

    init(
        bindingSequence: UInt64 = 0,
        nextLeaseSequence: UInt64,
        nextGapRevision: UInt64
    ) {
        self.bindingSequence = bindingSequence
        self.nextLeaseSequence = nextLeaseSequence
        self.nextGapRevision = nextGapRevision
    }

    static let initial = Self(
        bindingSequence: 0,
        nextLeaseSequence: 1,
        nextGapRevision: 1
    )
}

struct OrderedFactJournalAuthoritySnapshot: Sendable, Equatable {
    let bindingEpoch: AdmissionOpaqueIdentity
    let bindingSequence: UInt64
    let leaseEpoch: AdmissionOpaqueIdentity
    let nextLeaseSequence: UInt64
    let journalIdentity: UUID
    let nextGapRevision: UInt64
}

struct OrderedFactJournalOperationSnapshot: Sendable, Equatable {
    let offerNodeVisits: UInt64
    let takeNodeVisits: UInt64
    let acknowledgementNodeVisits: UInt64
    let evictionNodeVisits: UInt64
}

struct SequencedFact<Fact: Sendable>: Sendable {
    let generation: AdmissionGeneration
    let sequence: UInt64
    let fact: Fact
}

struct SequencedSnapshot<Snapshot: Sendable>: Sendable {
    let generation: AdmissionGeneration
    let throughSequence: UInt64
    let snapshot: Snapshot
}

struct FactGapToken: Hashable, Sendable {
    let generation: AdmissionGeneration
    let journalIdentity: UUID
    let revision: UInt64
}

struct FactGap: Error, Sendable, Equatable {
    let generation: AdmissionGeneration
    let missingSequences: ClosedRange<UInt64>
    let token: FactGapToken
}

struct ReplayHistoryGap<Fact: Sendable>: Sendable {
    let generation: AdmissionGeneration
    let missingSequences: ClosedRange<UInt64>
    let availableFacts: [SequencedFact<Fact>]
    let nextSequence: UInt64
}

enum OrderedFactOfferResult: Sendable {
    case admitted(sequence: UInt64, wake: AdmissionWakeDirective)
    case gapCommitted(FactGap, wake: AdmissionWakeDirective)
    case snapshotTooLarge
    case snapshotPhysicalCapacityExceeded
    case invalidSize
    case authorityExhausted
    case staleGeneration
    case closed
}

enum OrderedFactIncomingOfferRelease<Fact: Sendable, Snapshot: Sendable>: Sendable {
    case fact(Fact)
    case factAndSnapshot(Fact, OrderedFactSnapshotReplacement<Snapshot>)
}

enum OrderedFactOfferTransition<Fact: Sendable, Snapshot: Sendable>: Sendable {
    case retained(OrderedFactOfferResult)
    case released(
        OrderedFactOfferResult,
        OrderedFactIncomingOfferRelease<Fact, Snapshot>
    )
}

enum OrderedFactDrainPayload<Fact: Sendable>: Sendable {
    case facts(NonEmptyAdmissionBatch<SequencedFact<Fact>>)
    case gap(FactGap)
}

struct OrderedFactDrain<Fact: Sendable>: Sendable {
    let token: AdmissionDrainToken
    let payload: OrderedFactDrainPayload<Fact>
    let oldestRetainedAge: ExactAdmissionAge
}

enum OrderedFactTakeDrainResult<Fact: Sendable>: Sendable {
    case drain(OrderedFactDrain<Fact>)
    case cleanupRequired
    case empty
    case alreadyDraining
    case staleGeneration
    case closed
}

enum OrderedFactReplayRecovery: Sendable, Equatable {
    case exactHistory
    case currentSnapshot
}

enum OrderedFactImmediateReplayResult: Sendable {
    case factGap(FactGap)
    case invalidCursor(latestSequence: UInt64)
    case replayInProgress
    case staleGeneration
    case invalidated
}

enum OrderedFactRegisteredReplayResult<Fact: Sendable, Snapshot: Sendable>: Sendable {
    case facts([SequencedFact<Fact>], nextSequence: UInt64)
    case snapshot(SequencedSnapshot<Snapshot>, followingFacts: [SequencedFact<Fact>], nextSequence: UInt64)
    case historyGap(ReplayHistoryGap<Fact>)
}

enum OrderedFactReplayCompletion<Fact: Sendable, Snapshot: Sendable>: Sendable {
    case immediate(OrderedFactImmediateReplayResult)
    case registered(
        OrderedFactRegisteredReplayResult<Fact, Snapshot>,
        wake: AdmissionWakeDirective
    )
}

enum OrderedFactCurrentLifecycleState: Sendable, Equatable {
    case open
    case sealed
}

enum OrderedFactCurrentStateResult<Snapshot: Sendable>: Sendable {
    case current(
        snapshot: SequencedSnapshot<Snapshot>?,
        latestSequence: UInt64,
        lifecycle: OrderedFactCurrentLifecycleState
    )
    case nonCurrent(FactGap)
    case staleGeneration
    case invalidated
}

enum OrderedFactRecoveryResult: Sendable, Equatable {
    case recovered
    case staleGeneration
    case staleGapToken
    case incorrectSequence
    case snapshotTooLarge
    case snapshotPhysicalCapacityExceeded
    case invalidSize
    case notNonCurrent
    case closed
}

struct OrderedFactJournalDiagnostics: Sendable {
    let admission: AdmissionDiagnostics
    let latestSequence: UInt64
    let retainedFactCount: Int
    let retainedFactHighWater: Int
    let retainedByteCount: Int
    let retainedByteHighWater: Int
    let pendingFactCount: Int
    let leasedFactCount: Int
    let cleanupFactCount: Int
    let cleanupFactHighWater: Int
    let cleanupByteCount: Int
    let cleanupByteHighWater: Int
    let cleanupSnapshotCount: Int
    let cleanupSnapshotHighWater: Int
    let cleanupSnapshotByteCount: Int
    let cleanupSnapshotByteHighWater: Int
    let physicalRetainedFactCount: Int
    let physicalRetainedFactHighWater: Int
    let physicalRetainedByteCount: Int
    let physicalRetainedByteHighWater: Int
    let physicalRetainedSnapshotCount: Int
    let physicalRetainedSnapshotHighWater: Int
    let physicalRetainedSnapshotByteCount: Int
    let physicalRetainedSnapshotByteHighWater: Int
    let oldestCleanupAge: AdmissionAgeMeasurement?
    let activeReplayReaderCount: Int
    let outstandingCleanupTurnCount: Int
    let outstandingDrainCount: Int
    let currentness: OrderedFactJournalDiagnosticCurrentness
    let isQuiescent: Bool
}

enum OrderedFactJournalDiagnosticCurrentness: Sendable, Equatable {
    case current
    case nonCurrent(FactGap)
    case invalidated
}
