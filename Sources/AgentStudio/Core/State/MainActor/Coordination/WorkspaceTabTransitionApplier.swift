import Foundation

enum WorkspaceTabTransitionApplicationRejection: Equatable, Sendable {
    case inconsistentTabIdentity(
        shellTabID: UUID,
        graphTabID: UUID,
        activeArrangementTabID: UUID,
        selectedTabID: UUID
    )
    case shellInsertionIndexChanged(expected: Int, currentCount: Int)
    case graphInsertionIndexChanged(expected: Int, currentCount: Int)
    case tabShellAlreadyExists(UUID)
    case tabGraphAlreadyExists(UUID)
    case paneAlreadyOwned(paneID: UUID, ownerTabID: UUID)
    case activeArrangementCursorAlreadyExists(UUID)
    case duplicateActivePaneCursorInsertion(UUID)
    case activePaneCursorAlreadyExists(UUID)
    case duplicateActiveDrawerCursorInsertion(ArrangementDrawerCursorKey)
    case activeDrawerCursorAlreadyExists(ArrangementDrawerCursorKey)
}

enum WorkspaceTabTransitionApplicationResult: Equatable, Sendable {
    case applied
    case rejected(WorkspaceTabTransitionApplicationRejection)
}

enum WorkspaceTabTransitionPreflightResult: Equatable, Sendable {
    case ready(WorkspacePreparedTabTransitionApplication)
    case rejected(WorkspaceTabTransitionApplicationRejection)
}

struct WorkspacePreparedTabTransitionApplication: Equatable, Sendable {
    fileprivate let insertion: WorkspaceTabTransitionInsertion
}

@MainActor
final class WorkspaceTabTransitionApplier {
    private let workspaceTabShellAtom: WorkspaceTabShellAtom
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom

    init(
        workspaceTabShellAtom: WorkspaceTabShellAtom,
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    ) {
        self.workspaceTabShellAtom = workspaceTabShellAtom
        self.workspaceTabGraphAtom = workspaceTabGraphAtom
        self.workspaceArrangementCursorAtom = workspaceArrangementCursorAtom
    }

    func apply(_ transition: WorkspaceTabTransition) -> WorkspaceTabTransitionApplicationResult {
        switch preflight(transition) {
        case .ready(let preparation):
            apply(preparation)
            return .applied
        case .rejected(let rejection):
            return .rejected(rejection)
        }
    }

    func preflight(_ transition: WorkspaceTabTransition) -> WorkspaceTabTransitionPreflightResult {
        preflight(WorkspaceTabTransitionInsertion(transition))
    }

    func apply(_ preparation: WorkspacePreparedTabTransitionApplication) {
        preconditionPreparedApplicationIsFresh(preparation)
        applyPreparedInsertion(preparation.insertion)
    }

    func preconditionPreparedApplicationIsFresh(
        _ preparation: WorkspacePreparedTabTransitionApplication
    ) {
        switch preflight(preparation.insertion) {
        case .ready:
            return
        case .rejected(let rejection):
            preconditionFailure("prepared tab transition is stale: \(rejection)")
        }
    }

    private func applyPreparedInsertion(_ insertion: WorkspaceTabTransitionInsertion) {
        workspaceTabShellAtom.insertTabShell(insertion.shell, at: insertion.shellIndex)
        workspaceTabGraphAtom.insertTabState(insertion.graph, at: insertion.graphIndex)
        workspaceArrangementCursorAtom.insertActiveArrangementId(
            insertion.activeArrangementID,
            forTab: insertion.activeArrangementTabID
        )
        for paneCursor in insertion.paneCursors {
            workspaceArrangementCursorAtom.insertPaneCursor(
                paneCursor.state,
                forArrangement: paneCursor.arrangementID
            )
        }
        for drawerCursor in insertion.drawerCursors {
            workspaceArrangementCursorAtom.insertDrawerCursor(
                drawerCursor.state,
                for: drawerCursor.key
            )
        }
        workspaceTabShellAtom.cursorAtom.replaceActiveTab(insertion.selectedTabID)
    }

