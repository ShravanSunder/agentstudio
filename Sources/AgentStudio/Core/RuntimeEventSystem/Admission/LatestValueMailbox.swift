import Foundation
import os

// The admission contract requires raw lock, state, cleanup cursors, and token-bearing
// helpers to remain in one lexical owner through the S1h helper-graph cut.
// swiftlint:disable file_length

struct LatestValueLimits: Sendable, Equatable {
    let maximumValuesPerLease: Int
    let maximumAuxiliaryRetainedValues: Int
    let cleanupQuantum: AdmissionCleanupQuantum
}

struct LatestValueOfferResult: Sendable, Equatable {
    let receipt: AdmissionReceipt
    let wake: AdmissionWakeDirective
}

struct LatestValueDrain<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    let token: AdmissionDrainToken
    let valuesByKey: [Key: Value]
    let oldestRetainedAge: AdmissionAgeMeasurement?
}

enum LatestValueDrainResult<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    case drain(LatestValueDrain<Key, Value>)
    case cleanupRequired
    case empty
    case alreadyDraining
    case staleGeneration
    case closed
}

struct LatestValueAuthoritySnapshot: Sendable, Equatable {
    let bindingEpoch: AdmissionOpaqueIdentity
    let bindingSequence: UInt64
    let leaseEpoch: AdmissionOpaqueIdentity
    let leaseSequence: UInt64
    let bindingEpochRotationCount: UInt64
    let leaseEpochRotationCount: UInt64
}

struct LatestValueProducerPort<Key, Value>: Sendable
where Key: Hashable & Sendable, Value: Sendable {
    private let mailbox: LatestValueMailbox<Key, Value>

    fileprivate init(mailbox: LatestValueMailbox<Key, Value>) {
        self.mailbox = mailbox
    }

    func offer(
        generation: AdmissionGeneration,
        key: Key,
        value: Value
    ) -> LatestValueOfferResult {
        mailbox.offer(generation: generation, key: key, value: value)
    }
}

struct LatestValueConsumerPort<Key, Value>:
    AdmissionConsumerBindingSource, AdmissionCleanupConsumer
where Key: Hashable & Sendable, Value: Sendable {
    private let mailbox: LatestValueMailbox<Key, Value>

    fileprivate init(mailbox: LatestValueMailbox<Key, Value>) {
        self.mailbox = mailbox
    }

    func bindConsumer() -> AdmissionConsumerBindResult {
        mailbox.bindConsumer()
    }

    func takeDrain(
        binding: AdmissionConsumerBinding,
        generation: AdmissionGeneration
    ) -> LatestValueDrainResult<Key, Value> {
        mailbox.takeDrain(binding: binding, generation: generation)
    }

    func acknowledge(
        _ token: AdmissionDrainToken,
        disposition: AdmissionDrainDisposition
    ) -> AdmissionDrainAcknowledgement {
        mailbox.acknowledge(token, disposition: disposition)
    }

    func performCleanup(
        generation: AdmissionGeneration
    ) -> AdmissionCleanupTurnResult {
        mailbox.performCleanup(generation: generation)
    }
}

struct LatestValueLifecyclePort<Key, Value>: AdmissionCleanupConsumer
where Key: Hashable & Sendable, Value: Sendable {
    private let mailbox: LatestValueMailbox<Key, Value>

    fileprivate init(mailbox: LatestValueMailbox<Key, Value>) {
        self.mailbox = mailbox
    }

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

    var diagnostics: LatestValueAdmissionDiagnostics {
        mailbox.diagnostics
    }

    var authoritySnapshot: LatestValueAuthoritySnapshot {
        mailbox.authoritySnapshot
    }
}

final class LatestValueMailbox<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {
    private enum Lifecycle: Sendable {
        case open
        case sealed
        case invalidated
    }

    private struct RetainedValue: Sendable {
        let value: Value
        let firstRetainedAt: Duration
    }

    private struct ActiveDrain: Sendable {
        let token: AdmissionDrainToken
        let retainedValuesBySlot: [Int: RetainedValue]
        let retentionOrderSlots: [Int]
    }

    private enum ActiveDrainPresentationState: Sendable {
        case presented
        case awaitingInitialPresentation
        case awaitingRebindPresentation
    }

    private final class PendingSlotOrder: @unchecked Sendable {
        private var previousSlotBySlot: [Int]
        private var nextSlotBySlot: [Int]
        private var isPresentBySlot: [Bool]
        private(set) var firstSlot: Int?
        private(set) var lastSlot: Int?
        private(set) var count = 0

        init(slotCount: Int) {
            previousSlotBySlot = Array(repeating: -1, count: slotCount)
            nextSlotBySlot = Array(repeating: -1, count: slotCount)
            isPresentBySlot = Array(repeating: false, count: slotCount)
        }

        func append(
            _ slot: Int,
            token _: borrowing AdmissionProtectedRegionToken
        ) {
            precondition(isPresentBySlot[slot] == false)
            isPresentBySlot[slot] = true
            previousSlotBySlot[slot] = lastSlot ?? -1
            nextSlotBySlot[slot] = -1
            if let lastSlot {
                nextSlotBySlot[lastSlot] = slot
            } else {
                firstSlot = slot
            }
            lastSlot = slot
            count += 1
        }

        func prepend(
            contentsInOrder slots: [Int],
            token _: borrowing AdmissionProtectedRegionToken
        ) {
            for slot in slots.reversed() {
                precondition(isPresentBySlot[slot] == false)
                isPresentBySlot[slot] = true
                previousSlotBySlot[slot] = -1
                nextSlotBySlot[slot] = firstSlot ?? -1
                if let firstSlot {
                    previousSlotBySlot[firstSlot] = slot
                } else {
                    lastSlot = slot
                }
                firstSlot = slot
                count += 1
            }
        }

