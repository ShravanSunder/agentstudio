import Foundation

struct WorkspaceStateSnapshotPagerIdentity: Hashable, Sendable {
    let rawValue: UUID

    static func make() -> Self {
        Self(rawValue: UUIDv7.generate())
    }
}

struct WorkspaceStateSnapshotLeaseID: Hashable, Sendable {
    let rawValue: UUID

    fileprivate static func make() -> Self {
        Self(rawValue: UUIDv7.generate())
    }
}

struct WorkspaceStateSnapshotPageID: Hashable, Sendable {
    let rawValue: UUID

    private init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    static func make() -> Self {
        Self(rawValue: UUIDv7.generate())
    }
}

struct WorkspaceStateSnapshotLease: Hashable, Sendable {
    let pagerIdentity: WorkspaceStateSnapshotPagerIdentity
    let leaseID: WorkspaceStateSnapshotLeaseID
    let processGeneration: WorkspacePersistenceProcessGeneration
    let baseRevision: WorkspacePersistenceRevision

    @MainActor
    static func open(
        pagerIdentity: WorkspaceStateSnapshotPagerIdentity,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) -> Self {
        precondition(
            UUIDv7.isV7(pagerIdentity.rawValue),
            "workspace snapshot pager identity must be UUIDv7"
        )
        return Self(
            pagerIdentity: pagerIdentity,
            leaseID: .make(),
            processGeneration: revisionOwner.processGeneration,
            baseRevision: revisionOwner.committedRevision
        )
    }
}

enum WorkspaceStateSnapshotStoredValue<Value: Sendable>: Sendable {
    case value(Value)
    case absent
}

extension WorkspaceStateSnapshotStoredValue: Equatable where Value: Equatable {}

enum WorkspaceStateSnapshotParticipantRejection: Error, Equatable, Sendable {
    case activeLeaseExists
    case cleanupPending
    case cleanupValueCountOverflow
    case cleanupValueReleaseExceedsBudget
    case baseKeyAlreadyCopied
    case baseMembershipKeyCountCapacityExceeded
    case baseMembershipRawByteCapacityExceeded
    case baseMembershipRawByteCountOverflow
    case baseMembershipValueMissing
    case baseValueCopiedByDifferentPage
    case duplicateBaseMembershipKey
    case duplicateCurrentKey
    case foreignLease
    case foreignProcessGeneration
    case keyNotInBaseMembership
    case membershipLimitsUnavailable
    case membershipLimitsMismatch
    case physicalSlotCapacityExceeded
    case currentKeyMissing
    case noActiveLease
    case transactionNotActive
    case transactionDoesNotFollowBaseRevision
    case staleBaseCopyToken
}

struct WorkspaceStateSnapshotMembershipLimits: Equatable, Sendable {
    let maximumKeyCount: UInt64
    let maximumRawKeyBytes: UInt64
}

enum WorkspaceStateSnapshotParticipantOpenResult: Equatable, Sendable {
    case opened(baseMembershipCount: Int)
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

enum WorkspaceStateSnapshotMembershipRegistrationResult: Equatable, Sendable {
    case registered
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

enum SnapshotMembershipConfigurationResult: Equatable, Sendable {
    case configured
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

enum WorkspaceStateSnapshotMembershipMutationResult: Equatable, Sendable {
    case inserted
    case removed
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

enum WorkspaceStateSnapshotMembershipResult<Key: Hashable & Sendable>: Sendable {
    case membership([Key])
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

extension WorkspaceStateSnapshotMembershipResult: Equatable where Key: Equatable {}

enum WorkspaceStateSnapshotMutationResult: Equatable, Sendable {
    case noRetentionRequired
    case retainedFirstBaseValue
    case baseValueAlreadyRetained
    case baseValueAlreadyCopied
    case postBaseKeyExcluded
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

enum WorkspaceStateSnapshotBaseValueReadResult<Value: Sendable>: Sendable {
    case read(WorkspaceStateSnapshotStoredValue<Value>)
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

extension WorkspaceStateSnapshotBaseValueReadResult: Equatable where Value: Equatable {}

enum WorkspaceStateSnapshotMarkCopiedResult: Equatable, Sendable {
    case markedCopied
    case alreadyMarkedCopied
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

struct WorkspaceStateSnapshotParticipantDiagnostics: Equatable, Sendable {
    let baseMembershipCount: Int
    let copiedBaseValueCount: Int
    let retainedBaseValueCount: Int
    let physicalSlotCount: Int
    let reusableSlotCount: Int
    let cleanupRetainedValueCount: Int
}

struct WorkspaceStateSnapshotParticipantWorkDiagnostics: Equatable, Sendable {
    let leaseOpenCount: UInt64
    let leaseOpenSlotInspectionCount: UInt64
    let leaseOpenRawKeyByteComputationCount: UInt64
}

enum WorkspaceStateSnapshotParticipantDiagnosticsResult: Equatable, Sendable {
    case diagnostics(WorkspaceStateSnapshotParticipantDiagnostics)
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

struct WorkspaceStateSnapshotParticipantCloseReceipt: Equatable, Sendable {
    let releasedMembershipCount: Int
    let releasedBaseValueCount: Int
}

enum WorkspaceStateSnapshotParticipantCloseResult: Equatable, Sendable {
    case closed(WorkspaceStateSnapshotParticipantCloseReceipt)
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

enum WorkspaceStateSnapshotBaseSlotInspection<Key: Sendable, Value: Sendable>: Sendable {
    case item(
        key: Key,
        value: Value,
        copyToken: WorkspaceStateSnapshotBaseCopyToken,
        nextSlotCursor: Int
    )
    case skipped(nextSlotCursor: Int)
    case exhausted
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

enum WorkspaceStateSnapshotCleanupDrainResult: Equatable, Sendable {
    case drained(releasedValueCount: Int, remainingValueCount: Int)
    case complete
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}
