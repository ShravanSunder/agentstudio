import Foundation

enum WorkspaceStateSnapshotPageLimit: Equatable, Sendable {
    case itemCount
    case participantInspectionCount
    case rawByteCount
    case scannedItemCount
    case synchronousService
}

enum WorkspaceStateSnapshotPageLimitsValidationError: Error, Equatable, Sendable {
    case nonPositive(WorkspaceStateSnapshotPageLimit)
}

enum WorkspaceStateSnapshotPageLimitsValidationResult: Equatable, Sendable {
    case valid(WorkspaceStateSnapshotPageLimits)
    case rejected(WorkspaceStateSnapshotPageLimitsValidationError)
}

struct WorkspaceStateSnapshotPageLimits: Equatable, Sendable {
    let maximumItems: Int
    let maximumBytes: Int
    let maximumScannedItems: Int
    let maximumParticipantInspections: Int
    let maximumSynchronousServiceNanoseconds: UInt64

    private init(
        maximumItems: Int,
        maximumBytes: Int,
        maximumScannedItems: Int,
        maximumParticipantInspections: Int,
        maximumSynchronousServiceNanoseconds: UInt64
    ) {
        self.maximumItems = maximumItems
        self.maximumBytes = maximumBytes
        self.maximumScannedItems = maximumScannedItems
        self.maximumParticipantInspections = maximumParticipantInspections
        self.maximumSynchronousServiceNanoseconds = maximumSynchronousServiceNanoseconds
    }

    static func validated(
        maximumItems: Int,
        maximumBytes: Int,
        maximumScannedItems: Int,
        maximumParticipantInspections: Int = 32,
        maximumSynchronousServiceNanoseconds: UInt64
    ) -> WorkspaceStateSnapshotPageLimitsValidationResult {
        guard maximumItems > 0 else { return .rejected(.nonPositive(.itemCount)) }
        guard maximumBytes > 0 else { return .rejected(.nonPositive(.rawByteCount)) }
        guard maximumScannedItems > 0 else {
            return .rejected(.nonPositive(.scannedItemCount))
        }
        guard maximumParticipantInspections > 0 else {
            return .rejected(.nonPositive(.participantInspectionCount))
        }
        guard maximumSynchronousServiceNanoseconds > 0 else {
            return .rejected(.nonPositive(.synchronousService))
        }
        return .valid(
            Self(
                maximumItems: maximumItems,
                maximumBytes: maximumBytes,
                maximumScannedItems: maximumScannedItems,
                maximumParticipantInspections: maximumParticipantInspections,
                maximumSynchronousServiceNanoseconds: maximumSynchronousServiceNanoseconds
            )
        )
    }
}

enum WorkspaceStateSnapshotPagerOpenRejection: Equatable, Sendable {
    case activeLeaseExists(activeLeaseID: WorkspaceStateSnapshotLeaseID)
    case cleanupPending
    case duplicateParticipantID
    case participantRejected(WorkspaceStateSnapshotParticipantRejection)
}

enum WorkspaceStateSnapshotPagerOpenResult: Equatable, Sendable {
    case opened(WorkspaceStateSnapshotLease)
    case rejected(WorkspaceStateSnapshotPagerOpenRejection)
}

enum WorkspaceStateSnapshotPageDisposition: Equatable, Sendable {
    case transferred
    case retry
}

enum WorkspaceStateSnapshotPagerCloseDisposition: Equatable, Sendable {
    case completed
    case abort
}

protocol WorkspaceStateSnapshotIdentifiedItem: Sendable {
    associatedtype SnapshotParticipantID: Hashable, Sendable
    associatedtype SnapshotItemID: Hashable, Sendable

    var snapshotParticipantID: SnapshotParticipantID { get }
    var snapshotItemID: SnapshotItemID { get }
}

struct WorkspaceStateSnapshotPageItem<
    ParticipantID: Hashable & Sendable,
    Item: WorkspaceStateSnapshotIdentifiedItem
>: Sendable where Item.SnapshotParticipantID == ParticipantID {
    let item: Item
    let byteCount: Int

    var participantID: ParticipantID {
        item.snapshotParticipantID
    }

    var itemID: Item.SnapshotItemID {
        item.snapshotItemID
    }
}

extension WorkspaceStateSnapshotPageItem: Equatable
where ParticipantID: Equatable, Item: Equatable {}

struct WorkspaceStateSnapshotPage<
    ParticipantID: Hashable & Sendable,
    Item: WorkspaceStateSnapshotIdentifiedItem
