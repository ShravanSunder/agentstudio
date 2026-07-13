import Foundation
import os

// The admission contract keeps raw state, cleanup cursors, and token-bearing
// transitions in one lexical owner. Pure scalar mechanics remain in the
// companion file; splitting this owner to satisfy a line limit would weaken
// the protected-state boundary.
// swiftlint:disable file_length type_body_length

struct GatherMailboxAuthoritySeed<Key>: Sendable where Key: Hashable & Sendable {
    let bindingSequence: UInt64
    let leaseSequence: UInt64
    let recoveryCustodySequence: UInt64
    let recoveryStampsByKey: [Key: GatherRecoveryStamp]

    init(
        bindingSequence: UInt64 = 0,
        leaseSequence: UInt64 = 0,
        recoveryCustodySequence: UInt64 = 0,
        recoveryStampsByKey: [Key: GatherRecoveryStamp] = [:]
    ) {
        self.bindingSequence = bindingSequence
        self.leaseSequence = leaseSequence
        self.recoveryCustodySequence = recoveryCustodySequence
        self.recoveryStampsByKey = recoveryStampsByKey
    }
}

struct GatherMailboxAuthoritySnapshot: Sendable, Equatable {
    let bindingEpoch: AdmissionOpaqueIdentity
    let bindingSequence: UInt64
    let leaseEpoch: AdmissionOpaqueIdentity
    let leaseSequence: UInt64
    let recoveryCustodyEpoch: AdmissionOpaqueIdentity
    let recoveryCustodySequence: UInt64
}

struct GatherProducerPort<Key, Payload>: Sendable
where Key: Hashable & Sendable, Payload: Sendable {
    fileprivate let mailbox: BoundedGatherMailbox<Key, Payload>

    func offer(
        generation: AdmissionGeneration,
        contribution: GatherContribution<Key, Payload>
    ) -> GatherOfferResult<Key> {
        mailbox.offer(generation: generation, contribution: contribution)
    }
}

struct GatherConsumerPort<Key, Payload>: AdmissionConsumerBindingSource, AdmissionCleanupConsumer
where Key: Hashable & Sendable, Payload: Sendable {
    fileprivate let mailbox: BoundedGatherMailbox<Key, Payload>

    func bindConsumer() -> AdmissionConsumerBindResult {
        mailbox.bindConsumer()
    }

    func takeDrain(
        binding: AdmissionConsumerBinding,
        generation: AdmissionGeneration
    ) -> GatherTakeDrainResult<Key, Payload> {
        mailbox.takeDrain(binding: binding, generation: generation)
    }

    func acknowledge(
        token: AdmissionDrainToken,
        disposition: AdmissionDrainDisposition
    ) -> AdmissionDrainAcknowledgement {
        mailbox.acknowledge(token: token, disposition: disposition)
    }

    func performCleanup(
        generation: AdmissionGeneration
    ) -> AdmissionCleanupTurnResult {
        mailbox.performCleanup(generation: generation)
    }
}

struct GatherLifecyclePort<Key, Payload>: AdmissionCleanupConsumer
where Key: Hashable & Sendable, Payload: Sendable {
    fileprivate let mailbox: BoundedGatherMailbox<Key, Payload>

    func seal(generation: AdmissionGeneration) -> AdmissionControlResult {
        mailbox.seal(generation: generation)
    }

    func invalidate(generation: AdmissionGeneration) -> AdmissionControlResult {
        mailbox.invalidate(generation: generation)
    }

    func performCleanup(
        generation: AdmissionGeneration
    ) -> AdmissionCleanupTurnResult {
        mailbox.performCleanup(generation: generation)
    }

    var diagnostics: GatherAdmissionDiagnostics {
        mailbox.diagnostics
    }

    var authoritySnapshot: GatherMailboxAuthoritySnapshot {
        mailbox.authoritySnapshot
    }
}

