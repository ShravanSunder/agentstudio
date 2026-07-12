import Foundation

enum PressureStreamID: UInt8, CaseIterable, Sendable {
    case filesystemObservation
    case filesystemRepair
    case filesystemGitInvalidation
    case terminalViewport
    case terminalActivity
    case runtimeFacts
    case bridgeInvalidation
    case performanceEvidence

    var telemetryName: StaticString {
        switch self {
        case .filesystemObservation: "filesystem_observation"
        case .filesystemRepair: "filesystem_repair"
        case .filesystemGitInvalidation: "filesystem_git_invalidation"
        case .terminalViewport: "terminal_viewport"
        case .terminalActivity: "terminal_activity"
        case .runtimeFacts: "runtime_facts"
        case .bridgeInvalidation: "bridge_invalidation"
        case .performanceEvidence: "performance_evidence"
        }
    }
}

struct AdmissionGeneration: Hashable, Sendable {
    let owner: PressureStreamID
    let value: UInt64
}

enum AdmissionWakeDirective: Sendable, Equatable {
    case noWake
    case scheduleDrain
}

enum AdmissionDoorbellResult: Sendable, Equatable {
    case signaled
    case finished
}

protocol AdmissionDoorbellSignaler: Sendable {
    func signal()
}

protocol AdmissionDoorbellConsumer: Sendable {
    func nextSignal() async -> AdmissionDoorbellResult
}

protocol AdmissionDoorbellLifecycle: Sendable {
    func finish()
}

protocol AdmissionDoorbellOwner:
    AdmissionDoorbellSignaler, AdmissionDoorbellConsumer, AdmissionDoorbellLifecycle
{}

struct AdmissionProtectedRegionToken: ~Copyable, Sendable {
    fileprivate init() {}
}

enum AdmissionProtectedRegion {
    static func withToken<Result>(
        _ body: (borrowing AdmissionProtectedRegionToken) throws -> Result
    ) rethrows -> Result {
        try body(AdmissionProtectedRegionToken())
    }
}

struct AdmissionOpaqueIdentity: Hashable, Sendable {
    private let rawValue: UUID

    init() {
        rawValue = UUID()
    }

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

struct AdmissionConsumerBinding: Hashable, Sendable {
    private let mailboxIdentity: AdmissionOpaqueIdentity
    private let bindingEpoch: AdmissionOpaqueIdentity
    private let bindingSequence: UInt64

    init(
        mailboxIdentity: AdmissionOpaqueIdentity,
        bindingEpoch: AdmissionOpaqueIdentity,
        bindingSequence: UInt64
    ) {
        self.mailboxIdentity = mailboxIdentity
        self.bindingEpoch = bindingEpoch
        self.bindingSequence = bindingSequence
    }

    func matches(
        mailboxIdentity: AdmissionOpaqueIdentity,
        bindingEpoch: AdmissionOpaqueIdentity,
        bindingSequence: UInt64
    ) -> Bool {
        self.mailboxIdentity == mailboxIdentity
            && self.bindingEpoch == bindingEpoch
            && self.bindingSequence == bindingSequence
    }

    var tokenBindingSequence: UInt64 { bindingSequence }
}

struct AdmissionConsumerBindResult: Sendable, Equatable {
    let binding: AdmissionConsumerBinding
    let wake: AdmissionWakeDirective
}

protocol AdmissionConsumerBindingSource: Sendable {
    func bindConsumer() -> AdmissionConsumerBindResult
}

struct AdmissionDrainToken: Hashable, Sendable {
    let generation: AdmissionGeneration
    private let mailboxIdentity: AdmissionOpaqueIdentity
    private let bindingEpoch: AdmissionOpaqueIdentity
    private let bindingSequence: UInt64
    private let leaseEpoch: AdmissionOpaqueIdentity
    private let leaseSequence: UInt64

    init(
        generation: AdmissionGeneration,
        mailboxIdentity: AdmissionOpaqueIdentity,
        bindingEpoch: AdmissionOpaqueIdentity,
        bindingSequence: UInt64,
        leaseEpoch: AdmissionOpaqueIdentity,
        leaseSequence: UInt64
    ) {
        self.generation = generation
        self.mailboxIdentity = mailboxIdentity
        self.bindingEpoch = bindingEpoch
        self.bindingSequence = bindingSequence
        self.leaseEpoch = leaseEpoch
        self.leaseSequence = leaseSequence
    }