        func removeFirst(
            token _: borrowing AdmissionProtectedRegionToken
        ) -> Int? {
            guard let removedSlot = firstSlot else { return nil }
            let nextSlot = nextSlotBySlot[removedSlot]
            firstSlot = nextSlot >= 0 ? nextSlot : nil
            if let firstSlot {
                previousSlotBySlot[firstSlot] = -1
            } else {
                lastSlot = nil
            }
            previousSlotBySlot[removedSlot] = -1
            nextSlotBySlot[removedSlot] = -1
            isPresentBySlot[removedSlot] = false
            count -= 1
            return removedSlot
        }

        func first(
            token _: borrowing AdmissionProtectedRegionToken
        ) -> Int? {
            firstSlot
        }

        func isEmpty(
            token: borrowing AdmissionProtectedRegionToken
        ) -> Bool {
            first(token: token) == nil
        }
    }

    private enum CleanupSlotOrder: @unchecked Sendable {
        case bounded(slots: [Int], nextIndex: Int)
        case terminal(PendingSlotOrder)

        func first(
            token: borrowing AdmissionProtectedRegionToken
        ) -> Int? {
            switch self {
            case .bounded(let slots, let nextIndex):
                guard nextIndex < slots.count else { return nil }
                return slots[nextIndex]
            case .terminal(let order):
                return order.first(token: token)
            }
        }

        func isEmpty(
            token: borrowing AdmissionProtectedRegionToken
        ) -> Bool {
            first(token: token) == nil
        }

        mutating func removeFirst(
            token: borrowing AdmissionProtectedRegionToken
        ) -> Int? {
            switch self {
            case .bounded(let slots, let nextIndex):
                guard nextIndex < slots.count else { return nil }
                self = .bounded(slots: slots, nextIndex: nextIndex + 1)
                return slots[nextIndex]
            case .terminal(let order):
                return order.removeFirst(token: token)
            }
        }

        mutating func takeReusableTerminalOrder(
            token: borrowing AdmissionProtectedRegionToken
        ) -> PendingSlotOrder? {
            guard case .terminal(let order) = self, order.isEmpty(token: token) else {
                return nil
            }
            self = .bounded(slots: [], nextIndex: 0)
            return order
        }
    }

    private final class CleanupBatch: @unchecked Sendable {
        var retainedValuesBySlot: [Int: RetainedValue]
        var slotOrder: CleanupSlotOrder
        var next: CleanupBatch?
        let initialOldestRetainedTimestamp: Duration

        init(
            retainedValuesBySlot: [Int: RetainedValue],
            retentionOrderSlots: [Int],
            maximumValuesPerLease: Int,
            token _: borrowing AdmissionProtectedRegionToken
        ) {
            precondition(retentionOrderSlots.count <= maximumValuesPerLease)
            self.retainedValuesBySlot = retainedValuesBySlot
            slotOrder = .bounded(slots: retentionOrderSlots, nextIndex: 0)
            var initialOldestRetainedTimestamp: Duration?
            var visitedCount = 0
            for slot in retentionOrderSlots {
                precondition(visitedCount < maximumValuesPerLease)
                visitedCount += 1
                guard let retainedAt = retainedValuesBySlot[slot]?.firstRetainedAt else {
                    preconditionFailure("Latest cleanup order referenced an empty slot")
                }
                initialOldestRetainedTimestamp =
                    initialOldestRetainedTimestamp.map {
                        min($0, retainedAt)
                    } ?? retainedAt
            }
            guard let initialOldestRetainedTimestamp else {
                preconditionFailure("Latest cleanup batch cannot be empty")
            }
            self.initialOldestRetainedTimestamp = initialOldestRetainedTimestamp
        }

        init(
            retainedValuesBySlot: [Int: RetainedValue],
            terminalSlotOrder: PendingSlotOrder,
            token: borrowing AdmissionProtectedRegionToken
        ) {
            self.retainedValuesBySlot = retainedValuesBySlot
            slotOrder = .terminal(terminalSlotOrder)
            guard
                let initialOldestRetainedTimestamp = terminalSlotOrder.first(token: token).flatMap({
                    retainedValuesBySlot[$0]?.firstRetainedAt
                })
            else {
                preconditionFailure("Latest terminal cleanup batch cannot be empty")
            }
            self.initialOldestRetainedTimestamp = initialOldestRetainedTimestamp
        }
    }

    private enum CleanupAgePrecision: Sendable {
        case exact
        case pressureConservative
    }

    private struct CleanupAgeWatermark: Sendable {
        let retainedAt: Duration
        let precision: CleanupAgePrecision
    }

    private struct OfferTransition: Sendable {
        let result: LatestValueOfferResult
        let releasedValue: RetainedValue?
    }

    private struct CleanupDetachTransition: Sendable {
        let result: AdmissionCleanupTurnResult
        let authority: AdmissionOpaqueIdentity?
        var detachedValues: [RetainedValue]
        var retiredBatches: [CleanupBatch]
    }

    private struct InFlightCleanup: Sendable {
        let authority: AdmissionOpaqueIdentity
        let retainedValueCount: Int
        let oldestRetainedTimestamp: Duration?
    }

    private enum LockedTakeDrainResult: Sendable {
        case drain(ActiveDrain)
        case result(LatestValueDrainResult<Key, Value>)
    }

    private struct State: Sendable {
        let generation: AdmissionGeneration
        let mailboxIdentity: AdmissionOpaqueIdentity

        var lifecycle = Lifecycle.open
        var pendingValuesBySlot: [Int: RetainedValue] = [:]
        var pendingSlotOrder: PendingSlotOrder
        var reusableTerminalSlotOrder: PendingSlotOrder?
        var activeDrain: ActiveDrain?
        var cleanupHead: CleanupBatch?
        var cleanupTail: CleanupBatch?
        var inFlightCleanup: InFlightCleanup?
        var activeDrainPresentationState = ActiveDrainPresentationState.presented
        var wakePending = false
        var bindingEpoch = AdmissionOpaqueIdentity()
        var currentBindingSequence: UInt64
        var leaseEpoch = AdmissionOpaqueIdentity()
        var latestLeaseSequence: UInt64
        var bindingEpochRotationCount: UInt64 = 0
        var leaseEpochRotationCount: UInt64 = 0