final class BoundedGatherMailbox<Key, Payload>: @unchecked Sendable
where Key: Hashable & Sendable, Payload: Sendable {
    private final class ContributionNode: @unchecked Sendable {
        let retained: RetainedContribution
        var next: ContributionNode?

        init(retained: RetainedContribution) {
            self.retained = retained
        }
    }

    private final class ReadySlotNode: @unchecked Sendable {
        let slot: Int
        weak var previous: ReadySlotNode?
        var next: ReadySlotNode?

        init(slot: Int) {
            self.slot = slot
        }
    }

    private final class ContributionSlotNode: @unchecked Sendable {
        let slot: Int
        weak var previous: ContributionSlotNode?
        var next: ContributionSlotNode?

        init(slot: Int) {
            self.slot = slot
        }
    }

    private final class DeclaredSlotShell: @unchecked Sendable {
        weak var retainedNode: RetainedSlotNode?
    }

    private final class RetainedSlotNode: @unchecked Sendable {
        let slot: Int
        weak var previous: RetainedSlotNode?
        var next: RetainedSlotNode?
        var keyState = KeyState()

        init(slot: Int) {
            self.slot = slot
        }
    }

    private struct RetainedContribution: Sendable {
        let payload: Payload
        let footprint: GatherFootprint
        let recoverySignal: GatherRecoverySignal
        let retainedAt: Duration
    }

    enum AgePrecision: Sendable, Equatable {
        case exact
        case pressureConservative
    }

    struct AgeWatermark: Sendable {
        let retainedAt: Duration
        let precision: AgePrecision
    }

    private struct RecoveryCustodyIdentity: Hashable, Sendable {
        let epoch: AdmissionOpaqueIdentity
        let sequence: UInt64
    }

    private struct RecoverySlot: Sendable {
        let stamp: GatherRecoveryStamp
        let custodyIdentity: RecoveryCustodyIdentity
        let firstRetainedAt: Duration
    }

    private struct RecoveryCustodyReference: Sendable {
        let stamp: GatherRecoveryStamp
        let identity: RecoveryCustodyIdentity
    }

    private struct RetainedContributionBatch: Sendable {
        let first: RetainedContribution
        var remaining: [RetainedContribution]

        init(_ contributions: [RetainedContribution]) {
            guard let first = contributions.first else {
                preconditionFailure("Retained contribution batch cannot be empty")
            }
            self.first = first
            remaining = Array(contributions.dropFirst())
        }

        var count: Int { 1 + remaining.count }
        var values: [RetainedContribution] { [first] + remaining }
        var firstRetainedAt: Duration { first.retainedAt }
    }

    private enum RetainedLeasePayload: Sendable {
        case contributions(RetainedContributionBatch)
        case contributionsWithRecovery(
            RetainedContributionBatch,
            RecoveryCustodyReference
        )
        case recovery(RecoveryCustodyReference)

        var contributionCount: Int {
            switch self {
            case .contributions(let batch), .contributionsWithRecovery(let batch, _):
                batch.count
            case .recovery:
                0
            }
        }
    }

    private struct RetryBucket: Sendable {
        var payload: RetainedLeasePayload
        let itemCount: Int
        let byteCount: Int
    }

    private struct KeyState: Sendable {
        var pendingHead: ContributionNode?
        var pendingTail: ContributionNode?
        var queuedContributionCount = 0
        var queuedItemCount = 0
        var queuedByteCount = 0

        var retryBucket: RetryBucket?
        var recoverySlot: RecoverySlot?
        var readyNode: ReadySlotNode?
        var contributionNode: ContributionSlotNode?
        var pendingContributionCount = 0
        var pendingItemCount = 0
        var pendingByteCount = 0
        var isRetained = false
    }

    private struct ActiveLease: Sendable {
        var token: AdmissionDrainToken
        let slot: Int
        var payload: RetainedLeasePayload
        let itemCount: Int
        let byteCount: Int
    }

    private enum ActiveLeaseState: Sendable {
        case noActiveLease
        case awaitingPresentation(ActiveLease)
        case presented(ActiveLease)
    }

    private struct CleanupRelease: Sendable {
        let retained: RetainedContribution
        let trackedSlot: Int?
    }

    private struct CleanupTurnAccounting: Sendable {
        let releasedContributionCount: Int
        let releasedItemCount: Int
        let releasedByteCount: Int
        let releasedMetadataEntryCount: Int
        let trackedSlot: Int?
        let releasedOldestRetainedAt: Duration

        var releasedEntryCount: Int {
            releasedContributionCount + releasedMetadataEntryCount
        }
    }

    private struct CleanupDetachment: Sendable {
        let entries: NonEmptyAdmissionBatch<DetachedCleanupEntry>
        let accounting: CleanupTurnAccounting
    }

    private final class ContributionChainCleanupCursor: @unchecked Sendable {
        let slot: Int
        var head: ContributionNode?

        init(slot: Int, head: ContributionNode?) {
            self.slot = slot
            self.head = head
        }
    }

    private final class InvalidatedCleanupCursor: @unchecked Sendable {
        var nextRetainedNode: RetainedSlotNode?
        var currentNode: RetainedSlotNode?
        var currentHead: ContributionNode?
        var activeLease: ActiveLease?

        init(retainedHead: RetainedSlotNode?, activeLease: ActiveLease?) {
            nextRetainedNode = retainedHead
            self.activeLease = activeLease
        }
    }

    private enum CleanupStorage: @unchecked Sendable {
        case contributionChain(ContributionChainCleanupCursor)
        case invalidated(InvalidatedCleanupCursor)
    }

    private enum DetachedCleanupEntry: @unchecked Sendable {
        case contribution(CleanupRelease)
        case metadata(RetainedSlotNode)
    }

    private struct InFlightCleanup: Sendable {
        let authority: AdmissionOpaqueIdentity
        let contributionCount: Int
        let itemCount: Int
        let byteCount: Int
        let metadataEntryCount: Int
        let releasedOldestRetainedAt: Duration
        let trackedSlot: Int?
        let hasQueuedRemainder: Bool
    }

    private final class CleanupBatch: @unchecked Sendable {
        let storage: CleanupStorage
        let initialAgeWatermark: AgeWatermark
        var remainingContributionCount: Int
        var remainingItemCount: Int
        var remainingByteCount: Int
        var remainingMetadataEntryCount = 0
        var bufferedRelease: CleanupRelease?
        var next: CleanupBatch?

        init(
            storage: CleanupStorage,
            initialAgeWatermark: AgeWatermark,
            contributionCount: Int,
            itemCount: Int,
            byteCount: Int
        ) {
            self.storage = storage
            self.initialAgeWatermark = initialAgeWatermark
            remainingContributionCount = contributionCount
            remainingItemCount = itemCount
            remainingByteCount = byteCount
        }
    }

    private enum Lifecycle: Sendable {
        case open
        case sealed
        case invalidated
    }

    private struct State: Sendable {
        var lifecycle = Lifecycle.open
        let mailboxIdentity: AdmissionOpaqueIdentity
        var bindingEpoch: AdmissionOpaqueIdentity
        var bindingSequence: UInt64
        var leaseEpoch: AdmissionOpaqueIdentity
        var leaseSequence: UInt64
        var recoveryCustodyEpoch: AdmissionOpaqueIdentity
        var recoveryCustodySequence: UInt64
        var ordinaryAdmissionSealed: Bool
        let declaredSlotShells: [DeclaredSlotShell]
        var retainedHead: RetainedSlotNode?
        var retainedTail: RetainedSlotNode?
        var readyHead: ReadySlotNode?
        var readyTail: ReadySlotNode?
        var contributionHead: ContributionSlotNode?
        var contributionTail: ContributionSlotNode?
        var activeLease = ActiveLeaseState.noActiveLease
        var wakePending = false
        var cleanupHead: CleanupBatch?
        var cleanupTail: CleanupBatch?
        var inFlightCleanup: InFlightCleanup?
        var cleanupContributionCountBySlot: [Int]
        var cleanupItemCountBySlot: [Int]
        var cleanupByteCountBySlot: [Int]

        var offered: UInt64 = 0
        var admitted: UInt64 = 0
        var contracted: UInt64 = 0
        var rejectedStale: UInt64 = 0
        var rejectedUndeclared: UInt64 = 0
        var rejectedInvalid: UInt64 = 0
        var rejectedClosed: UInt64 = 0
        var repairEscalations: UInt64 = 0

        var retainedKeyCount = 0
        var retainedKeyHighWater = 0
        var retainedContributionCount = 0
        var retainedContributionHighWater = 0
        var retainedItemCount = 0
        var retainedItemHighWater = 0
        var retainedByteCount = 0
        var retainedByteHighWater = 0
        var pendingContributionCount = 0
        var pendingItemCount = 0
        var pendingByteCount = 0
        var leasedContributionCount = 0
        var leasedItemCount = 0
        var leasedByteCount = 0
        var cleanupContributionCount = 0
        var cleanupContributionHighWater = 0
        var cleanupItemCount = 0
        var cleanupItemHighWater = 0
        var cleanupByteCount = 0
        var cleanupByteHighWater = 0
        var cleanupMetadataEntryCount = 0
        var cleanupMetadataEntryHighWater = 0
        var physicalRetainedContributionHighWater = 0
        var physicalRetainedItemHighWater = 0
        var physicalRetainedByteHighWater = 0
        var oldestContributionWatermark: AgeWatermark?
        var oldestRecoveryWatermark: AgeWatermark?
        var oldestCleanupWatermark: AgeWatermark?
        var recoverySlotCount = 0
        var recoverySlotHighWater = 0
    }

    private enum InternalOfferResult {
        case admitted(
            disposition: GatherAdmissionDisposition<Key>,
            slot: Int,
            wake: AdmissionWakeDirective
        )
        case staleGeneration
        case undeclaredKey
        case invalidFootprint
        case closed
    }

    private enum OfferAttemptResult {
        case completed(InternalOfferResult)
        case completedDiscarding(
            InternalOfferResult,
            incomingContribution: GatherContribution<Key, Payload>
        )
        case prepareRecoveryCustodyEpoch
    }

    private enum RecoveryCustodyEpochPreparation: Sendable {
        case unprepared
        case prepared(AdmissionOpaqueIdentity)
    }

    private struct OfferContext {
        let now: Duration
        let resolvedSlot: Int?
    }

    private struct OfferAttempt {
        let offeredGeneration: AdmissionGeneration
        let contribution: GatherContribution<Key, Payload>
        let context: OfferContext
        let recoveryCustodyEpochPreparation: RecoveryCustodyEpochPreparation
    }

    private struct ResolvedOfferContext {
        let contribution: GatherContribution<Key, Payload>
        let now: Duration
        let slot: Int
        let recoveryCustodyEpochPreparation: RecoveryCustodyEpochPreparation
    }

    private enum RecoveryAdvanceMode: Sendable {
        case sequenced
        case exhausted
    }

    private enum ContractionTrigger: Sendable {
        case capacityPressure
        case recoveryAuthorityExhaustion
        case ordinaryAdmissionAlreadySealed

        var recoveryAdvanceMode: RecoveryAdvanceMode {
            switch self {
            case .capacityPressure: .sequenced
            case .recoveryAuthorityExhaustion, .ordinaryAdmissionAlreadySealed: .exhausted
            }
        }
    }

    private enum RetainedOfferRecoveryMode: Sendable {
        case withoutRecovery
        case sequenced
    }

    private enum ResolvedOfferAttempt {
        case retain(ResolvedOfferContext)
        case retainWithRecovery(ResolvedOfferContext)
        case contract(
            ResolvedOfferContext,
            trigger: ContractionTrigger
        )
    }

    private struct LeaseSnapshot: Sendable {
        let token: AdmissionDrainToken
        let slot: Int
        let payload: RetainedLeasePayload
    }

    private enum InternalTakeResult {
        case lease(LeaseSnapshot)
        case cleanupRequired
        case empty
        case alreadyLeased
        case staleGeneration
        case closed
    }

    private enum AcknowledgementOutcome: Sendable {
        case result(AdmissionDrainAcknowledgement)
        case accepted(AdmissionDrainAcknowledgement, releasedLease: ActiveLease)
    }

    private struct ExtractedLease {
        let payload: RetainedLeasePayload
        let itemCount: Int
        let byteCount: Int
    }

    private enum RetiredCleanupBatchCustody: @unchecked Sendable {
        case queuedRemainder
        case retired(CleanupBatch)
    }

    private final class CleanupExecution: @unchecked Sendable {
        private enum CustodyState {
            case detached(
                entries: NonEmptyAdmissionBatch<DetachedCleanupEntry>,
                retiredBatchCustody: RetiredCleanupBatchCustody
            )
            case released
        }

        let authority: AdmissionOpaqueIdentity
        private var custodyState: CustodyState

        init(
            authority: AdmissionOpaqueIdentity,
            entries: NonEmptyAdmissionBatch<DetachedCleanupEntry>,
            retiredBatchCustody: RetiredCleanupBatchCustody
        ) {
            self.authority = authority
            custodyState = .detached(
                entries: entries,
                retiredBatchCustody: retiredBatchCustody
            )
        }

        func releaseCustody() -> ReleasedCleanupAuthority {
            guard case .detached = custodyState else {
                preconditionFailure("Gather cleanup custody released more than once")
            }
            custodyState = .released
            return ReleasedCleanupAuthority(value: authority)
        }
    }

    private enum CleanupTurnOutcome: @unchecked Sendable {
        case cleanup(CleanupExecution)
        case alreadyCleaning
        case empty
        case staleGeneration
    }

    private struct ReleasedCleanupAuthority: Sendable {
        let value: AdmissionOpaqueIdentity
    }

    private enum RecoveryAdvance: Sendable {
        case escalated(GatherRecoveryStamp)
        case preserved(GatherRecoveryStamp)

        var stamp: GatherRecoveryStamp {
            switch self {
            case .escalated(let stamp), .preserved(let stamp): stamp
            }
        }
    }

    private enum CleanupContributionRemoval: Sendable {
        case released(RetainedContribution)
        case releasedFinal(RetainedContribution)
        case noContribution
    }

    private let generation: AdmissionGeneration
    private let canonicalKeysBySlot: [Key]
    private let declaredSlotsByKey: [Key: Int]
    private let limits: GatherMailboxLimits
    private let clock: AdmissionClock
    private let lock: OSAllocatedUnfairLock<State>

    private func withAdmissionProtectedState<Result: Sendable>(
        _ body:
            @Sendable (
                inout State,
                borrowing AdmissionProtectedRegionToken
            ) throws -> Result
    ) rethrows -> Result {
        try AdmissionProtectedRegion.withToken { token in
            try lock.withLock { state in
                try body(&state, token)
            }
        }
    }

    private static func ensureRetainedNode(
        slot: Int,
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) -> RetainedSlotNode {
        if let retainedNode = state.declaredSlotShells[slot].retainedNode {
            return retainedNode
        }
        let retainedNode = RetainedSlotNode(slot: slot)
        retainedNode.previous = state.retainedTail
        state.retainedTail?.next = retainedNode
        state.retainedHead = state.retainedHead ?? retainedNode
        state.retainedTail = retainedNode
        state.declaredSlotShells[slot].retainedNode = retainedNode
        return retainedNode
    }

    private static func incrementProtectedCounter(
        _ counter: inout UInt64,
        token _: borrowing AdmissionProtectedRegionToken
    ) {
        incrementAdmissionCounter(&counter)
    }

    var producerPort: GatherProducerPort<Key, Payload> {
        GatherProducerPort(mailbox: self)
    }

    var consumerPort: GatherConsumerPort<Key, Payload> {
        GatherConsumerPort(mailbox: self)
    }

    var lifecyclePort: GatherLifecyclePort<Key, Payload> {
        GatherLifecyclePort(mailbox: self)
    }

    convenience init<C: Clock & Sendable>(
        generation: AdmissionGeneration,
        declaredKeys: Set<Key>,
        limits: GatherMailboxLimits,
        clock: C
    ) where C.Duration == Duration {
        self.init(
            generation: generation,
            declaredKeys: declaredKeys,
            limits: limits,
            admissionClock: .make(clock: clock),
            authoritySeed: GatherMailboxAuthoritySeed()
        )
    }

    convenience init(
        generation: AdmissionGeneration,
        declaredKeys: Set<Key>,
        limits: GatherMailboxLimits
    ) {
        self.init(
            generation: generation,
            declaredKeys: declaredKeys,
            limits: limits,
            admissionClock: .continuous(),
            authoritySeed: GatherMailboxAuthoritySeed()
        )
    }

    convenience init<C: Clock & Sendable>(
        generation: AdmissionGeneration,
        declaredKeys: Set<Key>,
        limits: GatherMailboxLimits,
        clock: C,
        authoritySeed: GatherMailboxAuthoritySeed<Key>
    ) where C.Duration == Duration {
        self.init(
            generation: generation,
            declaredKeys: declaredKeys,
            limits: limits,
            admissionClock: .make(clock: clock),
            authoritySeed: authoritySeed
        )
    }

    private init(
        generation: AdmissionGeneration,
        declaredKeys: Set<Key>,
        limits: GatherMailboxLimits,
        admissionClock: AdmissionClock,
        authoritySeed: GatherMailboxAuthoritySeed<Key>
    ) {
        let normalizedLimits = Self.normalized(limits)
        precondition(
            Self.isConfigurationValid(
                declaredKeyCount: declaredKeys.count,
                limits: normalizedLimits
            ),
            "Gather limits must bound keys and permit cleanup of one admissible entry"
        )
        let canonicalKeys = Array(declaredKeys)
        let slotsByKey = Dictionary(
            uniqueKeysWithValues: canonicalKeys.enumerated().map { ($0.element, $0.offset) }
        )
        let now = admissionClock.now()
        let declaredSlotShells = canonicalKeys.map { _ in DeclaredSlotShell() }
        var seededRetainedHead: RetainedSlotNode?
        var seededRetainedTail: RetainedSlotNode?
        var seededReadyHead: ReadySlotNode?
        var seededReadyTail: ReadySlotNode?
        var seededRecoverySlotCount = 0
        for (key, stamp) in authoritySeed.recoveryStampsByKey {
            guard let slot = slotsByKey[key] else {
                preconditionFailure("Recovery authority seed contains an undeclared key")
            }
            let retainedNode = RetainedSlotNode(slot: slot)
            retainedNode.previous = seededRetainedTail
            seededRetainedTail?.next = retainedNode
            seededRetainedHead = seededRetainedHead ?? retainedNode
            seededRetainedTail = retainedNode

            let readyNode = ReadySlotNode(slot: slot)
            readyNode.previous = seededReadyTail
            seededReadyTail?.next = readyNode
            seededReadyHead = seededReadyHead ?? readyNode
            seededReadyTail = readyNode

            retainedNode.keyState = KeyState(
                recoverySlot: RecoverySlot(
                    stamp: stamp,
                    custodyIdentity: RecoveryCustodyIdentity(
                        epoch: AdmissionOpaqueIdentity(),
                        sequence: 0
                    ),
                    firstRetainedAt: now
                ),
                readyNode: readyNode,
                isRetained: true
            )
            declaredSlotShells[slot].retainedNode = retainedNode
            seededRecoverySlotCount += 1
        }
        let initialState = State(
            mailboxIdentity: AdmissionOpaqueIdentity(),
            bindingEpoch: AdmissionOpaqueIdentity(),
            bindingSequence: authoritySeed.bindingSequence,
            leaseEpoch: AdmissionOpaqueIdentity(),
            leaseSequence: authoritySeed.leaseSequence,
            recoveryCustodyEpoch: AdmissionOpaqueIdentity(),
            recoveryCustodySequence: authoritySeed.recoveryCustodySequence,
            ordinaryAdmissionSealed: authoritySeed.recoveryStampsByKey.values.contains(
                .authorityExhausted
            ),
            declaredSlotShells: declaredSlotShells,
            retainedHead: seededRetainedHead,
            retainedTail: seededRetainedTail,
            readyHead: seededReadyHead,
            readyTail: seededReadyTail,
            cleanupContributionCountBySlot: canonicalKeys.map { _ in 0 },
            cleanupItemCountBySlot: canonicalKeys.map { _ in 0 },
            cleanupByteCountBySlot: canonicalKeys.map { _ in 0 },
            retainedKeyCount: seededRecoverySlotCount,
            retainedKeyHighWater: seededRecoverySlotCount,
            oldestRecoveryWatermark: seededRecoverySlotCount > 0
                ? AgeWatermark(retainedAt: now, precision: .exact)
                : nil,
            recoverySlotCount: seededRecoverySlotCount,
            recoverySlotHighWater: seededRecoverySlotCount
        )

        self.generation = generation
        canonicalKeysBySlot = canonicalKeys
        declaredSlotsByKey = slotsByKey
        self.limits = normalizedLimits
        clock = admissionClock
        lock = OSAllocatedUnfairLock(initialState: initialState)
    }

    fileprivate func offer(
        generation offeredGeneration: AdmissionGeneration,
        contribution: GatherContribution<Key, Payload>
    ) -> GatherOfferResult<Key> {
        let offerContext = makeOfferContext(for: contribution.key)
        var recoveryCustodyEpochPreparation = RecoveryCustodyEpochPreparation.unprepared
        while true {
            let result = attemptOffer(
                OfferAttempt(
                    offeredGeneration: offeredGeneration,
                    contribution: contribution,
                    context: offerContext,
                    recoveryCustodyEpochPreparation: recoveryCustodyEpochPreparation
                )
            )
            switch result {
            case .completed(let result):
                return publicOfferResult(from: result)
            case .completedDiscarding(let result, let incomingContribution):
                withExtendedLifetime(incomingContribution) {}
                return publicOfferResult(from: result)
            case .prepareRecoveryCustodyEpoch:
                recoveryCustodyEpochPreparation = .prepared(AdmissionOpaqueIdentity())
            }
        }
    }

    private func makeOfferContext(
        for key: Key
    ) -> OfferContext {
        OfferContext(now: clock.now(), resolvedSlot: declaredSlotsByKey[key])
    }

    private func attemptOffer(_ attempt: OfferAttempt) -> OfferAttemptResult {
        withAdmissionProtectedState { state, token in
            guard attempt.offeredGeneration == generation else {
                Self.incrementProtectedCounter(&state.offered, token: token)
                Self.incrementProtectedCounter(&state.rejectedStale, token: token)
                return .completedDiscarding(
                    .staleGeneration,
                    incomingContribution: attempt.contribution
                )
            }
            guard state.lifecycle == .open else {
                Self.incrementProtectedCounter(&state.offered, token: token)
                Self.incrementProtectedCounter(&state.rejectedClosed, token: token)
                return .completedDiscarding(.closed, incomingContribution: attempt.contribution)
            }
            guard let slot = attempt.context.resolvedSlot else {
                Self.incrementProtectedCounter(&state.offered, token: token)
                Self.incrementProtectedCounter(&state.rejectedUndeclared, token: token)
                return .completedDiscarding(
                    .undeclaredKey,
                    incomingContribution: attempt.contribution
                )
            }
            guard Self.isValid(attempt.contribution.footprint) else {
                Self.incrementProtectedCounter(&state.offered, token: token)
                Self.incrementProtectedCounter(&state.rejectedInvalid, token: token)
                return .completedDiscarding(
                    .invalidFootprint,
                    incomingContribution: attempt.contribution
                )
            }

            let existingKeyState = state.declaredSlotShells[slot].retainedNode?.keyState ?? KeyState()
            let resolvedAttempt = resolveOfferAttempt(
                attempt,
                slot: slot,
                keyState: existingKeyState,
                state: state
            )
            let recoveryAdvanceRequired: Bool
            switch resolvedAttempt {
            case .retain:
                recoveryAdvanceRequired = false
            case .retainWithRecovery, .contract:
                recoveryAdvanceRequired = true
            }
            if recoveryAdvanceRequired, state.recoveryCustodySequence == .max {
                switch attempt.recoveryCustodyEpochPreparation {
                case .unprepared:
                    return .prepareRecoveryCustodyEpoch
                case .prepared:
                    break
                }
            }

            let retainedNode = Self.ensureRetainedNode(
                slot: slot,
                state: &state,
                token: token
            )
            var keyState = retainedNode.keyState

            Self.incrementProtectedCounter(&state.offered, token: token)
            switch resolvedAttempt {
            case .contract(let context, let trigger):
                return .completedDiscarding(
                    completeContractedOffer(
                        context,
                        trigger: trigger,
                        keyState: &keyState,
                        state: &state,
                        token: token
                    ),
                    incomingContribution: context.contribution
                )
            case .retain(let context):
                return .completed(
                    completeRetainedOffer(
                        context,
                        recovery: .withoutRecovery,
                        keyState: &keyState,
                        state: &state,
                        token: token
                    ))
            case .retainWithRecovery(let context):
                return .completed(
                    completeRetainedOffer(
                        context,
                        recovery: .sequenced,
                        keyState: &keyState,
                        state: &state,
                        token: token
                    ))
            }
        }
    }

    fileprivate func bindConsumer() -> AdmissionConsumerBindResult {
        let replacementBindingEpoch = AdmissionOpaqueIdentity()
        return withAdmissionProtectedState { state, _ in
            let nextBindingSequence = state.bindingSequence.addingReportingOverflow(1)
            if nextBindingSequence.overflow {
                state.bindingEpoch = replacementBindingEpoch
                state.bindingSequence = 1
            } else {
                state.bindingSequence = nextBindingSequence.partialValue
            }
            switch state.activeLease {
            case .noActiveLease:
                break
            case .awaitingPresentation(let lease), .presented(let lease):
                var activeLease: ActiveLease
                activeLease = lease
                activeLease.token = makeToken(state: state)
                state.activeLease = .awaitingPresentation(activeLease)
            }
            let hasServiceableCustody =
                state.retainedKeyCount > 0
                || state.cleanupContributionCount > 0
                || state.cleanupMetadataEntryCount > 0
            state.wakePending = hasServiceableCustody
            return AdmissionConsumerBindResult(
                binding: AdmissionConsumerBinding(
                    mailboxIdentity: state.mailboxIdentity,
                    bindingEpoch: state.bindingEpoch,
                    bindingSequence: state.bindingSequence
                ),
                wake: hasServiceableCustody ? .scheduleDrain : .noWake
            )
        }
    }

    fileprivate func takeDrain(
        binding: AdmissionConsumerBinding,
        generation requestedGeneration: AdmissionGeneration
    ) -> GatherTakeDrainResult<Key, Payload> {
        let replacementLeaseEpoch = AdmissionOpaqueIdentity()
        let result = withAdmissionProtectedState { state, token -> InternalTakeResult in
            guard requestedGeneration == generation else { return .staleGeneration }
            guard state.lifecycle != .invalidated else { return .closed }
            guard
                binding.matches(
                    mailboxIdentity: state.mailboxIdentity,
                    bindingEpoch: state.bindingEpoch,
                    bindingSequence: state.bindingSequence
                )
            else {
                return .alreadyLeased
            }

            switch state.activeLease {
            case .awaitingPresentation(let activeLease):
                state.activeLease = .presented(activeLease)
                state.wakePending = false
                return .lease(snapshot(from: activeLease))
            case .presented:
                return .alreadyLeased
            case .noActiveLease:
                break
            }

            if state.cleanupContributionCount > 0 || state.cleanupMetadataEntryCount > 0 {
                state.wakePending = false
                return .cleanupRequired
            }

            guard let slot = popReadySlot(state: &state, token: token) else {
                state.wakePending = false
                return state.lifecycle == .sealed ? .closed : .empty
            }
            guard let retainedNode = state.declaredSlotShells[slot].retainedNode else {
                preconditionFailure("Gather ready slot lost retained metadata")
            }
            var keyState = retainedNode.keyState
            let extracted = extractLease(
                slot: slot,
                keyState: &keyState,
                state: &state,
                limits: limits,
                token: token
            )
            allocateLeaseAuthority(
                replacementEpoch: replacementLeaseEpoch,
                state: &state,
                token: token
            )
            let activeLease = ActiveLease(
                token: makeToken(state: state),
                slot: slot,
                payload: extracted.payload,
                itemCount: extracted.itemCount,
                byteCount: extracted.byteCount
            )
            state.activeLease = .presented(activeLease)
            enqueueIfWorkRemains(
                slot: slot,
                keyState: &keyState,
                state: &state,
                token: token
            )
            refreshRetainedMembership(
                slot: slot,
                keyState: &keyState,
                state: &state,
                token: token
            )
            retainedNode.keyState = keyState
            state.wakePending = false
            return .lease(snapshot(from: activeLease))
        }
        return publicTakeResult(from: result)
    }

    fileprivate func acknowledge(
        token: AdmissionDrainToken,
        disposition: AdmissionDrainDisposition
    ) -> AdmissionDrainAcknowledgement {
        let outcome: AcknowledgementOutcome =
            withAdmissionProtectedState { state, protectedToken in
                guard state.lifecycle != .invalidated else { return .result(.closed) }
                guard token.generation == generation else {
                    return .result(.staleGeneration)
                }
                guard
                    token.belongsTo(
                        mailboxIdentity: state.mailboxIdentity,
                        bindingEpoch: state.bindingEpoch,
                        bindingSequence: state.bindingSequence
                    ), case .presented(let activeLease) = state.activeLease,
                    activeLease.token == token
                else {
                    return .result(.invalidToken)
                }

                state.activeLease = .noActiveLease
                guard let retainedNode = state.declaredSlotShells[activeLease.slot].retainedNode else {
                    preconditionFailure("Gather lease lost retained metadata")
                }
                var keyState = retainedNode.keyState
                subtractLeaseCounts(activeLease, state: &state, token: protectedToken)
                switch disposition {
                case .transferred:
                    subtractRetainedCounts(activeLease, state: &state, token: protectedToken)
                    switch activeLease.payload {
                    case .contributions:
                        break
                    case .contributionsWithRecovery(_, let recovery),
                        .recovery(let recovery):
                        if let recoverySlot = keyState.recoverySlot,
                            recoverySlot.custodyIdentity == recovery.identity
                        {
                            keyState.recoverySlot = nil
                            state.recoverySlotCount -= 1
                            state.oldestRecoveryWatermark = Self.ageWatermarkAfterPotentialRemoval(
                                removedOldestRetainedAt: recoverySlot.firstRetainedAt,
                                remainingCount: state.recoverySlotCount,
                                current: state.oldestRecoveryWatermark
                            )
                        }
                    }
                    enqueueIfWorkRemains(
                        slot: activeLease.slot,
                        keyState: &keyState,
                        state: &state,
                        token: protectedToken
                    )

                case .retry:
                    keyState.retryBucket = RetryBucket(
                        payload: activeLease.payload,
                        itemCount: activeLease.itemCount,
                        byteCount: activeLease.byteCount
                    )
                    addPendingCounts(
                        activeLease,
                        keyState: &keyState,
                        state: &state,
                        token: protectedToken
                    )
                    removeReadyNode(
                        keyState: &keyState,
                        state: &state,
                        token: protectedToken
                    )
                    enqueueReady(
                        slot: activeLease.slot,
                        keyState: &keyState,
                        state: &state,
                        token: protectedToken
                    )
                }

                refreshContributionMembership(
                    slot: activeLease.slot,
                    keyState: &keyState,
                    state: &state,
                    token: protectedToken
                )
                refreshRetainedMembership(
                    slot: activeLease.slot,
                    keyState: &keyState,
                    state: &state,
                    token: protectedToken
                )
                retainedNode.keyState = keyState
                let wake = requestWakeForRetainedWork(
                    state: &state,
                    token: protectedToken
                )
                return .accepted(.accepted(wake: wake), releasedLease: activeLease)
            }
        switch outcome {
        case .result(let result):
            return result
        case .accepted(let result, let releasedLease):
            withExtendedLifetime(releasedLease) {}
            return result
        }
    }

    fileprivate func seal(generation requestedGeneration: AdmissionGeneration) -> AdmissionControlResult {
        withAdmissionProtectedState { state, _ in
            guard requestedGeneration == generation else { return .staleGeneration }
            guard state.lifecycle == .open else { return .alreadyClosed }
            state.lifecycle = .sealed
            return .applied
        }
    }

    fileprivate func invalidate(generation requestedGeneration: AdmissionGeneration) -> AdmissionControlResult {
        withAdmissionProtectedState { state, token -> AdmissionControlResult in
            guard requestedGeneration == generation else { return .staleGeneration }
            guard state.lifecycle != .invalidated else { return .alreadyClosed }
            moveInvalidatedCustodyToCleanup(state: &state, token: token)
            state.lifecycle = .invalidated
            state.readyHead = nil
            state.readyTail = nil
            state.contributionHead = nil
            state.contributionTail = nil
            state.activeLease = .noActiveLease
            state.wakePending =
                state.cleanupContributionCount > 0
                || state.cleanupMetadataEntryCount > 0
            state.retainedKeyCount = 0
            state.retainedContributionCount = 0
            state.retainedItemCount = 0
            state.retainedByteCount = 0
            state.pendingContributionCount = 0
            state.pendingItemCount = 0
            state.pendingByteCount = 0
            state.leasedContributionCount = 0
            state.leasedItemCount = 0
            state.leasedByteCount = 0
            state.oldestContributionWatermark = nil
            state.oldestRecoveryWatermark = nil
            state.recoverySlotCount = 0
            updateHighWater(state: &state, token: token)
            return .applied
        }
    }

    fileprivate func performCleanup(
        generation requestedGeneration: AdmissionGeneration
    ) -> AdmissionCleanupTurnResult {
        let outcome = withAdmissionProtectedState { state, token -> CleanupTurnOutcome in
            guard requestedGeneration == generation else {
                return .staleGeneration
            }
            return detachCleanupTurn(state: &state, token: token)
        }
        let releasedAuthority: ReleasedCleanupAuthority
        switch outcome {
        case .alreadyCleaning:
            return .alreadyCleaning
        case .empty:
            return .empty
        case .staleGeneration:
            return .staleGeneration
        case .cleanup(let execution):
            releasedAuthority = execution.releaseCustody()
        }
        return withAdmissionProtectedState { state, token in
            finalizeCleanupTurn(
                authority: releasedAuthority,
                state: &state,
                token: token
            )
        }
    }

    fileprivate var diagnostics: GatherAdmissionDiagnostics {
        let now = clock.now()
        return withAdmissionProtectedState { state, _ in
            let outstandingLeaseCount: Int
            switch state.activeLease {
            case .noActiveLease:
                outstandingLeaseCount = 0
            case .awaitingPresentation, .presented:
                outstandingLeaseCount = 1
            }
            let oldestSemanticRetainedWatermark = Self.mergeAgeWatermarks(
                state.oldestContributionWatermark,
                state.oldestRecoveryWatermark
            )
            let physicalContributionCount = state.retainedContributionCount + state.cleanupContributionCount
            let physicalItemCount = state.retainedItemCount + state.cleanupItemCount
            let physicalByteCount = state.retainedByteCount + state.cleanupByteCount
            return GatherAdmissionDiagnostics(
                admission: AdmissionDiagnostics(
                    offered: state.offered,
                    admitted: state.admitted,
                    contracted: state.contracted,
                    rejectedStale: state.rejectedStale,
                    rejectedUndeclared: state.rejectedUndeclared,
                    rejectedInvalid: state.rejectedInvalid,
                    rejectedCapacity: 0,
                    rejectedClosed: state.rejectedClosed,
                    repairEscalations: state.repairEscalations,
                    pendingKeyCount: state.retainedKeyCount,
                    pendingKeyHighWater: state.retainedKeyHighWater,
                    oldestPendingAge: Self.ageMeasurement(
                        from: oldestSemanticRetainedWatermark,
                        to: now
                    )
                ),
                retainedContributionCount: state.retainedContributionCount,
                retainedContributionHighWater: state.retainedContributionHighWater,
                retainedItemCount: state.retainedItemCount,
                retainedItemHighWater: state.retainedItemHighWater,
                retainedByteCount: state.retainedByteCount,
                retainedByteHighWater: state.retainedByteHighWater,
                pendingContributionCount: state.pendingContributionCount,
                pendingItemCount: state.pendingItemCount,
                pendingByteCount: state.pendingByteCount,
                leasedContributionCount: state.leasedContributionCount,
                leasedItemCount: state.leasedItemCount,
                leasedByteCount: state.leasedByteCount,
                cleanupContributionCount: state.cleanupContributionCount,
                cleanupContributionHighWater: state.cleanupContributionHighWater,
                cleanupItemCount: state.cleanupItemCount,
                cleanupItemHighWater: state.cleanupItemHighWater,
                cleanupByteCount: state.cleanupByteCount,
                cleanupByteHighWater: state.cleanupByteHighWater,
                cleanupMetadataEntryCount: state.cleanupMetadataEntryCount,
                cleanupMetadataEntryHighWater: state.cleanupMetadataEntryHighWater,
                physicalRetainedContributionCount: physicalContributionCount,
                physicalRetainedContributionHighWater: state.physicalRetainedContributionHighWater,
                physicalRetainedItemCount: physicalItemCount,
                physicalRetainedItemHighWater: state.physicalRetainedItemHighWater,
                physicalRetainedByteCount: physicalByteCount,
                physicalRetainedByteHighWater: state.physicalRetainedByteHighWater,
                oldestCleanupAge: Self.ageMeasurement(
                    from: state.oldestCleanupWatermark,
                    to: now
                ),
                recoverySlotCount: state.recoverySlotCount,
                recoverySlotHighWater: state.recoverySlotHighWater,
                oldestRecoveryAge: Self.ageMeasurement(
                    from: state.oldestRecoveryWatermark,
                    to: now
                ),
                outstandingLeaseCount: outstandingLeaseCount,
                outstandingCleanupTurnCount: state.inFlightCleanup == nil ? 0 : 1,
                isQuiescent: physicalContributionCount == 0
                    && state.cleanupMetadataEntryCount == 0
                    && state.recoverySlotCount == 0
                    && outstandingLeaseCount == 0
            )
        }
    }

    fileprivate var authoritySnapshot: GatherMailboxAuthoritySnapshot {
        withAdmissionProtectedState { state, _ in
            GatherMailboxAuthoritySnapshot(
                bindingEpoch: state.bindingEpoch,
                bindingSequence: state.bindingSequence,
                leaseEpoch: state.leaseEpoch,
                leaseSequence: state.leaseSequence,
                recoveryCustodyEpoch: state.recoveryCustodyEpoch,
                recoveryCustodySequence: state.recoveryCustodySequence
            )
        }
    }
}