    func belongsTo(
        mailboxIdentity: AdmissionOpaqueIdentity,
        bindingEpoch: AdmissionOpaqueIdentity,
        bindingSequence: UInt64
    ) -> Bool {
        self.mailboxIdentity == mailboxIdentity
            && self.bindingEpoch == bindingEpoch
            && self.bindingSequence == bindingSequence
    }
}

enum AdmissionDrainDisposition: Sendable, Equatable {
    case transferred
    case retry
}

protocol LatestValueOverloadDisposition: Sendable {}

enum LatestValueLossyPresentation: LatestValueOverloadDisposition {}

enum LatestValueAuthoritativeResample: LatestValueOverloadDisposition {}

enum AdmissionDrainAcknowledgement: Sendable, Equatable {
    case accepted(wake: AdmissionWakeDirective)
    case staleGeneration
    case invalidToken
    case closed
}

enum AdmissionCleanupTurnResult: Sendable, Equatable {
    case performed(AdmissionCleanupTurn)
    case alreadyCleaning
    case blockedByReplayReader
    case empty
    case staleGeneration
}

protocol AdmissionCleanupConsumer: Sendable {
    func performCleanup(
        generation: AdmissionGeneration
    ) -> AdmissionCleanupTurnResult
}

enum AdmissionAgeMeasurement: Sendable, Equatable {
    case exact(Duration)
    case pressureConservative(Duration)
}

enum AdmissionControlResult: Sendable, Equatable {
    case applied
    case staleGeneration
    case alreadyClosed
}

struct AdmissionDiagnostics: Sendable, Equatable {
    let offered: UInt64
    let admitted: UInt64
    let contracted: UInt64
    let rejectedStale: UInt64
    let rejectedUndeclared: UInt64
    let rejectedInvalid: UInt64
    let rejectedCapacity: UInt64
    let rejectedClosed: UInt64
    let repairEscalations: UInt64
    let pendingKeyCount: Int
    let pendingKeyHighWater: Int
    let oldestPendingAge: AdmissionAgeMeasurement?
}

struct LatestValueAdmissionDiagnostics: Sendable, Equatable {
    let admission: AdmissionDiagnostics
    let semanticRetainedValueCount: Int
    let semanticRetainedValueHighWater: Int
    let pendingValueCount: Int
    let leasedValueCount: Int
    let cleanupValueCount: Int
    let cleanupValueHighWater: Int
    let physicalRetainedValueCount: Int
    let physicalRetainedValueHighWater: Int
    let oldestCleanupAge: AdmissionAgeMeasurement?
    let outstandingLeaseCount: Int
    let outstandingCleanupTurnCount: Int
    let isQuiescent: Bool
}

struct GatherFootprint: Sendable, Equatable {
    let itemCount: Int
    let byteCount: Int
}

struct GatherMailboxLimits: Sendable, Equatable {
    let maximumDeclaredKeys: Int
    let maximumRetainedContributions: Int
    let maximumRetainedItems: Int
    let maximumRetainedBytes: Int
    let maximumRetainedContributionsPerKey: Int
    let maximumRetainedItemsPerKey: Int
    let maximumRetainedBytesPerKey: Int
    let maximumContributionsPerLease: Int
    let maximumItemsPerLease: Int
    let maximumBytesPerLease: Int
    let cleanupQuantum: AdmissionCleanupQuantum
}

enum GatherRecoverySignal: Sendable, Equatable {
    case ordinary
    case authoritativeRecoveryRequired
}

enum GatherRecoveryStamp: Hashable, Sendable {
    case sequenced(UInt64)
    case authorityExhausted
}

struct GatherContribution<Key, Payload>: Sendable
where Key: Hashable & Sendable, Payload: Sendable {
    let key: Key
    let payload: Payload
    let footprint: GatherFootprint
    let recoverySignal: GatherRecoverySignal
}

struct GatherRecoveryRevision<Key>: Hashable, Sendable where Key: Hashable & Sendable {
    let generation: AdmissionGeneration
    let key: Key
    private let stamp: GatherRecoveryStamp