        var offered: UInt64 = 0
        var admitted: UInt64 = 0
        var contracted: UInt64 = 0
        var rejectedStale: UInt64 = 0
        var rejectedUndeclared: UInt64 = 0
        var rejectedInvalid: UInt64 = 0
        var rejectedCapacity: UInt64 = 0
        var rejectedClosed: UInt64 = 0
        var pendingKeyCount = 0
        var pendingKeyHighWater = 0
        var semanticRetainedValueHighWater = 0
        var cleanupValueCount = 0
        var cleanupValueHighWater = 0
        var oldestCleanupWatermark: CleanupAgeWatermark?
        var physicalRetainedValueHighWater = 0

        init(
            generation: AdmissionGeneration,
            mailboxIdentity: AdmissionOpaqueIdentity,
            initialBindingSequence: UInt64,
            initialLeaseSequence: UInt64,
            declaredSlotCount: Int
        ) {
            self.generation = generation
            self.mailboxIdentity = mailboxIdentity
            currentBindingSequence = initialBindingSequence
            latestLeaseSequence = initialLeaseSequence
            pendingSlotOrder = PendingSlotOrder(slotCount: declaredSlotCount)
            reusableTerminalSlotOrder = PendingSlotOrder(slotCount: declaredSlotCount)
        }
    }

    private let declaredKeysBySlot: [Key]
    private let declaredSlotByKey: [Key: Int]
    private let limits: LatestValueLimits
    private let clock: AdmissionClock
    private let lock: OSAllocatedUnfairLock<State>

    var producerPort: LatestValueProducerPort<Key, Value> {
        LatestValueProducerPort(mailbox: self)
    }

    var consumerPort: LatestValueConsumerPort<Key, Value> {
        LatestValueConsumerPort(mailbox: self)
    }

    var lifecyclePort: LatestValueLifecyclePort<Key, Value> {
        LatestValueLifecyclePort(mailbox: self)
    }

    convenience init(
        generation: AdmissionGeneration,
        declaredKeys: Set<Key>,
        limits: LatestValueLimits
    ) {
        self.init(
            generation: generation,
            declaredKeys: declaredKeys,
            limits: limits,
            admissionClock: .continuous(),
            initialBindingSequence: 0,
            initialLeaseSequence: 0
        )
    }

    convenience init(
        generation: AdmissionGeneration,
        declaredKeys: Set<Key>,
        limits: LatestValueLimits,
        initialBindingSequence: UInt64,
        initialLeaseSequence: UInt64
    ) {
        self.init(
            generation: generation,
            declaredKeys: declaredKeys,
            limits: limits,
            admissionClock: .continuous(),
            initialBindingSequence: initialBindingSequence,
            initialLeaseSequence: initialLeaseSequence
        )
    }

    convenience init<C: Clock & Sendable>(
        generation: AdmissionGeneration,
        declaredKeys: Set<Key>,
        limits: LatestValueLimits,
        clock: C
    ) where C.Duration == Duration {
        self.init(
            generation: generation,
            declaredKeys: declaredKeys,
            limits: limits,
            admissionClock: .make(clock: clock),
            initialBindingSequence: 0,
            initialLeaseSequence: 0
        )
    }

    private init(
        generation: AdmissionGeneration,
        declaredKeys: Set<Key>,
        limits: LatestValueLimits,
        admissionClock: AdmissionClock,
        initialBindingSequence: UInt64,
        initialLeaseSequence: UInt64
    ) {
        precondition(
            Self.isConfigurationValid(
                declaredKeyCount: declaredKeys.count,
                limits: limits
            ),
            "Latest-value cleanup requires a positive entry quantum and no byte quantum"
        )
        let declaredKeysBySlot = Array(declaredKeys)
        self.declaredKeysBySlot = declaredKeysBySlot
        declaredSlotByKey = Dictionary(
            uniqueKeysWithValues: declaredKeysBySlot.enumerated().map { slot, key in
                (key, slot)
            }
        )
        self.limits = limits
        clock = admissionClock
        lock = OSAllocatedUnfairLock(
            initialState: State(
                generation: generation,
                mailboxIdentity: AdmissionOpaqueIdentity(),
                initialBindingSequence: initialBindingSequence,
                initialLeaseSequence: initialLeaseSequence,
                declaredSlotCount: declaredKeysBySlot.count
            )
        )
    }

