import Foundation
import Observation

struct DrawerViewGraphState: Equatable, Hashable, Sendable {
    var layout: DrawerGridLayout
    var minimizedPaneIds: Set<UUID>

    init(layout: DrawerGridLayout = DrawerGridLayout(), minimizedPaneIds: Set<UUID> = []) {
        self.layout = layout
        self.minimizedPaneIds = minimizedPaneIds.intersection(layout.paneIds)
    }

    init(_ drawerView: DrawerView) {
        self.init(layout: drawerView.layout, minimizedPaneIds: drawerView.minimizedPaneIds)
    }
}

struct PaneArrangementGraphState: Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var isDefault: Bool
    var layout: Layout
    var minimizedPaneIds: Set<UUID>
    var showsMinimizedPanes: Bool
    var drawerViews: [UUID: DrawerViewGraphState]

    init(
        id: UUID,
        name: String,
        isDefault: Bool,
        layout: Layout,
        minimizedPaneIds: Set<UUID>,
        showsMinimizedPanes: Bool,
        drawerViews: [UUID: DrawerViewGraphState]
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.layout = layout
        self.minimizedPaneIds = minimizedPaneIds.intersection(layout.paneIds)
        self.showsMinimizedPanes = showsMinimizedPanes
        self.drawerViews = drawerViews
    }

    init(_ arrangement: PaneArrangement) {
        self.init(
            id: arrangement.id,
            name: arrangement.name,
            isDefault: arrangement.isDefault,
            layout: arrangement.layout,
            minimizedPaneIds: arrangement.minimizedPaneIds,
            showsMinimizedPanes: arrangement.showsMinimizedPanes,
            drawerViews: arrangement.drawerViews.mapValues(DrawerViewGraphState.init)
        )
    }
}

struct TabGraphState: Equatable, Hashable, Sendable {
    let tabId: UUID
    var allPaneIds: [UUID]
    var arrangements: [PaneArrangementGraphState]

    init(tabId: UUID, allPaneIds: [UUID], arrangements: [PaneArrangementGraphState]) {
        self.tabId = tabId
        self.allPaneIds = allPaneIds
        self.arrangements = arrangements
    }

    init(_ state: TabArrangementState) {
        self.init(
            tabId: state.tabId,
            allPaneIds: state.allPaneIds,
            arrangements: state.arrangements.map(PaneArrangementGraphState.init)
        )
    }
}

enum WorkspaceTabGraphPersistenceOperation: Equatable, Sendable {
    case insert(TabGraphState, at: Int)
    case update(TabGraphState)
    case remove(UUID)
}

enum WorkspaceTabGraphPersistencePreparationError: Error, Equatable {
    case duplicatePaneOwnership(paneID: UUID, firstTabID: UUID, secondTabID: UUID)
    case duplicateTabID(UUID)
    case invalidInsertionIndex(Int)
    case missingTabID(UUID)
    case ownerRegistration(WorkspaceParticipantRegistrationRejection)
    case snapshotParticipant(WorkspaceStateSnapshotParticipantRejection)
    case snapshotPreparation(WorkspaceSnapshotPreparationRejection)
}

private struct WorkspaceTabGraphPreparedPersistenceMutation {
    let transaction: WorkspacePersistenceTransaction
    let tabStates: [TabGraphState]
    let tabIndexByID: [UUID: Int]
    let tabIDByPaneID: [UUID: UUID]
}

@MainActor
@Observable
final class WorkspaceTabGraphAtom {
    private(set) var tabStates: [TabGraphState] = []
    private var tabIndexByID: [UUID: Int] = [:]
    private var tabIDByPaneID: [UUID: UUID] = [:]
    private let snapshotParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, TabGraphState>()

    func replaceStates(_ states: [TabGraphState]) {
        guard tabStates != states else { return }
        tabStates = states
        rebuildIndexes()
    }

    func tabState(_ tabId: UUID) -> TabGraphState? {
        tabIndexByID[tabId].map { tabStates[$0] }
    }

    func tabIndex(for tabID: UUID) -> Int? {
        tabIndexByID[tabID]
    }

    func tabID(containingPane paneID: UUID) -> UUID? {
        tabIDByPaneID[paneID]
    }

    func makePersistenceSnapshotParticipant(
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
            orderedBaseKeys: { [self] in tabStates.map(\.tabId) },
            currentValue: { [self] tabID in
                tabIndexByID[tabID].map { .value(tabStates[$0]) } ?? .absent
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
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws {
        var nextTabStates = tabStates
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

        let indexes = try Self.makeIndexes(nextTabStates)
        var snapshotMutations: [WorkspaceStateSnapshotParticipantMutation<UUID, TabGraphState>] = []
        snapshotMutations.reserveCapacity(tabStates.count + nextTabStates.count)
        for oldState in tabStates {
            guard let nextIndex = indexes.tabIndexByID[oldState.tabId] else {
                snapshotMutations.append(
                    .remove(.init(key: oldState.tabId, currentValue: .value(oldState)))
                )
                continue
            }
            if nextTabStates[nextIndex] != oldState {
                snapshotMutations.append(.replaceValue(key: oldState.tabId, currentValue: .value(oldState)))
            }
        }
        for state in nextTabStates where tabIndexByID[state.tabId] == nil {
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
        let preparedMutation = WorkspaceTabGraphPreparedPersistenceMutation(
            transaction: preparation.transaction,
            tabStates: nextTabStates,
            tabIndexByID: indexes.tabIndexByID,
            tabIDByPaneID: indexes.tabIDByPaneID
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
            throw WorkspaceTabGraphPersistencePreparationError.ownerRegistration(rejection)
        }
    }

    private func applyPreparedPersistenceMutation(
        _ mutation: WorkspaceTabGraphPreparedPersistenceMutation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) {
        precondition(
            revisionOwner.validateActiveCommit(mutation.transaction) == .active,
            "tab graph prepared mutation requires its exact active transaction"
        )
        tabStates = mutation.tabStates
        tabIndexByID = mutation.tabIndexByID
        tabIDByPaneID = mutation.tabIDByPaneID
    }

    private func rebuildIndexes() {
        var indexByID: [UUID: Int] = [:]
        var ownerByPaneID: [UUID: UUID] = [:]
        for (index, state) in tabStates.enumerated() {
            indexByID[state.tabId] = index
            for paneID in state.allPaneIds { ownerByPaneID[paneID] = state.tabId }
        }
        tabIndexByID = indexByID
        tabIDByPaneID = ownerByPaneID
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
            for (drawerID, drawer) in arrangement.drawerViews {
                byteCount += 16
                byteCount += drawer.layout.topRow.paneIds.count * 16
                byteCount += (drawer.layout.bottomRow?.paneIds.count ?? 0) * 16
                byteCount += drawer.minimizedPaneIds.count * 16
                _ = drawerID
            }
        }
        return max(byteCount, 1)
    }
}
