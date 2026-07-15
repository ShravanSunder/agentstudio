import Foundation

struct WorkspaceStateSnapshotBaseCopyToken: Hashable, Sendable {
    fileprivate struct ParticipantIdentity: Hashable, Sendable {
        let rawValue: UUID

        static func make() -> Self {
            let rawValue = UUIDv7.generate()
            precondition(
                UUIDv7.isV7(rawValue),
                "workspace snapshot participant identity must be UUIDv7"
            )
            return Self(rawValue: rawValue)
        }
    }

    fileprivate let participantIdentity: ParticipantIdentity
    fileprivate let leaseID: WorkspaceStateSnapshotLeaseID
    fileprivate let slotIndex: Int
    fileprivate let slotGeneration: UInt64
}

/// Owner-local fixed-base retention for one typed persistence key space.
///
/// This primitive owns a stable physical key index plus the first pre-change
/// value for base slots that have not yet been copied into an immutable page.
/// Lease opening captures counters and a slot upper bound only; it never walks
/// or retains an atom's fleet value collection.
@MainActor
final class WorkspaceStateSnapshotKeyedParticipant<
    Key: Hashable & Sendable,
    Value: Sendable
> {
    private final class RetainedValueNode {
        let slotIndex: Int
        let slotGeneration: UInt64
        var value: Value?
        var previous: RetainedValueNode?
        var next: RetainedValueNode?

        init(slotIndex: Int, slotGeneration: UInt64, value: Value) {
            self.slotIndex = slotIndex
            self.slotGeneration = slotGeneration
            self.value = value
        }
    }

    private struct CopiedMarker {
        let leaseID: WorkspaceStateSnapshotLeaseID
        let pageID: WorkspaceStateSnapshotPageID
    }

    private struct LiveSlotPayload {
        let key: Key
        let rawKeyByteCount: UInt64
        let insertedRevision: WorkspacePersistenceRevision
        let retainedValue: RetainedValueNode?
        let copiedMarker: CopiedMarker?
    }

    private struct RetiredBaseSlotPayload {
        let key: Key
        let rawKeyByteCount: UInt64
        let insertedRevision: WorkspacePersistenceRevision
        let retainedValue: RetainedValueNode
        let copiedMarker: CopiedMarker?
    }

    private enum SlotState {
        case reusable
        case live(LiveSlotPayload)
        case retiredBase(RetiredBaseSlotPayload)
    }

    private struct Slot {
        var generation: UInt64
        var state: SlotState
    }

    private struct ActiveLease {
        let lease: WorkspaceStateSnapshotLease
        let baseSlotUpperBound: Int
        let baseMembershipCount: Int
        let membershipLimits: WorkspaceStateSnapshotMembershipLimits
        var copiedBaseValueCount: Int
        var retainedValueHead: RetainedValueNode?
        var retainedValueTail: RetainedValueNode?
        var retainedBaseValueCount: Int
    }

    private struct NonemptyRetainedValueChain {
        enum Removal {
            case final(RetainedValueNode)
            case remaining(RetainedValueNode)
        }

        private(set) var head: RetainedValueNode
        private(set) var count: Int

        init(head: RetainedValueNode, count: Int) {
            precondition(count > 0, "nonempty retained-value chain requires positive count")
            self.head = head
            self.count = count
        }

        mutating func removeHead() -> Removal {
            let removedNode = head
            guard count > 1 else { return .final(removedNode) }
            guard let nextHead = removedNode.next else {
                preconditionFailure("retained-value chain ended before its checked count")
            }
            head = nextHead
            count -= 1
            return .remaining(removedNode)
        }
    }

    private struct CleanupState {
        let lease: WorkspaceStateSnapshotLease
        var retainedValues: NonemptyRetainedValueChain
    }

    private enum LeaseState {
        case idle
        case active(ActiveLease)
        case cleanup(CleanupState)
    }

    private struct LeaseOpenWorkCounter {
        var openCount: UInt64 = 0
        var slotInspectionCount: UInt64 = 0
        var rawKeyByteComputationCount: UInt64 = 0

        mutating func recordOpen() {
            openCount += 1
        }

        var diagnostics: WorkspaceStateSnapshotParticipantWorkDiagnostics {
            WorkspaceStateSnapshotParticipantWorkDiagnostics(
                leaseOpenCount: openCount,
                leaseOpenSlotInspectionCount: slotInspectionCount,
                leaseOpenRawKeyByteComputationCount: rawKeyByteComputationCount
            )
        }
    }

    private var slots: [Slot] = []
    private var currentSlotIndexByKey: [Key: Int] = [:]
    private var reusableSlotIndices: [Int] = []
    private var currentKeyCount = 0
    private var currentRawKeyByteCount: UInt64 = 0
    private var configuredMembershipLimits: WorkspaceStateSnapshotMembershipLimits?
    private var leaseState: LeaseState = .idle
    private var leaseOpenWorkCounter = LeaseOpenWorkCounter()
    private let participantIdentity = WorkspaceStateSnapshotBaseCopyToken.ParticipantIdentity.make()

    func configureMembershipLimits(
        _ limits: WorkspaceStateSnapshotMembershipLimits
    ) -> SnapshotMembershipConfigurationResult {
        switch leaseState {
        case .idle:
            break
        case .active:
            return .rejected(.activeLeaseExists)
        case .cleanup:
            return .rejected(.cleanupPending)
        }
        if let configuredMembershipLimits {
            return configuredMembershipLimits == limits
                ? .configured
                : .rejected(.membershipLimitsMismatch)
        }
        guard UInt64(currentKeyCount) <= limits.maximumKeyCount else {
            return .rejected(.baseMembershipKeyCountCapacityExceeded)
        }
        guard currentRawKeyByteCount <= limits.maximumRawKeyBytes else {
            return .rejected(.baseMembershipRawByteCapacityExceeded)
        }
        configuredMembershipLimits = limits
        return .configured
    }

    func registerInitialKey(
        _ key: Key,
        rawKeyByteCount: UInt64,
        limits: WorkspaceStateSnapshotMembershipLimits
    ) -> WorkspaceStateSnapshotMembershipRegistrationResult {
        registerInitialMembership(
            [(key: key, rawKeyByteCount: rawKeyByteCount)],
            limits: limits
        )
    }

    func registerInitialMembership(
        _ entries: [(key: Key, rawKeyByteCount: UInt64)],
        limits: WorkspaceStateSnapshotMembershipLimits
    ) -> WorkspaceStateSnapshotMembershipRegistrationResult {
        switch leaseState {
        case .idle:
            break
        case .active:
            return .rejected(.activeLeaseExists)
        case .cleanup:
            return .rejected(.cleanupPending)
        }
        if let configuredMembershipLimits, configuredMembershipLimits != limits {
            return .rejected(.membershipLimitsMismatch)
        }
        var uniqueKeys = Set<Key>()
        uniqueKeys.reserveCapacity(entries.count)
        for entry in entries {
            guard currentSlotIndexByKey[entry.key] == nil, uniqueKeys.insert(entry.key).inserted else {
                return .rejected(.duplicateCurrentKey)
            }
        }
        let nextKeyCount = UInt64(currentKeyCount).addingReportingOverflow(UInt64(entries.count))
        guard !nextKeyCount.overflow, nextKeyCount.partialValue <= limits.maximumKeyCount else {
            return .rejected(.baseMembershipKeyCountCapacityExceeded)
        }
        var nextRawKeyByteCount = currentRawKeyByteCount
        for entry in entries {
            let sum = nextRawKeyByteCount.addingReportingOverflow(entry.rawKeyByteCount)
            guard !sum.overflow else {
                return .rejected(.baseMembershipRawByteCountOverflow)
            }
            guard sum.partialValue <= limits.maximumRawKeyBytes else {
                return .rejected(.baseMembershipRawByteCapacityExceeded)
            }
            nextRawKeyByteCount = sum.partialValue
        }
        configuredMembershipLimits = limits
        for entry in entries {
            let slotIndex = allocateSlot(
                key: entry.key,
                rawKeyByteCount: entry.rawKeyByteCount,
                insertedRevision: .zero
            )
            currentSlotIndexByKey[entry.key] = slotIndex
        }
        currentKeyCount += entries.count
        currentRawKeyByteCount = nextRawKeyByteCount
        return .registered
    }

    func open(
        lease: WorkspaceStateSnapshotLease,
        limits: WorkspaceStateSnapshotMembershipLimits
    ) -> WorkspaceStateSnapshotParticipantOpenResult {
        switch leaseState {
        case .active:
            return .rejected(.activeLeaseExists)
        case .cleanup:
            return .rejected(.cleanupPending)
        case .idle:
            break
        }
        guard UInt64(currentKeyCount) <= limits.maximumKeyCount else {
            return .rejected(.baseMembershipKeyCountCapacityExceeded)
        }
        guard currentRawKeyByteCount <= limits.maximumRawKeyBytes else {
            return .rejected(.baseMembershipRawByteCapacityExceeded)
        }
        if let configuredMembershipLimits, configuredMembershipLimits != limits {
            return .rejected(.membershipLimitsMismatch)
        }
        configuredMembershipLimits = limits
        leaseOpenWorkCounter.recordOpen()
        leaseState = .active(
            ActiveLease(
                lease: lease,
                baseSlotUpperBound: slots.count,
                baseMembershipCount: currentKeyCount,
                membershipLimits: limits,
                copiedBaseValueCount: 0,
                retainedValueHead: nil,
                retainedValueTail: nil,
                retainedBaseValueCount: 0
            )
        )
        return .opened(baseMembershipCount: currentKeyCount)
    }

    func workDiagnostics() -> WorkspaceStateSnapshotParticipantWorkDiagnostics {
        leaseOpenWorkCounter.diagnostics
    }

    func recordWillChange(
        key: Key,
        currentValue: @autoclosure () -> WorkspaceStateSnapshotStoredValue<Value>,
        transaction: WorkspacePersistenceTransaction,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) -> WorkspaceStateSnapshotMutationResult {
        guard validateActiveTransaction(transaction, revisionOwner: revisionOwner) else {
            return .rejected(.transactionNotActive)
        }
        guard case .active(var activeLease) = leaseState else {
            return .noRetentionRequired
        }
        guard transaction.processGeneration == activeLease.lease.processGeneration else {
            return .rejected(.foreignProcessGeneration)
        }
        guard transaction.proposedRevision > activeLease.lease.baseRevision else {
            return .rejected(.transactionDoesNotFollowBaseRevision)
        }
        guard let slotIndex = currentSlotIndexByKey[key] else {
            return .postBaseKeyExcluded
        }
        let slot = slots[slotIndex]
        guard case .live(let liveSlot) = slot.state else { return .postBaseKeyExcluded }
        guard liveSlot.insertedRevision <= activeLease.lease.baseRevision else {
            return .postBaseKeyExcluded
        }
        guard liveSlot.copiedMarker?.leaseID != activeLease.lease.leaseID else {
            return .baseValueAlreadyCopied
        }
        guard liveSlot.retainedValue == nil else { return .baseValueAlreadyRetained }
        guard case .value(let retainedBaseValue) = currentValue() else {
            return .rejected(.baseMembershipValueMissing)
        }
        let node = RetainedValueNode(
            slotIndex: slotIndex,
            slotGeneration: slot.generation,
            value: retainedBaseValue
        )
        appendRetainedNode(node, to: &activeLease)
        slots[slotIndex].state = .live(
            LiveSlotPayload(
                key: liveSlot.key,
                rawKeyByteCount: liveSlot.rawKeyByteCount,
                insertedRevision: liveSlot.insertedRevision,
                retainedValue: node,
                copiedMarker: liveSlot.copiedMarker
            )
        )
        leaseState = .active(activeLease)
        return .retainedFirstBaseValue
    }

    func recordInserted(
        key: Key,
        rawKeyByteCount: UInt64,
        transaction: WorkspacePersistenceTransaction,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) -> WorkspaceStateSnapshotMembershipMutationResult {
        guard validateActiveTransaction(transaction, revisionOwner: revisionOwner) else {
            return .rejected(.transactionNotActive)
        }
        guard currentSlotIndexByKey[key] == nil else {
            return .rejected(.duplicateCurrentKey)
        }
        guard let membershipLimits = configuredMembershipLimits else {
            return .rejected(.membershipLimitsUnavailable)
        }
        guard UInt64(currentKeyCount) < membershipLimits.maximumKeyCount else {
            return .rejected(.baseMembershipKeyCountCapacityExceeded)
        }
        let nextRawByteCount = currentRawKeyByteCount.addingReportingOverflow(rawKeyByteCount)
        guard !nextRawByteCount.overflow else {
            return .rejected(.baseMembershipRawByteCountOverflow)
        }
        guard nextRawByteCount.partialValue <= membershipLimits.maximumRawKeyBytes else {
            return .rejected(.baseMembershipRawByteCapacityExceeded)
        }
        if reusableSlotIndices.isEmpty {
            let physicalSlotCapacity = membershipLimits.maximumKeyCount.multipliedReportingOverflow(by: 2)
            guard
                !physicalSlotCapacity.overflow,
                UInt64(slots.count) < physicalSlotCapacity.partialValue
            else {
                return .rejected(.physicalSlotCapacityExceeded)
            }
        }
        let slotIndex = allocateSlot(
            key: key,
            rawKeyByteCount: rawKeyByteCount,
            insertedRevision: transaction.proposedRevision
        )
        currentSlotIndexByKey[key] = slotIndex
        currentKeyCount += 1
        currentRawKeyByteCount = nextRawByteCount.partialValue
        return .inserted
    }

    func recordRemoved(
        key: Key,
        currentValue: @autoclosure () -> WorkspaceStateSnapshotStoredValue<Value>,
        transaction: WorkspacePersistenceTransaction,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) -> WorkspaceStateSnapshotMembershipMutationResult {
        guard validateActiveTransaction(transaction, revisionOwner: revisionOwner) else {
            return .rejected(.transactionNotActive)
        }
        guard let slotIndex = currentSlotIndexByKey[key] else {
            return .rejected(.currentKeyMissing)
        }
        let slot = slots[slotIndex]
        guard case .live(let liveSlot) = slot.state else {
            return .rejected(.currentKeyMissing)
        }

        var retainedNodeForUnreadBase: RetainedValueNode?
        if case .active(let activeLease) = leaseState,
            liveSlot.insertedRevision <= activeLease.lease.baseRevision,
            liveSlot.copiedMarker?.leaseID != activeLease.lease.leaseID,
            liveSlot.retainedValue == nil
        {
            guard case .value(let baseValue) = currentValue() else {
                return .rejected(.baseMembershipValueMissing)
            }
            retainedNodeForUnreadBase = RetainedValueNode(
                slotIndex: slotIndex,
                slotGeneration: slot.generation,
                value: baseValue
            )
        }

        currentSlotIndexByKey.removeValue(forKey: key)
        currentKeyCount -= 1
        currentRawKeyByteCount -= liveSlot.rawKeyByteCount

        if case .active(var activeLease) = leaseState,
            liveSlot.insertedRevision <= activeLease.lease.baseRevision,
            liveSlot.copiedMarker?.leaseID != activeLease.lease.leaseID
        {
            let node: RetainedValueNode
            if let retainedValue = liveSlot.retainedValue {
                node = retainedValue
            } else {
                guard let retainedNodeForUnreadBase else { preconditionFailure() }
                node = retainedNodeForUnreadBase
                appendRetainedNode(node, to: &activeLease)
            }
            slots[slotIndex].state = .retiredBase(
                RetiredBaseSlotPayload(
                    key: liveSlot.key,
                    rawKeyByteCount: liveSlot.rawKeyByteCount,
                    insertedRevision: liveSlot.insertedRevision,
                    retainedValue: node,
                    copiedMarker: liveSlot.copiedMarker
                )
            )
            leaseState = .active(activeLease)
        } else {
            makeSlotReusable(slotIndex)
        }
        return .removed
    }

    func baseSlotUpperBound(
        for lease: WorkspaceStateSnapshotLease
    ) -> Result<Int, WorkspaceStateSnapshotParticipantRejection> {
        guard case .active(let activeLease) = leaseState else {
            return .failure(.noActiveLease)
        }
        guard activeLease.lease == lease else { return .failure(.foreignLease) }
        return .success(activeLease.baseSlotUpperBound)
    }

    func inspectBaseSlot(
        lease: WorkspaceStateSnapshotLease,
        slotCursor: Int,
        currentValue: (Key) -> WorkspaceStateSnapshotStoredValue<Value>
    ) -> WorkspaceStateSnapshotBaseSlotInspection<Key, Value> {
        guard case .active(let activeLease) = leaseState else {
            return .rejected(.noActiveLease)
        }
        guard activeLease.lease == lease else { return .rejected(.foreignLease) }
        guard slotCursor >= 0 else { return .rejected(.staleBaseCopyToken) }
        guard slotCursor < activeLease.baseSlotUpperBound else { return .exhausted }
        let slot = slots[slotCursor]
        let nextSlotCursor = slotCursor + 1
        switch slot.state {
        case .reusable:
            return .skipped(nextSlotCursor: nextSlotCursor)
        case .live(let liveSlot):
            guard liveSlot.insertedRevision <= activeLease.lease.baseRevision else {
                return .skipped(nextSlotCursor: nextSlotCursor)
            }
            guard liveSlot.copiedMarker?.leaseID != activeLease.lease.leaseID else {
                return .skipped(nextSlotCursor: nextSlotCursor)
            }
            if let retainedValue = liveSlot.retainedValue, let value = retainedValue.value {
                return .item(
                    key: liveSlot.key,
                    value: value,
                    copyToken: .init(
                        participantIdentity: participantIdentity,
                        leaseID: lease.leaseID,
                        slotIndex: slotCursor,
                        slotGeneration: slot.generation
                    ),
                    nextSlotCursor: nextSlotCursor
                )
            }
            guard case .value(let value) = currentValue(liveSlot.key) else {
                return .rejected(.baseMembershipValueMissing)
            }
            return .item(
                key: liveSlot.key,
                value: value,
                copyToken: .init(
                    participantIdentity: participantIdentity,
                    leaseID: lease.leaseID,
                    slotIndex: slotCursor,
                    slotGeneration: slot.generation
                ),
                nextSlotCursor: nextSlotCursor
            )
        case .retiredBase(let retiredBaseSlot):
            guard retiredBaseSlot.insertedRevision <= activeLease.lease.baseRevision else {
                return .skipped(nextSlotCursor: nextSlotCursor)
            }
            guard retiredBaseSlot.copiedMarker?.leaseID != activeLease.lease.leaseID else {
                return .skipped(nextSlotCursor: nextSlotCursor)
            }
            guard let value = retiredBaseSlot.retainedValue.value else {
                return .rejected(.baseMembershipValueMissing)
            }
            return .item(
                key: retiredBaseSlot.key,
                value: value,
                copyToken: .init(
                    participantIdentity: participantIdentity,
                    leaseID: lease.leaseID,
                    slotIndex: slotCursor,
                    slotGeneration: slot.generation
                ),
                nextSlotCursor: nextSlotCursor
            )
        }
    }

    func markBaseValueCopied(
        lease: WorkspaceStateSnapshotLease,
        copyToken: WorkspaceStateSnapshotBaseCopyToken,
        pageID: WorkspaceStateSnapshotPageID
    ) -> WorkspaceStateSnapshotMarkCopiedResult {
        guard case .active(var activeLease) = leaseState else {
            return .rejected(.noActiveLease)
        }
        guard activeLease.lease == lease else { return .rejected(.foreignLease) }
        guard copyToken.participantIdentity == participantIdentity else {
            return .rejected(.staleBaseCopyToken)
        }
        guard copyToken.leaseID == lease.leaseID else {
            return .rejected(.staleBaseCopyToken)
        }
        guard slots.indices.contains(copyToken.slotIndex) else {
            return .rejected(.staleBaseCopyToken)
        }
        let slot = slots[copyToken.slotIndex]
        guard slot.generation == copyToken.slotGeneration else {
            return .rejected(.staleBaseCopyToken)
        }
        let marker = CopiedMarker(leaseID: lease.leaseID, pageID: pageID)
        switch slot.state {
        case .reusable:
            return .rejected(.staleBaseCopyToken)
        case .live(let liveSlot):
            if let copiedMarker = liveSlot.copiedMarker,
                copiedMarker.leaseID == lease.leaseID
            {
                return copiedMarker.pageID == pageID
                    ? .alreadyMarkedCopied
                    : .rejected(.baseValueCopiedByDifferentPage)
            }
            if let retainedValue = liveSlot.retainedValue {
                unlinkRetainedNode(retainedValue, from: &activeLease)
            }
            slots[copyToken.slotIndex].state = .live(
                LiveSlotPayload(
                    key: liveSlot.key,
                    rawKeyByteCount: liveSlot.rawKeyByteCount,
                    insertedRevision: liveSlot.insertedRevision,
                    retainedValue: nil,
                    copiedMarker: marker
                )
            )
        case .retiredBase(let retiredBaseSlot):
            if let copiedMarker = retiredBaseSlot.copiedMarker,
                copiedMarker.leaseID == lease.leaseID
            {
                return copiedMarker.pageID == pageID
                    ? .alreadyMarkedCopied
                    : .rejected(.baseValueCopiedByDifferentPage)
            }
            unlinkRetainedNode(retiredBaseSlot.retainedValue, from: &activeLease)
            makeSlotReusable(copyToken.slotIndex)
        }
        activeLease.copiedBaseValueCount += 1
        leaseState = .active(activeLease)
        return .markedCopied
    }

    func diagnostics(
        for lease: WorkspaceStateSnapshotLease
    ) -> WorkspaceStateSnapshotParticipantDiagnosticsResult {
        guard case .active(let activeLease) = leaseState else {
            return .rejected(.noActiveLease)
        }
        guard activeLease.lease == lease else {
            return .rejected(.foreignLease)
        }
        return .diagnostics(
            WorkspaceStateSnapshotParticipantDiagnostics(
                baseMembershipCount: activeLease.baseMembershipCount,
                copiedBaseValueCount: activeLease.copiedBaseValueCount,
                retainedBaseValueCount: activeLease.retainedBaseValueCount,
                physicalSlotCount: slots.count,
                reusableSlotCount: reusableSlotIndices.count,
                cleanupRetainedValueCount: 0
            )
        )
    }

    func close(
        lease: WorkspaceStateSnapshotLease
    ) -> WorkspaceStateSnapshotParticipantCloseResult {
        guard case .active(let activeLease) = leaseState else {
            return .rejected(.noActiveLease)
        }
        guard activeLease.lease == lease else {
            return .rejected(.foreignLease)
        }
        if activeLease.retainedBaseValueCount == 0 {
            leaseState = .idle
        } else {
            guard let retainedValueHead = activeLease.retainedValueHead else {
                preconditionFailure("positive retained-value count requires a head")
            }
            leaseState = .cleanup(
                CleanupState(
                    lease: lease,
                    retainedValues: NonemptyRetainedValueChain(
                        head: retainedValueHead,
                        count: activeLease.retainedBaseValueCount
                    )
                )
            )
        }
        return .closed(
            WorkspaceStateSnapshotParticipantCloseReceipt(
                releasedMembershipCount: activeLease.baseMembershipCount,
                releasedBaseValueCount: activeLease.retainedBaseValueCount
            )
        )
    }

    func drainCleanup(maximumValues: Int) -> WorkspaceStateSnapshotCleanupDrainResult {
        guard case .cleanup(var cleanup) = leaseState else { return .complete }
        guard maximumValues > 0 else {
            return .drained(
                releasedValueCount: 0,
                remainingValueCount: cleanup.retainedValues.count
            )
        }
        var releasedValueCount = 0
        while releasedValueCount < maximumValues {
            let removal = cleanup.retainedValues.removeHead()
            switch removal {
            case .final(let finalNode):
                releaseRetainedNode(finalNode)
                releasedValueCount += 1
                leaseState = .idle
                return .drained(
                    releasedValueCount: releasedValueCount,
                    remainingValueCount: 0
                )
            case .remaining(let removedNode):
                cleanup.retainedValues.head.previous = nil
                releaseRetainedNode(removedNode)
                releasedValueCount += 1
            }
        }
        leaseState = .cleanup(cleanup)
        return .drained(
            releasedValueCount: releasedValueCount,
            remainingValueCount: cleanup.retainedValues.count
        )
    }

    private var cleanupCount: Int {
        guard case .cleanup(let cleanup) = leaseState else { return 0 }
        return cleanup.retainedValues.count
    }

    private func releaseRetainedNode(_ node: RetainedValueNode) {
        if slots.indices.contains(node.slotIndex),
            slots[node.slotIndex].generation == node.slotGeneration
        {
            switch slots[node.slotIndex].state {
            case .live(let liveSlot) where liveSlot.retainedValue === node:
                slots[node.slotIndex].state = .live(
                    LiveSlotPayload(
                        key: liveSlot.key,
                        rawKeyByteCount: liveSlot.rawKeyByteCount,
                        insertedRevision: liveSlot.insertedRevision,
                        retainedValue: nil,
                        copiedMarker: liveSlot.copiedMarker
                    )
                )
            case .retiredBase(let retiredBaseSlot)
            where retiredBaseSlot.retainedValue === node:
                makeSlotReusable(node.slotIndex)
            default:
                break
            }
        }
        node.previous = nil
        node.next = nil
        node.value = nil
    }

    private func allocateSlot(
        key: Key,
        rawKeyByteCount: UInt64,
        insertedRevision: WorkspacePersistenceRevision
    ) -> Int {
        if let slotIndex = reusableSlotIndices.popLast() {
            let nextGeneration = slots[slotIndex].generation &+ 1
            precondition(nextGeneration != 0, "workspace snapshot slot generation exhausted")
            slots[slotIndex] = Slot(
                generation: nextGeneration,
                state: .live(
                    LiveSlotPayload(
                        key: key,
                        rawKeyByteCount: rawKeyByteCount,
                        insertedRevision: insertedRevision,
                        retainedValue: nil,
                        copiedMarker: nil
                    )
                )
            )
            return slotIndex
        }
        slots.append(
            Slot(
                generation: 1,
                state: .live(
                    LiveSlotPayload(
                        key: key,
                        rawKeyByteCount: rawKeyByteCount,
                        insertedRevision: insertedRevision,
                        retainedValue: nil,
                        copiedMarker: nil
                    )
                )
            )
        )
        return slots.count - 1
    }

    private func makeSlotReusable(_ slotIndex: Int) {
        guard slots.indices.contains(slotIndex) else { return }
        guard case .reusable = slots[slotIndex].state else {
            slots[slotIndex].state = .reusable
            reusableSlotIndices.append(slotIndex)
            return
        }
    }

    private func appendRetainedNode(_ node: RetainedValueNode, to activeLease: inout ActiveLease) {
        node.previous = activeLease.retainedValueTail
        activeLease.retainedValueTail?.next = node
        activeLease.retainedValueTail = node
        if activeLease.retainedValueHead == nil { activeLease.retainedValueHead = node }
        activeLease.retainedBaseValueCount += 1
    }

    private func unlinkRetainedNode(_ node: RetainedValueNode, from activeLease: inout ActiveLease) {
        if let previous = node.previous { previous.next = node.next } else { activeLease.retainedValueHead = node.next }
        if let next = node.next { next.previous = node.previous } else { activeLease.retainedValueTail = node.previous }
        node.previous = nil
        node.next = nil
        node.value = nil
        activeLease.retainedBaseValueCount -= 1
    }

    private func validateActiveTransaction(
        _ transaction: WorkspacePersistenceTransaction,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) -> Bool {
        transaction.processGeneration == revisionOwner.processGeneration
            && revisionOwner.validateActiveCommit(transaction) == .active
    }
}