    static func isConfigurationValid(
        declaredKeyCount: Int,
        limits: LatestValueLimits
    ) -> Bool {
        let doubledDeliveryLimit = limits.maximumValuesPerLease.multipliedReportingOverflow(by: 2)
        let physicalCapacity = declaredKeyCount.addingReportingOverflow(
            limits.maximumAuxiliaryRetainedValues
        )
        return declaredKeyCount >= 0
            && limits.maximumValuesPerLease > 0
            && doubledDeliveryLimit.overflow == false
            && limits.maximumAuxiliaryRetainedValues >= doubledDeliveryLimit.partialValue
            && physicalCapacity.overflow == false
            && limits.cleanupQuantum.isValid
            && limits.cleanupQuantum.maximumBytes == nil
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

    fileprivate func bindConsumer() -> AdmissionConsumerBindResult {
        withAdmissionProtectedState { state, _ in
            let nextBindingSequence = state.currentBindingSequence.addingReportingOverflow(1)
            if nextBindingSequence.overflow {
                state.bindingEpoch = AdmissionOpaqueIdentity()
                state.currentBindingSequence = 1
                incrementAdmissionCounter(&state.bindingEpochRotationCount)
            } else {
                state.currentBindingSequence = nextBindingSequence.partialValue
            }

            let wake: AdmissionWakeDirective
            if state.activeDrain != nil {
                state.activeDrainPresentationState = .awaitingRebindPresentation
                state.wakePending = true
                wake = .scheduleDrain
            } else if state.pendingValuesBySlot.isEmpty == false || state.cleanupValueCount > 0 {
                state.wakePending = true
                wake = .scheduleDrain
            } else {
                wake = .noWake
            }
            return AdmissionConsumerBindResult(
                binding: AdmissionConsumerBinding(
                    mailboxIdentity: state.mailboxIdentity,
                    bindingEpoch: state.bindingEpoch,
                    bindingSequence: state.currentBindingSequence
                ),
                wake: wake
            )
        }
    }

    fileprivate func offer(
        generation: AdmissionGeneration,
        key: Key,
        value: Value
    ) -> LatestValueOfferResult {
        let now = clock.now()
        let declaredSlot = declaredSlotByKey[key]
        let incomingValue = RetainedValue(value: value, firstRetainedAt: now)
        let transition = withAdmissionProtectedState { state, token in
            incrementAdmissionCounter(&state.offered)

            guard generation == state.generation else {
                incrementAdmissionCounter(&state.rejectedStale)
                return OfferTransition(
                    result: LatestValueOfferResult(receipt: .staleGeneration, wake: .noWake),
                    releasedValue: incomingValue
                )
            }
            guard state.lifecycle == .open else {
                incrementAdmissionCounter(&state.rejectedClosed)
                return OfferTransition(
                    result: LatestValueOfferResult(receipt: .closed, wake: .noWake),
                    releasedValue: incomingValue
                )
            }
            guard let declaredSlot else {
                incrementAdmissionCounter(&state.rejectedUndeclared)
                return OfferTransition(
                    result: LatestValueOfferResult(receipt: .undeclaredKey, wake: .noWake),
                    releasedValue: incomingValue
                )
            }

            let receipt: AdmissionReceipt
            if let retainedValue = state.pendingValuesBySlot[declaredSlot] {
                let leasedValueCount = state.activeDrain?.retainedValuesBySlot.count ?? 0
                let auxiliaryCount = leasedValueCount.addingReportingOverflow(
                    state.cleanupValueCount
                )
                guard
                    auxiliaryCount.overflow == false,
                    auxiliaryCount.partialValue < limits.maximumAuxiliaryRetainedValues
                else {
                    incrementAdmissionCounter(&state.rejectedCapacity)
                    return OfferTransition(
                        result: LatestValueOfferResult(
                            receipt: .physicalCapacityExceeded,
                            wake: .noWake
                        ),
                        releasedValue: incomingValue
                    )
                }

                state.pendingValuesBySlot[declaredSlot] = RetainedValue(
                    value: value,
                    firstRetainedAt: retainedValue.firstRetainedAt
                )
                Self.appendCleanupBatch(
                    retainedValuesBySlot: [declaredSlot: retainedValue],
                    retentionOrderSlots: [declaredSlot],
                    maximumValuesPerLease: limits.maximumValuesPerLease,
                    state: &state,
                    token: token
                )
                incrementAdmissionCounter(&state.contracted)
                receipt = .replacedPrevious
            } else {
                state.pendingValuesBySlot[declaredSlot] = incomingValue
                state.pendingSlotOrder.append(declaredSlot, token: token)
                if state.activeDrain?.retainedValuesBySlot[declaredSlot] == nil {
                    state.pendingKeyCount += 1
                    state.pendingKeyHighWater = max(
                        state.pendingKeyHighWater,
                        state.pendingKeyCount
                    )
                }
                receipt = .admitted
            }
            incrementAdmissionCounter(&state.admitted)

            Self.refreshRetainedHighWaters(state: &state, token: token)

            return OfferTransition(
                result: LatestValueOfferResult(
                    receipt: receipt,
                    wake: Self.scheduleWakeForAcceptedOffer(
                        state: &state,
                        token: token
                    )
                ),
                releasedValue: nil
            )
        }

        withExtendedLifetime(transition.releasedValue) {}
        return transition.result
    }

    fileprivate func takeDrain(
        binding: AdmissionConsumerBinding,
        generation: AdmissionGeneration
    ) -> LatestValueDrainResult<Key, Value> {
        let now = clock.now()
        let lockedResult = withAdmissionProtectedState { state, token in
            Self.takeDrain(
                state: &state,
                token: token,
                binding: binding,
                generation: generation,
                maximumValuesPerLease: limits.maximumValuesPerLease
            )
        }

        switch lockedResult {
        case .drain(let activeDrain):
            return makeDrain(activeDrain: activeDrain, now: now)
        case .result(let result):
            return result
        }
    }

    fileprivate func acknowledge(
        _ token: AdmissionDrainToken,
        disposition: AdmissionDrainDisposition
    ) -> AdmissionDrainAcknowledgement {
        let result = withAdmissionProtectedState { state, protectedToken in
            guard state.lifecycle != .invalidated else {
                return AdmissionDrainAcknowledgement.closed
            }
            guard token.generation == state.generation else {
                return AdmissionDrainAcknowledgement.staleGeneration
            }
            guard
                token.belongsTo(
                    mailboxIdentity: state.mailboxIdentity,
                    bindingEpoch: state.bindingEpoch,
                    bindingSequence: state.currentBindingSequence
                )
            else {
                return AdmissionDrainAcknowledgement.invalidToken
            }
            guard let activeDrain = state.activeDrain, activeDrain.token == token else {
                return AdmissionDrainAcknowledgement.invalidToken
            }
            state.activeDrain = nil
            state.activeDrainPresentationState = .presented

            switch disposition {
            case .transferred:
                for slot in activeDrain.retentionOrderSlots
                where state.pendingValuesBySlot[slot] == nil {
                    state.pendingKeyCount -= 1
                }
                Self.appendCleanupBatch(
                    retainedValuesBySlot: activeDrain.retainedValuesBySlot,
                    retentionOrderSlots: activeDrain.retentionOrderSlots,
                    maximumValuesPerLease: limits.maximumValuesPerLease,
                    state: &state,
                    token: protectedToken
                )

            case .retry:
                var displacedValuesBySlot: [Int: RetainedValue] = [:]
                var displacedRetentionOrderSlots: [Int] = []
                var retriedRetentionOrderSlots: [Int] = []
                displacedValuesBySlot.reserveCapacity(activeDrain.retainedValuesBySlot.count)
                displacedRetentionOrderSlots.reserveCapacity(activeDrain.retentionOrderSlots.count)
                retriedRetentionOrderSlots.reserveCapacity(activeDrain.retentionOrderSlots.count)
                for slot in activeDrain.retentionOrderSlots {
                    guard let leasedValue = activeDrain.retainedValuesBySlot[slot] else { continue }
                    if state.pendingValuesBySlot[slot] != nil {
                        incrementAdmissionCounter(&state.contracted)
                        displacedValuesBySlot[slot] = leasedValue
                        displacedRetentionOrderSlots.append(slot)
                    } else {
                        state.pendingValuesBySlot[slot] = leasedValue
                        retriedRetentionOrderSlots.append(slot)
                    }
                }
                state.pendingSlotOrder.prepend(
                    contentsInOrder: retriedRetentionOrderSlots,
                    token: protectedToken
                )
                Self.appendCleanupBatch(
                    retainedValuesBySlot: displacedValuesBySlot,
                    retentionOrderSlots: displacedRetentionOrderSlots,
                    maximumValuesPerLease: limits.maximumValuesPerLease,
                    state: &state,
                    token: protectedToken
                )
            }

            state.activeDrainPresentationState = .presented
            Self.refreshRetainedHighWaters(state: &state, token: protectedToken)
            return .accepted(
                wake: Self.scheduleWakeAfterAcknowledgement(
                    state: &state,
                    token: protectedToken
                )
            )
        }

        return result
    }

    fileprivate func seal(generation: AdmissionGeneration) -> AdmissionControlResult {
        withAdmissionProtectedState { state, _ in
            guard generation == state.generation else { return .staleGeneration }
            guard state.lifecycle == .open else { return .alreadyClosed }
            state.lifecycle = .sealed
            return .applied
        }
    }

    fileprivate func invalidate(generation: AdmissionGeneration) -> AdmissionControlResult {
        withAdmissionProtectedState { state, token in
            guard generation == state.generation else {
                return .staleGeneration
            }
            guard state.lifecycle != .invalidated else {
                return .alreadyClosed
            }
            Self.invalidateState(
                state: &state,
                token: token,
                maximumValuesPerLease: limits.maximumValuesPerLease
            )
            return .applied
        }
    }

    fileprivate func performCleanup(
        generation: AdmissionGeneration
    ) -> AdmissionCleanupTurnResult {
        var transition = withAdmissionProtectedState { state, token in
            Self.detachCleanup(
                state: &state,
                token: token,
                generation: generation,
                cleanupQuantum: limits.cleanupQuantum
            )
        }

        guard let authority = transition.authority else { return transition.result }
        transition.detachedValues.removeAll(keepingCapacity: false)
        transition.retiredBatches.removeAll(keepingCapacity: false)
        return withAdmissionProtectedState { state, token in
            Self.finalizeCleanup(
                state: &state,
                token: token,
                authority: authority,
                maximumValuesPerLease: limits.maximumValuesPerLease,
                maximumAuxiliaryRetainedValues: limits.maximumAuxiliaryRetainedValues
            )
        }
    }

    fileprivate var diagnostics: LatestValueAdmissionDiagnostics {
        let now = clock.now()
        return withAdmissionProtectedState { state, token in
            let pendingValueCount = state.pendingValuesBySlot.count
            let leasedValueCount = state.activeDrain?.retainedValuesBySlot.count ?? 0
            let semanticRetainedValueCount = pendingValueCount + leasedValueCount
            let physicalRetainedValueCount = semanticRetainedValueCount + state.cleanupValueCount
            return LatestValueAdmissionDiagnostics(
                admission: AdmissionDiagnostics(
                    offered: state.offered,
                    admitted: state.admitted,
                    contracted: state.contracted,
                    rejectedStale: state.rejectedStale,
                    rejectedUndeclared: state.rejectedUndeclared,
                    rejectedInvalid: state.rejectedInvalid,
                    rejectedCapacity: state.rejectedCapacity,
                    rejectedClosed: state.rejectedClosed,
                    repairEscalations: 0,
                    pendingKeyCount: state.pendingKeyCount,
                    pendingKeyHighWater: state.pendingKeyHighWater,
                    oldestPendingAge: exactAdmissionAge(
                        from: Self.oldestRetainedTimestamp(
                            state: state,
                            token: token
                        ),
                        to: now
                    )
                ),
                semanticRetainedValueCount: semanticRetainedValueCount,
                semanticRetainedValueHighWater: state.semanticRetainedValueHighWater,
                pendingValueCount: pendingValueCount,
                leasedValueCount: leasedValueCount,
                cleanupValueCount: state.cleanupValueCount,
                cleanupValueHighWater: state.cleanupValueHighWater,
                physicalRetainedValueCount: physicalRetainedValueCount,
                physicalRetainedValueHighWater: state.physicalRetainedValueHighWater,
                oldestCleanupAge: Self.cleanupAgeMeasurement(
                    from: state.oldestCleanupWatermark,
                    to: now
                ),
                outstandingLeaseCount: state.activeDrain == nil ? 0 : 1,
                outstandingCleanupTurnCount: state.inFlightCleanup == nil ? 0 : 1,
                isQuiescent: physicalRetainedValueCount == 0 && state.activeDrain == nil
            )
        }
    }

    fileprivate var authoritySnapshot: LatestValueAuthoritySnapshot {
        withAdmissionProtectedState { state, _ in
            LatestValueAuthoritySnapshot(
                bindingEpoch: state.bindingEpoch,
                bindingSequence: state.currentBindingSequence,
                leaseEpoch: state.leaseEpoch,
                leaseSequence: state.latestLeaseSequence,
                bindingEpochRotationCount: state.bindingEpochRotationCount,
                leaseEpochRotationCount: state.leaseEpochRotationCount
            )
        }
    }
}

extension LatestValueMailbox {
    private static func detachCleanup(
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken,
        generation: AdmissionGeneration,
        cleanupQuantum: AdmissionCleanupQuantum
    ) -> CleanupDetachTransition {
        guard generation == state.generation else {
            return emptyCleanupTransition(result: .staleGeneration)
        }
        guard state.inFlightCleanup == nil else {
            return emptyCleanupTransition(result: .alreadyCleaning)
        }
        guard state.cleanupValueCount > 0 else {
            return emptyCleanupTransition(result: .empty)
        }

        var detachedValues: [RetainedValue] = []
        detachedValues.reserveCapacity(
            min(cleanupQuantum.maximumEntries, state.cleanupValueCount)
        )
        var retiredBatches: [CleanupBatch] = []
        while detachedValues.count < cleanupQuantum.maximumEntries,
            let cleanupHead = state.cleanupHead
        {
            while detachedValues.count < cleanupQuantum.maximumEntries,
                let slot = cleanupHead.slotOrder.removeFirst(token: token)
            {
                if let retainedValue = cleanupHead.retainedValuesBySlot.removeValue(forKey: slot) {
                    detachedValues.append(retainedValue)
                }
            }

            guard cleanupHead.slotOrder.isEmpty(token: token) else { continue }
            if let reusableOrder = cleanupHead.slotOrder.takeReusableTerminalOrder(token: token) {
                precondition(state.reusableTerminalSlotOrder == nil)
                state.reusableTerminalSlotOrder = reusableOrder
            }
            state.cleanupHead = cleanupHead.next
            cleanupHead.next = nil
            if state.cleanupHead == nil {
                state.cleanupTail = nil
            }
            retiredBatches.append(cleanupHead)
        }

        precondition(detachedValues.isEmpty == false)
        let authority = AdmissionOpaqueIdentity()
        state.inFlightCleanup = InFlightCleanup(
            authority: authority,
            retainedValueCount: detachedValues.count,
            oldestRetainedTimestamp: detachedValues.lazy.map(\.firstRetainedAt).min()
        )
        refreshRetainedHighWaters(state: &state, token: token)
        return CleanupDetachTransition(
            result: .empty,
            authority: authority,
            detachedValues: detachedValues,
            retiredBatches: retiredBatches
        )
    }

