import Foundation
import os

// swiftlint:disable file_length

final class OrderedFactJournal<Fact: Sendable, Snapshot: Sendable>: @unchecked Sendable {
    private enum Lifecycle: Sendable {
        case open, sealed, invalidated
    }

    private struct ProductGapState: Sendable {
        let gap: FactGap
        let firstRetainedAt: Duration
        var needsTransfer: Bool
    }

    private struct RetainedSnapshot: Sendable {
        let sequencedSnapshot: SequencedSnapshot<Snapshot>
        let estimatedBytes: Int, firstRetainedAt: Duration
    }

    private enum LeasePayload: Sendable {
        case facts(OrderedFactHistoryLease<Fact>)
        case gap(FactGap, firstRetainedAt: Duration)
    }

    private struct DrainLease: Sendable {
        var token: AdmissionDrainToken
        let payload: LeasePayload
        var needsPresentation: Bool
    }

    private final class SnapshotCleanupNode: @unchecked Sendable {
        let retainedSnapshot: RetainedSnapshot
        var next: SnapshotCleanupNode?

        init(
            retainedSnapshot: RetainedSnapshot,
            token _: borrowing AdmissionProtectedRegionToken
        ) {
            self.retainedSnapshot = retainedSnapshot
        }
    }

    private struct CleanupBatch: Sendable {
        let factHistory: OrderedFactDetachedHistory<Fact>?
        let snapshots: [RetainedSnapshot]
        let release: OrderedFactCleanupRelease
        let oldestRetainedAt: Duration?
    }

    private struct InFlightCleanup: Sendable {
        let authority: AdmissionOpaqueIdentity
        let release: OrderedFactCleanupRelease
        let oldestRetainedAt: Duration?
    }

    private struct CleanupDetachTransition: Sendable {
        let result: AdmissionCleanupTurnResult
        let authority: AdmissionOpaqueIdentity?
        var batch: CleanupBatch?
    }

    private struct State: Sendable {
        var lifecycle = Lifecycle.open
        var latestSequence, historyUnavailableThrough: UInt64
        var history = OrderedFactHistory<Fact>()
        var retainedSnapshot: RetainedSnapshot?
        var productGap: ProductGapState?
        var drainLease: DrainLease?
        var wakePending = false
        var bindingEpoch = AdmissionOpaqueIdentity(), leaseEpoch = AdmissionOpaqueIdentity()
        var bindingSequence: UInt64, nextLeaseSequence: UInt64 = 1
        var journalIdentity = UUID()
        var nextGapRevision: UInt64 = 1

        var cleanupFactHead, cleanupFactTail: OrderedFactHistoryNode<Fact>?
        var cleanupFactCount = 0, cleanupFactBytes = 0
        var cleanupSnapshotHead, cleanupSnapshotTail: SnapshotCleanupNode?
        var cleanupSnapshotCount = 0, cleanupSnapshotBytes = 0
        var inFlightCleanup: InFlightCleanup?
        var activeReplayReaderIdentity: AdmissionOpaqueIdentity?

        var offered: UInt64 = 0, admitted: UInt64 = 0, contracted: UInt64 = 0
        var rejectedStale: UInt64 = 0, rejectedInvalid: UInt64 = 0, rejectedCapacity: UInt64 = 0
        var rejectedClosed: UInt64 = 0, repairEscalations: UInt64 = 0
        var pendingHighWater = 0, retainedFactHighWater = 0
        var retainedByteHighWater = 0, cleanupFactHighWater = 0
        var cleanupByteHighWater = 0, cleanupSnapshotHighWater = 0
        var cleanupSnapshotByteHighWater = 0, physicalRetainedFactHighWater = 0
        var physicalRetainedByteHighWater = 0, physicalRetainedSnapshotHighWater = 0
        var physicalRetainedSnapshotByteHighWater = 0

        init(
            initialSequence: UInt64,
            retainedSnapshot: RetainedSnapshot?,
            authoritySeeds: OrderedFactJournalAuthoritySeeds
        ) {
            latestSequence = initialSequence
            historyUnavailableThrough = initialSequence
            self.retainedSnapshot = retainedSnapshot
            bindingSequence = authoritySeeds.bindingSequence
            nextLeaseSequence = authoritySeeds.nextLeaseSequence
            nextGapRevision = authoritySeeds.nextGapRevision
            physicalRetainedByteHighWater = retainedSnapshot?.estimatedBytes ?? 0
            physicalRetainedSnapshotHighWater = retainedSnapshot == nil ? 0 : 1
            physicalRetainedSnapshotByteHighWater = retainedSnapshot?.estimatedBytes ?? 0
        }

        var cleanupByteCount: Int { cleanupFactBytes + cleanupSnapshotBytes }
        var physicalRetainedFactCount: Int { history.retainedFactCount + cleanupFactCount }
        var physicalRetainedByteCount: Int {
            history.retainedByteCount
                + (retainedSnapshot?.estimatedBytes ?? 0)
                + cleanupFactBytes
                + cleanupSnapshotBytes
        }
        var physicalRetainedSnapshotCount: Int {
            cleanupSnapshotCount + (retainedSnapshot == nil ? 0 : 1)
        }
        var physicalRetainedSnapshotByteCount: Int {
            (retainedSnapshot?.estimatedBytes ?? 0) + cleanupSnapshotBytes
        }

        var hasQueuedCleanupCustody: Bool { cleanupFactHead != nil || cleanupSnapshotHead != nil }

        var hasCleanupCustody: Bool {
            cleanupFactCount > 0 || cleanupSnapshotCount > 0 || inFlightCleanup != nil
        }

