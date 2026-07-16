import Foundation

enum WorkspaceTabGraphPersistenceOperation: Equatable, Sendable {
    case insert(TabGraphState, at: Int)
    case update(TabGraphState)
    case remove(UUID)
}

enum WorkspaceTabGraphPersistencePreparationError: Error, Equatable {
    case duplicatePaneOwnership(paneID: UUID, firstTabID: UUID, secondTabID: UUID)
    case duplicateTabID(UUID)
    case emptyCapture
    case invalidInsertionIndex(Int)
    case missingTabID(UUID)
    case ownerRegistration(WorkspaceParticipantRegistrationRejection)
    case snapshotParticipant(WorkspaceStateSnapshotParticipantRejection)
    case snapshotPreparation(WorkspaceSnapshotPreparationRejection)
}

private struct WorkspaceTabGraphPreparedPersistenceMutation {
    let transaction: WorkspacePersistenceTransaction
    let tabStates: [TabGraphState]
}

@MainActor
final class WorkspaceTabGraphPersistenceAdapter {
    private let atom: WorkspaceTabGraphAtom
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let snapshotParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, TabGraphState>()

    init(atom: WorkspaceTabGraphAtom, revisionOwner: WorkspacePersistenceRevisionOwner) {
        self.atom = atom
        self.revisionOwner = revisionOwner
    }

    func makeSnapshotParticipant(
        limits: WorkspaceStateSnapshotMembershipLimits
    ) -> SnapshotPagerParticipantConstructionResult<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    > {
        WorkspaceStateSnapshotPagerParticipant<
            WorkspacePersistenceSnapshotParticipantID,
            WorkspacePersistenceSnapshotItem
        >.typed(
            participantID: .tabGraphs,
            keyedParticipant: snapshotParticipant,
            membershipLimits: limits,
            orderedBaseKeys: { [atom] in atom.tabStates.map(\.tabId) },
            currentValue: { [atom] tabID in
                atom.tabState(tabID).map { .value($0) } ?? .absent
            },
            projection: WorkspaceStateSnapshotItemProjection(
                itemIDForKey: { .tabGraph($0) },
                projectItem: { _, state in
                    WorkspaceStateSnapshotPagerTypedItem(
                        item: .tabGraph(state),
                        estimatedByteCount: Self.estimatedSnapshotByteCount(state)
                    )
                }
            ),
            rawKeyByteCount: { _ in 16 }
        )
    }

    func preparePersistenceMutation(
        _ operations: [WorkspaceTabGraphPersistenceOperation],
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        var nextTabStates = atom.tabStates
        for operation in operations {
            switch operation {
            case .insert(let state, let index):
                guard !nextTabStates.contains(where: { $0.tabId == state.tabId }) else {
                    throw WorkspaceTabGraphPersistencePreparationError.duplicateTabID(state.tabId)
                }
                guard index >= 0, index <= nextTabStates.count else {
                    throw WorkspaceTabGraphPersistencePreparationError.invalidInsertionIndex(index)
                }
                nextTabStates.insert(state, at: index)
            case .update(let state):
                guard let index = nextTabStates.firstIndex(where: { $0.tabId == state.tabId }) else {
                    throw WorkspaceTabGraphPersistencePreparationError.missingTabID(state.tabId)
                }
                nextTabStates[index] = state
            case .remove(let tabID):
                guard let index = nextTabStates.firstIndex(where: { $0.tabId == tabID }) else {
                    throw WorkspaceTabGraphPersistencePreparationError.missingTabID(tabID)
                }
                nextTabStates.remove(at: index)
            }
        }

        try prepareReplacement(nextTabStates, for: preparation)
    }

    func capturePersistencePreimages(
        _ capture: WorkspaceTabGraphPersistenceCapture,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        guard !capture.operations.isEmpty else {
            throw WorkspaceTabGraphPersistencePreparationError.emptyCapture
        }
        var capturedTabIDs = Set<UUID>()
        capturedTabIDs.reserveCapacity(capture.operations.count)
        var mutations: [WorkspaceStateSnapshotParticipantMutation<UUID, TabGraphState>] = []
        mutations.reserveCapacity(capture.operations.count)

        for operation in capture.operations {
            let tabID: UUID
            switch operation {
            case .insertion(let id), .valueChange(let id), .removal(let id):
                tabID = id
            }
            guard capturedTabIDs.insert(tabID).inserted else {
                throw WorkspaceTabGraphPersistencePreparationError.duplicateTabID(tabID)
            }
            switch operation {
            case .insertion:
                guard atom.tabState(tabID) == nil else {
                    throw WorkspaceTabGraphPersistencePreparationError.duplicateTabID(tabID)
                }
                mutations.append(.insert(.init(key: tabID, rawKeyByteCount: 16)))
            case .valueChange:
                guard let currentState = atom.tabState(tabID) else {
                    throw WorkspaceTabGraphPersistencePreparationError.missingTabID(tabID)
                }
                mutations.append(.replaceValue(key: tabID, currentValue: .value(currentState)))
            case .removal:
                guard let currentState = atom.tabState(tabID) else {
                    throw WorkspaceTabGraphPersistencePreparationError.missingTabID(tabID)
                }
                mutations.append(.remove(.init(key: tabID, currentValue: .value(currentState))))
            }
        }

        switch snapshotParticipant.prepare(mutations, for: preparation, revisionOwner: revisionOwner) {
        case .prepared:
            break
        case .rejected(let rejection):
            throw WorkspaceTabGraphPersistencePreparationError.snapshotPreparation(rejection)
        }
    }

