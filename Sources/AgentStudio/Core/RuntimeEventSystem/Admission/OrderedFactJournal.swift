import Foundation
import os

// swiftlint:disable file_length

final class OrderedFactJournal<Fact: Sendable, Snapshot: Sendable>: @unchecked Sendable {
    private typealias ProductGapState = OrderedFactProductGapState
    private typealias LeasePayload = OrderedFactDrainLeasePayload<Fact>
    private typealias DrainLease = OrderedFactDrainLeaseState<Fact>
    private typealias OfferContext = OrderedFactOfferContext<Fact, Snapshot>
    private typealias ExistingGapOfferContext = OrderedFactExistingGapOfferContext

    private struct RetainedSnapshot: Sendable {
        let sequencedSnapshot: SequencedSnapshot<Snapshot>
        let estimatedBytes: Int, firstRetainedAt: Duration
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

    private typealias CleanupCustody = OrderedFactCleanupCustody<
        OrderedFactDetachedHistory<Fact>, RetainedSnapshot
    >

    private struct CleanupDetachment: Sendable {
        let custody: CleanupCustody
        let release: OrderedFactCleanupRelease, oldestRetainedAt: Duration
    }

    private struct InFlightCleanup: Sendable {
        let authority: AdmissionOpaqueIdentity
        let release: OrderedFactCleanupRelease, oldestRetainedAt: Duration
    }

    private enum CleanupDetachTransition: Sendable {
        case unavailable(AdmissionCleanupTurnResult)
        case detached(authority: AdmissionOpaqueIdentity, detachment: CleanupDetachment)
    }

    private enum CleanupReleaseTransition: Sendable {
        case unavailable(AdmissionCleanupTurnResult)
        case released(authority: AdmissionOpaqueIdentity)
    }