extension BoundedGatherMailbox {
    private func resolveOfferAttempt(
        _ attempt: OfferAttempt,
        slot: Int,
        keyState: KeyState,
        state: State
    ) -> ResolvedOfferAttempt {
        let recoveryWouldExhaust = Self.recoveryWouldExhaust(
            signal: attempt.contribution.recoverySignal,
            recoverySlot: keyState.recoverySlot
        )
        let fitsCapacity =
            fitsPhysicalCapacity(
                attempt.contribution.footprint,
                slot: slot,
                keyState: keyState,
                state: state
            ) && fitsLeaseQuantum(attempt.contribution.footprint)
        let context = ResolvedOfferContext(
            contribution: attempt.contribution,
            now: attempt.context.now,
            slot: slot,
            recoveryCustodyEpochPreparation: attempt.recoveryCustodyEpochPreparation
        )
        if state.ordinaryAdmissionSealed {
            return .contract(
                context,
                trigger: .ordinaryAdmissionAlreadySealed
            )
        }
        if recoveryWouldExhaust {
            return .contract(
                context,
                trigger: .recoveryAuthorityExhaustion
            )
        }
        if !fitsCapacity {
            return .contract(
                context,
                trigger: .capacityPressure
            )
        }
        switch attempt.contribution.recoverySignal {
        case .ordinary:
            return .retain(context)
        case .authoritativeRecoveryRequired:
            return .retainWithRecovery(context)
        }
    }

