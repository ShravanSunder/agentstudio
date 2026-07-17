import Foundation

enum WorkspaceCreatePaneInExistingTabApplyRejection: Equatable, Sendable {
    case staleActiveArrangement(
        tabID: UUID,
        expected: WorkspaceActiveArrangementSelection,
        actual: WorkspaceActiveArrangementSelection
    )
    case staleActivePane(
        arrangementID: UUID,
        expected: WorkspaceActivePaneCursorWitness,
        actual: WorkspaceActivePaneCursorWitness
    )
    case staleDrawerIdentity(
        drawerID: UUID,
        expected: WorkspaceProposedDrawerIdentityWitness,
        actual: WorkspaceProposedDrawerIdentityWitness
    )
    case stalePaneIdentity(
        paneID: UUID,
        expected: WorkspaceProposedPaneIdentityWitness,
        actual: WorkspaceProposedPaneIdentityWitness
    )
    case staleTabGraph(
        tabID: UUID,
        expected: TabGraphState,
        actual: WorkspaceCreatePaneTargetTabWitness
    )
    case staleZoom(tabID: UUID, expected: WorkspaceZoomSelection, actual: WorkspaceZoomSelection)
}

enum WorkspaceCreatePaneInExistingTabApplyResult: Equatable, Sendable {
    case applied
    case rejected(WorkspaceCreatePaneInExistingTabApplyRejection)
}

enum WorkspaceCreatePaneInExistingTabPreflightResult: Equatable, Sendable {
    case ready(WorkspacePreparedExistingTabPaneCreation)
    case rejected(WorkspaceCreatePaneInExistingTabApplyRejection)
}

struct WorkspacePreparedExistingTabPaneCreation: Equatable, Sendable {
    fileprivate let transition: WorkspaceCreatePaneInExistingTabTransition
}

@MainActor
final class WorkspaceCreatePaneInExistingTabTransitionApplier {
    private let workspacePaneGraphAtom: WorkspacePaneGraphAtom
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    private let workspacePanePresentationAtom: WorkspacePanePresentationAtom

    init(
        workspacePaneGraphAtom: WorkspacePaneGraphAtom,
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom,
        workspacePanePresentationAtom: WorkspacePanePresentationAtom
    ) {
        self.workspacePaneGraphAtom = workspacePaneGraphAtom
        self.workspaceTabGraphAtom = workspaceTabGraphAtom
        self.workspaceArrangementCursorAtom = workspaceArrangementCursorAtom
        self.workspacePanePresentationAtom = workspacePanePresentationAtom
    }

    func apply(
        _ transition: WorkspaceCreatePaneInExistingTabTransition
    ) -> WorkspaceCreatePaneInExistingTabApplyResult {
        switch preflight(transition) {
        case .ready(let preparation):
            apply(preparation)
            return .applied
        case .rejected(let rejection):
            return .rejected(rejection)
        }
    }

