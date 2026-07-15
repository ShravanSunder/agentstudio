import Foundation
import Observation

struct ArrangementDrawerCursorKey: Hashable, Sendable {
    let arrangementId: UUID
    let drawerId: UUID
}

struct ArrangementPaneCursorState: Equatable, Hashable, Sendable {
    var activePaneId: UUID?
}

struct ArrangementDrawerCursorState: Equatable, Hashable, Sendable {
    var activeChildId: UUID?
}

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
    let operations: WorkspaceArrangementCursorPersistenceOperations
}

@MainActor
@Observable
final class WorkspaceArrangementCursorAtom {
    private(set) var activeArrangementIdsByTabId: [UUID: UUID] = [:]
    private(set) var paneCursorsByArrangementId: [UUID: ArrangementPaneCursorState] = [:]
    private(set) var drawerCursorsByKey: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState] = [:]
    private let activeArrangementSnapshotParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, UUID>()
    private let activePaneSnapshotParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, UUID>()
    private let activeDrawerChildSnapshotParticipant = WorkspaceStateSnapshotKeyedParticipant<
        ArrangementDrawerCursorKey,
        UUID
    >()

    func replaceStates(_ states: [TabArrangementState]) {
        var activeArrangementIdsByTabId: [UUID: UUID] = [:]
        var paneCursorsByArrangementId: [UUID: ArrangementPaneCursorState] = [:]
        var drawerCursorsByKey: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState] = [:]

        for state in states {
            activeArrangementIdsByTabId[state.tabId] = state.activeArrangementId
            for arrangement in state.arrangements {
                paneCursorsByArrangementId[arrangement.id] = ArrangementPaneCursorState(
                    activePaneId: arrangement.activePaneId
                )
                for (drawerId, drawerView) in arrangement.drawerViews {
                    drawerCursorsByKey[
                        ArrangementDrawerCursorKey(arrangementId: arrangement.id, drawerId: drawerId)
                    ] = ArrangementDrawerCursorState(activeChildId: drawerView.activeChildId)
                }
            }
        }

        guard
            self.activeArrangementIdsByTabId != activeArrangementIdsByTabId
                || self.paneCursorsByArrangementId != paneCursorsByArrangementId
                || self.drawerCursorsByKey != drawerCursorsByKey
        else { return }

        self.activeArrangementIdsByTabId = activeArrangementIdsByTabId
        self.paneCursorsByArrangementId = paneCursorsByArrangementId
        self.drawerCursorsByKey = drawerCursorsByKey
    }

    func activeArrangementId(forTab tabId: UUID) -> UUID? {
        activeArrangementIdsByTabId[tabId]
    }

    func activePaneId(forArrangement arrangementId: UUID) -> UUID? {
        paneCursorsByArrangementId[arrangementId]?.activePaneId
    }

    func activeChildId(forArrangement arrangementId: UUID, drawerId: UUID) -> UUID? {
        drawerCursorsByKey[ArrangementDrawerCursorKey(arrangementId: arrangementId, drawerId: drawerId)]?.activeChildId
    }

    func makePersistenceSnapshotParticipants(
        limits: WorkspaceStateSnapshotMembershipLimits
    ) -> ArrangementCursorParticipantsResult {
        let activeArrangements = WorkspaceStateSnapshotPagerParticipant<
            WorkspacePersistenceSnapshotParticipantID,
            WorkspacePersistenceSnapshotItem
        >.typed(
            participantID: .activeArrangements,
            keyedParticipant: activeArrangementSnapshotParticipant,
            membershipLimits: limits,
            orderedBaseKeys: { [self] in Array(activeArrangementIdsByTabId.keys) },
            currentValue: { [self] tabID in
                activeArrangementIdsByTabId[tabID].map { .value($0) } ?? .absent
            },
            projection: WorkspaceStateSnapshotItemProjection(
                itemIDForKey: { .activeArrangement(tabID: $0) },
                projectItem: { tabID, arrangementID in
                    WorkspaceStateSnapshotPagerTypedItem(
                        item: .activeArrangement(tabID: tabID, arrangementID: arrangementID),
                        estimatedByteCount: 32
                    )
                }
            ),
            rawKeyByteCount: { _ in 16 }
        )
        guard case .constructed(let activeArrangementsParticipant) = activeArrangements else {
            return .rejected(Self.rejection(from: activeArrangements))
        }

        let activePanes = WorkspaceStateSnapshotPagerParticipant<
            WorkspacePersistenceSnapshotParticipantID,
            WorkspacePersistenceSnapshotItem
        >.typed(
            participantID: .activePanes,
            keyedParticipant: activePaneSnapshotParticipant,
            membershipLimits: limits,
            orderedBaseKeys: { [self] in
                paneCursorsByArrangementId.compactMap { arrangementID, cursor in
                    cursor.activePaneId == nil ? nil : arrangementID
                }
            },
            currentValue: { [self] arrangementID in
                paneCursorsByArrangementId[arrangementID]?.activePaneId.map { .value($0) } ?? .absent
            },
            projection: WorkspaceStateSnapshotItemProjection(
                itemIDForKey: { .activePane(arrangementID: $0) },
                projectItem: { arrangementID, paneID in
                    WorkspaceStateSnapshotPagerTypedItem(
                        item: .activePane(arrangementID: arrangementID, paneID: paneID),
                        estimatedByteCount: 32
                    )
                }
            ),
            rawKeyByteCount: { _ in 16 }
        )
        guard case .constructed(let activePanesParticipant) = activePanes else {
            return .rejected(Self.rejection(from: activePanes))
        }

        let activeDrawerChildren = WorkspaceStateSnapshotPagerParticipant<
            WorkspacePersistenceSnapshotParticipantID,
            WorkspacePersistenceSnapshotItem
        >.typed(
            participantID: .activeDrawerChildren,
            keyedParticipant: activeDrawerChildSnapshotParticipant,
            membershipLimits: limits,
            orderedBaseKeys: { [self] in
                drawerCursorsByKey.compactMap { key, cursor in
                    cursor.activeChildId == nil ? nil : key
                }
            },
            currentValue: { [self] key in
                drawerCursorsByKey[key]?.activeChildId.map { .value($0) } ?? .absent
            },
            projection: WorkspaceStateSnapshotItemProjection(
                itemIDForKey: { .activeDrawerChild($0) },
                projectItem: { key, childPaneID in
                    WorkspaceStateSnapshotPagerTypedItem(
                        item: .activeDrawerChild(key: key, childPaneID: childPaneID),
                        estimatedByteCount: 48
                    )
                }
            ),
            rawKeyByteCount: { _ in 32 }
        )
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
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws {
        try validateUniqueOperationKeys(operations)
        let activeArrangementMutations = makeActiveArrangementSnapshotMutations(operations.activeArrangements)
        let activePaneMutations = makeActivePaneSnapshotMutations(operations.activePanes)
        let activeDrawerChildMutations = makeActiveDrawerChildSnapshotMutations(operations.activeDrawerChildren)

        try prepare(
            activeArrangementSnapshotParticipant,
            mutations: activeArrangementMutations,
            preparation: preparation,
            revisionOwner: revisionOwner
        )
        try prepare(
            activePaneSnapshotParticipant,
            mutations: activePaneMutations,
            preparation: preparation,
            revisionOwner: revisionOwner
        )
        try prepare(
            activeDrawerChildSnapshotParticipant,
            mutations: activeDrawerChildMutations,
            preparation: preparation,
            revisionOwner: revisionOwner
        )

        let preparedMutation = ArrangementCursorPreparedMutation(
            transaction: preparation.transaction,
            operations: operations
        )
        switch revisionOwner.registerPreparedParticipantMutation(
            participant: self,
            preparation: preparation,
            apply: { [self] in applyPreparedPersistenceMutation(preparedMutation, revisionOwner: revisionOwner) },
            cancel: {}
        ) {
        case .registered:
            break
        case .rejected(let rejection):
            throw ArrangementCursorPreparationError.ownerRegistration(rejection)
        }
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
                if let current = activeArrangementIdsByTabId[tabID] {
                    return .replaceValue(key: tabID, currentValue: .value(current))
                }
                return .insert(.init(key: tabID, rawKeyByteCount: 16))
            case .remove(let tabID):
                guard let current = activeArrangementIdsByTabId[tabID] else { return nil }
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
                if let current = paneCursorsByArrangementId[arrangementID]?.activePaneId {
                    return .replaceValue(key: arrangementID, currentValue: .value(current))
                }
                return .insert(.init(key: arrangementID, rawKeyByteCount: 16))
            case .clearSelection(let arrangementID), .removeCursor(let arrangementID):
                guard let current = paneCursorsByArrangementId[arrangementID]?.activePaneId else { return nil }
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
                if let current = drawerCursorsByKey[key]?.activeChildId {
                    return .replaceValue(key: key, currentValue: .value(current))
                }
                return .insert(.init(key: key, rawKeyByteCount: 32))
            case .clearSelection(let key), .removeCursor(let key):
                guard let current = drawerCursorsByKey[key]?.activeChildId else { return nil }
                return .remove(.init(key: key, currentValue: .value(current)))
            }
        }
    }

    private func prepare<Key: Hashable & Sendable>(
        _ participant: WorkspaceStateSnapshotKeyedParticipant<Key, UUID>,
        mutations: [WorkspaceStateSnapshotParticipantMutation<Key, UUID>],
        preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws {
        guard !mutations.isEmpty else { return }
        switch participant.prepare(mutations, for: preparation, revisionOwner: revisionOwner) {
        case .prepared:
            break
        case .rejected(let rejection):
            throw ArrangementCursorPreparationError.snapshotPreparation(rejection)
        }
    }

    private func applyPreparedPersistenceMutation(
        _ mutation: ArrangementCursorPreparedMutation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) {
        precondition(
            revisionOwner.validateActiveCommit(mutation.transaction) == .active,
            "arrangement cursor prepared mutation requires its exact active transaction"
        )
        for operation in mutation.operations.activeArrangements {
            switch operation {
            case .set(let tabID, let arrangementID): activeArrangementIdsByTabId[tabID] = arrangementID
            case .remove(let tabID): activeArrangementIdsByTabId.removeValue(forKey: tabID)
            }
        }
        for operation in mutation.operations.activePanes {
            switch operation {
            case .set(let arrangementID, let paneID):
                paneCursorsByArrangementId[arrangementID] = .init(activePaneId: paneID)
            case .clearSelection(let arrangementID):
                paneCursorsByArrangementId[arrangementID] = .init(activePaneId: nil)
            case .removeCursor(let arrangementID):
                paneCursorsByArrangementId.removeValue(forKey: arrangementID)
            }
        }
        for operation in mutation.operations.activeDrawerChildren {
            switch operation {
            case .set(let key, let childPaneID):
                drawerCursorsByKey[key] = .init(activeChildId: childPaneID)
            case .clearSelection(let key):
                drawerCursorsByKey[key] = .init(activeChildId: nil)
            case .removeCursor(let key):
                drawerCursorsByKey.removeValue(forKey: key)
            }
        }
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
