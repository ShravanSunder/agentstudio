import Foundation

enum WorkspaceActiveArrangementPersistenceOperation: Equatable, Sendable {
    case set(tabID: UUID, arrangementID: UUID)
    case remove(tabID: UUID)
}

enum WorkspaceActivePanePersistenceOperation: Equatable, Sendable {
    case set(arrangementID: UUID, paneID: UUID)
    case clearSelection(arrangementID: UUID)
    case removeCursor(arrangementID: UUID)
}

enum WorkspaceActiveDrawerChildPersistenceOperation: Equatable, Sendable {
    case set(key: ArrangementDrawerCursorKey, childPaneID: UUID)
    case clearSelection(key: ArrangementDrawerCursorKey)
    case removeCursor(key: ArrangementDrawerCursorKey)
}

struct WorkspaceArrangementCursorPersistenceOperations: Equatable, Sendable {
    let activeArrangements: [WorkspaceActiveArrangementPersistenceOperation]
    let activePanes: [WorkspaceActivePanePersistenceOperation]
    let activeDrawerChildren: [WorkspaceActiveDrawerChildPersistenceOperation]
}

enum ArrangementCursorPreparationError: Error, Equatable {
    case duplicateActiveArrangementOperation(UUID)
    case duplicateActiveDrawerChildOperation(ArrangementDrawerCursorKey)
    case duplicateActivePaneOperation(UUID)
    case ownerRegistration(WorkspaceParticipantRegistrationRejection)
    case snapshotParticipant(WorkspaceStateSnapshotParticipantRejection)
    case snapshotPreparation(WorkspaceSnapshotPreparationRejection)
}

struct WorkspaceArrangementCursorSnapshotParticipants {
    let activeArrangements:
        WorkspaceStateSnapshotPagerParticipant<
            WorkspacePersistenceSnapshotParticipantID,
            WorkspacePersistenceSnapshotItem
        >
    let activePanes:
        WorkspaceStateSnapshotPagerParticipant<
            WorkspacePersistenceSnapshotParticipantID,
            WorkspacePersistenceSnapshotItem
        >
    let activeDrawerChildren:
        WorkspaceStateSnapshotPagerParticipant<
            WorkspacePersistenceSnapshotParticipantID,
            WorkspacePersistenceSnapshotItem
        >
}

enum ArrangementCursorParticipantsResult {
    case constructed(WorkspaceArrangementCursorSnapshotParticipants)
    case rejected(WorkspaceStateSnapshotParticipantRejection)
}

private struct ArrangementCursorPreparedMutation {
    let transaction: WorkspacePersistenceTransaction
    let activeArrangementIdsByTabId: [UUID: UUID]
    let paneCursorsByArrangementId: [UUID: ArrangementPaneCursorState]
    let drawerCursorsByKey: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState]
}

@MainActor
final class WorkspaceArrangementCursorPersistenceAdapter {
    private let atom: WorkspaceArrangementCursorAtom
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let activeArrangementSnapshotParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, UUID>()
    private let activePaneSnapshotParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, UUID>()
    private let activeDrawerChildSnapshotParticipant = WorkspaceStateSnapshotKeyedParticipant<
        ArrangementDrawerCursorKey,
        UUID
    >()

    init(atom: WorkspaceArrangementCursorAtom, revisionOwner: WorkspacePersistenceRevisionOwner) {
        self.atom = atom
        self.revisionOwner = revisionOwner
    }

    func makeSnapshotParticipants(
        limits: WorkspaceStateSnapshotMembershipLimits
    ) -> ArrangementCursorParticipantsResult {
        let activeArrangements = makeActiveArrangementParticipant(limits: limits)
        guard case .constructed(let activeArrangementsParticipant) = activeArrangements else {
            return .rejected(Self.rejection(from: activeArrangements))
        }
        let activePanes = makeActivePaneParticipant(limits: limits)
        guard case .constructed(let activePanesParticipant) = activePanes else {
            return .rejected(Self.rejection(from: activePanes))
        }
        let activeDrawerChildren = makeActiveDrawerChildParticipant(limits: limits)
        guard case .constructed(let activeDrawerChildrenParticipant) = activeDrawerChildren else {
            return .rejected(Self.rejection(from: activeDrawerChildren))
        }
        return .constructed(
            WorkspaceArrangementCursorSnapshotParticipants(
                activeArrangements: activeArrangementsParticipant,
                activePanes: activePanesParticipant,
                activeDrawerChildren: activeDrawerChildrenParticipant
            )
        )
    }

