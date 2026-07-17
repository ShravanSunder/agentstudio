import Foundation

enum WorkspaceVisibilityApplyRejection: Equatable, Sendable {
    case staleTabGraph(
        tabID: UUID,
        expected: TabGraphState,
        actual: WorkspaceTabGraphStateWitness
    )
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
    case staleZoom(
        tabID: UUID,
        expected: WorkspaceZoomSelection,
        actual: WorkspaceZoomSelection
    )
}

enum WorkspaceVisibilityApplyResult: Equatable, Sendable {
    case applied
    case rejected(WorkspaceVisibilityApplyRejection)
}

enum WorkspaceVisibilityPreflightResult: Equatable, Sendable {
    case ready(WorkspacePreparedVisibilityApplication)
    case rejected(WorkspaceVisibilityApplyRejection)
}

struct WorkspacePreparedVisibilityApplication: Equatable, Sendable {
    fileprivate let transition: WorkspaceActiveArrangementVisibilityTransition
}

@MainActor
final class WorkspaceVisibilityTransitionApplier {
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    private let workspacePanePresentationAtom: WorkspacePanePresentationAtom

    init(
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom,
        workspacePanePresentationAtom: WorkspacePanePresentationAtom
    ) {
        self.workspaceTabGraphAtom = workspaceTabGraphAtom
        self.workspaceArrangementCursorAtom = workspaceArrangementCursorAtom
        self.workspacePanePresentationAtom = workspacePanePresentationAtom
    }

    func apply(
        _ transition: WorkspaceActiveArrangementVisibilityTransition
    ) -> WorkspaceVisibilityApplyResult {
        switch preflight(transition) {
        case .ready(let preparation):
            apply(preparation)
            return .applied
        case .rejected(let rejection):
            return .rejected(rejection)
        }
    }

    func preflight(
        _ transition: WorkspaceActiveArrangementVisibilityTransition
    ) -> WorkspaceVisibilityPreflightResult {
        if let rejection = preflightTabGraph(transition.tabGraph) {
            return .rejected(rejection)
        }
        if let rejection = preflightActiveArrangement(transition.activeArrangement) {
            return .rejected(rejection)
        }
        if let rejection = preflightActivePane(transition.activePane) {
            return .rejected(rejection)
        }
        if let rejection = preflightZoom(transition.zoom) {
            return .rejected(rejection)
        }
        return .ready(WorkspacePreparedVisibilityApplication(transition: transition))
    }

    func apply(_ preparation: WorkspacePreparedVisibilityApplication) {
        preconditionPreparedApplicationIsFresh(preparation)
        applyTabGraph(preparation.transition.tabGraph)
        applyCursors(
            activeArrangement: preparation.transition.activeArrangement,
            activePane: preparation.transition.activePane
        )
        applyZoom(preparation.transition.zoom)
    }

    private func preconditionPreparedApplicationIsFresh(
        _ preparation: WorkspacePreparedVisibilityApplication
    ) {
        switch preflight(preparation.transition) {
        case .ready:
            return
        case .rejected(let rejection):
            preconditionFailure("prepared visibility transition is stale: \(rejection)")
        }
    }

    private func preflightTabGraph(
        _ transition: WorkspaceVisibilityTabGraphTransition
    ) -> WorkspaceVisibilityApplyRejection? {
        let tabID: UUID
        let expected: TabGraphState
        switch transition {
        case .witness(let id, let state), .replace(let id, let state, _):
            tabID = id
            expected = state
        }
        let actual = workspaceTabGraphAtom.tabState(tabID)
        guard actual == expected else {
            return .staleTabGraph(
                tabID: tabID,
                expected: expected,
                actual: actual.map(WorkspaceTabGraphStateWitness.present) ?? .missing
            )
        }
        return nil
    }

