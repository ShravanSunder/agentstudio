struct SnapshotProjectedMembership<Key: Hashable & Sendable> {
    private enum ProjectedKeyState {
        case present(rawKeyByteCount: UInt64)
        case absent
    }

    private let baselineRawKeyByteCount: (Key) -> UInt64?
    private var projectedKeyStateByKey: [Key: ProjectedKeyState] = [:]
    var keyCount: UInt64
    var totalRawKeyByteCount: UInt64
    var physicalSlotCount: UInt64
    var reusableSlotCount: UInt64

    init(
        keyCount: UInt64,
        totalRawKeyByteCount: UInt64,
        physicalSlotCount: UInt64,
        reusableSlotCount: UInt64,
        baselineRawKeyByteCount: @escaping (Key) -> UInt64?
    ) {
        self.baselineRawKeyByteCount = baselineRawKeyByteCount
        self.keyCount = keyCount
        self.totalRawKeyByteCount = totalRawKeyByteCount
        self.physicalSlotCount = physicalSlotCount
        self.reusableSlotCount = reusableSlotCount
    }

    func rawKeyByteCount(for key: Key) -> UInt64? {
        if let projectedKeyState = projectedKeyStateByKey[key] {
            switch projectedKeyState {
            case .present(let rawKeyByteCount): rawKeyByteCount
            case .absent: nil
            }
        } else {
            baselineRawKeyByteCount(key)
        }
    }

    mutating func remove(key: Key, makesSlotReusable: Bool) {
        guard let rawKeyByteCount = rawKeyByteCount(for: key) else {
            preconditionFailure("validated prepared removal lost projected membership")
        }
        projectedKeyStateByKey[key] = .absent
        keyCount -= 1
        totalRawKeyByteCount -= rawKeyByteCount
        if makesSlotReusable { reusableSlotCount += 1 }
    }

    mutating func insert(_ insertion: WorkspaceStateSnapshotMembershipInsertion<Key>) {
        projectedKeyStateByKey[insertion.key] = .present(rawKeyByteCount: insertion.rawKeyByteCount)
        keyCount += 1
        totalRawKeyByteCount += insertion.rawKeyByteCount
        if reusableSlotCount > 0 { reusableSlotCount -= 1 } else { physicalSlotCount += 1 }
    }
}

struct SnapshotRemovalProjection: Sendable {
    let makesSlotReusable: Bool
}

enum SnapshotParticipantMutationPlanner {
    static func validate<Key: Hashable & Sendable, Value: Sendable>(
        _ mutations: [WorkspaceStateSnapshotParticipantMutation<Key, Value>],
        limits: WorkspaceStateSnapshotMembershipLimits?,
        projectedMembership: inout SnapshotProjectedMembership<Key>,
        validateValueReplacement: (Key, WorkspaceStateSnapshotStoredValue<Value>)
            -> WorkspaceStateSnapshotParticipantRejection?,
        removalValidator: (WorkspaceStateSnapshotMembershipRemoval<Key, Value>)
            -> Result<SnapshotRemovalProjection, WorkspaceStateSnapshotParticipantRejection>
    ) -> WorkspaceStateSnapshotParticipantRejection? {
        var preparedKeys = Set<Key>()
        for mutation in mutations {
            switch mutation {
            case .replaceValue(let key, let currentValue):
                guard preparedKeys.insert(key).inserted else { return .duplicatePreparedMutationKey }
                if let rejection = validateValueReplacement(key, currentValue) { return rejection }
            case .insert(let insertion):
                guard preparedKeys.insert(insertion.key).inserted else { return .duplicatePreparedMutationKey }
                if let rejection = validateInsertion(insertion, limits: limits, membership: &projectedMembership) {
                    return rejection
                }
            case .remove(let removal):
                guard preparedKeys.insert(removal.key).inserted else { return .duplicatePreparedMutationKey }
                if let rejection = validateRemoval(removal, membership: &projectedMembership) { return rejection }
            case .replaceMembership(let removal, let insertion):
                let keys = removal.key == insertion.key ? [removal.key] : [removal.key, insertion.key]
                guard keys.allSatisfy({ preparedKeys.insert($0).inserted }) else {
                    return .duplicatePreparedMutationKey
                }
                if let rejection = validateRemoval(removal, membership: &projectedMembership) { return rejection }
                if let rejection = validateInsertion(insertion, limits: limits, membership: &projectedMembership) {
                    return rejection
                }
            }
        }
        return nil

        func validateRemoval(
            _ removal: WorkspaceStateSnapshotMembershipRemoval<Key, Value>,
            membership: inout SnapshotProjectedMembership<Key>
        ) -> WorkspaceStateSnapshotParticipantRejection? {
            switch removalValidator(removal) {
            case .success(let projection):
                membership.remove(key: removal.key, makesSlotReusable: projection.makesSlotReusable)
                return nil
            case .failure(let rejection): return rejection
            }
        }
    }

    private static func validateInsertion<Key: Hashable & Sendable>(
        _ insertion: WorkspaceStateSnapshotMembershipInsertion<Key>,
        limits: WorkspaceStateSnapshotMembershipLimits?,
        membership: inout SnapshotProjectedMembership<Key>
    ) -> WorkspaceStateSnapshotParticipantRejection? {
        guard membership.rawKeyByteCount(for: insertion.key) == nil else { return .duplicateCurrentKey }
        guard let limits else { return .membershipLimitsUnavailable }
        guard membership.keyCount < limits.maximumKeyCount else {
            return .baseMembershipKeyCountCapacityExceeded
        }
        let projectedRawBytes = membership.totalRawKeyByteCount.addingReportingOverflow(insertion.rawKeyByteCount)
        guard !projectedRawBytes.overflow else { return .baseMembershipRawByteCountOverflow }
        guard projectedRawBytes.partialValue <= limits.maximumRawKeyBytes else {
            return .baseMembershipRawByteCapacityExceeded
        }
        if membership.reusableSlotCount == 0 {
            let capacity = limits.maximumKeyCount.multipliedReportingOverflow(by: 2)
            guard !capacity.overflow, membership.physicalSlotCount < capacity.partialValue else {
                return .physicalSlotCapacityExceeded
            }
        }
        membership.insert(insertion)
        return nil
    }
}