    func prepareReplacement(
        _ nextTabStates: [TabGraphState],
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        let indexes = try Self.makeIndexes(nextTabStates)
        var snapshotMutations: [WorkspaceStateSnapshotParticipantMutation<UUID, TabGraphState>] = []
        snapshotMutations.reserveCapacity(atom.tabStates.count + nextTabStates.count)
        for oldState in atom.tabStates {
            guard let nextIndex = indexes.tabIndexByID[oldState.tabId] else {
                snapshotMutations.append(.remove(.init(key: oldState.tabId, currentValue: .value(oldState))))
                continue
            }
            if nextTabStates[nextIndex] != oldState {
                snapshotMutations.append(.replaceValue(key: oldState.tabId, currentValue: .value(oldState)))
            }
        }
        let currentTabIDs = Set(atom.tabStates.map(\.tabId))
        for state in nextTabStates where !currentTabIDs.contains(state.tabId) {
            snapshotMutations.append(.insert(.init(key: state.tabId, rawKeyByteCount: 16)))
        }

        if !snapshotMutations.isEmpty {
            switch snapshotParticipant.prepare(
                snapshotMutations,
                for: preparation,
                revisionOwner: revisionOwner
            ) {
            case .prepared:
                break
            case .rejected(let rejection):
                throw WorkspaceTabGraphPersistencePreparationError.snapshotPreparation(rejection)
            }
        }
        try registerPreparedReplacement(
            nextTabStates,
            for: preparation
        )
    }

    func registerInitialReplacement(
        token _: borrowing WorkspaceCompositionPreinstallToken,
        _ tabStates: [TabGraphState],
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        _ = try Self.makeIndexes(tabStates)
        try registerPreparedReplacement(
            tabStates,
            for: preparation
        )
    }

    private func registerPreparedReplacement(
        _ tabStates: [TabGraphState],
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        let preparedMutation = WorkspaceTabGraphPreparedPersistenceMutation(
            transaction: preparation.transaction,
            tabStates: tabStates
        )
        switch revisionOwner.registerPreparedParticipantMutation(
            participant: self,
            preparation: preparation,
            apply: { [atom, revisionOwner = self.revisionOwner] in
                precondition(
                    revisionOwner.validateActiveCommit(preparedMutation.transaction) == .active,
                    "tab graph prepared mutation requires its exact active transaction"
                )
                atom.replaceTabStates(preparedMutation.tabStates)
            },
            cancel: {}
        ) {
        case .registered:
            break
        case .rejected(let rejection):
            throw WorkspaceTabGraphPersistencePreparationError.ownerRegistration(rejection)
        }
    }

    private static func makeIndexes(
        _ states: [TabGraphState]
    ) throws -> (tabIndexByID: [UUID: Int], tabIDByPaneID: [UUID: UUID]) {
        var tabIndexByID: [UUID: Int] = [:]
        var tabIDByPaneID: [UUID: UUID] = [:]
        for (index, state) in states.enumerated() {
            guard tabIndexByID.updateValue(index, forKey: state.tabId) == nil else {
                throw WorkspaceTabGraphPersistencePreparationError.duplicateTabID(state.tabId)
            }
            for paneID in state.allPaneIds {
                if let firstTabID = tabIDByPaneID.updateValue(state.tabId, forKey: paneID),
                    firstTabID != state.tabId
                {
                    throw WorkspaceTabGraphPersistencePreparationError.duplicatePaneOwnership(
                        paneID: paneID,
                        firstTabID: firstTabID,
                        secondTabID: state.tabId
                    )
                }
            }
        }
        return (tabIndexByID, tabIDByPaneID)
    }

    private static func estimatedSnapshotByteCount(_ state: TabGraphState) -> Int {
        var byteCount = 16 + (state.allPaneIds.count * 16)
        for arrangement in state.arrangements {
            byteCount += 16 + arrangement.name.utf8.count + 3
            byteCount += arrangement.layout.paneIds.count * 16
            byteCount += arrangement.minimizedPaneIds.count * 16
            for drawer in arrangement.drawerViews.values {
                byteCount += 16
                byteCount += drawer.layout.topRow.paneIds.count * 16
                byteCount += (drawer.layout.bottomRow?.paneIds.count ?? 0) * 16
                byteCount += drawer.minimizedPaneIds.count * 16
            }
        }
        return max(byteCount, 1)
    }
}