        var isCleanupEligible: Bool {
            hasQueuedCleanupCustody
                && inFlightCleanup == nil
                && activeReplayReaderIdentity == nil
        }
    }

    private let generation: AdmissionGeneration
    private let maximumRetainedFacts: Int
    private let maximumRetainedBytes: Int
    private let snapshotLimits: OrderedFactSnapshotLimits
    private let drainQuantum: OrderedFactDrainQuantum
    private let cleanupQuantum: AdmissionCleanupQuantum
    private let mailboxIdentity = AdmissionOpaqueIdentity()
    private let clock: AdmissionClock
    private let lock: OSAllocatedUnfairLock<State>

    init(
        generation: AdmissionGeneration,
        maximumRetainedFacts: Int,
        maximumRetainedBytes: Int,
        snapshotLimits: OrderedFactSnapshotLimits,
        maximumDrainFacts: Int,
        cleanupQuantum: AdmissionCleanupQuantum,
        initialSequence: UInt64 = 0,
        initialSnapshot: Snapshot?,
        initialSnapshotBytes: Int,
        admissionClock: AdmissionClock = .continuous(),
        authoritySeeds: OrderedFactJournalAuthoritySeeds = .initial
    ) throws {
        self.generation = generation
        self.maximumRetainedFacts = Swift.max(0, maximumRetainedFacts)
        self.maximumRetainedBytes = Swift.max(0, maximumRetainedBytes)
        self.snapshotLimits = normalizedOrderedFactSnapshotLimits(snapshotLimits)
        drainQuantum = OrderedFactDrainQuantum(maximumFacts: Swift.max(1, maximumDrainFacts))
        self.cleanupQuantum = cleanupQuantum
        try validateOrderedFactJournalConfiguration(
            cleanupQuantum: cleanupQuantum,
            maximumRetainedBytes: self.maximumRetainedBytes,
            snapshotLimits: self.snapshotLimits,
            initialSnapshot: initialSnapshot,
            initialSnapshotBytes: initialSnapshotBytes
        )
        clock = admissionClock
        let initialRetainedAt = initialSnapshot == nil ? Duration.zero : clock.now()
        lock = OSAllocatedUnfairLock(
            initialState: Self.makeInitialState(
                generation: generation,
                initialSequence: initialSequence,
                initialSnapshot: initialSnapshot,
                initialSnapshotBytes: initialSnapshotBytes,
                initialRetainedAt: initialRetainedAt,
                authoritySeeds: authoritySeeds
            ))
    }

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
}

extension OrderedFactJournal {
    func bindConsumer() -> AdmissionConsumerBindResult {
        withAdmissionProtectedState { state, token in
            let nextBindingSequence = state.bindingSequence.addingReportingOverflow(1)
            if nextBindingSequence.overflow {
                state.bindingEpoch = AdmissionOpaqueIdentity()
                state.bindingSequence = 1
            } else {
                state.bindingSequence = nextBindingSequence.partialValue
            }

            if var drainLease = state.drainLease {
                drainLease.token = allocateDrainToken(state: &state, token: token)
                drainLease.needsPresentation = true
                state.drainLease = drainLease
                state.wakePending = true
            } else if hasTransferWork(state: state, token: token) || state.isCleanupEligible {
                state.wakePending = true
            }

            return AdmissionConsumerBindResult(
                binding: AdmissionConsumerBinding(
                    mailboxIdentity: mailboxIdentity,
                    bindingEpoch: state.bindingEpoch,
                    bindingSequence: state.bindingSequence
                ),
                wake: state.wakePending ? .scheduleDrain : .noWake
            )
        }
    }

    func offer(
        generation offeredGeneration: AdmissionGeneration,
        fact: Fact,
        estimatedFactBytes: Int,
        snapshotReplacement: OrderedFactSnapshotReplacement<Snapshot>?
    ) -> OrderedFactOfferResult {
        let now = clock.now()
        return withAdmissionProtectedState { state, token in
            let preflight = classifyOrderedFactOffer(
                lifecycle: (offeredGeneration == generation, state.lifecycle == .open),
                estimatedFactBytes: estimatedFactBytes,
                estimatedSnapshotBytes: snapshotReplacement?.estimatedBytes,
                snapshotLimits: snapshotLimits,
                snapshotPressure: (
                    state.physicalRetainedSnapshotCount,
                    state.physicalRetainedSnapshotByteCount
                )
            )
            if let rejection = applyOfferPreflight(preflight, state: &state, token: token) {
                return rejection
            }

            let nextSequence = state.latestSequence.addingReportingOverflow(1)
            guard nextSequence.overflow == false else {
                state.lifecycle = .sealed
                incrementAdmissionCounter(&state.rejectedClosed)
                return .authorityExhausted
            }

            let sequence = nextSequence.partialValue
            if state.productGap != nil {
                let result = commitOfferIntoExistingGap(
                    sequence: sequence,
                    snapshotReplacement: snapshotReplacement,
                    now: now,
                    state: &state,
                    token: token
                )
                return result
            }

            evictTransferredHistoryToFit(
                additionalBytes: estimatedFactBytes,
                state: &state,
                token: token
            )
            guard canRetainFact(bytes: estimatedFactBytes, state: state, token: token) else {
                let lowerBound =
                    state.history.firstPendingSequence
                    ?? sequence
                let gap = commitGap(
                    missing: lowerBound...sequence,
                    at: now,
                    state: &state,
                    token: token
                )
                state.latestSequence = sequence
                applySnapshotReplacement(
                    snapshotReplacement,
                    through: sequence,
                    retainedAt: now,
                    state: &state,
                    token: token
                )
                incrementAdmissionCounter(&state.admitted)
                incrementAdmissionCounter(&state.repairEscalations)
                incrementAdmissionCounter(&state.contracted)
                state.drainLease = nil
                let wake = requestWake(state: &state, token: token)
                updateHighWater(state: &state, token: token)
                return .gapCommitted(gap, wake: wake)
            }

            state.latestSequence = sequence
            state.history.append(
                SequencedFact(
                    generation: generation,
                    sequence: sequence,
                    fact: fact
                ),
                estimatedBytes: estimatedFactBytes,
                firstRetainedAt: now
            )
            applySnapshotReplacement(
                snapshotReplacement,
                through: sequence,
                retainedAt: now,
                state: &state,
                token: token
            )
            incrementAdmissionCounter(&state.admitted)
            let wake = requestWake(state: &state, token: token)
            updateHighWater(state: &state, token: token)
            return .admitted(sequence: sequence, wake: wake)
        }
    }