    private struct State: Sendable {
        var lifecycle = OrderedFactJournalLifecycle.open
        var latestSequence, historyUnavailableThrough: UInt64
        var history = OrderedFactHistory<Fact>()
        var retainedSnapshot: RetainedSnapshot?
        var productGap = ProductGapState.noGap
        var drainLease = DrainLease.noLease
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
    private let maximumRetainedFacts, maximumRetainedBytes: Int
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
        initialSnapshotReplacement: OrderedFactSnapshotReplacement<Snapshot>?,
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
            initialSnapshotReplacement: initialSnapshotReplacement
        )
        clock = admissionClock
        let initialRetainedAt = initialSnapshotReplacement == nil ? Duration.zero : clock.now()
        lock = OSAllocatedUnfairLock(
            initialState: Self.makeInitialState(
                generation: generation,
                initialSequence: initialSequence,
                initialSnapshotReplacement: initialSnapshotReplacement,
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

            switch state.drainLease {
            case .awaitingPresentation(_, let payload), .presented(_, let payload):
                state.drainLease = .awaitingPresentation(
                    allocateDrainToken(state: &state, token: token), payload
                )
                state.wakePending = true
            case .noLease:
                if hasTransferWork(state: state, token: token) || state.isCleanupEligible {
                    state.wakePending = true
                }
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
        let context = OfferContext(
            offeredGeneration: offeredGeneration,
            fact: fact,
            estimatedFactBytes: estimatedFactBytes,
            snapshotReplacement: snapshotReplacement,
            retainedAt: clock.now()
        )
        let transition = withAdmissionProtectedState { state, token in
            commitOffer(context, state: &state, token: token)
        }
        return releaseOrderedFactIncomingOffer(transition)
    }

    private func commitOffer(
        _ context: OfferContext,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) -> OrderedFactOfferTransition<Fact, Snapshot> {
        let preflight = classifyOrderedFactOffer(
            lifecycle: (context.offeredGeneration == generation, state.lifecycle == .open),
            estimatedFactBytes: context.estimatedFactBytes,
            estimatedSnapshotBytes: context.snapshotReplacement?.estimatedBytes,
            snapshotLimits: snapshotLimits,
            snapshotPressure: (
                state.physicalRetainedSnapshotCount,
                state.physicalRetainedSnapshotByteCount
            )
        )
        switch preflight {
        case .reject(let rejection):
            let result = applyOrderedFactOfferRejection(
                rejection,
                offered: &state.offered,
                rejectedStale: &state.rejectedStale,
                rejectedClosed: &state.rejectedClosed,
                rejectedInvalid: &state.rejectedInvalid,
                rejectedCapacity: &state.rejectedCapacity
            )
            return .released(result, context.incomingRelease)
        case .admit:
            incrementAdmissionCounter(&state.offered)
        }

        return commitAdmittedOffer(context, state: &state, token: token)
    }

    private func commitAdmittedOffer(
        _ context: OfferContext,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) -> OrderedFactOfferTransition<Fact, Snapshot> {

        let nextSequence = state.latestSequence.addingReportingOverflow(1)
        guard nextSequence.overflow == false else {
            state.lifecycle = .sealed
            incrementAdmissionCounter(&state.rejectedClosed)
            return .released(.authorityExhausted, context.incomingRelease)
        }

        let sequence = nextSequence.partialValue
        switch state.productGap {
        case .noGap:
            break
        case .pendingTransfer(let gap, let firstRetainedAt),
            .transferred(let gap, let firstRetainedAt):
            let result = commitOfferIntoExistingGap(
                ExistingGapOfferContext(gap: gap, firstRetainedAt: firstRetainedAt),
                sequence: sequence,
                offer: context,
                state: &state,
                token: token
            )
            return .released(result, .fact(context.fact))
        }

        evictTransferredHistoryToFit(
            additionalBytes: context.estimatedFactBytes,
            state: &state,
            token: token
        )
        guard canRetainFact(bytes: context.estimatedFactBytes, state: state, token: token) else {
            let lowerBound =
                state.history.firstPendingSequence
                ?? sequence
            let gap = commitGap(
                missing: lowerBound...sequence,
                at: context.retainedAt,
                state: &state,
                token: token
            )
            state.latestSequence = sequence
            applySnapshotReplacement(
                context.snapshotReplacement,
                through: sequence,
                retainedAt: context.retainedAt,
                state: &state,
                token: token
            )
            incrementAdmissionCounter(&state.admitted)
            incrementAdmissionCounter(&state.repairEscalations)
            incrementAdmissionCounter(&state.contracted)
            state.drainLease = .noLease
            let wake = requestWake(state: &state, token: token)
            updateHighWater(state: &state, token: token)
            return .released(.gapCommitted(gap, wake: wake), .fact(context.fact))
        }

        state.latestSequence = sequence
        state.history.append(
            SequencedFact(
                generation: generation,
                sequence: sequence,
                fact: context.fact
            ),
            estimatedBytes: context.estimatedFactBytes,
            firstRetainedAt: context.retainedAt
        )
        applySnapshotReplacement(
            context.snapshotReplacement,
            through: sequence,
            retainedAt: context.retainedAt,
            state: &state,
            token: token
        )
        incrementAdmissionCounter(&state.admitted)
        let wake = requestWake(state: &state, token: token)
        updateHighWater(state: &state, token: token)
        return .retained(.admitted(sequence: sequence, wake: wake))
    }

    private func commitOfferIntoExistingGap(
        _ gapContext: ExistingGapOfferContext,
        sequence: UInt64,
        offer: OfferContext,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) -> OrderedFactOfferResult {
        let gap = widenGap(
            gapContext.gap,
            firstRetainedAt: gapContext.firstRetainedAt,
            through: sequence,
            state: &state,
            token: token
        )
        state.latestSequence = sequence
        applySnapshotReplacement(
            offer.snapshotReplacement,
            through: sequence,
            retainedAt: offer.retainedAt,
            state: &state,
            token: token
        )
        incrementAdmissionCounter(&state.admitted)
        incrementAdmissionCounter(&state.contracted)
        incrementAdmissionCounter(&state.repairEscalations)
        state.drainLease = .noLease
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

            switch state.drainLease {
            case .awaitingPresentation(let drainToken, let payload):
                state.drainLease = .presented(drainToken, payload)
                state.wakePending = false
                return makeOrderedFactJournalDrain(token: drainToken, payload: payload, now: now)
            case .presented:
                return .alreadyDraining
            case .noLease:
                break
            }
            guard state.hasCleanupCustody == false else { return .cleanupRequired }

            if case .pendingTransfer(let gap, let firstRetainedAt) = state.productGap {
                let drainToken = allocateDrainToken(state: &state, token: token)
                let payload = LeasePayload.gap(gap, firstRetainedAt: firstRetainedAt)
                state.drainLease = .presented(drainToken, payload)
                state.wakePending = false
                return makeOrderedFactJournalDrain(token: drainToken, payload: payload, now: now)
            }

            guard let historyLease = state.history.takeLease(quantum: drainQuantum) else {
                state.wakePending = false
                return state.lifecycle == .sealed ? .closed : .empty
            }

            let drainToken = allocateDrainToken(state: &state, token: token)
            let payload = LeasePayload.facts(historyLease)
            state.drainLease = .presented(drainToken, payload)
            state.wakePending = false
            return makeOrderedFactJournalDrain(token: drainToken, payload: payload, now: now)
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
            guard case .presented(let leaseToken, let payload) = state.drainLease,
                leaseToken == drainToken
            else {
                return .invalidToken
            }

            switch (payload, disposition) {
            case (.facts(let historyLease), .transferred):
                guard state.history.acknowledgeTransferredLease(historyLease) else {
                    return .invalidToken
                }
            case (.gap(let gap, _), .transferred):
                if case .pendingTransfer(let currentGap, let firstRetainedAt) = state.productGap,
                    currentGap.token == gap.token
                {
                    state.productGap = .transferred(
                        currentGap, firstRetainedAt: firstRetainedAt
                    )
                }
            case (_, .retry):
                break
            }

            state.drainLease = .noLease
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
            state.productGap = .noGap
            state.drainLease = .noLease
            state.wakePending = state.isCleanupEligible
            updateHighWater(state: &state, token: token)
            return .applied
        }
    }

    func performCleanup(
        generation requestedGeneration: AdmissionGeneration
    ) -> AdmissionCleanupTurnResult {
        let transition = withAdmissionProtectedState { state, token in
            detachCleanup(
                requestedGeneration: requestedGeneration,
                state: &state,
                token: token
            )
        }
        let releaseTransition = releaseCleanup(consume transition)
        switch releaseTransition {
        case .unavailable(let result):
            return result
        case .released(let authority):
            return withAdmissionProtectedState { state, token in
                finalizeCleanup(authority: authority, state: &state, token: token)
            }
        }
    }

    private static func makeInitialState(
        generation: AdmissionGeneration,
        initialSequence: UInt64,
        initialSnapshotReplacement: OrderedFactSnapshotReplacement<Snapshot>?,
        initialRetainedAt: Duration,
        authoritySeeds: OrderedFactJournalAuthoritySeeds
    ) -> State {
        let retainedSnapshot = initialSnapshotReplacement.map {
            RetainedSnapshot(
                sequencedSnapshot: SequencedSnapshot(
                    generation: generation,
                    throughSequence: initialSequence,
                    snapshot: $0.snapshot
                ),
                estimatedBytes: $0.estimatedBytes,
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
        state.productGap = .pendingTransfer(gap, firstRetainedAt: now)
        return gap
    }
    private func widenGap(
        _ existingGap: FactGap,
        firstRetainedAt: Duration,
        through sequence: UInt64,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) -> FactGap {
        let gapToken = nextGapToken(state: &state, token: token)
        let gap = FactGap(
            generation: generation,
            missingSequences: existingGap.missingSequences.lowerBound...sequence,
            token: gapToken
        )
        state.productGap = .pendingTransfer(gap, firstRetainedAt: firstRetainedAt)
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
        guard case .noLease = state.drainLease, state.wakePending == false else { return .noWake }
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
        let pendingCount = state.history.pendingFactCount + pendingProductGapCount(state.productGap)
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
        state.history.pendingFactCount > 0 || pendingProductGapCount(state.productGap) > 0
    }
    private func pendingProductGapCount(_ productGap: ProductGapState) -> Int {
        if case .pendingTransfer = productGap { 1 } else { 0 }
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
            return .unavailable(.staleGeneration)
        }
        guard state.inFlightCleanup == nil else {
            return .unavailable(.alreadyCleaning)
        }
        guard state.activeReplayReaderIdentity == nil else {
            return .unavailable(state.hasQueuedCleanupCustody ? .blockedByReplayReader : .empty)
        }
        guard state.hasQueuedCleanupCustody else {
            return .unavailable(.empty)
        }
        let detachment = detachCleanupBatch(state: &state, token: token)
        let authority = AdmissionOpaqueIdentity()
        state.inFlightCleanup = InFlightCleanup(
            authority: authority,
            release: detachment.release,
            oldestRetainedAt: detachment.oldestRetainedAt
        )
        state.wakePending = false
        return .detached(authority: authority, detachment: detachment)
    }

    private func detachCleanupBatch(
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) -> CleanupDetachment {
        var releasedEntryCount = 0
        var releasedByteCount = 0
        let (maximumEntries, maximumBytes) = orderedFactCleanupLimits(cleanupQuantum)
        var detachedFactHead: OrderedFactHistoryNode<Fact>?
        var detachedFactTail: OrderedFactHistoryNode<Fact>?
        var detachedFactCount = 0
        var detachedFactBytes = 0
        var detachedFactOldestAt: Duration?

        while releasedEntryCount < maximumEntries,
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
        detachedSnapshots.reserveCapacity(maximumEntries - releasedEntryCount)
        while releasedEntryCount < maximumEntries,
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
        precondition(releasedEntryCount > 0, "Ordered fact cleanup quantum made no progress")

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
        let snapshotCustody = detachedSnapshots.first.map {
            NonEmptyAdmissionBatch(first: $0, remaining: Array(detachedSnapshots.dropFirst()))
        }
        let custody: CleanupCustody
        switch (detachedFactHistory, snapshotCustody) {
        case (.some(let facts), .none):
            custody = .facts(facts)
        case (.none, .some(let snapshots)):
            custody = .snapshots(snapshots)
        case (.some(let facts), .some(let snapshots)):
            custody = .factsAndSnapshots(facts, snapshots)
        case (.none, .none):
            preconditionFailure("Ordered fact cleanup detached empty custody")
        }
        let oldestRetainedAt =
            switch custody {
            case .facts(let facts): facts.oldestRetainedAt
            case .snapshots(let snapshots): snapshots.first.firstRetainedAt
            case .factsAndSnapshots(let facts, let snapshots):
                Swift.min(facts.oldestRetainedAt, snapshots.first.firstRetainedAt)
            }
        return CleanupDetachment(
            custody: custody,
            release: OrderedFactCleanupRelease(
                factCount: detachedFactCount,
                factBytes: detachedFactBytes,
                snapshotCount: detachedSnapshots.count,
                snapshotBytes: detachedSnapshots.reduce(0) { $0 + $1.estimatedBytes },
                entryCount: releasedEntryCount,
                byteCount: releasedByteCount
            ),
            oldestRetainedAt: oldestRetainedAt
        )
    }
    private func releaseCleanup(
        _ transition: consuming CleanupDetachTransition
    ) -> CleanupReleaseTransition {
        switch consume transition {
        case .unavailable(let result):
            return .unavailable(result)
        case .detached(let authority, let detachment):
            releaseOrderedFactCleanupCustody(detachment.custody)
            return .released(authority: authority)
        }
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
                release: .entriesAndBytes(
                    count: inFlight.release.entryCount,
                    bytes: inFlight.release.byteCount
                ),
                wake: wake
            ))
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
                return .immediate(.staleGeneration)
            }
            guard state.lifecycle != .invalidated else {
                return .immediate(.invalidated)
            }
            switch state.productGap {
            case .noGap:
                break
            case .pendingTransfer(let gap, _), .transferred(let gap, _):
                return .immediate(.factGap(gap))
            }
            guard sequence <= state.latestSequence else {
                return .immediate(.invalidCursor(latestSequence: state.latestSequence))
            }
            guard state.activeReplayReaderIdentity == nil else {
                return .immediate(.replayInProgress)
            }