>: Sendable where Item.SnapshotParticipantID == ParticipantID {
    let pageID: WorkspaceStateSnapshotPageID
    let lease: WorkspaceStateSnapshotLease
    let participantID: ParticipantID
    let items: [WorkspaceStateSnapshotPageItem<ParticipantID, Item>]
    let itemCount: Int
    let byteCount: Int

    let nextParticipantIndex: Int
    let nextMembershipOffset: Int
    let exhaustsLease: Bool
}

extension WorkspaceStateSnapshotPage: Equatable
where ParticipantID: Equatable, Item: Equatable {}

struct WorkspaceStateSnapshotExhaustionReceipt: Equatable, Sendable {
    let lease: WorkspaceStateSnapshotLease
    let pageCount: UInt64
    let itemCount: UInt64
    let byteCount: UInt64
}

struct WorkspaceStateSnapshotPageProgressReceipt: Equatable, Sendable {
    let lease: WorkspaceStateSnapshotLease
    let nextParticipantIndex: Int
    let participantInspectionCount: Int
}

enum WorkspaceStateSnapshotPageTakeRejection<
    ParticipantID: Hashable & Sendable,
    ItemID: Hashable & Sendable
>: Equatable, Sendable {
    case foreignPager
    case noActiveLease
    case foreignLease
    case pageAlreadyOutstanding(pageID: WorkspaceStateSnapshotPageID)
    case itemExceedsByteLimit(
        participantID: ParticipantID,
        itemID: ItemID,
        itemBytes: Int,
        maximumBytes: Int
    )
    case invalidItemByteCount(participantID: ParticipantID, itemID: ItemID)
    case itemParticipantMismatch(
        expected: ParticipantID,
        actual: ParticipantID,
        itemID: ItemID
    )
    case itemIdentityMismatch(
        participantID: ParticipantID,
        expected: ItemID,
        actual: ItemID
    )
    case itemByteCountOverflow
    case scannedItemLimitReachedWithoutProgress
    case synchronousServiceLimitReachedWithoutProgress
    case participantRejected(WorkspaceStateSnapshotParticipantRejection)
    case participantCommitRejected(WorkspaceStateSnapshotParticipantRejection)
    case mainActorWorkRejected(MainActorWorkInvalidity)
}

enum WorkspaceStateSnapshotPageCaptureRequestResult: Sendable {
    case requested(WorkspaceStateSnapshotPageCaptureRequest)
    case rejected(MainActorWorkInvalidity)
}

enum WorkspaceStateSnapshotPagerCleanupDrainResult: Equatable, Sendable {
    case drained(releasedValueCount: Int, remainingValueCount: Int)
    case complete
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

enum WorkspaceStateSnapshotPageTakeResult<
    ParticipantID: Hashable & Sendable,
    Item: WorkspaceStateSnapshotIdentifiedItem
>: Sendable where Item.SnapshotParticipantID == ParticipantID {
    case page(WorkspaceStateSnapshotPage<ParticipantID, Item>)
    case replayed(WorkspaceStateSnapshotPage<ParticipantID, Item>)
    case yielded(WorkspaceStateSnapshotPageProgressReceipt)
    case exhausted(WorkspaceStateSnapshotExhaustionReceipt)
    case rejected(WorkspaceStateSnapshotPageTakeRejection<ParticipantID, Item.SnapshotItemID>)
}

extension WorkspaceStateSnapshotPageTakeResult: Equatable
where ParticipantID: Equatable, Item: Equatable {}

enum WorkspaceStateSnapshotPageAcknowledgementRejection: Equatable, Sendable {
    case noActiveLease
    case foreignLease
    case noPageOutstanding
    case pageMismatch(
        submitted: WorkspaceStateSnapshotPageID,
        outstanding: WorkspaceStateSnapshotPageID
    )
    case duplicateAcknowledgement(pageID: WorkspaceStateSnapshotPageID)
    case staleAcknowledgement(
        submitted: WorkspaceStateSnapshotPageID,
        outstanding: WorkspaceStateSnapshotPageID
    )
}

enum WorkspaceStateSnapshotPageAcknowledgementResult: Equatable, Sendable {
    case acknowledged(pageID: WorkspaceStateSnapshotPageID)
    case queuedForRetry(pageID: WorkspaceStateSnapshotPageID)
    case rejected(WorkspaceStateSnapshotPageAcknowledgementRejection)
}

struct WorkspaceStateSnapshotPagerCloseReceipt: Equatable, Sendable {
    let lease: WorkspaceStateSnapshotLease
    let disposition: WorkspaceStateSnapshotPagerCloseDisposition
    let releasedParticipantCount: Int
    let releasedMembershipCount: Int
    let releasedRetainedBaseValueCount: Int
}

enum WorkspaceStateSnapshotPagerCloseRejection: Equatable, Sendable {
    case noActiveLease
    case foreignLease
    case staleLease
    case pageOutstanding(pageID: WorkspaceStateSnapshotPageID)
    case participantsIncomplete
    case participantRejected(WorkspaceStateSnapshotParticipantRejection)
}

enum WorkspaceStateSnapshotPagerCloseResult: Equatable, Sendable {
    case completed(WorkspaceStateSnapshotPagerCloseReceipt)
    case aborted(WorkspaceStateSnapshotPagerCloseReceipt)
    case alreadyClosed(WorkspaceStateSnapshotPagerCloseReceipt)
    case rejected(WorkspaceStateSnapshotPagerCloseRejection)
}

@MainActor
final class WorkspaceStateSnapshotPagerLeaseAuthority {
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private(set) var activeLease: WorkspaceStateSnapshotLease?