    private func applyOfferPreflight(
        _ preflight: OrderedFactOfferPreflight,
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) -> OrderedFactOfferResult? {
        switch preflight {
        case .staleGeneration:
            incrementAdmissionCounter(&state.offered)
            incrementAdmissionCounter(&state.rejectedStale)
            return .staleGeneration
        case .closed:
            incrementAdmissionCounter(&state.offered)
            incrementAdmissionCounter(&state.rejectedClosed)
            return .closed
        case .invalidSize:
            incrementAdmissionCounter(&state.offered)
            incrementAdmissionCounter(&state.rejectedInvalid)
            return .invalidSize
        case .snapshotTooLarge:
            incrementAdmissionCounter(&state.offered)
            incrementAdmissionCounter(&state.rejectedInvalid)
            return .snapshotTooLarge
        case .snapshotPhysicalCapacityExceeded:
            incrementAdmissionCounter(&state.offered)
            incrementAdmissionCounter(&state.rejectedCapacity)
            return .snapshotPhysicalCapacityExceeded
        case .admit:
            incrementAdmissionCounter(&state.offered)
            return nil
        }
    }

    private func commitOfferIntoExistingGap(
        sequence: UInt64,
        snapshotReplacement: OrderedFactSnapshotReplacement<Snapshot>?,
        now: Duration,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) -> OrderedFactOfferResult {
        guard let existingGap = state.productGap else {
            preconditionFailure("Existing-gap offer transition requires product gap custody")
        }
        let gap = widenGap(
            existingGap,
            through: sequence,
            state: &state,
            token: token
        )
        state.latestSequence = sequence
        applySnapshotReplacement(
            snapshotReplacement,
            through: sequence,
            retainedAt: now,
            state: &state,
            token: token
        )
        incrementAdmissionCounter(&state.admitted)
        incrementAdmissionCounter(&state.contracted)
        incrementAdmissionCounter(&state.repairEscalations)
        state.drainLease = nil
        let wake = requestWake(state: &state, token: token)
        updateHighWater(state: &state, token: token)
        return .gapCommitted(gap, wake: wake)
    }

    func takeDrain(
        binding: AdmissionConsumerBinding,
        generation requestedGeneration: AdmissionGeneration
    ) -> OrderedFactTakeDrainResult<Fact> {
        let now = clock.now()
        return withAdmissionProtectedState { state, token in
            guard requestedGeneration == generation else { return .staleGeneration }
            guard state.lifecycle != .invalidated else { return .closed }
            guard
                binding.matches(
                    mailboxIdentity: mailboxIdentity,
                    bindingEpoch: state.bindingEpoch,
                    bindingSequence: state.bindingSequence
                )
            else { return .alreadyDraining }

            if var drainLease = state.drainLease {
                guard drainLease.needsPresentation else { return .alreadyDraining }
                drainLease.needsPresentation = false
                state.drainLease = drainLease
                state.wakePending = false
                return makeDrain(from: drainLease, now: now, token: token)
            }
            guard state.hasCleanupCustody == false else { return .cleanupRequired }

            if let productGap = state.productGap, productGap.needsTransfer {
                let drainToken = allocateDrainToken(state: &state, token: token)
                let drainLease = DrainLease(
                    token: drainToken,
                    payload: .gap(productGap.gap, firstRetainedAt: productGap.firstRetainedAt),
                    needsPresentation: false
                )
                state.drainLease = drainLease
                state.wakePending = false
                return makeDrain(from: drainLease, now: now, token: token)
            }

            guard let historyLease = state.history.takeLease(quantum: drainQuantum) else {
                state.wakePending = false
                return state.lifecycle == .sealed ? .closed : .empty
            }

            let drainToken = allocateDrainToken(state: &state, token: token)
            let drainLease = DrainLease(
                token: drainToken,
                payload: .facts(historyLease),
                needsPresentation: false
            )
            state.drainLease = drainLease
            state.wakePending = false
            return makeDrain(from: drainLease, now: now, token: token)
        }
    }

