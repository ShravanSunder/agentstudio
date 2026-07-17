import Foundation

enum WorkspaceCrossTabPaneMoveApplyRejection: Equatable, Sendable {
    case malformedPaneWitness(WorkspaceCrossTabPaneWitness)
    case stalePane(
        paneID: UUID,
        expected: WorkspaceCrossTabPaneWitness,
        actual: WorkspaceCrossTabPaneWitness
    )
    case staleOwnership(
        paneID: UUID,
        expected: WorkspaceCrossTabPaneOwnershipWitness,
        actual: WorkspaceCrossTabPaneOwnershipWitness
    )
    case staleSourceTab(
        tabID: UUID,
        expected: TabGraphState,
        actual: WorkspaceCrossTabTabWitness
    )
    case staleDestinationTab(
        tabID: UUID,
        expected: TabGraphState,
        actual: WorkspaceCrossTabTabWitness
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
    case staleActiveTab(
        expected: WorkspaceTabCursorSelection,
        actual: WorkspaceTabCursorSelection
    )
    case staleZoom(
        tabID: UUID,
        expected: WorkspaceZoomSelection,
        actual: WorkspaceZoomSelection
    )
}

enum WorkspaceCrossTabPaneMoveApplyResult: Equatable, Sendable {
    case applied
    case rejected(WorkspaceCrossTabPaneMoveApplyRejection)
}

enum WorkspaceCrossTabPaneMovePreflightResult: Equatable, Sendable {
    case ready(WorkspacePreparedCrossTabPaneMoveApplication)
    case rejected(WorkspaceCrossTabPaneMoveApplyRejection)
}

struct WorkspacePreparedCrossTabPaneMoveApplication: Equatable, Sendable {
    fileprivate let transition: WorkspaceCrossTabPaneMoveTransition
}

@MainActor
final class WorkspaceCrossTabPaneMoveTransitionApplier {
    private let workspacePaneGraphAtom: WorkspacePaneGraphAtom
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    private let workspaceTabCursorAtom: WorkspaceTabCursorAtom
    private let workspacePanePresentationAtom: WorkspacePanePresentationAtom

    init(
        workspacePaneGraphAtom: WorkspacePaneGraphAtom,
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom,
        workspaceTabCursorAtom: WorkspaceTabCursorAtom,
        workspacePanePresentationAtom: WorkspacePanePresentationAtom
    ) {
        self.workspacePaneGraphAtom = workspacePaneGraphAtom
        self.workspaceTabGraphAtom = workspaceTabGraphAtom
        self.workspaceArrangementCursorAtom = workspaceArrangementCursorAtom
        self.workspaceTabCursorAtom = workspaceTabCursorAtom
        self.workspacePanePresentationAtom = workspacePanePresentationAtom
    }

    func apply(
        _ transition: WorkspaceCrossTabPaneMoveTransition
    ) -> WorkspaceCrossTabPaneMoveApplyResult {
        switch preflight(transition) {
        case .ready(let prepared):
            apply(prepared)
            return .applied
        case .rejected(let rejection):
            return .rejected(rejection)
        }
    }

    func preflight(
        _ transition: WorkspaceCrossTabPaneMoveTransition
    ) -> WorkspaceCrossTabPaneMovePreflightResult {
        if let rejection = preflightPane(transition) { return .rejected(rejection) }
        if let rejection = preflightOwnership(transition) { return .rejected(rejection) }
        if let rejection = preflightTabGraphs(transition) { return .rejected(rejection) }
        if let rejection = preflightActiveArrangement(transition.sourceActiveArrangement) {
            return .rejected(rejection)
        }
        if let rejection = preflightActiveArrangement(transition.destinationActiveArrangement) {
            return .rejected(rejection)
        }
        for mutation in transition.sourceActivePanes {
            if let rejection = preflightActivePane(mutation) { return .rejected(rejection) }
        }
        for mutation in transition.destinationActivePanes {
            if let rejection = preflightActivePane(mutation) { return .rejected(rejection) }
        }
        if let rejection = preflightActiveTab(transition.activeTab) { return .rejected(rejection) }
        if let rejection = preflightZoom(transition.sourceZoom) { return .rejected(rejection) }
        if let rejection = preflightZoom(transition.destinationZoom) { return .rejected(rejection) }
        return .ready(.init(transition: transition))
    }