    init(revisionOwner: WorkspacePersistenceRevisionOwner) {
        self.revisionOwner = revisionOwner
    }

    func open(
        pagerIdentity: WorkspaceStateSnapshotPagerIdentity,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) -> WorkspaceStateSnapshotPagerOpenResult {
        guard revisionOwner === self.revisionOwner else {
            preconditionFailure("snapshot pager and lease authority must share one revision owner")
        }
        if let activeLease {
            return .rejected(.activeLeaseExists(activeLeaseID: activeLease.leaseID))
        }
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: pagerIdentity,
            revisionOwner: revisionOwner
        )
        activeLease = lease
        return .opened(lease)
    }

    func release(_ lease: WorkspaceStateSnapshotLease) -> Bool {
        guard activeLease == lease else { return false }
        activeLease = nil
        return true
    }
}

@MainActor
struct WorkspaceStateSnapshotItemProjection<
    OwnerKey: Sendable,
    OwnerValue: Sendable,
    Item: WorkspaceStateSnapshotIdentifiedItem
> {
    let itemIDForKey: (OwnerKey) -> Item.SnapshotItemID
    let projectItem: (OwnerKey, OwnerValue) -> WorkspaceStateSnapshotPagerTypedItem<Item>
}

@MainActor
struct WorkspaceStateSnapshotPagerParticipant<
    ParticipantID: Hashable & Sendable,
    Item: WorkspaceStateSnapshotIdentifiedItem