    func preflight(
        _ transition: WorkspaceCreatePaneInExistingTabTransition
    ) -> WorkspaceCreatePaneInExistingTabPreflightResult {
        let paneID = transition.paneInsertion.id
        let expectedPane: WorkspaceProposedPaneIdentityWitness = .vacant
        let actualPane = paneIdentityWitness(paneID)
        guard actualPane == expectedPane else {
            return .rejected(
                .stalePaneIdentity(paneID: paneID, expected: expectedPane, actual: actualPane)
            )
        }

        guard let drawerID = transition.paneInsertion.drawer?.drawerId else {
            preconditionFailure("created layout pane transition requires one drawer identity")
        }
        let expectedDrawer: WorkspaceProposedDrawerIdentityWitness = .vacant
        let actualDrawer = drawerIdentityWitness(drawerID)
        guard actualDrawer == expectedDrawer else {
            return .rejected(
                .staleDrawerIdentity(drawerID: drawerID, expected: expectedDrawer, actual: actualDrawer)
            )
        }

        let actualTabState = workspaceTabGraphAtom.tabState(transition.previousTab.tabId)
        let actualTab = actualTabState.map(WorkspaceCreatePaneTargetTabWitness.present) ?? .missing
        guard actualTab == .present(transition.previousTab) else {
            return .rejected(
                .staleTabGraph(
                    tabID: transition.previousTab.tabId,
                    expected: transition.previousTab,
                    actual: actualTab
                )
            )
        }

        let actualArrangement =
            workspaceArrangementCursorAtom.activeArrangementId(forTab: transition.previousTab.tabId)
            .map(WorkspaceActiveArrangementSelection.selected) ?? .missing
        guard actualArrangement == transition.activeArrangement else {
            return .rejected(
                .staleActiveArrangement(
                    tabID: transition.previousTab.tabId,
                    expected: transition.activeArrangement,
                    actual: actualArrangement
                )
            )
        }

        for mutation in transition.activePaneMutations {
            let arrangementID: UUID
            let expected: WorkspaceActivePaneCursorWitness
            switch mutation {
            case .witness(let id, let witness), .replace(let id, let witness, _):
                arrangementID = id
                expected = witness
            }
            let actual = activePaneWitness(arrangementID)
            guard actual == expected else {
                return .rejected(
                    .staleActivePane(
                        arrangementID: arrangementID,
                        expected: expected,
                        actual: actual
                    )
                )
            }
        }

        let tabID: UUID
        let expectedZoom: WorkspaceZoomSelection
        switch transition.zoom {
        case .witness(let id, let expected):
            tabID = id
            expectedZoom = expected
        case .clear(let id, let previousPaneID):
            tabID = id
            expectedZoom = .zoomed(previousPaneID)
        }
        let actualZoom = zoomWitness(tabID)
        guard actualZoom == expectedZoom else {
            return .rejected(.staleZoom(tabID: tabID, expected: expectedZoom, actual: actualZoom))
        }
        return .ready(.init(transition: transition))
    }

    func apply(_ preparation: WorkspacePreparedExistingTabPaneCreation) {
        guard case .ready = preflight(preparation.transition) else {
            preconditionFailure("prepared create-pane-in-existing-tab application became stale")
        }
        let transition = preparation.transition
        workspacePaneGraphAtom.setCanonicalPaneState(transition.paneInsertion)
        workspaceTabGraphAtom.replaceTabStateAndOwnership(transition.replacementTab)
        for mutation in transition.activePaneMutations {
            guard case .replace(let arrangementID, _, let replacement) = mutation else { continue }
            workspaceArrangementCursorAtom.setPaneCursor(
                ArrangementPaneCursorState(activePaneId: replacement.paneID),
                forArrangement: arrangementID
            )
        }
        if case .clear(let tabID, _) = transition.zoom {
            workspacePanePresentationAtom.setZoomedPaneId(nil, forTab: tabID)
        }
    }

    private func paneIdentityWitness(_ paneID: UUID) -> WorkspaceProposedPaneIdentityWitness {
        let paneExists = workspacePaneGraphAtom.paneState(paneID) != nil
        let tabOwner = workspaceTabGraphAtom.tabID(containingPane: paneID)
        switch (paneExists, tabOwner) {
        case (false, nil): return .vacant
        case (true, nil): return .paneGraphOccupied
        case (false, .some(let tabID)): return .tabOwned(tabID: tabID)
        case (true, .some(let tabID)): return .paneGraphOccupiedAndTabOwned(tabID: tabID)
        }
    }

    private func drawerIdentityWitness(_ drawerID: UUID) -> WorkspaceProposedDrawerIdentityWitness {
        workspacePaneGraphAtom.parentPaneID(containingDrawer: drawerID)
            .map(WorkspaceProposedDrawerIdentityWitness.owned) ?? .vacant
    }

    private func activePaneWitness(_ arrangementID: UUID) -> WorkspaceActivePaneCursorWitness {
        guard workspaceArrangementCursorAtom.hasPaneCursor(arrangementID: arrangementID) else { return .missing }
        return .present(
            workspaceArrangementCursorAtom.activePaneId(forArrangement: arrangementID)
                .map(WorkspacePaneSelection.selected) ?? .noSelection
        )
    }

    private func zoomWitness(_ tabID: UUID) -> WorkspaceZoomSelection {
        workspacePanePresentationAtom.zoomedPaneId(forTab: tabID)
            .map(WorkspaceZoomSelection.zoomed) ?? .notZoomed
    }
}

extension WorkspacePaneSelection {
    fileprivate var paneID: UUID? {
        switch self {
        case .noSelection: nil
        case .selected(let paneID): paneID
        }
    }
}
