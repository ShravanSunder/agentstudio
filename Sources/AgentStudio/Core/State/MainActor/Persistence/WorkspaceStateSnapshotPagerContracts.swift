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

struct WorkspaceStateSnapshotPageItem<
    ParticipantID: Hashable & Sendable,
    Key: Hashable & Sendable,
    Value: Sendable
>: Sendable {
    let participantID: ParticipantID
    let key: Key
    let storedValue: WorkspaceStateSnapshotStoredValue<Value>
    let byteCount: Int
}

extension WorkspaceStateSnapshotPageItem: Equatable
where ParticipantID: Equatable, Key: Equatable, Value: Equatable {}

struct WorkspaceStateSnapshotPage<
    ParticipantID: Hashable & Sendable,
    Key: Hashable & Sendable,
    Value: Sendable
>: Sendable {
    let pageID: WorkspaceStateSnapshotPageID
    let lease: WorkspaceStateSnapshotLease
    let participantID: ParticipantID
    let items: [WorkspaceStateSnapshotPageItem<ParticipantID, Key, Value>]
    let itemCount: Int
    let byteCount: Int

    let nextParticipantIndex: Int
    let nextMembershipOffset: Int
    let exhaustsLease: Bool
}

extension WorkspaceStateSnapshotPage: Equatable
where ParticipantID: Equatable, Key: Equatable, Value: Equatable {}

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
    Key: Hashable & Sendable
>: Equatable, Sendable {
    case foreignPager
    case noActiveLease
    case foreignLease
    case pageAlreadyOutstanding(pageID: WorkspaceStateSnapshotPageID)
    case itemExceedsByteLimit(
        participantID: ParticipantID,
        key: Key,
        itemBytes: Int,
        maximumBytes: Int
    )
    case invalidItemByteCount(participantID: ParticipantID, key: Key)
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
    Key: Hashable & Sendable,
    Value: Sendable
>: Sendable {
    case page(WorkspaceStateSnapshotPage<ParticipantID, Key, Value>)
    case replayed(WorkspaceStateSnapshotPage<ParticipantID, Key, Value>)
    case yielded(WorkspaceStateSnapshotPageProgressReceipt)
    case exhausted(WorkspaceStateSnapshotExhaustionReceipt)
    case rejected(WorkspaceStateSnapshotPageTakeRejection<ParticipantID, Key>)
}

extension WorkspaceStateSnapshotPageTakeResult: Equatable
where ParticipantID: Equatable, Key: Equatable, Value: Equatable {}

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
    Key: Hashable & Sendable,
    Value: Sendable
> {
    let participantID: ParticipantID
    let keyedParticipant: WorkspaceStateSnapshotKeyedParticipant<Key, Value>
    let orderedBaseKeys: () -> [Key]
    let currentValue: (Key) -> WorkspaceStateSnapshotStoredValue<Value>
    let estimatedByteCount: (Key, WorkspaceStateSnapshotStoredValue<Value>) -> Int
    let rawKeyByteCount: (Key) -> UInt64

    init(
        participantID: ParticipantID,
        keyedParticipant: WorkspaceStateSnapshotKeyedParticipant<Key, Value>,
        orderedBaseKeys: @escaping () -> [Key],
        currentValue: @escaping (Key) -> WorkspaceStateSnapshotStoredValue<Value>,
        estimatedByteCount:
            @escaping (
                Key,
                WorkspaceStateSnapshotStoredValue<Value>
            ) -> Int,
        rawKeyByteCount: @escaping (Key) -> UInt64 = { _ in 1 }
    ) {
        self.participantID = participantID
        self.keyedParticipant = keyedParticipant
        self.orderedBaseKeys = orderedBaseKeys
        self.currentValue = currentValue
        self.estimatedByteCount = estimatedByteCount
        self.rawKeyByteCount = rawKeyByteCount
    }
}