    func acknowledge(
        _ drainToken: AdmissionDrainToken,
        disposition: AdmissionDrainDisposition
    ) -> AdmissionDrainAcknowledgement {
        withAdmissionProtectedState { state, protectedToken in
            guard state.lifecycle != .invalidated else { return .closed }
            guard drainToken.generation == generation else {
                return .staleGeneration
            }
            guard
                drainToken.belongsTo(
                    mailboxIdentity: mailboxIdentity,
                    bindingEpoch: state.bindingEpoch,
                    bindingSequence: state.bindingSequence
                )
            else {
                return .invalidToken
            }
            guard let lease = state.drainLease, lease.token == drainToken else {
                return .invalidToken
            }

            switch (lease.payload, disposition) {
            case (.facts(let historyLease), .transferred):
                guard state.history.acknowledgeTransferredLease(historyLease) else {
                    return .invalidToken
                }
            case (.gap(let gap, _), .transferred):
                if state.productGap?.gap.token == gap.token {
                    state.productGap?.needsTransfer = false
                }
            case (_, .retry):
                break
            }

            state.drainLease = nil
            let wake = requestWakeForRemainingWork(state: &state, token: protectedToken)
            updateHighWater(state: &state, token: protectedToken)
            return .accepted(wake: wake)
        }
    }

    func seal(generation requestedGeneration: AdmissionGeneration) -> AdmissionControlResult {
        withAdmissionProtectedState { state, _ in
            guard requestedGeneration == generation else { return .staleGeneration }
            guard state.lifecycle == .open else { return .alreadyClosed }
            state.lifecycle = .sealed
            return .applied
        }
    }

    func invalidate(
        generation requestedGeneration: AdmissionGeneration
    ) -> AdmissionControlResult {
        withAdmissionProtectedState { state, token in
            guard requestedGeneration == generation else {
                return .staleGeneration
            }
            guard state.lifecycle != .invalidated else { return .alreadyClosed }
            state.lifecycle = .invalidated
            enqueueCleanupHistory(
                state.history.detachAll(),
                state: &state,
                token: token
            )
            let invalidatedSnapshot = state.retainedSnapshot
            state.retainedSnapshot = nil
            enqueueCleanupSnapshot(invalidatedSnapshot, state: &state, token: token)
            state.productGap = nil
            state.drainLease = nil
            state.wakePending = state.isCleanupEligible
            updateHighWater(state: &state, token: token)
            return .applied
        }
    }

    func performCleanup(
        generation requestedGeneration: AdmissionGeneration
    ) -> AdmissionCleanupTurnResult {
        var transition = withAdmissionProtectedState { state, token in
            detachCleanup(
                requestedGeneration: requestedGeneration,
                state: &state,
                token: token
            )
        }
        guard let authority = transition.authority else { return transition.result }
        transition.batch = nil
        return withAdmissionProtectedState { state, token in
            finalizeCleanup(authority: authority, state: &state, token: token)
        }
    }

    private static func makeInitialState(
        generation: AdmissionGeneration,
        initialSequence: UInt64,
        initialSnapshot: Snapshot?,
        initialSnapshotBytes: Int,
        initialRetainedAt: Duration,
        authoritySeeds: OrderedFactJournalAuthoritySeeds
    ) -> State {
        let retainedSnapshot = initialSnapshot.map {
            RetainedSnapshot(
                sequencedSnapshot: SequencedSnapshot(
                    generation: generation,
                    throughSequence: initialSequence,
                    snapshot: $0
                ),
                estimatedBytes: initialSnapshotBytes,
                firstRetainedAt: initialRetainedAt
            )
        }
        return State(
            initialSequence: initialSequence,
            retainedSnapshot: retainedSnapshot,
            authoritySeeds: authoritySeeds
        )
    }

    private func applySnapshotReplacement(
        _ replacement: OrderedFactSnapshotReplacement<Snapshot>?,
        through sequence: UInt64,
        retainedAt: Duration,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        guard let replacement else { return }
        let bytes = replacement.estimatedBytes
        let previousSnapshot = state.retainedSnapshot
        state.retainedSnapshot = nil
        enqueueCleanupSnapshot(previousSnapshot, state: &state, token: token)
        state.retainedSnapshot = RetainedSnapshot(
            sequencedSnapshot: SequencedSnapshot(
                generation: generation,
                throughSequence: sequence,
                snapshot: replacement.snapshot
            ),
            estimatedBytes: bytes,
            firstRetainedAt: retainedAt
        )
        updateHighWater(state: &state, token: token)
    }

    private func evictTransferredHistoryToFit(
        additionalBytes: Int,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        guard state.activeReplayReaderIdentity == nil,
            canRetainFact(bytes: additionalBytes, state: state, token: token) == false,
            let detachedPrefix = state.history.detachTransferredPrefix()
        else { return }

        state.historyUnavailableThrough = Swift.max(
            state.historyUnavailableThrough,
            detachedPrefix.unavailableThrough
        )
        enqueueCleanupHistory(detachedPrefix.history, state: &state, token: token)
    }

    private func canRetainFact(
        bytes: Int,
        state: State,
        token _: borrowing AdmissionProtectedRegionToken
    ) -> Bool {
        state.physicalRetainedFactCount < maximumRetainedFacts
            && bytes <= maximumRetainedBytes
                - state.history.retainedByteCount
                - state.cleanupFactBytes
    }

    private func commitGap(
        missing: ClosedRange<UInt64>,
        at now: Duration,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) -> FactGap {
        let gapToken = nextGapToken(state: &state, token: token)
        let gap = FactGap(
            generation: generation,
            missingSequences: missing,
            token: gapToken
        )
        enqueueCleanupHistory(state.history.detachAll(), state: &state, token: token)
        state.productGap = ProductGapState(
            gap: gap,
            firstRetainedAt: now,
            needsTransfer: true
        )
        return gap
    }

    private func widenGap(
        _ existing: ProductGapState,
        through sequence: UInt64,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) -> FactGap {
        let gapToken = nextGapToken(state: &state, token: token)
        let gap = FactGap(
            generation: generation,
            missingSequences: existing.gap.missingSequences.lowerBound...sequence,
            token: gapToken
        )
        state.productGap = ProductGapState(
            gap: gap,
            firstRetainedAt: existing.firstRetainedAt,
            needsTransfer: true
        )
        return gap
    }