    private static func emptyCleanupTransition(
        result: AdmissionCleanupTurnResult
    ) -> CleanupDetachTransition {
        CleanupDetachTransition(
            result: result,
            authority: nil,
            detachedValues: [],
            retiredBatches: []
        )
    }

    private static func finalizeCleanup(
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken,
        authority: AdmissionOpaqueIdentity,
        maximumValuesPerLease: Int,
        maximumAuxiliaryRetainedValues: Int
    ) -> AdmissionCleanupTurnResult {
        guard let inFlightCleanup = state.inFlightCleanup else {
            preconditionFailure("Latest cleanup authority disappeared before finalization")
        }
        guard inFlightCleanup.authority == authority else {
            preconditionFailure("Latest cleanup authority changed before finalization")
        }
        state.cleanupValueCount -= inFlightCleanup.retainedValueCount
        state.inFlightCleanup = nil
        state.oldestCleanupWatermark = cleanupWatermarkAfterRelease(
            releasedOldestRetainedAt: inFlightCleanup.oldestRetainedTimestamp,
            remainingCount: state.cleanupValueCount,
            current: state.oldestCleanupWatermark
        )

        let reservedDelivery = reservePendingDrainAfterCleanupFinalization(
            state: &state,
            token: token,
            maximumValuesPerLease: maximumValuesPerLease,
            maximumAuxiliaryRetainedValues: maximumAuxiliaryRetainedValues
        )
        let hasUnpresentedActiveDrain =
            state.activeDrain != nil
            && state.activeDrainPresentationState != .presented
        let hasDrainableSemanticWork =
            state.activeDrain == nil && state.pendingValuesBySlot.isEmpty == false
        let wake: AdmissionWakeDirective
        if state.cleanupValueCount > 0 || reservedDelivery || hasUnpresentedActiveDrain
            || hasDrainableSemanticWork
        {
            state.wakePending = true
            wake = .scheduleDrain
        } else {
            state.wakePending = false
            wake = .noWake
        }
        refreshRetainedHighWaters(state: &state, token: token)
        return .performed(
            AdmissionCleanupTurn(
                releasedEntryCount: inFlightCleanup.retainedValueCount,
                releasedByteCount: nil,
                wake: wake
            )
        )
    }