    private func completeContractedOffer(
        _ attempt: ResolvedOfferContext,
        trigger: ContractionTrigger,
        keyState: inout KeyState,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) -> InternalOfferResult {
        retireQueuedPending(
            slot: attempt.slot,
            keyState: &keyState,
            state: &state,
            token: token
        )
        let advance = advanceRecovery(
            at: attempt.now,
            mode: trigger.recoveryAdvanceMode,
            custodyEpochPreparation: attempt.recoveryCustodyEpochPreparation,
            keyState: &keyState,
            state: &state,
            token: token
        )
        let cause = Self.contractionCause(trigger: trigger, recoveryAdvance: advance)
        if case .escalated = advance {
            Self.incrementProtectedCounter(&state.repairEscalations, token: token)
        }
        enqueueReady(slot: attempt.slot, keyState: &keyState, state: &state, token: token)
        refreshRetainedMembership(
            slot: attempt.slot,
            keyState: &keyState,
            state: &state,
            token: token
        )
        state.declaredSlotShells[attempt.slot].retainedNode?.keyState = keyState
        Self.incrementProtectedCounter(&state.admitted, token: token)
        Self.incrementProtectedCounter(&state.contracted, token: token)
        updateHighWater(state: &state, token: token)
        return .admitted(
            disposition: .contractedToRecovery(
                recoveryRevision(slot: attempt.slot, stamp: advance.stamp),
                cause
            ),
            slot: attempt.slot,
            wake: requestWake(state: &state, token: token)
        )
    }