    private func nextGapToken(
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) -> FactGapToken {
        let token = FactGapToken(
            generation: generation,
            journalIdentity: state.journalIdentity,
            revision: state.nextGapRevision
        )
        if state.nextGapRevision == UInt64.max {
            state.journalIdentity = UUID()
            state.nextGapRevision = 1
        } else {
            state.nextGapRevision += 1
        }
        return token
    }

    private func allocateDrainToken(
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) -> AdmissionDrainToken {
        let token = AdmissionDrainToken(
            generation: generation,
            mailboxIdentity: mailboxIdentity,
            bindingEpoch: state.bindingEpoch,
            bindingSequence: state.bindingSequence,
            leaseEpoch: state.leaseEpoch,
            leaseSequence: state.nextLeaseSequence
        )
        if state.nextLeaseSequence == UInt64.max {
            state.leaseEpoch = AdmissionOpaqueIdentity()
            state.nextLeaseSequence = 1
        } else {
            state.nextLeaseSequence += 1
        }
        return token
    }

    private func requestWake(
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) -> AdmissionWakeDirective {
        guard state.drainLease == nil, state.wakePending == false else { return .noWake }
        state.wakePending = true
        return .scheduleDrain
    }

    private func requestWakeForRemainingWork(
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) -> AdmissionWakeDirective {
        guard hasTransferWork(state: state, token: token) || state.isCleanupEligible else {
            state.wakePending = false
            return .noWake
        }
        return requestWake(state: &state, token: token)
    }

    private func updateHighWater(
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) {
        let pendingCount =
            state.history.pendingFactCount
            + ((state.productGap?.needsTransfer == true) ? 1 : 0)
        state.pendingHighWater = Swift.max(state.pendingHighWater, pendingCount)
        state.retainedFactHighWater = Swift.max(
            state.retainedFactHighWater,
            state.history.retainedFactCount
        )
        state.retainedByteHighWater = Swift.max(
            state.retainedByteHighWater,
            state.history.retainedByteCount
        )
        state.cleanupFactHighWater = Swift.max(
            state.cleanupFactHighWater,
            state.cleanupFactCount
        )
        state.cleanupByteHighWater = Swift.max(
            state.cleanupByteHighWater,
            state.cleanupByteCount
        )
        state.cleanupSnapshotHighWater = Swift.max(
            state.cleanupSnapshotHighWater,
            state.cleanupSnapshotCount
        )
        state.cleanupSnapshotByteHighWater = Swift.max(
            state.cleanupSnapshotByteHighWater,
            state.cleanupSnapshotBytes
        )
        state.physicalRetainedFactHighWater = Swift.max(
            state.physicalRetainedFactHighWater,
            state.physicalRetainedFactCount
        )
        state.physicalRetainedByteHighWater = Swift.max(
            state.physicalRetainedByteHighWater,
            state.physicalRetainedByteCount
        )
        state.physicalRetainedSnapshotHighWater = Swift.max(
            state.physicalRetainedSnapshotHighWater,
            state.physicalRetainedSnapshotCount
        )
        state.physicalRetainedSnapshotByteHighWater = Swift.max(
            state.physicalRetainedSnapshotByteHighWater,
            state.physicalRetainedSnapshotByteCount
        )
    }

    private func hasTransferWork(
        state: State,
        token _: borrowing AdmissionProtectedRegionToken
    ) -> Bool {
        state.history.pendingFactCount > 0 || state.productGap?.needsTransfer == true
    }

    private func enqueueCleanupHistory(
        _ detachedHistory: OrderedFactDetachedHistory<Fact>?,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        guard let detachedHistory else { return }
        if let cleanupTail = state.cleanupFactTail {
            cleanupTail.next = detachedHistory.head
        } else {
            state.cleanupFactHead = detachedHistory.head
        }
        state.cleanupFactTail = detachedHistory.tail
        state.cleanupFactCount += detachedHistory.factCount
        state.cleanupFactBytes += detachedHistory.byteCount
        updateHighWater(state: &state, token: token)
    }

    private func enqueueCleanupSnapshot(
        _ retainedSnapshot: RetainedSnapshot?,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        guard let retainedSnapshot else { return }
        let cleanupNode = SnapshotCleanupNode(
            retainedSnapshot: retainedSnapshot,
            token: token
        )
        if let cleanupTail = state.cleanupSnapshotTail {
            cleanupTail.next = cleanupNode
        } else {
            state.cleanupSnapshotHead = cleanupNode
        }
        state.cleanupSnapshotTail = cleanupNode
        state.cleanupSnapshotCount += 1
        state.cleanupSnapshotBytes += retainedSnapshot.estimatedBytes
        updateHighWater(state: &state, token: token)
    }

    private func detachCleanup(
        requestedGeneration: AdmissionGeneration,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) -> CleanupDetachTransition {
        guard requestedGeneration == generation else {
            return emptyCleanupTransition(result: .staleGeneration)
        }
        guard state.inFlightCleanup == nil else {
            return emptyCleanupTransition(result: .alreadyCleaning)
        }
        guard state.activeReplayReaderIdentity == nil else {
            return emptyCleanupTransition(
                result: state.hasQueuedCleanupCustody ? .blockedByReplayReader : .empty
            )
        }
        guard state.hasQueuedCleanupCustody else {
            return emptyCleanupTransition(result: .empty)
        }
        guard let batch = detachCleanupBatch(state: &state, token: token) else {
            return emptyCleanupTransition(result: .empty)
        }
        let authority = AdmissionOpaqueIdentity()
        state.inFlightCleanup = InFlightCleanup(
            authority: authority,
            release: batch.release,
            oldestRetainedAt: batch.oldestRetainedAt
        )
        state.wakePending = false
        return CleanupDetachTransition(result: .empty, authority: authority, batch: batch)
    }

