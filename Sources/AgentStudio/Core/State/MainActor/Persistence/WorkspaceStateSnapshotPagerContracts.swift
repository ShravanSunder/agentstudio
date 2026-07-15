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
    associatedtype SnapshotItemID: Hashable, Sendable

    var snapshotItemID: SnapshotItemID { get }
}

struct WorkspaceStateSnapshotPageItem<
    ParticipantID: Hashable & Sendable,
    Item: WorkspaceStateSnapshotIdentifiedItem
>: Sendable {
    let participantID: ParticipantID
    let item: Item
    let byteCount: Int

    var itemID: Item.SnapshotItemID {
        item.snapshotItemID
    }
}

extension WorkspaceStateSnapshotPageItem: Equatable
where ParticipantID: Equatable, Item: Equatable {}

struct WorkspaceStateSnapshotPage<
    ParticipantID: Hashable & Sendable,
    Item: WorkspaceStateSnapshotIdentifiedItem
>: Sendable {
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

enum WorkspaceStateSnapshotPageTakeResult<
    ParticipantID: Hashable & Sendable,
    Item: WorkspaceStateSnapshotIdentifiedItem
>: Sendable {
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
struct WorkspaceStateSnapshotPagerParticipant<
    ParticipantID: Hashable & Sendable,
    Item: WorkspaceStateSnapshotIdentifiedItem
> {
    let participantID: ParticipantID
    private let openAction:
        (WorkspaceStateSnapshotLease, WorkspaceStateSnapshotMembershipLimits) ->
            WorkspaceStateSnapshotParticipantOpenResult
    private let membershipCountAction: (WorkspaceStateSnapshotLease) -> WorkspaceStateSnapshotPagerMembershipCountResult
    private let captureItemAction:
        (WorkspaceStateSnapshotLease, Int) ->
            WorkspaceStateSnapshotPagerItemCaptureResult<Item>
    private let markBaseValueCopiedAction:
        (WorkspaceStateSnapshotLease, Int, WorkspaceStateSnapshotPageID) ->
            WorkspaceStateSnapshotMarkCopiedResult
    private let closeAction: (WorkspaceStateSnapshotLease) -> WorkspaceStateSnapshotParticipantCloseResult

    static func typed<OwnerKey: Hashable & Sendable, OwnerValue: Sendable>(
        participantID: ParticipantID,
        keyedParticipant: WorkspaceStateSnapshotKeyedParticipant<OwnerKey, OwnerValue>,
        orderedBaseKeys: @escaping () -> [OwnerKey],
        currentValue: @escaping (OwnerKey) -> WorkspaceStateSnapshotStoredValue<OwnerValue>,
        projectItem:
            @escaping (OwnerKey, OwnerValue) ->
            WorkspaceStateSnapshotPagerTypedItem<Item>,
        rawKeyByteCount: @escaping (OwnerKey) -> UInt64 = { _ in 1 }
    ) -> Self {
        Self(
            participantID: participantID,
            openAction: { lease, limits in
                keyedParticipant.open(
                    lease: lease,
                    orderedBaseKeys: orderedBaseKeys(),
                    limits: limits,
                    rawByteCountForKey: rawKeyByteCount
                )
            },
            membershipCountAction: { lease in
                switch keyedParticipant.membership(for: lease) {
                case .membership(let membership):
                    .count(membership.count)
                case .rejected(let rejection):
                    .rejected(rejection)
                }
            },
            captureItemAction: { lease, membershipOffset in
                let membership: [OwnerKey]
                switch keyedParticipant.membership(for: lease) {
                case .membership(let activeMembership):
                    membership = activeMembership
                case .rejected(let rejection):
                    return .rejected(rejection)
                }
                precondition(
                    membership.indices.contains(membershipOffset),
                    "snapshot pager membership offset must be in bounds"
                )
                let ownerKey = membership[membershipOffset]
                let readResult = keyedParticipant.readBaseValue(
                    lease: lease,
                    key: ownerKey,
                    currentValue: currentValue(ownerKey)
                )
                guard case .read(.value(let ownerValue)) = readResult else {
                    guard case .rejected(let rejection) = readResult else {
                        preconditionFailure("base membership values must be present")
                    }
                    return .rejected(rejection)
                }
                let projectedItem = projectItem(ownerKey, ownerValue)
                return .captured(projectedItem)
            },
            markBaseValueCopiedAction: { lease, membershipOffset, pageID in
                let membership: [OwnerKey]
                switch keyedParticipant.membership(for: lease) {
                case .membership(let activeMembership):
                    membership = activeMembership
                case .rejected(let rejection):
                    return .rejected(rejection)
                }
                precondition(
                    membership.indices.contains(membershipOffset),
                    "snapshot pager membership offset must be in bounds"
                )
                return keyedParticipant.markBaseValueCopied(
                    lease: lease,
                    key: membership[membershipOffset],
                    pageID: pageID
                )
            },
            closeAction: { lease in keyedParticipant.close(lease: lease) }
        )
    }

    func open(
        lease: WorkspaceStateSnapshotLease,
        limits: WorkspaceStateSnapshotMembershipLimits
    ) -> WorkspaceStateSnapshotParticipantOpenResult {
        openAction(lease, limits)
    }

    func membershipCount(
        for lease: WorkspaceStateSnapshotLease
    ) -> WorkspaceStateSnapshotPagerMembershipCountResult {
        membershipCountAction(lease)
    }

    func captureItem(
        lease: WorkspaceStateSnapshotLease,
        membershipOffset: Int
    ) -> WorkspaceStateSnapshotPagerItemCaptureResult<Item> {
        captureItemAction(lease, membershipOffset)
    }

    func markBaseValueCopied(
        lease: WorkspaceStateSnapshotLease,
        membershipOffset: Int,
        pageID: WorkspaceStateSnapshotPageID
    ) -> WorkspaceStateSnapshotMarkCopiedResult {
        markBaseValueCopiedAction(lease, membershipOffset, pageID)
    }

    func close(
        lease: WorkspaceStateSnapshotLease
    ) -> WorkspaceStateSnapshotParticipantCloseResult {
        closeAction(lease)
    }
}

enum WorkspaceStateSnapshotPagerMembershipCountResult: Equatable, Sendable {
    case count(Int)
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

enum WorkspaceStateSnapshotPagerItemCaptureResult<
    Item: WorkspaceStateSnapshotIdentifiedItem
>: Sendable {
    case captured(WorkspaceStateSnapshotPagerTypedItem<Item>)
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

struct WorkspaceStateSnapshotPagerTypedItem<
    Item: WorkspaceStateSnapshotIdentifiedItem
>: Sendable {
    let item: Item
    let estimatedByteCount: Int
}