    private func preflightActiveArrangement(
        _ transition: WorkspaceVisibilityActiveArrangementTransition
    ) -> WorkspaceVisibilityApplyRejection? {
        let tabID: UUID
        let expected: WorkspaceActiveArrangementSelection
        switch transition {
        case .witness(let id, let selection):
            tabID = id
            expected = selection
        case .insert(let id, _):
            tabID = id
            expected = .missing
        case .replace(let id, let previous, _):
            tabID = id
            expected = .selected(previous)
        }
        let actual = activeArrangementSelection(tabID: tabID)
        guard actual == expected else {
            return .staleActiveArrangement(
                tabID: tabID,
                expected: expected,
                actual: actual
            )
        }
        return nil
    }

    private func preflightActivePane(
        _ transition: WorkspaceVisibilityActivePaneTransition
    ) -> WorkspaceVisibilityApplyRejection? {
        let arrangementID: UUID
        let expected: WorkspaceActivePaneCursorWitness
        switch transition {
        case .notRead:
            return nil
        case .witness(let id, let witness), .insert(let id, let witness, _):
            arrangementID = id
            expected = witness
        case .replace(let id, let previous, _), .remove(let id, let previous):
            arrangementID = id
            expected = .present(.selected(previous))
        }
        let actual = activePaneWitness(arrangementID: arrangementID)
        guard actual == expected else {
            return .staleActivePane(
                arrangementID: arrangementID,
                expected: expected,
                actual: actual
            )
        }
        return nil
    }

    private func preflightZoom(
        _ transition: WorkspaceVisibilityZoomTransition
    ) -> WorkspaceVisibilityApplyRejection? {
        let tabID: UUID
        let expected: WorkspaceZoomSelection
        switch transition {
        case .notRead:
            return nil
        case .witness(let id, let selection):
            tabID = id
            expected = selection
        case .clear(let id, let previous):
            tabID = id
            expected = .zoomed(previous)
        }
        let actual = zoomSelection(tabID: tabID)
        guard actual == expected else {
            return .staleZoom(tabID: tabID, expected: expected, actual: actual)
        }
        return nil
    }

    private func applyTabGraph(_ transition: WorkspaceVisibilityTabGraphTransition) {
        guard case .replace(_, _, let replacement) = transition else { return }
        workspaceTabGraphAtom.replaceTabStatePreservingIdentity(replacement)
    }

    private func applyCursors(
        activeArrangement: WorkspaceVisibilityActiveArrangementTransition,
        activePane: WorkspaceVisibilityActivePaneTransition
    ) {
        switch activeArrangement {
        case .witness:
            break
        case .insert(let tabID, let replacement), .replace(let tabID, _, let replacement):
            workspaceArrangementCursorAtom.setActiveArrangementId(replacement, forTab: tabID)
        }

        switch activePane {
        case .notRead, .witness:
            break
        case .insert(let arrangementID, _, let replacement),
            .replace(let arrangementID, _, let replacement):
            workspaceArrangementCursorAtom.setPaneCursor(
                ArrangementPaneCursorState(activePaneId: replacement),
                forArrangement: arrangementID
            )
        case .remove(let arrangementID, _):
            workspaceArrangementCursorAtom.setPaneCursor(
                ArrangementPaneCursorState(activePaneId: nil),
                forArrangement: arrangementID
            )
        }
    }

    private func applyZoom(_ transition: WorkspaceVisibilityZoomTransition) {
        guard case .clear(let tabID, _) = transition else { return }
        workspacePanePresentationAtom.setZoomedPaneId(nil, forTab: tabID)
    }

    private func activeArrangementSelection(
        tabID: UUID
    ) -> WorkspaceActiveArrangementSelection {
        workspaceArrangementCursorAtom.activeArrangementId(forTab: tabID)
            .map(WorkspaceActiveArrangementSelection.selected) ?? .missing
    }

    private func activePaneWitness(
        arrangementID: UUID
    ) -> WorkspaceActivePaneCursorWitness {
        guard
            let state = workspaceArrangementCursorAtom.paneCursorsByArrangementId[arrangementID]
        else { return .missing }
        return .present(state.activePaneId.map(WorkspacePaneSelection.selected) ?? .noSelection)
    }

    private func zoomSelection(tabID: UUID) -> WorkspaceZoomSelection {
        workspacePanePresentationAtom.zoomedPaneId(forTab: tabID)
            .map(WorkspaceZoomSelection.zoomed) ?? .notZoomed
    }
}