    private static func contractionCause(
        trigger: ContractionTrigger,
        recoveryAdvance: RecoveryAdvance
    ) -> GatherContractionCause {
        switch trigger {
        case .ordinaryAdmissionAlreadySealed:
            .ordinaryAdmissionAlreadySealed
        case .recoveryAuthorityExhaustion:
            .recoveryAuthorityExhaustedTransition
        case .capacityPressure:
            switch recoveryAdvance {
            case .escalated(.authorityExhausted):
                .recoveryAuthorityExhaustedTransition
            case .escalated(.sequenced), .preserved:
                .capacityPressure
            }
        }
    }

    private func completeRetainedOffer(
        _ attempt: ResolvedOfferContext,
        recovery: RetainedOfferRecoveryMode,
        keyState: inout KeyState,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) -> InternalOfferResult {
        append(
            RetainedContribution(
                payload: attempt.contribution.payload,
                footprint: attempt.contribution.footprint,
                recoverySignal: attempt.contribution.recoverySignal,
                retainedAt: attempt.now
            ),
            slot: attempt.slot,
            to: &keyState,
            state: &state,
            token: token
        )
        let disposition: GatherAdmissionDisposition<Key>
        switch recovery {
        case .sequenced:
            let advance = advanceRecovery(
                at: attempt.now,
                mode: .sequenced,
                custodyEpochPreparation: attempt.recoveryCustodyEpochPreparation,
                keyState: &keyState,
                state: &state,
                token: token
            )
            if case .escalated = advance {
                Self.incrementProtectedCounter(&state.repairEscalations, token: token)
            }
            disposition = .retainedWithRecovery(
                recoveryRevision(slot: attempt.slot, stamp: advance.stamp)
            )
        case .withoutRecovery:
            disposition = .retained
        }
        enqueueReady(slot: attempt.slot, keyState: &keyState, state: &state, token: token)
        refreshRetainedMembership(
            slot: attempt.slot,
            keyState: &keyState,
            state: &state,
            token: token
        )
        state.declaredSlotShells[attempt.slot].retainedNode?.keyState = keyState
        Self.incrementProtectedCounter(&state.admitted, token: token)
        updateHighWater(state: &state, token: token)
        return .admitted(
            disposition: disposition,
            slot: attempt.slot,
            wake: requestWake(state: &state, token: token)
        )
    }

    private func publicOfferResult(from result: InternalOfferResult) -> GatherOfferResult<Key> {
        switch result {
        case .admitted(let disposition, _, let wake):
            return .admitted(disposition, wake: wake)
        case .staleGeneration:
            return .staleGeneration
        case .undeclaredKey:
            return .undeclaredKey
        case .invalidFootprint:
            return .invalidFootprint
        case .closed:
            return .closed
        }
    }

    private func publicTakeResult(
        from result: InternalTakeResult
    ) -> GatherTakeDrainResult<Key, Payload> {
        switch result {
        case .lease(let snapshot):
            let key = canonicalKeysBySlot[snapshot.slot]
            let payload: GatherDrainPayload<Key, Payload>
            switch snapshot.payload {
            case .contributions(let batch):
                payload = .contributions(publicContributions(from: batch, key: key))
            case .contributionsWithRecovery(let batch, let recovery):
                payload = .contributionsWithRecovery(
                    publicContributions(from: batch, key: key),
                    GatherRecoveryRevision(
                        generation: generation,
                        key: key,
                        stamp: recovery.stamp
                    )
                )
            case .recovery(let recovery):
                payload = .recovery(
                    GatherRecoveryRevision(
                        generation: generation,
                        key: key,
                        stamp: recovery.stamp
                    )
                )
            }
            return .lease(
                GatherDrainLease(
                    token: snapshot.token,
                    key: key,
                    payload: payload
                )
            )
        case .cleanupRequired: return .cleanupRequired
        case .empty: return .empty
        case .alreadyLeased: return .alreadyLeased
        case .staleGeneration: return .staleGeneration
        case .closed: return .closed
        }
    }

    private func publicContributions(
        from batch: RetainedContributionBatch,
        key: Key
    ) -> NonEmptyAdmissionBatch<GatherContribution<Key, Payload>> {
        func publicContribution(
            _ retained: RetainedContribution
        ) -> GatherContribution<Key, Payload> {
            GatherContribution(
                key: key,
                payload: retained.payload,
                footprint: retained.footprint,
                recoverySignal: retained.recoverySignal
            )
        }
        return NonEmptyAdmissionBatch(
            first: publicContribution(batch.first),
            remaining: batch.remaining.map(publicContribution)
        )
    }

    private func recoveryRevision(
        slot: Int,
        stamp: GatherRecoveryStamp
    ) -> GatherRecoveryRevision<Key> {
        GatherRecoveryRevision(
            generation: generation,
            key: canonicalKeysBySlot[slot],
            stamp: stamp
        )
    }

    private func fitsPhysicalCapacity(
        _ footprint: GatherFootprint,
        slot: Int,
        keyState: KeyState,
        state: State
    ) -> Bool {
        guard
            let globalContributions = Self.checkedSum(
                state.retainedContributionCount,
                state.cleanupContributionCount,
                1
            ),
            let globalItems = Self.checkedSum(
                state.retainedItemCount,
                state.cleanupItemCount,
                footprint.itemCount
            ),
            let globalBytes = Self.checkedSum(
                state.retainedByteCount,
                state.cleanupByteCount,
                footprint.byteCount
            ),
            let keyContributions = Self.checkedSum(
                keyState.pendingContributionCount,
                leasedContributionCount(slot: slot, state: state),
                state.cleanupContributionCountBySlot[slot],
                1
            ),
            let keyItems = Self.checkedSum(
                keyState.pendingItemCount,
                leasedItemCount(slot: slot, state: state),
                state.cleanupItemCountBySlot[slot],
                footprint.itemCount
            ),
            let keyBytes = Self.checkedSum(
                keyState.pendingByteCount,
                leasedByteCount(slot: slot, state: state),
                state.cleanupByteCountBySlot[slot],
                footprint.byteCount
            )
        else { return false }
        return globalContributions <= limits.maximumRetainedContributions
            && globalItems <= limits.maximumRetainedItems
            && globalBytes <= limits.maximumRetainedBytes
            && keyContributions <= limits.maximumRetainedContributionsPerKey
            && keyItems <= limits.maximumRetainedItemsPerKey
            && keyBytes <= limits.maximumRetainedBytesPerKey
    }