    init(generation: AdmissionGeneration, key: Key, stamp: GatherRecoveryStamp) {
        self.generation = generation
        self.key = key
        self.stamp = stamp
    }
}

enum GatherAdmissionDisposition<Key>: Sendable where Key: Hashable & Sendable {
    case retained
    case retainedWithRecovery(GatherRecoveryRevision<Key>)
    case contractedToRecovery(GatherRecoveryRevision<Key>)
}

enum GatherOfferResult<Key>: Sendable where Key: Hashable & Sendable {
    case admitted(GatherAdmissionDisposition<Key>, wake: AdmissionWakeDirective)
    case staleGeneration
    case undeclaredKey
    case invalidFootprint
    case closed
}

enum GatherDrainPayload<Key, Payload>: Sendable
where Key: Hashable & Sendable, Payload: Sendable {
    case contributions(NonEmptyAdmissionBatch<GatherContribution<Key, Payload>>)
    case contributionsWithRecovery(
        NonEmptyAdmissionBatch<GatherContribution<Key, Payload>>,
        GatherRecoveryRevision<Key>
    )
    case recovery(GatherRecoveryRevision<Key>)
}

struct GatherDrainLease<Key, Payload>: Sendable
where Key: Hashable & Sendable, Payload: Sendable {
    let token: AdmissionDrainToken
    let key: Key
    let payload: GatherDrainPayload<Key, Payload>
}

enum GatherTakeDrainResult<Key, Payload>: Sendable
where Key: Hashable & Sendable, Payload: Sendable {
    case lease(GatherDrainLease<Key, Payload>)
    case cleanupRequired
    case empty
    case alreadyLeased
    case staleGeneration
    case closed
}

struct GatherAdmissionDiagnostics: Sendable, Equatable {
    let admission: AdmissionDiagnostics
    let retainedContributionCount: Int
    let retainedContributionHighWater: Int
    let retainedItemCount: Int
    let retainedItemHighWater: Int
    let retainedByteCount: Int
    let retainedByteHighWater: Int
    let pendingContributionCount: Int
    let pendingItemCount: Int
    let pendingByteCount: Int
    let leasedContributionCount: Int
    let leasedItemCount: Int
    let leasedByteCount: Int
    let cleanupContributionCount: Int
    let cleanupContributionHighWater: Int
    let cleanupItemCount: Int
    let cleanupItemHighWater: Int
    let cleanupByteCount: Int
    let cleanupByteHighWater: Int
    let cleanupMetadataEntryCount: Int
    let cleanupMetadataEntryHighWater: Int
    let physicalRetainedContributionCount: Int
    let physicalRetainedContributionHighWater: Int
    let physicalRetainedItemCount: Int
    let physicalRetainedItemHighWater: Int
    let physicalRetainedByteCount: Int
    let physicalRetainedByteHighWater: Int
    let oldestCleanupAge: AdmissionAgeMeasurement?
    let recoverySlotCount: Int
    let recoverySlotHighWater: Int
    let oldestRecoveryAge: AdmissionAgeMeasurement?
    let outstandingLeaseCount: Int
    let outstandingCleanupTurnCount: Int
    let isQuiescent: Bool
}

struct AdmissionClock: Sendable {
    let now: @Sendable () -> Duration

    static func continuous() -> Self {
        make(clock: ContinuousClock())
    }

    static func make<C: Clock>(clock: C) -> Self where C.Duration == Duration, C: Sendable {
        let origin = clock.now
        return Self(now: { origin.duration(to: clock.now) })
    }
}

func admissionAge(from start: Duration?, to end: Duration) -> Duration? {
    guard let start else { return nil }
    return Swift.max(.zero, end - start)
}

func exactAdmissionAge(
    from start: Duration?,
    to end: Duration
) -> AdmissionAgeMeasurement? {
    admissionAge(from: start, to: end).map(AdmissionAgeMeasurement.exact)
}

func incrementAdmissionCounter(_ counter: inout UInt64, by increment: UInt64 = 1) {
    let result = counter.addingReportingOverflow(increment)
    counter = result.overflow ? .max : result.partialValue
}