    private func emptyCleanupTransition(result: AdmissionCleanupTurnResult)
        -> CleanupDetachTransition
    {
        CleanupDetachTransition(result: result, authority: nil, batch: nil)
    }

    private func detachCleanupBatch(
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) -> CleanupBatch? {
        var releasedEntryCount = 0
        var releasedByteCount = 0
        let maximumBytes = cleanupQuantum.maximumBytes!
        var detachedFactHead: OrderedFactHistoryNode<Fact>?
        var detachedFactTail: OrderedFactHistoryNode<Fact>?
        var detachedFactCount = 0
        var detachedFactBytes = 0
        var detachedFactOldestAt: Duration?

        while releasedEntryCount < cleanupQuantum.maximumEntries,
            let cleanupHead = state.cleanupFactHead
        {
            let factBytes = cleanupHead.record.estimatedBytes
            guard releasedByteCount + factBytes <= maximumBytes else { break }
            state.cleanupFactHead = cleanupHead.next
            cleanupHead.next = nil
            if let detachedFactTail {
                detachedFactTail.next = cleanupHead
            } else {
                detachedFactHead = cleanupHead
                detachedFactOldestAt = cleanupHead.record.firstRetainedAt
            }
            detachedFactTail = cleanupHead
            detachedFactCount += 1
            detachedFactBytes += factBytes
            releasedEntryCount += 1
            releasedByteCount += factBytes
        }
        if state.cleanupFactHead == nil { state.cleanupFactTail = nil }

        var detachedSnapshots: [RetainedSnapshot] = []
        detachedSnapshots.reserveCapacity(cleanupQuantum.maximumEntries - releasedEntryCount)
        while releasedEntryCount < cleanupQuantum.maximumEntries,
            let cleanupHead = state.cleanupSnapshotHead
        {
            let snapshotBytes = cleanupHead.retainedSnapshot.estimatedBytes
            guard releasedByteCount + snapshotBytes <= maximumBytes else { break }
            state.cleanupSnapshotHead = cleanupHead.next
            cleanupHead.next = nil
            detachedSnapshots.append(cleanupHead.retainedSnapshot)
            releasedEntryCount += 1
            releasedByteCount += snapshotBytes
        }
        if state.cleanupSnapshotHead == nil { state.cleanupSnapshotTail = nil }
        guard releasedEntryCount > 0 else { return nil }

        let detachedFactHistory: OrderedFactDetachedHistory<Fact>?
        if let detachedFactHead, let detachedFactTail, let detachedFactOldestAt {
            detachedFactHistory = OrderedFactDetachedHistory(
                head: detachedFactHead,
                tail: detachedFactTail,
                factCount: detachedFactCount,
                byteCount: detachedFactBytes,
                oldestRetainedAt: detachedFactOldestAt
            )
        } else {
            detachedFactHistory = nil
        }
        return CleanupBatch(
            factHistory: detachedFactHistory,
            snapshots: detachedSnapshots,
            release: OrderedFactCleanupRelease(
                factCount: detachedFactCount,
                factBytes: detachedFactBytes,
                snapshotCount: detachedSnapshots.count,
                snapshotBytes: detachedSnapshots.reduce(0) { $0 + $1.estimatedBytes },
                entryCount: releasedEntryCount,
                byteCount: releasedByteCount
            ),
            oldestRetainedAt: minimumAdmissionTimestamp(
                detachedFactHistory?.oldestRetainedAt,
                detachedSnapshots.lazy.map(\.firstRetainedAt).min()
            )
        )
    }

    private func finalizeCleanup(
        authority: AdmissionOpaqueIdentity,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) -> AdmissionCleanupTurnResult {
        guard let inFlight = state.inFlightCleanup else {
            preconditionFailure("Journal cleanup authority disappeared before finalization")
        }
        guard inFlight.authority == authority else {
            preconditionFailure("Journal cleanup authority changed before finalization")
        }
        state.cleanupFactCount -= inFlight.release.factCount
        state.cleanupFactBytes -= inFlight.release.factBytes
        state.cleanupSnapshotCount -= inFlight.release.snapshotCount
        state.cleanupSnapshotBytes -= inFlight.release.snapshotBytes
        state.inFlightCleanup = nil
        let wake: AdmissionWakeDirective
        if state.isCleanupEligible {
            state.wakePending = true
            wake = .scheduleDrain
        } else {
            state.wakePending = false
            wake = .noWake
        }
        updateHighWater(state: &state, token: token)
        return .performed(
            AdmissionCleanupTurn(
                releasedEntryCount: inFlight.release.entryCount,
                releasedByteCount: inFlight.release.byteCount,
                wake: wake
            ))
    }

    private func makeDrain(
        from drainLease: DrainLease,
        now: Duration,
        token _: borrowing AdmissionProtectedRegionToken
    ) -> OrderedFactTakeDrainResult<Fact> {
        let content: (payload: OrderedFactDrainPayload<Fact>, firstRetainedAt: Duration?) =
            switch drainLease.payload {
            case .facts(let historyLease):
                (.facts(historyLease.sequencedFacts), historyLease.firstRetainedAt)
            case .gap(let gap, let firstRetainedAt):
                (.gap(gap), firstRetainedAt)
            }
        return makeOrderedFactDrainResult(
            token: drainLease.token,
            payload: content.payload,
            firstRetainedAt: content.firstRetainedAt,
            now: now
        )
    }

}