    private func fitsLeaseQuantum(_ footprint: GatherFootprint) -> Bool {
        limits.maximumContributionsPerLease > 0
            && footprint.itemCount <= limits.maximumItemsPerLease
            && footprint.byteCount <= limits.maximumBytesPerLease
    }

    private func append(
        _ retained: RetainedContribution,
        slot: Int,
        to keyState: inout KeyState,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        let node = ContributionNode(retained: retained)
        keyState.pendingTail?.next = node
        keyState.pendingHead = keyState.pendingHead ?? node
        keyState.pendingTail = node
        Self.addChecked(1, to: &keyState.queuedContributionCount)
        Self.addChecked(retained.footprint.itemCount, to: &keyState.queuedItemCount)
        Self.addChecked(retained.footprint.byteCount, to: &keyState.queuedByteCount)
        Self.addChecked(1, to: &keyState.pendingContributionCount)
        Self.addChecked(retained.footprint.itemCount, to: &keyState.pendingItemCount)
        Self.addChecked(retained.footprint.byteCount, to: &keyState.pendingByteCount)
        Self.addChecked(1, to: &state.pendingContributionCount)
        Self.addChecked(retained.footprint.itemCount, to: &state.pendingItemCount)
        Self.addChecked(retained.footprint.byteCount, to: &state.pendingByteCount)
        Self.addChecked(1, to: &state.retainedContributionCount)
        Self.addChecked(retained.footprint.itemCount, to: &state.retainedItemCount)
        Self.addChecked(retained.footprint.byteCount, to: &state.retainedByteCount)
        state.oldestContributionWatermark = Self.mergeAgeWatermarks(
            state.oldestContributionWatermark,
            AgeWatermark(retainedAt: retained.retainedAt, precision: .exact)
        )
        refreshContributionMembership(
            slot: slot,
            keyState: &keyState,
            state: &state,
            token: token
        )
    }

    private func retireQueuedPending(
        slot: Int,
        keyState: inout KeyState,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        guard let pendingHead = keyState.pendingHead else { return }
        let cleanupBatch = CleanupBatch(
            storage: .contributionChain(
                ContributionChainCleanupCursor(slot: slot, head: pendingHead)
            ),
            initialAgeWatermark: AgeWatermark(
                retainedAt: pendingHead.retained.retainedAt,
                precision: .exact
            ),
            contributionCount: keyState.queuedContributionCount,
            itemCount: keyState.queuedItemCount,
            byteCount: keyState.queuedByteCount
        )
        enqueueCleanupBatch(
            cleanupBatch,
            trackedSlot: slot,
            state: &state,
            token: token
        )

        keyState.pendingContributionCount -= keyState.queuedContributionCount
        keyState.pendingItemCount -= keyState.queuedItemCount
        keyState.pendingByteCount -= keyState.queuedByteCount
        state.pendingContributionCount -= keyState.queuedContributionCount
        state.pendingItemCount -= keyState.queuedItemCount
        state.pendingByteCount -= keyState.queuedByteCount
        state.retainedContributionCount -= keyState.queuedContributionCount
        state.retainedItemCount -= keyState.queuedItemCount
        state.retainedByteCount -= keyState.queuedByteCount
        state.oldestContributionWatermark = Self.ageWatermarkAfterPotentialRemoval(
            removedOldestRetainedAt: pendingHead.retained.retainedAt,
            remainingCount: state.retainedContributionCount,
            current: state.oldestContributionWatermark
        )

        keyState.pendingHead = nil
        keyState.pendingTail = nil
        keyState.queuedContributionCount = 0
        keyState.queuedItemCount = 0
        keyState.queuedByteCount = 0
        refreshContributionMembership(
            slot: slot,
            keyState: &keyState,
            state: &state,
            token: token
        )
    }

    private func enqueueCleanupBatch(
        _ batch: CleanupBatch,
        trackedSlot: Int?,
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) {
        state.cleanupTail?.next = batch
        state.cleanupHead = state.cleanupHead ?? batch
        state.cleanupTail = batch
        Self.addChecked(batch.remainingContributionCount, to: &state.cleanupContributionCount)
        Self.addChecked(batch.remainingItemCount, to: &state.cleanupItemCount)
        Self.addChecked(batch.remainingByteCount, to: &state.cleanupByteCount)
        Self.addChecked(
            batch.remainingMetadataEntryCount,
            to: &state.cleanupMetadataEntryCount
        )
        if let trackedSlot {
            Self.addChecked(
                batch.remainingContributionCount,
                to: &state.cleanupContributionCountBySlot[trackedSlot]
            )
            Self.addChecked(
                batch.remainingItemCount,
                to: &state.cleanupItemCountBySlot[trackedSlot]
            )
            Self.addChecked(
                batch.remainingByteCount,
                to: &state.cleanupByteCountBySlot[trackedSlot]
            )
        }
        state.oldestCleanupWatermark = Self.mergeAgeWatermarks(
            state.oldestCleanupWatermark,
            batch.initialAgeWatermark
        )
        state.cleanupMetadataEntryHighWater = max(
            state.cleanupMetadataEntryHighWater,
            state.cleanupMetadataEntryCount
        )
    }

    private func moveInvalidatedCustodyToCleanup(
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        guard let retainedHead = state.retainedHead else { return }
        guard
            let oldestWatermark = Self.mergeAgeWatermarks(
                state.oldestContributionWatermark,
                state.oldestRecoveryWatermark
            )
        else {
            preconditionFailure("Retained gather custody is missing its age stamp")
        }
        let activeLease: ActiveLease?
        switch state.activeLease {
        case .awaitingPresentation(let lease), .presented(let lease):
            activeLease = lease
        case .noActiveLease:
            activeLease = nil
        }
        let batch = CleanupBatch(
            storage: .invalidated(
                InvalidatedCleanupCursor(
                    retainedHead: retainedHead,
                    activeLease: activeLease
                )
            ),
            initialAgeWatermark: oldestWatermark,
            contributionCount: state.retainedContributionCount,
            itemCount: state.retainedItemCount,
            byteCount: state.retainedByteCount
        )
        batch.remainingMetadataEntryCount = state.retainedKeyCount
        enqueueCleanupBatch(batch, trackedSlot: nil, state: &state, token: token)
        state.retainedHead = nil
        state.retainedTail = nil
    }

    private func dequeueCleanupBatch(
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) -> CleanupBatch? {
        guard let batch = state.cleanupHead else { return nil }
        state.cleanupHead = batch.next
        if state.cleanupHead == nil {
            state.cleanupTail = nil
        }
        batch.next = nil
        return batch
    }

    private func detachCleanupTurn(
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) -> CleanupTurnOutcome {
        guard state.inFlightCleanup == nil else {
            return .alreadyCleaning
        }
        guard let batch = dequeueCleanupBatch(state: &state, token: token) else {
            return .empty
        }
        let detachment = takeCleanupReleases(from: batch, token: token)
        let authority = AdmissionOpaqueIdentity()
        state.inFlightCleanup = InFlightCleanup(
            authority: authority,
            contributionCount: detachment.accounting.releasedContributionCount,
            itemCount: detachment.accounting.releasedItemCount,
            byteCount: detachment.accounting.releasedByteCount,
            metadataEntryCount: detachment.accounting.releasedMetadataEntryCount,
            releasedOldestRetainedAt: detachment.accounting.releasedOldestRetainedAt,
            trackedSlot: detachment.accounting.trackedSlot,
            hasQueuedRemainder: batch.remainingContributionCount > 0
                || batch.remainingMetadataEntryCount > 0
        )
        if batch.remainingContributionCount > 0 || batch.remainingMetadataEntryCount > 0 {
            batch.next = state.cleanupHead
            state.cleanupHead = batch
            state.cleanupTail = state.cleanupTail ?? batch
        }
        let retiredBatchCustody: RetiredCleanupBatchCustody
        if batch.remainingContributionCount == 0 && batch.remainingMetadataEntryCount == 0 {
            retiredBatchCustody = .retired(batch)
        } else {
            retiredBatchCustody = .queuedRemainder
        }
        return .cleanup(
            CleanupExecution(
                authority: authority,
                entries: detachment.entries,
                retiredBatchCustody: retiredBatchCustody
            )
        )
    }

    private func takeCleanupReleases(
        from batch: CleanupBatch,
        token: borrowing AdmissionProtectedRegionToken
    ) -> CleanupDetachment {
        let maximumEntries: Int
        let maximumBytes: Int
        switch limits.cleanupQuantum {
        case .entries:
            preconditionFailure("Gather cleanup requires an entry-and-byte quantum")
        case .entriesAndBytes(let entries, let bytes):
            maximumEntries = entries
            maximumBytes = bytes
        }
        var entries: [DetachedCleanupEntry] = []
        entries.reserveCapacity(maximumEntries)
        var releasedContributionCount = 0
        var releasedMetadataEntryCount = 0
        var releasedItemCount = 0
        var releasedBytes = 0
        var trackedSlot: Int?
        while entries.count < maximumEntries {
            guard let entry = nextCleanupEntry(from: batch, token: token) else { break }
            switch entry {
            case .contribution(let release):
                let nextReleasedBytes = releasedBytes + release.retained.footprint.byteCount
                if nextReleasedBytes > maximumBytes {
                    batch.bufferedRelease = release
                    break
                }
                entries.append(entry)
                releasedContributionCount += 1
                trackedSlot = trackedSlot ?? release.trackedSlot
                releasedItemCount += release.retained.footprint.itemCount
                releasedBytes = nextReleasedBytes
                batch.remainingContributionCount -= 1
                batch.remainingItemCount -= release.retained.footprint.itemCount
                batch.remainingByteCount -= release.retained.footprint.byteCount
            case .metadata:
                entries.append(entry)
                releasedMetadataEntryCount += 1
                batch.remainingMetadataEntryCount -= 1
            }
        }
        precondition(entries.isEmpty == false, "Gather cleanup quantum made no progress")
        return CleanupDetachment(
            entries: NonEmptyAdmissionBatch(
                first: entries[0],
                remaining: Array(entries.dropFirst())
            ),
            accounting: CleanupTurnAccounting(
                releasedContributionCount: releasedContributionCount,
                releasedItemCount: releasedItemCount,
                releasedByteCount: releasedBytes,
                releasedMetadataEntryCount: releasedMetadataEntryCount,
                trackedSlot: trackedSlot,
                releasedOldestRetainedAt: batch.initialAgeWatermark.retainedAt
            )
        )
    }