    private static func reservePendingDrainAfterCleanupFinalization(
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken,
        maximumValuesPerLease: Int,
        maximumAuxiliaryRetainedValues: Int
    ) -> Bool {
        guard state.lifecycle == .open || state.lifecycle == .sealed else { return false }
        guard state.activeDrain == nil else { return false }
        guard state.pendingValuesBySlot.isEmpty == false else { return false }

        let availableAuxiliaryCapacity =
            maximumAuxiliaryRetainedValues
            .subtractingReportingOverflow(state.cleanupValueCount)
        guard
            availableAuxiliaryCapacity.overflow == false,
            availableAuxiliaryCapacity.partialValue > 0
        else { return false }

        let leaseLimit = min(
            maximumValuesPerLease,
            state.pendingValuesBySlot.count,
            availableAuxiliaryCapacity.partialValue
        )
        guard leaseLimit > 0 else { return false }

        state.activeDrain = formActiveDrain(
            state: &state,
            token: token,
            leaseLimit: leaseLimit
        )
        state.activeDrainPresentationState = .awaitingInitialPresentation
        return true
    }

    private static func scheduleWakeForAcceptedOffer(
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) -> AdmissionWakeDirective {
        guard state.activeDrain == nil, state.wakePending == false else { return .noWake }
        state.wakePending = true
        return .scheduleDrain
    }

