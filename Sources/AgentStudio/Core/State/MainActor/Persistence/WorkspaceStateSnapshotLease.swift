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

enum WorkspaceStateSnapshotParticipantRejection: Equatable, Sendable {
    case activeLeaseExists
    case baseKeyAlreadyMaterialized
    case baseMembershipValueMissing
    case duplicateBaseMembershipKey
    case foreignLease
    case foreignProcessGeneration
    case keyNotInBaseMembership
    case noActiveLease
    case transactionNotActive
    case transactionDoesNotFollowBaseRevision
}

enum WorkspaceStateSnapshotParticipantOpenResult: Equatable, Sendable {
    case opened(baseMembershipCount: Int)
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

enum WorkspaceStateSnapshotMembershipResult<Key: Hashable & Sendable>: Sendable {
    case membership([Key])
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

extension WorkspaceStateSnapshotMembershipResult: Equatable where Key: Equatable {}

enum WorkspaceStateSnapshotMutationResult: Equatable, Sendable {
    case retainedFirstBaseValue
    case baseValueAlreadyRetained
    case baseValueAlreadyMaterialized
    case postBaseKeyExcluded
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

enum WorkspaceStateSnapshotMaterializationResult<Value: Sendable>: Sendable {
    case materialized(WorkspaceStateSnapshotStoredValue<Value>)
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

extension WorkspaceStateSnapshotMaterializationResult: Equatable where Value: Equatable {}

struct WorkspaceStateSnapshotParticipantDiagnostics: Equatable, Sendable {
    let baseMembershipCount: Int
    let materializedCount: Int
    let retainedBaseValueCount: Int
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

/// Owner-local fixed-base retention for one typed persistence key space.
///
/// This primitive stores only an independently built key vector plus the first
/// pre-change value for base keys that have not yet been copied into an
/// immutable pager page. It never retains an atom's fleet value collection.
@MainActor
final class WorkspaceStateSnapshotKeyedParticipant<
    Key: Hashable & Sendable,
    Value: Sendable
> {
    private struct ActiveLease {
        let lease: WorkspaceStateSnapshotLease
        let orderedBaseKeys: [Key]
        let baseKeySet: Set<Key>
        var materializedKeys: Set<Key>
        var retainedBaseValues: [Key: WorkspaceStateSnapshotStoredValue<Value>]
    }

    private var activeLease: ActiveLease?

    func open<BaseKeys: Sequence>(
        lease: WorkspaceStateSnapshotLease,
        orderedBaseKeys: BaseKeys
    ) -> WorkspaceStateSnapshotParticipantOpenResult where BaseKeys.Element == Key {
        guard activeLease == nil else {
            return .rejected(.activeLeaseExists)
        }

        // Build a fresh buffer deliberately. `Array(existingArray)` may retain
        // the caller's copy-on-write backing storage.
        var copiedKeys: [Key] = []
        var copiedKeySet = Set<Key>()
        for key in orderedBaseKeys {
            guard copiedKeySet.insert(key).inserted else {
                return .rejected(.duplicateBaseMembershipKey)
            }
            copiedKeys.append(key)
        }

        activeLease = ActiveLease(
            lease: lease,
            orderedBaseKeys: copiedKeys,
            baseKeySet: copiedKeySet,
            materializedKeys: [],
            retainedBaseValues: [:]
        )
        return .opened(baseMembershipCount: copiedKeys.count)
    }

    func membership(
        for lease: WorkspaceStateSnapshotLease
    ) -> WorkspaceStateSnapshotMembershipResult<Key> {
        guard let activeLease else {
            return .rejected(.noActiveLease)
        }
        guard activeLease.lease == lease else {
            return .rejected(.foreignLease)
        }
        return .membership(activeLease.orderedBaseKeys)
    }

    func recordWillChange(
        lease: WorkspaceStateSnapshotLease,
        key: Key,
        currentValue: @autoclosure () -> WorkspaceStateSnapshotStoredValue<Value>,
        transaction: WorkspacePersistenceTransaction,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) -> WorkspaceStateSnapshotMutationResult {
        guard var activeLease else {
            return .rejected(.noActiveLease)
        }
        guard activeLease.lease == lease else {
            return .rejected(.foreignLease)
        }
        guard transaction.processGeneration == lease.processGeneration else {
            return .rejected(.foreignProcessGeneration)
        }
        guard revisionOwner.validateActiveCommit(transaction) == .active else {
            return .rejected(.transactionNotActive)
        }
        guard
            transaction.expectedPreviousRevision >= lease.baseRevision,
            transaction.proposedRevision > lease.baseRevision
        else {
            return .rejected(.transactionDoesNotFollowBaseRevision)
        }
        guard activeLease.baseKeySet.contains(key) else {
            return .postBaseKeyExcluded
        }
        guard !activeLease.materializedKeys.contains(key) else {
            return .baseValueAlreadyMaterialized
        }
        guard activeLease.retainedBaseValues[key] == nil else {
            return .baseValueAlreadyRetained
        }
        let retainedBaseValue = currentValue()
        guard case .value = retainedBaseValue else {
            return .rejected(.baseMembershipValueMissing)
        }

        activeLease.retainedBaseValues[key] = retainedBaseValue
        self.activeLease = activeLease
        return .retainedFirstBaseValue
    }

    func materializeBaseValue(
        lease: WorkspaceStateSnapshotLease,
        key: Key,
        currentValue: @autoclosure () -> WorkspaceStateSnapshotStoredValue<Value>
    ) -> WorkspaceStateSnapshotMaterializationResult<Value> {
        guard var activeLease else {
            return .rejected(.noActiveLease)
        }
        guard activeLease.lease == lease else {
            return .rejected(.foreignLease)
        }
        guard activeLease.baseKeySet.contains(key) else {
            return .rejected(.keyNotInBaseMembership)
        }
        guard activeLease.materializedKeys.insert(key).inserted else {
            return .rejected(.baseKeyAlreadyMaterialized)
        }

        let baseValue = activeLease.retainedBaseValues.removeValue(forKey: key) ?? currentValue()
        self.activeLease = activeLease
        return .materialized(baseValue)
    }

    func diagnostics(
        for lease: WorkspaceStateSnapshotLease
    ) -> WorkspaceStateSnapshotParticipantDiagnosticsResult {
        guard let activeLease else {
            return .rejected(.noActiveLease)
        }
        guard activeLease.lease == lease else {
            return .rejected(.foreignLease)
        }
        return .diagnostics(
            WorkspaceStateSnapshotParticipantDiagnostics(
                baseMembershipCount: activeLease.orderedBaseKeys.count,
                materializedCount: activeLease.materializedKeys.count,
                retainedBaseValueCount: activeLease.retainedBaseValues.count
            )
        )
    }

    func close(
        lease: WorkspaceStateSnapshotLease
    ) -> WorkspaceStateSnapshotParticipantCloseResult {
        guard let activeLease else {
            return .rejected(.noActiveLease)
        }
        guard activeLease.lease == lease else {
            return .rejected(.foreignLease)
        }
        self.activeLease = nil
        return .closed(
            WorkspaceStateSnapshotParticipantCloseReceipt(
                releasedMembershipCount: activeLease.orderedBaseKeys.count,
                releasedBaseValueCount: activeLease.retainedBaseValues.count
            )
        )
    }
}