    private func nextCleanupEntry(
        from batch: CleanupBatch,
        token: borrowing AdmissionProtectedRegionToken
    ) -> DetachedCleanupEntry? {
        if let bufferedRelease = batch.bufferedRelease {
            batch.bufferedRelease = nil
            return .contribution(bufferedRelease)
        }
        switch batch.storage {
        case .contributionChain(let cursor):
            guard let node = cursor.head else { return nil }
            cursor.head = node.next
            node.next = nil
            return .contribution(
                CleanupRelease(retained: node.retained, trackedSlot: cursor.slot)
            )
        case .invalidated(let cursor):
            return nextInvalidatedCleanupEntry(from: cursor, token: token)
        }
    }

    private func nextInvalidatedCleanupEntry(
        from cursor: InvalidatedCleanupCursor,
        token _: borrowing AdmissionProtectedRegionToken
    ) -> DetachedCleanupEntry? {
        if cursor.currentNode == nil, let retainedNode = cursor.nextRetainedNode {
            cursor.nextRetainedNode = retainedNode.next
            retainedNode.previous = nil
            retainedNode.next = nil
            cursor.currentNode = retainedNode
            cursor.currentHead = retainedNode.keyState.pendingHead
            retainedNode.keyState.pendingHead = nil
            retainedNode.keyState.pendingTail = nil
        }
        guard let currentNode = cursor.currentNode else { return nil }
        if cursor.activeLease?.slot == currentNode.slot, var activeLease = cursor.activeLease {
            switch removeCleanupContribution(from: &activeLease.payload) {
            case .released(let retained):
                cursor.activeLease = activeLease
                return .contribution(CleanupRelease(retained: retained, trackedSlot: nil))
            case .releasedFinal(let retained):
                cursor.activeLease = nil
                return .contribution(CleanupRelease(retained: retained, trackedSlot: nil))
            case .noContribution:
                break
            }
        }
        if let node = cursor.currentHead {
            cursor.currentHead = node.next
            node.next = nil
            return .contribution(CleanupRelease(retained: node.retained, trackedSlot: nil))
        }
        if var retryBucket = currentNode.keyState.retryBucket {
            switch removeCleanupContribution(from: &retryBucket.payload) {
            case .released(let retained):
                currentNode.keyState.retryBucket = retryBucket
                return .contribution(CleanupRelease(retained: retained, trackedSlot: nil))
            case .releasedFinal(let retained):
                currentNode.keyState.retryBucket = nil
                return .contribution(CleanupRelease(retained: retained, trackedSlot: nil))
            case .noContribution:
                break
            }
        }
        currentNode.keyState.readyNode?.previous = nil
        currentNode.keyState.readyNode?.next = nil
        currentNode.keyState.contributionNode?.previous = nil
        currentNode.keyState.contributionNode?.next = nil
        currentNode.keyState = KeyState()
        if cursor.activeLease?.slot == currentNode.slot {
            cursor.activeLease = nil
        }
        cursor.currentNode = nil
        return .metadata(currentNode)
    }

    private func removeCleanupContribution(
        from payload: inout RetainedLeasePayload
    ) -> CleanupContributionRemoval {
        switch payload {
        case .recovery:
            return .noContribution
        case .contributions(var batch):
            if let retained = batch.remaining.popLast() {
                payload = .contributions(batch)
                return .released(retained)
            }
            return .releasedFinal(batch.first)
        case .contributionsWithRecovery(var batch, let recovery):
            if let retained = batch.remaining.popLast() {
                payload = .contributionsWithRecovery(batch, recovery)
                return .released(retained)
            }
            payload = .recovery(recovery)
            return .released(batch.first)
        }
    }

    private func finalizeCleanupTurn(
        authority: ReleasedCleanupAuthority,
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) -> AdmissionCleanupTurnResult {
        guard let inFlight = state.inFlightCleanup else {
            preconditionFailure("Gather cleanup authority disappeared before finalization")
        }
        guard inFlight.authority == authority.value else {
            preconditionFailure("Gather cleanup authority changed before finalization")
        }
        if let trackedSlot = inFlight.trackedSlot {
            state.cleanupContributionCountBySlot[trackedSlot] -= inFlight.contributionCount
            state.cleanupItemCountBySlot[trackedSlot] -= inFlight.itemCount
            state.cleanupByteCountBySlot[trackedSlot] -= inFlight.byteCount
        }
        state.cleanupContributionCount -= inFlight.contributionCount
        state.cleanupItemCount -= inFlight.itemCount
        state.cleanupByteCount -= inFlight.byteCount
        state.cleanupMetadataEntryCount -= inFlight.metadataEntryCount
        let remainingEntryCount =
            state.cleanupContributionCount
            + state.cleanupMetadataEntryCount
        state.oldestCleanupWatermark = Self.ageWatermarkAfterPotentialRemoval(
            removedOldestRetainedAt: inFlight.releasedOldestRetainedAt,
            remainingCount: remainingEntryCount,
            current: state.oldestCleanupWatermark
        )
        state.inFlightCleanup = nil
        state.wakePending = state.retainedKeyCount > 0 || remainingEntryCount > 0
        return .performed(
            AdmissionCleanupTurn(
                release: .entriesAndBytes(
                    count: inFlight.contributionCount + inFlight.metadataEntryCount,
                    bytes: inFlight.byteCount
                ),
                wake: remainingEntryCount > 0 ? .scheduleDrain : .noWake
            )
        )
    }

    private func extractLease(
        slot: Int,
        keyState: inout KeyState,
        state: inout State,
        limits: GatherMailboxLimits,
        token: borrowing AdmissionProtectedRegionToken
    ) -> ExtractedLease {
        if let retryBucket = keyState.retryBucket {
            keyState.retryBucket = nil
            movePendingToLeased(
                contributions: retryBucket.payload.contributionCount,
                items: retryBucket.itemCount,
                bytes: retryBucket.byteCount,
                keyState: &keyState,
                state: &state,
                token: token
            )
            refreshContributionMembership(
                slot: slot,
                keyState: &keyState,
                state: &state,
                token: token
            )
            return ExtractedLease(
                payload: retryBucket.payload,
                itemCount: retryBucket.itemCount,
                byteCount: retryBucket.byteCount
            )
        }

        var contributions: [RetainedContribution] = []
        contributions.reserveCapacity(limits.maximumContributionsPerLease)
        var itemCount = 0
        var byteCount = 0
        while let node = keyState.pendingHead,
            contributions.count < limits.maximumContributionsPerLease,
            let nextItemCount = Self.checkedSum(itemCount, node.retained.footprint.itemCount),
            let nextByteCount = Self.checkedSum(byteCount, node.retained.footprint.byteCount),
            nextItemCount <= limits.maximumItemsPerLease,
            nextByteCount <= limits.maximumBytesPerLease
        {
            keyState.pendingHead = node.next
            if keyState.pendingHead == nil { keyState.pendingTail = nil }
            node.next = nil
            contributions.append(node.retained)
            itemCount = nextItemCount
            byteCount = nextByteCount
        }
        keyState.queuedContributionCount -= contributions.count
        keyState.queuedItemCount -= itemCount
        keyState.queuedByteCount -= byteCount
        movePendingToLeased(
            contributions: contributions.count,
            items: itemCount,
            bytes: byteCount,
            keyState: &keyState,
            state: &state,
            token: token
        )
        refreshContributionMembership(
            slot: slot,
            keyState: &keyState,
            state: &state,
            token: token
        )
        let payload: RetainedLeasePayload
        switch (contributions.first, keyState.recoverySlot) {
        case (.some, .none):
            payload = .contributions(RetainedContributionBatch(contributions))
        case (.some, .some(let recoverySlot)):
            payload = .contributionsWithRecovery(
                RetainedContributionBatch(contributions),
                RecoveryCustodyReference(
                    stamp: recoverySlot.stamp,
                    identity: recoverySlot.custodyIdentity
                )
            )
        case (.none, .some(let recoverySlot)):
            payload = .recovery(
                RecoveryCustodyReference(
                    stamp: recoverySlot.stamp,
                    identity: recoverySlot.custodyIdentity
                )
            )
        case (.none, .none):
            preconditionFailure("Gather ready queue contains a key without serviceable custody")
        }
        return ExtractedLease(payload: payload, itemCount: itemCount, byteCount: byteCount)
    }

    private func movePendingToLeased(
        contributions: Int,
        items: Int,
        bytes: Int,
        keyState: inout KeyState,
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) {
        keyState.pendingContributionCount -= contributions
        keyState.pendingItemCount -= items
        keyState.pendingByteCount -= bytes
        state.pendingContributionCount -= contributions
        state.pendingItemCount -= items
        state.pendingByteCount -= bytes
        Self.addChecked(contributions, to: &state.leasedContributionCount)
        Self.addChecked(items, to: &state.leasedItemCount)
        Self.addChecked(bytes, to: &state.leasedByteCount)
    }

    private func advanceRecovery(
        at now: Duration,
        mode: RecoveryAdvanceMode,
        custodyEpochPreparation: RecoveryCustodyEpochPreparation,
        keyState: inout KeyState,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) -> RecoveryAdvance {
        let previousStamp = keyState.recoverySlot?.stamp
        let firstRetainedAt = keyState.recoverySlot?.firstRetainedAt ?? now
        let advance: RecoveryAdvance
        switch mode {
        case .exhausted:
            if state.ordinaryAdmissionSealed {
                advance = .preserved(.authorityExhausted)
            } else {
                advance = .escalated(.authorityExhausted)
                state.ordinaryAdmissionSealed = true
            }
        case .sequenced where state.ordinaryAdmissionSealed:
            advance = .preserved(.authorityExhausted)
        case .sequenced:
            switch previousStamp {
            case .none:
                advance = .escalated(.sequenced(1))
            case .sequenced(let sequence):
                let next = sequence.addingReportingOverflow(1)
                if next.overflow {
                    advance = .escalated(.authorityExhausted)
                    state.ordinaryAdmissionSealed = true
                } else {
                    advance = .escalated(.sequenced(next.partialValue))
                }
            case .authorityExhausted:
                advance = .preserved(.authorityExhausted)
                state.ordinaryAdmissionSealed = true
            }
        }
        if keyState.recoverySlot == nil {
            state.recoverySlotCount += 1
            state.oldestRecoveryWatermark = Self.mergeAgeWatermarks(
                state.oldestRecoveryWatermark,
                AgeWatermark(retainedAt: now, precision: .exact)
            )
        }
        keyState.recoverySlot = RecoverySlot(
            stamp: advance.stamp,
            custodyIdentity: allocateRecoveryCustodyIdentity(
                preparation: custodyEpochPreparation,
                state: &state,
                token: token
            ),
            firstRetainedAt: firstRetainedAt
        )
        return advance
    }