> where Item.SnapshotParticipantID == ParticipantID {
    let participantID: ParticipantID
    private let membershipLimits: WorkspaceStateSnapshotMembershipLimits
    private let openAction:
        (WorkspaceStateSnapshotLease, WorkspaceStateSnapshotMembershipLimits) ->
            WorkspaceStateSnapshotParticipantOpenResult
    private let slotUpperBoundAction: (WorkspaceStateSnapshotLease) -> WorkspaceStateSnapshotPagerSlotUpperBoundResult
    private let inspectBaseSlotAction:
        (WorkspaceStateSnapshotLease, Int) ->
            WorkspaceStateSnapshotPagerSlotInspectionResult<Item>
    private let markBaseValueCopiedAction:
        (WorkspaceStateSnapshotLease, WorkspaceStateSnapshotBaseCopyToken, WorkspaceStateSnapshotPageID) ->
            WorkspaceStateSnapshotMarkCopiedResult
    private let closeAction: (WorkspaceStateSnapshotLease) -> WorkspaceStateSnapshotParticipantCloseResult
    private let drainCleanupAction: (Int) -> WorkspaceStateSnapshotCleanupDrainResult

    static func typed<OwnerKey: Hashable & Sendable, OwnerValue: Sendable>(
        participantID: ParticipantID,
        keyedParticipant: WorkspaceStateSnapshotKeyedParticipant<OwnerKey, OwnerValue>,
        membershipLimits: WorkspaceStateSnapshotMembershipLimits,
        orderedBaseKeys: @escaping () -> [OwnerKey],
        currentValue: @escaping (OwnerKey) -> WorkspaceStateSnapshotStoredValue<OwnerValue>,
        projection: WorkspaceStateSnapshotItemProjection<OwnerKey, OwnerValue, Item>,
        rawKeyByteCount: @escaping (OwnerKey) -> UInt64 = { _ in 1 }
    ) -> SnapshotPagerParticipantConstructionResult<ParticipantID, Item> {
        let initialMembership = orderedBaseKeys().map { ownerKey in
            (key: ownerKey, rawKeyByteCount: rawKeyByteCount(ownerKey))
        }
        switch keyedParticipant.registerInitialMembership(
            initialMembership,
            limits: membershipLimits
        ) {
        case .registered:
            break
        case .rejected(let rejection):
            return .rejected(rejection)
        }
        return .constructed(
            Self(
                participantID: participantID,
                membershipLimits: membershipLimits,
                openAction: { lease, limits in
                    keyedParticipant.open(
                        lease: lease,
                        limits: limits
                    )
                },
                slotUpperBoundAction: { lease in
                    switch keyedParticipant.baseSlotUpperBound(for: lease) {
                    case .success(let slotUpperBound):
                        .upperBound(slotUpperBound)
                    case .failure(let rejection):
                        .rejected(rejection)
                    }
                },
                inspectBaseSlotAction: { lease, slotCursor in
                    switch keyedParticipant.inspectBaseSlot(
                        lease: lease,
                        slotCursor: slotCursor,
                        currentValue: currentValue
                    ) {
                    case .item(let ownerKey, let ownerValue, let copyToken, let nextSlotCursor):
                        .item(
                            projection.projectItem(ownerKey, ownerValue),
                            expectedItemID: projection.itemIDForKey(ownerKey),
                            copyToken: copyToken,
                            nextSlotCursor: nextSlotCursor
                        )
                    case .skipped(let nextSlotCursor):
                        .skipped(nextSlotCursor: nextSlotCursor)
                    case .exhausted:
                        .exhausted
                    case .rejected(let rejection):
                        .rejected(rejection)
                    }
                },
                markBaseValueCopiedAction: { lease, copyToken, pageID in
                    keyedParticipant.markBaseValueCopied(
                        lease: lease,
                        copyToken: copyToken,
                        pageID: pageID
                    )
                },
                closeAction: { lease in keyedParticipant.close(lease: lease) },
                drainCleanupAction: { maximumValues in
                    keyedParticipant.drainCleanup(maximumValues: maximumValues)
                }
            ))
    }

    func open(lease: WorkspaceStateSnapshotLease) -> WorkspaceStateSnapshotParticipantOpenResult {
        openAction(lease, membershipLimits)
    }

    func slotUpperBound(
        for lease: WorkspaceStateSnapshotLease
    ) -> WorkspaceStateSnapshotPagerSlotUpperBoundResult {
        slotUpperBoundAction(lease)
    }

    func inspectBaseSlot(
        lease: WorkspaceStateSnapshotLease,
        slotCursor: Int
    ) -> WorkspaceStateSnapshotPagerSlotInspectionResult<Item> {
        inspectBaseSlotAction(lease, slotCursor)
    }

    func markBaseValueCopied(
        lease: WorkspaceStateSnapshotLease,
        copyToken: WorkspaceStateSnapshotBaseCopyToken,
        pageID: WorkspaceStateSnapshotPageID
    ) -> WorkspaceStateSnapshotMarkCopiedResult {
        markBaseValueCopiedAction(lease, copyToken, pageID)
    }

    func close(
        lease: WorkspaceStateSnapshotLease
    ) -> WorkspaceStateSnapshotParticipantCloseResult {
        closeAction(lease)
    }

    func drainCleanup(maximumValues: Int) -> WorkspaceStateSnapshotCleanupDrainResult {
        drainCleanupAction(maximumValues)
    }
}

@MainActor
enum SnapshotPagerParticipantConstructionResult<
    ParticipantID: Hashable & Sendable,
    Item: WorkspaceStateSnapshotIdentifiedItem
> where Item.SnapshotParticipantID == ParticipantID {
    case constructed(WorkspaceStateSnapshotPagerParticipant<ParticipantID, Item>)
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

enum WorkspaceStateSnapshotPagerSlotUpperBoundResult: Equatable, Sendable {
    case upperBound(Int)
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

enum WorkspaceStateSnapshotPagerSlotInspectionResult<
    Item: WorkspaceStateSnapshotIdentifiedItem
>: Sendable {
    case item(
        WorkspaceStateSnapshotPagerTypedItem<Item>,
        expectedItemID: Item.SnapshotItemID,
        copyToken: WorkspaceStateSnapshotBaseCopyToken,
        nextSlotCursor: Int
    )
    case skipped(nextSlotCursor: Int)
    case exhausted
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

struct WorkspaceStateSnapshotPagerTypedItem<
    Item: WorkspaceStateSnapshotIdentifiedItem
>: Sendable {
    let item: Item
    let estimatedByteCount: Int
}