extension OrderedFactJournal {
    func replay(
        after sequence: UInt64,
        generation requestedGeneration: AdmissionGeneration,
        recovery: OrderedFactReplayRecovery
    ) -> OrderedFactReplayCompletion<Fact, Snapshot> {
        completeReplay(
            captureReplay(
                after: sequence,
                generation: requestedGeneration,
                recovery: recovery
            ))
    }

    func captureReplay(
        after sequence: UInt64,
        generation requestedGeneration: AdmissionGeneration,
        recovery: OrderedFactReplayRecovery
    ) -> OrderedFactReplayCapture<Fact, Snapshot> {
        withAdmissionProtectedState { state, _ in
            guard requestedGeneration == generation else {
                return OrderedFactReplayCapture<Fact, Snapshot>(
                    readerIdentity: nil,
                    content: .immediate(.staleGeneration)
                )
            }
            guard state.lifecycle != .invalidated else {
                return OrderedFactReplayCapture(
                    readerIdentity: nil,
                    content: .immediate(.invalidated)
                )
            }
            if let productGap = state.productGap {
                return OrderedFactReplayCapture(
                    readerIdentity: nil,
                    content: .immediate(.factGap(productGap.gap))
                )
            }
            guard sequence <= state.latestSequence else {
                return OrderedFactReplayCapture(
                    readerIdentity: nil,
                    content: .immediate(.invalidCursor(latestSequence: state.latestSequence))
                )
            }
            guard state.activeReplayReaderIdentity == nil else {
                return OrderedFactReplayCapture(
                    readerIdentity: nil,
                    content: .immediate(.replayInProgress)
                )
            }

            let readerIdentity = AdmissionOpaqueIdentity()
            state.activeReplayReaderIdentity = readerIdentity
            return OrderedFactReplayCapture(
                readerIdentity: readerIdentity,
                content: .history(
                    OrderedFactReplayHistoryCapture(
                        bounds: state.history.replayBounds,
                        afterSequence: sequence,
                        latestSequence: state.latestSequence,
                        historyUnavailableThrough: state.historyUnavailableThrough,
                        snapshot: state.retainedSnapshot?.sequencedSnapshot,
                        recovery: recovery
                    ))
            )
        }
    }

    func completeReplay(
        _ capture: OrderedFactReplayCapture<Fact, Snapshot>
    ) -> OrderedFactReplayCompletion<Fact, Snapshot> {
        let result = materializeOrderedFactReplay(capture, generation: generation)
        guard let readerIdentity = capture.readerIdentity else {
            return OrderedFactReplayCompletion(result: result, wake: .noWake)
        }
        let wake = withAdmissionProtectedState { state, token in
            guard state.activeReplayReaderIdentity == readerIdentity else {
                return AdmissionWakeDirective.noWake
            }
            state.activeReplayReaderIdentity = nil
            guard state.isCleanupEligible else { return .noWake }
            return requestWake(state: &state, token: token)
        }
        return OrderedFactReplayCompletion(result: result, wake: wake)
    }

    func currentState(
        generation requestedGeneration: AdmissionGeneration
    ) -> OrderedFactCurrentStateResult<Snapshot> {
        withAdmissionProtectedState { state, _ in
            guard requestedGeneration == generation else { return .staleGeneration }
            guard state.lifecycle != .invalidated else { return .invalidated }
            if let productGap = state.productGap {
                return .nonCurrent(productGap.gap)
            }
            return .current(
                snapshot: state.retainedSnapshot?.sequencedSnapshot,
                latestSequence: state.latestSequence,
                isSealed: state.lifecycle == .sealed
            )
        }
    }

    func resynchronize(
        generation requestedGeneration: AdmissionGeneration,
        gapToken: FactGapToken,
        throughSequence: UInt64,
        snapshot: Snapshot,
        estimatedSnapshotBytes: Int
    ) -> OrderedFactRecoveryResult {
        guard estimatedSnapshotBytes >= 0 else { return .invalidSize }
        let now = clock.now()
        return withAdmissionProtectedState { state, token in
            guard requestedGeneration == generation else { return .staleGeneration }
            guard state.lifecycle != .invalidated else { return .closed }
            guard let productGap = state.productGap else { return .notNonCurrent }
            guard productGap.gap.token == gapToken else { return .staleGapToken }
            guard throughSequence == productGap.gap.missingSequences.upperBound,
                throughSequence == state.latestSequence
            else { return .incorrectSequence }
            let bytes = estimatedSnapshotBytes
            guard bytes <= snapshotLimits.maximumSnapshotBytes else { return .snapshotTooLarge }
            guard
                orderedFactSnapshotCapacityAllows(
                    limits: snapshotLimits,
                    currentCount: state.physicalRetainedSnapshotCount,
                    currentBytes: state.physicalRetainedSnapshotByteCount,
                    additionalBytes: bytes
                )
            else {
                return .snapshotPhysicalCapacityExceeded
            }

            let previousSnapshot = state.retainedSnapshot
            state.retainedSnapshot = nil
            enqueueCleanupSnapshot(previousSnapshot, state: &state, token: token)
            state.retainedSnapshot = RetainedSnapshot(
                sequencedSnapshot: SequencedSnapshot(
                    generation: generation,
                    throughSequence: throughSequence,
                    snapshot: snapshot
                ),
                estimatedBytes: bytes,
                firstRetainedAt: now
            )
            state.historyUnavailableThrough = Swift.max(
                state.historyUnavailableThrough,
                productGap.gap.missingSequences.upperBound
            )
            state.productGap = nil
            state.drainLease = nil
            state.wakePending = state.isCleanupEligible
            updateHighWater(state: &state, token: token)
            return .recovered
        }
    }