    private func allocateRecoveryCustodyIdentity(
        preparation: RecoveryCustodyEpochPreparation,
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) -> RecoveryCustodyIdentity {
        let next = state.recoveryCustodySequence.addingReportingOverflow(1)
        if next.overflow {
            switch preparation {
            case .prepared(let replacementEpoch):
                state.recoveryCustodyEpoch = replacementEpoch
                state.recoveryCustodySequence = 1
            case .unprepared:
                preconditionFailure("Recovery custody epoch replacement was not prepared")
            }
        } else {
            state.recoveryCustodySequence = next.partialValue
        }
        return RecoveryCustodyIdentity(
            epoch: state.recoveryCustodyEpoch,
            sequence: state.recoveryCustodySequence
        )
    }

    private func allocateLeaseAuthority(
        replacementEpoch: AdmissionOpaqueIdentity,
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) {
        let next = state.leaseSequence.addingReportingOverflow(1)
        if next.overflow {
            state.leaseEpoch = replacementEpoch
            state.leaseSequence = 1
        } else {
            state.leaseSequence = next.partialValue
        }
    }

    private func makeToken(state: State) -> AdmissionDrainToken {
        AdmissionDrainToken(
            generation: generation,
            mailboxIdentity: state.mailboxIdentity,
            bindingEpoch: state.bindingEpoch,
            bindingSequence: state.bindingSequence,
            leaseEpoch: state.leaseEpoch,
            leaseSequence: state.leaseSequence
        )
    }

    private func snapshot(from activeLease: ActiveLease) -> LeaseSnapshot {
        LeaseSnapshot(
            token: activeLease.token,
            slot: activeLease.slot,
            payload: activeLease.payload
        )
    }

    private func enqueueReady(
        slot: Int,
        keyState: inout KeyState,
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) {
        guard keyState.readyNode == nil else { return }
        let node = ReadySlotNode(slot: slot)
        node.previous = state.readyTail
        state.readyTail?.next = node
        state.readyHead = state.readyHead ?? node
        state.readyTail = node
        keyState.readyNode = node
    }

    private func enqueueIfWorkRemains(
        slot: Int,
        keyState: inout KeyState,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        if keyState.pendingContributionCount > 0 || keyState.recoverySlot != nil {
            enqueueReady(slot: slot, keyState: &keyState, state: &state, token: token)
        } else {
            removeReadyNode(keyState: &keyState, state: &state, token: token)
        }
    }

    private func popReadySlot(
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) -> Int? {
        guard let node = state.readyHead else { return nil }
        state.readyHead = node.next
        state.readyHead?.previous = nil
        if state.readyHead == nil { state.readyTail = nil }
        node.next = nil
        state.declaredSlotShells[node.slot].retainedNode?.keyState.readyNode = nil
        return node.slot
    }

    private func removeReadyNode(
        keyState: inout KeyState,
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) {
        guard let node = keyState.readyNode else { return }
        let previous = node.previous
        let next = node.next
        previous?.next = next
        next?.previous = previous
        if state.readyHead === node { state.readyHead = next }
        if state.readyTail === node { state.readyTail = previous }
        node.previous = nil
        node.next = nil
        keyState.readyNode = nil
    }

    private func refreshContributionMembership(
        slot: Int,
        keyState: inout KeyState,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        if keyState.pendingContributionCount > 0 {
            enqueueContributionSlotIfNeeded(
                slot: slot,
                keyState: &keyState,
                state: &state,
                token: token
            )
        } else {
            removeContributionSlot(keyState: &keyState, state: &state, token: token)
        }
    }

    private func enqueueContributionSlotIfNeeded(
        slot: Int,
        keyState: inout KeyState,
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) {
        guard keyState.contributionNode == nil else { return }
        let node = ContributionSlotNode(slot: slot)
        node.previous = state.contributionTail
        state.contributionTail?.next = node
        state.contributionHead = state.contributionHead ?? node
        state.contributionTail = node
        keyState.contributionNode = node
    }

    private func removeContributionSlot(
        keyState: inout KeyState,
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) {
        guard let node = keyState.contributionNode else { return }
        let previous = node.previous
        let next = node.next
        previous?.next = next
        next?.previous = previous
        if state.contributionHead === node { state.contributionHead = next }
        if state.contributionTail === node { state.contributionTail = previous }
        node.previous = nil
        node.next = nil
        keyState.contributionNode = nil
    }

    private func refreshRetainedMembership(
        slot: Int,
        keyState: inout KeyState,
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) {
        let hasActiveLeaseForSlot: Bool
        switch state.activeLease {
        case .noActiveLease:
            hasActiveLeaseForSlot = false
        case .awaitingPresentation(let lease), .presented(let lease):
            hasActiveLeaseForSlot = lease.slot == slot
        }
        let hasCustody =
            keyState.pendingContributionCount > 0
            || keyState.recoverySlot != nil
            || hasActiveLeaseForSlot
        if hasCustody != keyState.isRetained {
            keyState.isRetained = hasCustody
            state.retainedKeyCount += hasCustody ? 1 : -1
            if hasCustody == false,
                let retainedNode = state.declaredSlotShells[slot].retainedNode
            {
                let previous = retainedNode.previous
                let next = retainedNode.next
                previous?.next = next
                next?.previous = previous
                if state.retainedHead === retainedNode { state.retainedHead = next }
                if state.retainedTail === retainedNode { state.retainedTail = previous }
                retainedNode.previous = nil
                retainedNode.next = nil
                state.declaredSlotShells[slot].retainedNode = nil
            }
        }
    }

    private func requestWake(
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) -> AdmissionWakeDirective {
        guard case .noActiveLease = state.activeLease, state.wakePending == false else {
            return .noWake
        }
        state.wakePending = true
        return .scheduleDrain
    }

    private func requestWakeForRetainedWork(
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) -> AdmissionWakeDirective {
        guard state.readyHead != nil else {
            state.wakePending = false
            return .noWake
        }
        return requestWake(state: &state, token: token)
    }

    private func subtractLeaseCounts(
        _ lease: ActiveLease,
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) {
        state.leasedContributionCount -= lease.payload.contributionCount
        state.leasedItemCount -= lease.itemCount
        state.leasedByteCount -= lease.byteCount
    }

    private func subtractRetainedCounts(
        _ lease: ActiveLease,
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) {
        state.retainedContributionCount -= lease.payload.contributionCount
        state.retainedItemCount -= lease.itemCount
        state.retainedByteCount -= lease.byteCount
        let removedOldestRetainedAt: Duration?
        switch lease.payload {
        case .contributions(let batch), .contributionsWithRecovery(let batch, _):
            removedOldestRetainedAt = batch.firstRetainedAt
        case .recovery:
            removedOldestRetainedAt = nil
        }
        if let removedOldestRetainedAt {
            state.oldestContributionWatermark = Self.ageWatermarkAfterPotentialRemoval(
                removedOldestRetainedAt: removedOldestRetainedAt,
                remainingCount: state.retainedContributionCount,
                current: state.oldestContributionWatermark
            )
        }
    }

    private func addPendingCounts(
        _ lease: ActiveLease,
        keyState: inout KeyState,
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) {
        Self.addChecked(lease.payload.contributionCount, to: &keyState.pendingContributionCount)
        Self.addChecked(lease.itemCount, to: &keyState.pendingItemCount)
        Self.addChecked(lease.byteCount, to: &keyState.pendingByteCount)
        Self.addChecked(lease.payload.contributionCount, to: &state.pendingContributionCount)
        Self.addChecked(lease.itemCount, to: &state.pendingItemCount)
        Self.addChecked(lease.byteCount, to: &state.pendingByteCount)
    }

    private func leasedContributionCount(slot: Int, state: State) -> Int {
        switch state.activeLease {
        case .noActiveLease:
            return 0
        case .awaitingPresentation(let lease), .presented(let lease):
            return lease.slot == slot ? lease.payload.contributionCount : 0
        }
    }

    private func leasedItemCount(slot: Int, state: State) -> Int {
        switch state.activeLease {
        case .noActiveLease:
            return 0
        case .awaitingPresentation(let lease), .presented(let lease):
            return lease.slot == slot ? lease.itemCount : 0
        }
    }

    private func leasedByteCount(slot: Int, state: State) -> Int {
        switch state.activeLease {
        case .noActiveLease:
            return 0
        case .awaitingPresentation(let lease), .presented(let lease):
            return lease.slot == slot ? lease.byteCount : 0
        }
    }

    private func updateHighWater(
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) {
        state.retainedKeyHighWater = max(state.retainedKeyHighWater, state.retainedKeyCount)
        state.retainedContributionHighWater = max(
            state.retainedContributionHighWater,
            state.retainedContributionCount
        )
        state.retainedItemHighWater = max(state.retainedItemHighWater, state.retainedItemCount)
        state.retainedByteHighWater = max(state.retainedByteHighWater, state.retainedByteCount)
        state.cleanupContributionHighWater = max(
            state.cleanupContributionHighWater,
            state.cleanupContributionCount
        )
        state.cleanupItemHighWater = max(state.cleanupItemHighWater, state.cleanupItemCount)
        state.cleanupByteHighWater = max(state.cleanupByteHighWater, state.cleanupByteCount)
        state.physicalRetainedContributionHighWater = max(
            state.physicalRetainedContributionHighWater,
            state.retainedContributionCount + state.cleanupContributionCount
        )
        state.physicalRetainedItemHighWater = max(
            state.physicalRetainedItemHighWater,
            state.retainedItemCount + state.cleanupItemCount
        )
        state.physicalRetainedByteHighWater = max(
            state.physicalRetainedByteHighWater,
            state.retainedByteCount + state.cleanupByteCount
        )
        state.recoverySlotHighWater = max(state.recoverySlotHighWater, state.recoverySlotCount)
    }

    private static func recoveryWouldExhaust(
        signal: GatherRecoverySignal,
        recoverySlot: RecoverySlot?
    ) -> Bool {
        guard signal == .authoritativeRecoveryRequired else { return false }
        return switch recoverySlot?.stamp {
        case .sequenced(.max), .authorityExhausted: true
        default: false
        }
    }

}