            let readerIdentity = AdmissionOpaqueIdentity()
            state.activeReplayReaderIdentity = readerIdentity
            return .registered(
                readerIdentity: readerIdentity,
                history: OrderedFactReplayHistoryCapture(
                    bounds: state.history.replayBounds,
                    afterSequence: sequence,
                    latestSequence: state.latestSequence,
                    historyUnavailableThrough: state.historyUnavailableThrough,
                    snapshot: state.retainedSnapshot?.sequencedSnapshot,
                    recovery: recovery
                )
            )
        }
    }

    func completeReplay(
        _ capture: OrderedFactReplayCapture<Fact, Snapshot>
    ) -> OrderedFactReplayCompletion<Fact, Snapshot> {
        switch capture {
        case .immediate(let result):
            return .immediate(result)
        case .registered(let readerIdentity, let historyCapture):
            let result = materializeOrderedFactRegisteredReplay(
                historyCapture,
                generation: generation
            )
            let wake = withAdmissionProtectedState { state, token in
                guard state.activeReplayReaderIdentity == readerIdentity else {
                    return AdmissionWakeDirective.noWake
                }
                state.activeReplayReaderIdentity = nil
                guard state.isCleanupEligible else { return .noWake }
                return requestWake(state: &state, token: token)
            }
            return .registered(result, wake: wake)
        }
    }

    func currentState(
        generation requestedGeneration: AdmissionGeneration
    ) -> OrderedFactCurrentStateResult<Snapshot> {
        withAdmissionProtectedState { state, _ in
            guard requestedGeneration == generation else { return .staleGeneration }
            guard state.lifecycle != .invalidated else { return .invalidated }
            switch state.productGap {
            case .noGap:
                break
            case .pendingTransfer(let gap, _), .transferred(let gap, _):
                return .nonCurrent(gap)
            }
            let currentLifecycle: OrderedFactCurrentLifecycleState =
                switch state.lifecycle {
                case .open: .open
                case .sealed: .sealed
                case .invalidated: preconditionFailure("Invalidated journal passed current-state guard")
                }
            return .current(
                snapshot: state.retainedSnapshot?.sequencedSnapshot,
                latestSequence: state.latestSequence,
                lifecycle: currentLifecycle
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
            let productGap: FactGap
            switch state.productGap {
            case .noGap:
                return .notNonCurrent
            case .pendingTransfer(let gap, _), .transferred(let gap, _):
                productGap = gap
            }
            guard productGap.token == gapToken else { return .staleGapToken }
            guard throughSequence == productGap.missingSequences.upperBound,
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
                productGap.missingSequences.upperBound
            )
            state.productGap = .noGap
            state.drainLease = .noLease
            state.wakePending = state.isCleanupEligible
            updateHighWater(state: &state, token: token)
            return .recovered
        }
    }

    var diagnostics: OrderedFactJournalDiagnostics {
        let now = clock.now()
        return withAdmissionProtectedState { state, _ in
            let pendingCount =
                state.history.pendingFactCount + pendingProductGapCount(state.productGap)
            let oldestRecord = state.history.oldestPendingRetainedAt
            let oldestGap: Duration? =
                switch state.productGap {
                case .pendingTransfer(_, let firstRetainedAt): firstRetainedAt
                case .noGap, .transferred: nil
                }
            let oldestCleanupAt = minimumAdmissionTimestamp(
                minimumAdmissionTimestamp(
                    state.cleanupFactHead?.record.firstRetainedAt,
                    state.cleanupSnapshotHead?.retainedSnapshot.firstRetainedAt
                ),
                state.inFlightCleanup?.oldestRetainedAt
            )
            let leasedFactCount: Int
            switch state.drainLease {
            case .presented(_, .facts(let historyLease)),
                .awaitingPresentation(_, .facts(let historyLease)):
                leasedFactCount = historyLease.factCount
            case .noLease, .presented(_, .gap), .awaitingPresentation(_, .gap):
                leasedFactCount = 0
            }
            let currentness = orderedFactDiagnosticCurrentness(state.lifecycle, state.productGap)
            let hasNoProductGap: Bool = if case .noGap = state.productGap { true } else { false }
            let hasNoDrainLease: Bool = if case .noLease = state.drainLease { true } else { false }
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
                outstandingDrainCount: hasNoDrainLease ? 0 : 1,
                currentness: currentness,
                isQuiescent: state.history.retainedFactCount == 0
                    && state.retainedSnapshot == nil
                    && hasNoProductGap
                    && hasNoDrainLease
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