    var diagnostics: OrderedFactJournalDiagnostics {
        let now = clock.now()
        return withAdmissionProtectedState { state, _ in
            let pendingCount =
                state.history.pendingFactCount
                + ((state.productGap?.needsTransfer == true) ? 1 : 0)
            let oldestRecord = state.history.oldestPendingRetainedAt
            let oldestGap =
                state.productGap?.needsTransfer == true
                ? state.productGap?.firstRetainedAt
                : nil
            let oldestCleanupAt = minimumAdmissionTimestamp(
                minimumAdmissionTimestamp(
                    state.cleanupFactHead?.record.firstRetainedAt,
                    state.cleanupSnapshotHead?.retainedSnapshot.firstRetainedAt
                ),
                state.inFlightCleanup?.oldestRetainedAt
            )
            let leasedFactCount: Int
            if case .facts(let historyLease) = state.drainLease?.payload {
                leasedFactCount = historyLease.factCount
            } else {
                leasedFactCount = 0
            }
            return OrderedFactJournalDiagnostics(
                admission: AdmissionDiagnostics(
                    offered: state.offered,
                    admitted: state.admitted,
                    contracted: state.contracted,
                    rejectedStale: state.rejectedStale,
                    rejectedUndeclared: 0,
                    rejectedInvalid: state.rejectedInvalid,
                    rejectedCapacity: state.rejectedCapacity,
                    rejectedClosed: state.rejectedClosed,
                    repairEscalations: state.repairEscalations,
                    pendingKeyCount: pendingCount,
                    pendingKeyHighWater: state.pendingHighWater,
                    oldestPendingAge: exactAdmissionAge(
                        from: minimumAdmissionTimestamp(oldestRecord, oldestGap),
                        to: now
                    )
                ),
                latestSequence: state.latestSequence,
                retainedFactCount: state.history.retainedFactCount,
                retainedFactHighWater: state.retainedFactHighWater,
                retainedByteCount: state.history.retainedByteCount,
                retainedByteHighWater: state.retainedByteHighWater,
                pendingFactCount: state.history.pendingFactCount,
                leasedFactCount: leasedFactCount,
                cleanupFactCount: state.cleanupFactCount,
                cleanupFactHighWater: state.cleanupFactHighWater,
                cleanupByteCount: state.cleanupByteCount,
                cleanupByteHighWater: state.cleanupByteHighWater,
                cleanupSnapshotCount: state.cleanupSnapshotCount,
                cleanupSnapshotHighWater: state.cleanupSnapshotHighWater,
                cleanupSnapshotByteCount: state.cleanupSnapshotBytes,
                cleanupSnapshotByteHighWater: state.cleanupSnapshotByteHighWater,
                physicalRetainedFactCount: state.physicalRetainedFactCount,
                physicalRetainedFactHighWater: state.physicalRetainedFactHighWater,
                physicalRetainedByteCount: state.physicalRetainedByteCount,
                physicalRetainedByteHighWater: state.physicalRetainedByteHighWater,
                physicalRetainedSnapshotCount: state.physicalRetainedSnapshotCount,
                physicalRetainedSnapshotHighWater: state.physicalRetainedSnapshotHighWater,
                physicalRetainedSnapshotByteCount: state.physicalRetainedSnapshotByteCount,
                physicalRetainedSnapshotByteHighWater: state.physicalRetainedSnapshotByteHighWater,
                oldestCleanupAge: exactAdmissionAge(from: oldestCleanupAt, to: now),
                activeReplayReaderCount: state.activeReplayReaderIdentity == nil ? 0 : 1,
                outstandingCleanupTurnCount: state.inFlightCleanup == nil ? 0 : 1,
                outstandingDrainCount: state.drainLease == nil ? 0 : 1,
                productGap: state.productGap?.gap,
                isCurrent: state.lifecycle != .invalidated && state.productGap == nil,
                isQuiescent: state.history.retainedFactCount == 0
                    && state.retainedSnapshot == nil
                    && state.productGap == nil
                    && state.drainLease == nil
                    && state.hasCleanupCustody == false
                    && state.activeReplayReaderIdentity == nil
            )
        }
    }

    var authoritySnapshot: OrderedFactJournalAuthoritySnapshot {
        withAdmissionProtectedState { state, _ in
            OrderedFactJournalAuthoritySnapshot(
                bindingEpoch: state.bindingEpoch,
                bindingSequence: state.bindingSequence,
                leaseEpoch: state.leaseEpoch,
                nextLeaseSequence: state.nextLeaseSequence,
                journalIdentity: state.journalIdentity,
                nextGapRevision: state.nextGapRevision
            )
        }
    }

    var operationSnapshot: OrderedFactJournalOperationSnapshot {
        withAdmissionProtectedState { state, _ in
            let historyOperations = state.history.operationSnapshot
            return OrderedFactJournalOperationSnapshot(
                offerNodeVisits: historyOperations.offerNodeVisits,
                takeNodeVisits: historyOperations.takeNodeVisits,
                acknowledgementNodeVisits: historyOperations.acknowledgementNodeVisits,
                evictionNodeVisits: historyOperations.evictionNodeVisits
            )
        }
    }
}