    func apply(_ prepared: WorkspacePreparedCrossTabPaneMoveApplication) {
        guard case .ready = preflight(prepared.transition) else {
            preconditionFailure("prepared cross-tab pane move application became stale")
        }
        let transition = prepared.transition
        workspaceTabGraphAtom.replaceTabStatesTransferringPaneOwnership(
            source: transition.replacementSourceTab,
            destination: transition.replacementDestinationTab
        )
        applyActiveArrangement(transition.sourceActiveArrangement)
        applyActiveArrangement(transition.destinationActiveArrangement)
        for mutation in transition.sourceActivePanes { applyActivePane(mutation) }
        for mutation in transition.destinationActivePanes { applyActivePane(mutation) }
        applyActiveTab(transition.activeTab)
        applyZoom(transition.sourceZoom)
        applyZoom(transition.destinationZoom)
    }

    private func preflightPane(
        _ transition: WorkspaceCrossTabPaneMoveTransition
    ) -> WorkspaceCrossTabPaneMoveApplyRejection? {
        let paneID: UUID
        switch transition.pane {
        case .missing:
            return .malformedPaneWitness(transition.pane)
        case .present(let pane): paneID = pane.id
        }
        let actual = workspacePaneGraphAtom.paneState(paneID).map(WorkspaceCrossTabPaneWitness.present) ?? .missing
        return actual == transition.pane
            ? nil : .stalePane(paneID: paneID, expected: transition.pane, actual: actual)
    }

    private func preflightOwnership(
        _ transition: WorkspaceCrossTabPaneMoveTransition
    ) -> WorkspaceCrossTabPaneMoveApplyRejection? {
        let paneID: UUID
        switch transition.pane {
        case .missing:
            return .malformedPaneWitness(transition.pane)
        case .present(let pane): paneID = pane.id
        }
        let expected: WorkspaceCrossTabPaneOwnershipWitness = .owned(tabID: transition.previousSourceTab.tabId)
        let actual = paneOwnershipWitness(paneID)
        return actual == expected
            ? nil : .staleOwnership(paneID: paneID, expected: expected, actual: actual)
    }

    private func preflightTabGraphs(
        _ transition: WorkspaceCrossTabPaneMoveTransition
    ) -> WorkspaceCrossTabPaneMoveApplyRejection? {
        let sourceActual = tabWitness(transition.previousSourceTab.tabId)
        guard sourceActual == .present(transition.previousSourceTab) else {
            return .staleSourceTab(
                tabID: transition.previousSourceTab.tabId,
                expected: transition.previousSourceTab,
                actual: sourceActual
            )
        }
        let destinationActual = tabWitness(transition.previousDestinationTab.tabId)
        guard destinationActual == .present(transition.previousDestinationTab) else {
            return .staleDestinationTab(
                tabID: transition.previousDestinationTab.tabId,
                expected: transition.previousDestinationTab,
                actual: destinationActual
            )
        }
        return nil
    }

    private func preflightActiveArrangement(
        _ mutation: WorkspaceCrossTabActiveArrangementMutation
    ) -> WorkspaceCrossTabPaneMoveApplyRejection? {
        let tabID: UUID
        let expected: WorkspaceActiveArrangementSelection
        switch mutation {
        case .witness(let id, let witness):
            tabID = id
            expected = witness
        case .replace(let id, let previous, _):
            tabID = id
            expected = .selected(previous)
        }
        let actual = activeArrangementWitness(tabID)
        return actual == expected
            ? nil : .staleActiveArrangement(tabID: tabID, expected: expected, actual: actual)
    }

    private func preflightActivePane(
        _ mutation: WorkspaceCrossTabActivePaneMutation
    ) -> WorkspaceCrossTabPaneMoveApplyRejection? {
        let arrangementID: UUID
        let expected: WorkspaceActivePaneCursorWitness
        switch mutation {
        case .witness(let id, let witness), .replace(let id, let witness, _):
            arrangementID = id
            expected = witness
        }
        let actual = activePaneWitness(arrangementID)
        return actual == expected
            ? nil : .staleActivePane(arrangementID: arrangementID, expected: expected, actual: actual)
    }