    private func preflight(
        _ insertion: WorkspaceTabTransitionInsertion
    ) -> WorkspaceTabTransitionPreflightResult {
        guard
            insertion.shell.id == insertion.graph.tabId,
            insertion.shell.id == insertion.activeArrangementTabID,
            insertion.shell.id == insertion.selectedTabID
        else {
            return .rejected(
                .inconsistentTabIdentity(
                    shellTabID: insertion.shell.id,
                    graphTabID: insertion.graph.tabId,
                    activeArrangementTabID: insertion.activeArrangementTabID,
                    selectedTabID: insertion.selectedTabID
                )
            )
        }
        guard insertion.shellIndex == workspaceTabShellAtom.tabShells.count else {
            return .rejected(
                .shellInsertionIndexChanged(
                    expected: insertion.shellIndex,
                    currentCount: workspaceTabShellAtom.tabShells.count
                )
            )
        }
        guard insertion.graphIndex == workspaceTabGraphAtom.tabStates.count else {
            return .rejected(
                .graphInsertionIndexChanged(
                    expected: insertion.graphIndex,
                    currentCount: workspaceTabGraphAtom.tabStates.count
                )
            )
        }
        guard workspaceTabShellAtom.tabShell(insertion.shell.id) == nil else {
            return .rejected(.tabShellAlreadyExists(insertion.shell.id))
        }
        guard workspaceTabGraphAtom.tabState(insertion.graph.tabId) == nil else {
            return .rejected(.tabGraphAlreadyExists(insertion.graph.tabId))
        }
        for paneID in insertion.graph.allPaneIds {
            if let ownerTabID = workspaceTabGraphAtom.tabID(containingPane: paneID) {
                return .rejected(.paneAlreadyOwned(paneID: paneID, ownerTabID: ownerTabID))
            }
        }
        guard
            workspaceArrangementCursorAtom.activeArrangementIdsByTabId[
                insertion.activeArrangementTabID
            ] == nil
        else {
            return .rejected(
                .activeArrangementCursorAlreadyExists(insertion.activeArrangementTabID)
            )
        }

        var paneCursorArrangementIDs: Set<UUID> = []
        for paneCursor in insertion.paneCursors {
            guard paneCursorArrangementIDs.insert(paneCursor.arrangementID).inserted else {
                return .rejected(.duplicateActivePaneCursorInsertion(paneCursor.arrangementID))
            }
            guard
                workspaceArrangementCursorAtom.paneCursorsByArrangementId[
                    paneCursor.arrangementID
                ] == nil
            else {
                return .rejected(.activePaneCursorAlreadyExists(paneCursor.arrangementID))
            }
        }

        var drawerCursorKeys: Set<ArrangementDrawerCursorKey> = []
        for drawerCursor in insertion.drawerCursors {
            guard drawerCursorKeys.insert(drawerCursor.key).inserted else {
                return .rejected(.duplicateActiveDrawerCursorInsertion(drawerCursor.key))
            }
            guard workspaceArrangementCursorAtom.drawerCursorsByKey[drawerCursor.key] == nil else {
                return .rejected(.activeDrawerCursorAlreadyExists(drawerCursor.key))
            }
        }
        return .ready(WorkspacePreparedTabTransitionApplication(insertion: insertion))
    }
}

private struct WorkspaceTabTransitionInsertion: Equatable, Sendable {
    let shell: TabShell
    let shellIndex: Int
    let selectedTabID: UUID
    let graph: TabGraphState
    let graphIndex: Int
    let activeArrangementTabID: UUID
    let activeArrangementID: UUID
    let paneCursors: [WorkspaceTabPaneCursorInsertion]
    let drawerCursors: [WorkspaceTabDrawerCursorInsertion]

    init(_ transition: WorkspaceTabTransition) {
        switch transition.shell {
        case .insert(let shell, let index):
            self.shell = shell
            shellIndex = index
        }
        switch transition.activeTab {
        case .select(let tabID):
            selectedTabID = tabID
        }
        switch transition.graph {
        case .insert(let graph, let index):
            self.graph = graph
            graphIndex = index
        }
        switch transition.activeArrangement {
        case .insert(let tabID, let arrangementID):
            activeArrangementTabID = tabID
            activeArrangementID = arrangementID
        }
        paneCursors = transition.activePanes.map(WorkspaceTabPaneCursorInsertion.init)
        drawerCursors = transition.activeDrawerChildren.map(WorkspaceTabDrawerCursorInsertion.init)
    }
}

private struct WorkspaceTabPaneCursorInsertion: Equatable, Sendable {
    let arrangementID: UUID
    let state: ArrangementPaneCursorState

    init(_ transition: WorkspaceActivePaneTransition) {
        switch transition {
        case .insert(let arrangementID, let selection):
            self.arrangementID = arrangementID
            state = ArrangementPaneCursorState(activePaneId: selection.selectedID)
        }
    }
}

private struct WorkspaceTabDrawerCursorInsertion: Equatable, Sendable {
    let key: ArrangementDrawerCursorKey
    let state: ArrangementDrawerCursorState

    init(_ transition: WorkspaceActiveDrawerChildTransition) {
        switch transition {
        case .insert(let key, let selection):
            self.key = key
            state = ArrangementDrawerCursorState(activeChildId: selection.selectedID)
        }
    }
}

extension WorkspaceTabCursorSelection {
    fileprivate var selectedID: UUID? {
        switch self {
        case .noSelection:
            nil
        case .selected(let paneID):
            paneID
        }
    }
}