    private static func scheduleWakeAfterAcknowledgement(
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) -> AdmissionWakeDirective {
        guard state.cleanupValueCount > 0 || state.pendingValuesBySlot.isEmpty == false else {
            state.wakePending = false
            return .noWake
        }
        state.wakePending = true
        return .scheduleDrain
    }

    private static func takeDrain(
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken,
        binding: AdmissionConsumerBinding,
        generation: AdmissionGeneration,
        maximumValuesPerLease: Int
    ) -> LockedTakeDrainResult {
        guard generation == state.generation else { return .result(.staleGeneration) }
        guard state.lifecycle != .invalidated else { return .result(.closed) }
        guard
            binding.matches(
                mailboxIdentity: state.mailboxIdentity,
                bindingEpoch: state.bindingEpoch,
                bindingSequence: state.currentBindingSequence
            )
        else { return .result(.alreadyDraining) }

        if let activeDrain = state.activeDrain {
            switch state.activeDrainPresentationState {
            case .presented:
                return .result(.alreadyDraining)
            case .awaitingInitialPresentation:
                state.activeDrainPresentationState = .presented
                state.wakePending = false
                return .drain(activeDrain)
            case .awaitingRebindPresentation:
                let reboundDrain = ActiveDrain(
                    token: nextDrainToken(state: &state, token: token),
                    retainedValuesBySlot: activeDrain.retainedValuesBySlot,
                    retentionOrderSlots: activeDrain.retentionOrderSlots
                )
                state.activeDrain = reboundDrain
                state.activeDrainPresentationState = .presented
                state.wakePending = false
                return .drain(reboundDrain)
            }
        }

        guard state.cleanupValueCount == 0 else {
            return .result(.cleanupRequired)
        }
        guard state.pendingValuesBySlot.isEmpty == false else {
            return .result(state.lifecycle == .sealed ? .closed : .empty)
        }

        state.wakePending = false
        let activeDrain = formActiveDrain(
            state: &state,
            token: token,
            leaseLimit: min(maximumValuesPerLease, state.pendingValuesBySlot.count)
        )
        state.activeDrain = activeDrain
        state.activeDrainPresentationState = .presented
        return .drain(activeDrain)
    }

    private static func formActiveDrain(
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken,
        leaseLimit: Int
    ) -> ActiveDrain {
        precondition(state.activeDrain == nil)
        precondition(leaseLimit > 0)

        var retainedValuesBySlot: [Int: RetainedValue] = [:]
        var retentionOrderSlots: [Int] = []
        retainedValuesBySlot.reserveCapacity(leaseLimit)
        retentionOrderSlots.reserveCapacity(leaseLimit)
        while retentionOrderSlots.count < leaseLimit,
            let slot = state.pendingSlotOrder.removeFirst(token: token)
        {
            guard let retainedValue = state.pendingValuesBySlot.removeValue(forKey: slot) else {
                preconditionFailure("Latest pending order referenced an empty slot")
            }
            retainedValuesBySlot[slot] = retainedValue
            retentionOrderSlots.append(slot)
        }
        precondition(retentionOrderSlots.isEmpty == false)
        return ActiveDrain(
            token: nextDrainToken(state: &state, token: token),
            retainedValuesBySlot: retainedValuesBySlot,
            retentionOrderSlots: retentionOrderSlots
        )
    }

    private static func nextDrainToken(
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) -> AdmissionDrainToken {
        let nextLeaseSequence = state.latestLeaseSequence.addingReportingOverflow(1)
        if nextLeaseSequence.overflow {
            state.leaseEpoch = AdmissionOpaqueIdentity()
            state.latestLeaseSequence = 1
            incrementAdmissionCounter(&state.leaseEpochRotationCount)
        } else {
            state.latestLeaseSequence = nextLeaseSequence.partialValue
        }
        return AdmissionDrainToken(
            generation: state.generation,
            mailboxIdentity: state.mailboxIdentity,
            bindingEpoch: state.bindingEpoch,
            bindingSequence: state.currentBindingSequence,
            leaseEpoch: state.leaseEpoch,
            leaseSequence: state.latestLeaseSequence
        )
    }

    private func makeDrain(
        activeDrain: ActiveDrain,
        now: Duration
    ) -> LatestValueDrainResult<Key, Value> {
        var valuesByKey: [Key: Value] = [:]
        valuesByKey.reserveCapacity(activeDrain.retainedValuesBySlot.count)
        for (slot, retainedValue) in activeDrain.retainedValuesBySlot {
            valuesByKey[declaredKeysBySlot[slot]] = retainedValue.value
        }

        return .drain(
            LatestValueDrain(
                token: activeDrain.token,
                valuesByKey: valuesByKey,
                oldestRetainedAge: exactAdmissionAge(
                    from: activeDrain.retentionOrderSlots.first.flatMap {
                        activeDrain.retainedValuesBySlot[$0]?.firstRetainedAt
                    },
                    to: now
                )
            )
        )
    }