    private func preflightActiveTab(
        _ mutation: WorkspaceCrossTabActiveTabMutation
    ) -> WorkspaceCrossTabPaneMoveApplyRejection? {
        let expected: WorkspaceTabCursorSelection
        switch mutation {
        case .witness(let witness): expected = witness
        case .replace(let previous, _): expected = previous
        }
        let actual = activeTabWitness()
        return actual == expected ? nil : .staleActiveTab(expected: expected, actual: actual)
    }

    private func preflightZoom(
        _ mutation: WorkspaceCrossTabZoomMutation
    ) -> WorkspaceCrossTabPaneMoveApplyRejection? {
        let tabID: UUID
        let expected: WorkspaceZoomSelection
        switch mutation {
        case .witness(let id, let witness):
            tabID = id
            expected = witness
        case .clear(let id, let paneID):
            tabID = id
            expected = .zoomed(paneID)
        }
        let actual = zoomWitness(tabID)
        return actual == expected ? nil : .staleZoom(tabID: tabID, expected: expected, actual: actual)
    }

    private func applyActiveArrangement(_ mutation: WorkspaceCrossTabActiveArrangementMutation) {
        guard case .replace(let tabID, _, let replacementID) = mutation else { return }
        workspaceArrangementCursorAtom.setActiveArrangementId(replacementID, forTab: tabID)
    }

    private func applyActivePane(_ mutation: WorkspaceCrossTabActivePaneMutation) {
        guard case .replace(let arrangementID, _, let replacement) = mutation else { return }
        let paneID: UUID?
        switch replacement {
        case .noSelection: paneID = nil
        case .selected(let selectedPaneID): paneID = selectedPaneID
        }
        workspaceArrangementCursorAtom.setPaneCursor(
            .init(activePaneId: paneID),
            forArrangement: arrangementID
        )
    }

    private func applyActiveTab(_ mutation: WorkspaceCrossTabActiveTabMutation) {
        guard case .replace(_, let replacementTabID) = mutation else { return }
        workspaceTabCursorAtom.replaceActiveTab(replacementTabID)
    }

    private func applyZoom(_ mutation: WorkspaceCrossTabZoomMutation) {
        guard case .clear(let tabID, _) = mutation else { return }
        workspacePanePresentationAtom.setZoomedPaneId(nil, forTab: tabID)
    }

    private func paneOwnershipWitness(_ paneID: UUID) -> WorkspaceCrossTabPaneOwnershipWitness {
        workspaceTabGraphAtom.tabID(containingPane: paneID)
            .map(WorkspaceCrossTabPaneOwnershipWitness.owned) ?? .absent
    }

    private func tabWitness(_ tabID: UUID) -> WorkspaceCrossTabTabWitness {
        workspaceTabGraphAtom.tabState(tabID).map(WorkspaceCrossTabTabWitness.present) ?? .missing
    }

    private func activeArrangementWitness(_ tabID: UUID) -> WorkspaceActiveArrangementSelection {
        workspaceArrangementCursorAtom.activeArrangementId(forTab: tabID)
            .map(WorkspaceActiveArrangementSelection.selected) ?? .missing
    }

    private func activePaneWitness(_ arrangementID: UUID) -> WorkspaceActivePaneCursorWitness {
        guard workspaceArrangementCursorAtom.hasPaneCursor(arrangementID: arrangementID) else { return .missing }
        return .present(
            workspaceArrangementCursorAtom.activePaneId(forArrangement: arrangementID)
                .map(WorkspacePaneSelection.selected) ?? .noSelection
        )
    }

    private func activeTabWitness() -> WorkspaceTabCursorSelection {
        workspaceTabCursorAtom.activeTabId.map(WorkspaceTabCursorSelection.selected) ?? .noSelection
    }

    private func zoomWitness(_ tabID: UUID) -> WorkspaceZoomSelection {
        workspacePanePresentationAtom.zoomedPaneId(forTab: tabID)
            .map(WorkspaceZoomSelection.zoomed) ?? .notZoomed
    }
}