    func preparePersistenceMutation(
        _ operations: WorkspaceArrangementCursorPersistenceOperations,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        try validateUniqueOperationKeys(operations)
        try prepare(
            activeArrangementSnapshotParticipant,
            mutations: makeActiveArrangementSnapshotMutations(operations.activeArrangements),
            preparation: preparation
        )
        try prepare(
            activePaneSnapshotParticipant,
            mutations: makeActivePaneSnapshotMutations(operations.activePanes),
            preparation: preparation
        )
        try prepare(
            activeDrawerChildSnapshotParticipant,
            mutations: makeActiveDrawerChildSnapshotMutations(operations.activeDrawerChildren),
            preparation: preparation
        )

        var activeArrangements = atom.activeArrangementIdsByTabId
        var paneCursors = atom.paneCursorsByArrangementId
        var drawerCursors = atom.drawerCursorsByKey
        Self.apply(
            operations,
            activeArrangements: &activeArrangements,
            paneCursors: &paneCursors,
            drawerCursors: &drawerCursors
        )
        try registerPreparedReplacement(
            activeArrangementIdsByTabId: activeArrangements,
            paneCursorsByArrangementId: paneCursors,
            drawerCursorsByKey: drawerCursors,
            for: preparation
        )
    }

    func prepareReplacement(
        activeArrangementIdsByTabId: [UUID: UUID],
        paneCursorsByArrangementId: [UUID: ArrangementPaneCursorState],
        drawerCursorsByKey: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState],
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        try prepare(
            activeArrangementSnapshotParticipant,
            mutations: Self.makeReplacementMutations(
                current: atom.activeArrangementIdsByTabId,
                replacement: activeArrangementIdsByTabId,
                rawKeyByteCount: 16
            ),
            preparation: preparation
        )
        try prepare(
            activePaneSnapshotParticipant,
            mutations: Self.makeReplacementMutations(
                current: atom.paneCursorsByArrangementId.compactMapValues(\.activePaneId),
                replacement: paneCursorsByArrangementId.compactMapValues(\.activePaneId),
                rawKeyByteCount: 16
            ),
            preparation: preparation
        )
        try prepare(
            activeDrawerChildSnapshotParticipant,
            mutations: Self.makeReplacementMutations(
                current: atom.drawerCursorsByKey.compactMapValues(\.activeChildId),
                replacement: drawerCursorsByKey.compactMapValues(\.activeChildId),
                rawKeyByteCount: 32
            ),
            preparation: preparation
        )
        try registerPreparedReplacement(
            activeArrangementIdsByTabId: activeArrangementIdsByTabId,
            paneCursorsByArrangementId: paneCursorsByArrangementId,
            drawerCursorsByKey: drawerCursorsByKey,
            for: preparation
        )
    }

    func registerInitialReplacement(
        token _: borrowing WorkspaceCompositionPreinstallToken,
        activeArrangementIdsByTabId: [UUID: UUID],
        paneCursorsByArrangementId: [UUID: ArrangementPaneCursorState],
        drawerCursorsByKey: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState],
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        try registerPreparedReplacement(
            activeArrangementIdsByTabId: activeArrangementIdsByTabId,
            paneCursorsByArrangementId: paneCursorsByArrangementId,
            drawerCursorsByKey: drawerCursorsByKey,
            for: preparation
        )
    }

    private func registerPreparedReplacement(
        activeArrangementIdsByTabId: [UUID: UUID],
        paneCursorsByArrangementId: [UUID: ArrangementPaneCursorState],
        drawerCursorsByKey: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState],
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        let preparedMutation = ArrangementCursorPreparedMutation(
            transaction: preparation.transaction,
            activeArrangementIdsByTabId: activeArrangementIdsByTabId,
            paneCursorsByArrangementId: paneCursorsByArrangementId,
            drawerCursorsByKey: drawerCursorsByKey
        )
        switch revisionOwner.registerPreparedParticipantMutation(
            participant: self,
            preparation: preparation,
            apply: { [atom, revisionOwner = self.revisionOwner] in
                precondition(
                    revisionOwner.validateActiveCommit(preparedMutation.transaction) == .active,
                    "arrangement cursor prepared mutation requires its exact active transaction"
                )
                atom.replaceCursors(
                    activeArrangementIdsByTabId: preparedMutation.activeArrangementIdsByTabId,
                    paneCursorsByArrangementId: preparedMutation.paneCursorsByArrangementId,
                    drawerCursorsByKey: preparedMutation.drawerCursorsByKey
                )
            },
            cancel: {}
        ) {
        case .registered:
            break
        case .rejected(let rejection):
            throw ArrangementCursorPreparationError.ownerRegistration(rejection)
        }
    }

    private func makeActiveArrangementParticipant(
        limits: WorkspaceStateSnapshotMembershipLimits
    ) -> SnapshotPagerParticipantConstructionResult<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    > {
        WorkspaceStateSnapshotPagerParticipant.typed(
            participantID: .activeArrangements,
            keyedParticipant: activeArrangementSnapshotParticipant,
            membershipLimits: limits,
            orderedBaseKeys: { [atom] in Array(atom.activeArrangementIdsByTabId.keys) },
            currentValue: { [atom] tabID in atom.activeArrangementId(forTab: tabID).map { .value($0) } ?? .absent },
            projection: WorkspaceStateSnapshotItemProjection(
                itemIDForKey: { .activeArrangement(tabID: $0) },
                projectItem: { tabID, arrangementID in
                    .init(item: .activeArrangement(tabID: tabID, arrangementID: arrangementID), estimatedByteCount: 32)
                }
            ),
            rawKeyByteCount: { _ in 16 }
        )
    }

    private func makeActivePaneParticipant(
        limits: WorkspaceStateSnapshotMembershipLimits
    ) -> SnapshotPagerParticipantConstructionResult<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    > {
        WorkspaceStateSnapshotPagerParticipant.typed(
            participantID: .activePanes,
            keyedParticipant: activePaneSnapshotParticipant,
            membershipLimits: limits,
            orderedBaseKeys: { [atom] in
                atom.paneCursorsByArrangementId.compactMap { $0.value.activePaneId == nil ? nil : $0.key }
            },
            currentValue: { [atom] arrangementID in
                atom.activePaneId(forArrangement: arrangementID).map { .value($0) } ?? .absent
            },
            projection: WorkspaceStateSnapshotItemProjection(
                itemIDForKey: { .activePane(arrangementID: $0) },
                projectItem: { arrangementID, paneID in
                    .init(item: .activePane(arrangementID: arrangementID, paneID: paneID), estimatedByteCount: 32)
                }
            ),
            rawKeyByteCount: { _ in 16 }
        )
    }

    private func makeActiveDrawerChildParticipant(
        limits: WorkspaceStateSnapshotMembershipLimits
    ) -> SnapshotPagerParticipantConstructionResult<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    > {
        WorkspaceStateSnapshotPagerParticipant.typed(
            participantID: .activeDrawerChildren,
            keyedParticipant: activeDrawerChildSnapshotParticipant,
            membershipLimits: limits,
            orderedBaseKeys: { [atom] in
                atom.drawerCursorsByKey.compactMap { $0.value.activeChildId == nil ? nil : $0.key }
            },
            currentValue: { [atom] key in
                atom.activeChildId(forArrangement: key.arrangementId, drawerId: key.drawerId).map { .value($0) }
                    ?? .absent
            },
            projection: WorkspaceStateSnapshotItemProjection(
                itemIDForKey: { .activeDrawerChild($0) },
                projectItem: { key, childPaneID in
                    .init(item: .activeDrawerChild(key: key, childPaneID: childPaneID), estimatedByteCount: 48)
                }
            ),
            rawKeyByteCount: { _ in 32 }
        )
    }

    private func validateUniqueOperationKeys(
        _ operations: WorkspaceArrangementCursorPersistenceOperations
    ) throws {
        var tabIDs = Set<UUID>()
        for operation in operations.activeArrangements {
            let tabID: UUID
            switch operation {
            case .set(let id, _), .remove(let id): tabID = id
            }
            guard tabIDs.insert(tabID).inserted else {
                throw ArrangementCursorPreparationError.duplicateActiveArrangementOperation(tabID)
            }
        }
        var arrangementIDs = Set<UUID>()
        for operation in operations.activePanes {
            let arrangementID: UUID
            switch operation {
            case .set(let id, _), .clearSelection(let id), .removeCursor(let id): arrangementID = id
            }
            guard arrangementIDs.insert(arrangementID).inserted else {
                throw ArrangementCursorPreparationError.duplicateActivePaneOperation(arrangementID)
            }
        }
        var drawerKeys = Set<ArrangementDrawerCursorKey>()
        for operation in operations.activeDrawerChildren {
            let key: ArrangementDrawerCursorKey
            switch operation {
            case .set(let value, _), .clearSelection(let value), .removeCursor(let value): key = value
            }
            guard drawerKeys.insert(key).inserted else {
                throw ArrangementCursorPreparationError.duplicateActiveDrawerChildOperation(key)
            }
        }
    }

    private func makeActiveArrangementSnapshotMutations(
        _ operations: [WorkspaceActiveArrangementPersistenceOperation]
    ) -> [WorkspaceStateSnapshotParticipantMutation<UUID, UUID>] {
        operations.compactMap { operation in
            switch operation {
            case .set(let tabID, _):
                if let current = atom.activeArrangementId(forTab: tabID) {
                    return .replaceValue(key: tabID, currentValue: .value(current))
                }
                return .insert(.init(key: tabID, rawKeyByteCount: 16))
            case .remove(let tabID):
                guard let current = atom.activeArrangementId(forTab: tabID) else { return nil }
                return .remove(.init(key: tabID, currentValue: .value(current)))
            }
        }
    }

    private func makeActivePaneSnapshotMutations(
        _ operations: [WorkspaceActivePanePersistenceOperation]
    ) -> [WorkspaceStateSnapshotParticipantMutation<UUID, UUID>] {
        operations.compactMap { operation in
            switch operation {
            case .set(let arrangementID, _):
                if let current = atom.activePaneId(forArrangement: arrangementID) {
                    return .replaceValue(key: arrangementID, currentValue: .value(current))
                }
                return .insert(.init(key: arrangementID, rawKeyByteCount: 16))
            case .clearSelection(let arrangementID), .removeCursor(let arrangementID):
                guard let current = atom.activePaneId(forArrangement: arrangementID) else { return nil }
                return .remove(.init(key: arrangementID, currentValue: .value(current)))
            }
        }
    }

    private func makeActiveDrawerChildSnapshotMutations(
        _ operations: [WorkspaceActiveDrawerChildPersistenceOperation]
    ) -> [WorkspaceStateSnapshotParticipantMutation<ArrangementDrawerCursorKey, UUID>] {
        operations.compactMap { operation in
            switch operation {
            case .set(let key, _):
                if let current = atom.activeChildId(forArrangement: key.arrangementId, drawerId: key.drawerId) {
                    return .replaceValue(key: key, currentValue: .value(current))
                }
                return .insert(.init(key: key, rawKeyByteCount: 32))
            case .clearSelection(let key), .removeCursor(let key):
                guard let current = atom.activeChildId(forArrangement: key.arrangementId, drawerId: key.drawerId) else {
                    return nil
                }
                return .remove(.init(key: key, currentValue: .value(current)))
            }
        }
    }

    private func prepare<Key: Hashable & Sendable>(
        _ participant: WorkspaceStateSnapshotKeyedParticipant<Key, UUID>,
        mutations: [WorkspaceStateSnapshotParticipantMutation<Key, UUID>],
        preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        guard !mutations.isEmpty else { return }
        switch participant.prepare(mutations, for: preparation, revisionOwner: revisionOwner) {
        case .prepared:
            break
        case .rejected(let rejection):
            throw ArrangementCursorPreparationError.snapshotPreparation(rejection)
        }
    }

    private static func apply(
        _ operations: WorkspaceArrangementCursorPersistenceOperations,
        activeArrangements: inout [UUID: UUID],
        paneCursors: inout [UUID: ArrangementPaneCursorState],
        drawerCursors: inout [ArrangementDrawerCursorKey: ArrangementDrawerCursorState]
    ) {
        for operation in operations.activeArrangements {
            switch operation {
            case .set(let tabID, let arrangementID): activeArrangements[tabID] = arrangementID
            case .remove(let tabID): activeArrangements.removeValue(forKey: tabID)
            }
        }
        for operation in operations.activePanes {
            switch operation {
            case .set(let arrangementID, let paneID): paneCursors[arrangementID] = .init(activePaneId: paneID)
            case .clearSelection(let arrangementID): paneCursors[arrangementID] = .init(activePaneId: nil)
            case .removeCursor(let arrangementID): paneCursors.removeValue(forKey: arrangementID)
            }
        }
        for operation in operations.activeDrawerChildren {
            switch operation {
            case .set(let key, let childPaneID): drawerCursors[key] = .init(activeChildId: childPaneID)
            case .clearSelection(let key): drawerCursors[key] = .init(activeChildId: nil)
            case .removeCursor(let key): drawerCursors.removeValue(forKey: key)
            }
        }
    }

    private static func makeReplacementMutations<Key: Hashable & Sendable>(
        current: [Key: UUID],
        replacement: [Key: UUID],
        rawKeyByteCount: UInt64
    ) -> [WorkspaceStateSnapshotParticipantMutation<Key, UUID>] {
        var mutations: [WorkspaceStateSnapshotParticipantMutation<Key, UUID>] = []
        mutations.reserveCapacity(current.count + replacement.count)
        for (key, currentValue) in current {
            guard let replacementValue = replacement[key] else {
                mutations.append(.remove(.init(key: key, currentValue: .value(currentValue))))
                continue
            }
            if replacementValue != currentValue {
                mutations.append(.replaceValue(key: key, currentValue: .value(currentValue)))
            }
        }
        for key in replacement.keys where current[key] == nil {
            mutations.append(.insert(.init(key: key, rawKeyByteCount: rawKeyByteCount)))
        }
        return mutations
    }

    private static func rejection(
        from result: SnapshotPagerParticipantConstructionResult<
            WorkspacePersistenceSnapshotParticipantID,
            WorkspacePersistenceSnapshotItem
        >
    ) -> WorkspaceStateSnapshotParticipantRejection {
        guard case .rejected(let rejection) = result else {
            preconditionFailure("constructed snapshot participant has no rejection")
        }
        return rejection
    }
}