    private static func invalidateState(
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken,
        maximumValuesPerLease: Int
    ) {
        if let activeDrain = state.activeDrain {
            appendCleanupBatch(
                retainedValuesBySlot: activeDrain.retainedValuesBySlot,
                retentionOrderSlots: activeDrain.retentionOrderSlots,
                maximumValuesPerLease: maximumValuesPerLease,
                state: &state,
                token: token
            )
        }
        if state.pendingValuesBySlot.isEmpty == false {
            guard let replacementOrder = state.reusableTerminalSlotOrder else {
                preconditionFailure("Latest terminal order storage is already in use")
            }
            let terminalOrder = state.pendingSlotOrder
            state.pendingSlotOrder = replacementOrder
            state.reusableTerminalSlotOrder = nil
            appendTerminalCleanupBatch(
                retainedValuesBySlot: state.pendingValuesBySlot,
                terminalSlotOrder: terminalOrder,
                state: &state,
                token: token
            )
        }
        state.lifecycle = .invalidated
        state.pendingValuesBySlot = [:]
        state.activeDrain = nil
        state.activeDrainPresentationState = .presented
        state.wakePending = false
        state.pendingKeyCount = 0
        refreshRetainedHighWaters(state: &state, token: token)
    }

    private static func oldestRetainedTimestamp(
        state: State,
        token: borrowing AdmissionProtectedRegionToken
    ) -> Duration? {
        let pendingOldest = state.pendingSlotOrder.first(token: token).flatMap {
            state.pendingValuesBySlot[$0]?.firstRetainedAt
        }
        let leasedOldest = state.activeDrain.flatMap { activeDrain in
            activeDrain.retentionOrderSlots.first.flatMap {
                activeDrain.retainedValuesBySlot[$0]?.firstRetainedAt
            }
        }

        return switch (pendingOldest, leasedOldest) {
        case (.some(let pending), .some(let leased)):
            min(pending, leased)
        case (.some(let pending), .none):
            pending
        case (.none, .some(let leased)):
            leased
        case (.none, .none):
            nil
        }
    }

    private static func mergeCleanupWatermark(
        current: CleanupAgeWatermark?,
        retainedAt: Duration
    ) -> CleanupAgeWatermark {
        guard let current else {
            return CleanupAgeWatermark(retainedAt: retainedAt, precision: .exact)
        }
        guard retainedAt < current.retainedAt else { return current }
        return CleanupAgeWatermark(retainedAt: retainedAt, precision: .exact)
    }

    private static func cleanupWatermarkAfterRelease(
        releasedOldestRetainedAt: Duration?,
        remainingCount: Int,
        current: CleanupAgeWatermark?
    ) -> CleanupAgeWatermark? {
        guard remainingCount > 0 else { return nil }
        guard let current else {
            preconditionFailure("Latest cleanup custody is missing its age watermark")
        }
        guard
            let releasedOldestRetainedAt,
            releasedOldestRetainedAt <= current.retainedAt
        else { return current }
        return CleanupAgeWatermark(
            retainedAt: current.retainedAt,
            precision: .pressureConservative
        )
    }

    private static func cleanupAgeMeasurement(
        from watermark: CleanupAgeWatermark?,
        to now: Duration
    ) -> AdmissionAgeMeasurement? {
        guard let watermark else { return nil }
        let age = max(.zero, now - watermark.retainedAt)
        return switch watermark.precision {
        case .exact: .exact(age)
        case .pressureConservative: .pressureConservative(age)
        }
    }

    private static func appendCleanupBatch(
        retainedValuesBySlot: [Int: RetainedValue],
        retentionOrderSlots: [Int],
        maximumValuesPerLease: Int,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        guard retainedValuesBySlot.isEmpty == false else { return }
        let batch = CleanupBatch(
            retainedValuesBySlot: retainedValuesBySlot,
            retentionOrderSlots: retentionOrderSlots,
            maximumValuesPerLease: maximumValuesPerLease,
            token: token
        )
        state.oldestCleanupWatermark = mergeCleanupWatermark(
            current: state.oldestCleanupWatermark,
            retainedAt: batch.initialOldestRetainedTimestamp
        )
        if let cleanupTail = state.cleanupTail {
            cleanupTail.next = batch
        } else {
            state.cleanupHead = batch
        }
        state.cleanupTail = batch
        state.cleanupValueCount += retainedValuesBySlot.count
        state.cleanupValueHighWater = max(
            state.cleanupValueHighWater,
            state.cleanupValueCount
        )
    }

    private static func appendTerminalCleanupBatch(
        retainedValuesBySlot: [Int: RetainedValue],
        terminalSlotOrder: PendingSlotOrder,
        state: inout State,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        guard retainedValuesBySlot.isEmpty == false else { return }
        let batch = CleanupBatch(
            retainedValuesBySlot: retainedValuesBySlot,
            terminalSlotOrder: terminalSlotOrder,
            token: token
        )
        state.oldestCleanupWatermark = mergeCleanupWatermark(
            current: state.oldestCleanupWatermark,
            retainedAt: batch.initialOldestRetainedTimestamp
        )
        if let cleanupTail = state.cleanupTail {
            cleanupTail.next = batch
        } else {
            state.cleanupHead = batch
        }
        state.cleanupTail = batch
        state.cleanupValueCount += retainedValuesBySlot.count
        state.cleanupValueHighWater = max(
            state.cleanupValueHighWater,
            state.cleanupValueCount
        )
    }

    private static func refreshRetainedHighWaters(
        state: inout State,
        token _: borrowing AdmissionProtectedRegionToken
    ) {
        let semanticRetainedValueCount =
            state.pendingValuesBySlot.count
            + (state.activeDrain?.retainedValuesBySlot.count ?? 0)
        let physicalRetainedValueCount = semanticRetainedValueCount + state.cleanupValueCount
        state.semanticRetainedValueHighWater = max(
            state.semanticRetainedValueHighWater,
            semanticRetainedValueCount
        )
        state.physicalRetainedValueHighWater = max(
            state.physicalRetainedValueHighWater,
            physicalRetainedValueCount
        )
    }
}
