import Foundation

enum WorkspaceClosePaneInRetainedTabApplyRejection: Equatable, Sendable {
    case stalePane(
        paneID: UUID,
        expected: WorkspaceClosePaneWitness,
        actual: WorkspaceClosePaneWitness
    )
    case staleOwnership(
        paneID: UUID,
        expected: WorkspaceClosePaneOwnershipWitness,
        actual: WorkspaceClosePaneOwnershipWitness
    )
    case staleTab(
        tabID: UUID,
        expected: TabGraphState,
        actual: WorkspaceClosePaneTabWitness
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
    case staleDrawerCursor(
        expected: WorkspaceDrawerCursorSelection,
        actual: WorkspaceDrawerCursorSelection
    )
}

enum WorkspaceClosePaneInRetainedTabApplyResult: Equatable, Sendable {
    case applied
    case rejected(WorkspaceClosePaneInRetainedTabApplyRejection)
}

enum WorkspaceClosePaneInRetainedTabPreflightResult: Equatable, Sendable {
    case ready(WorkspacePreparedClosePaneInRetainedTabApplication)
    case rejected(WorkspaceClosePaneInRetainedTabApplyRejection)
}

struct WorkspacePreparedClosePaneInRetainedTabApplication: Equatable, Sendable {
    fileprivate let transition: WorkspaceClosePaneInRetainedTabTransition
}

@MainActor
final class WorkspaceClosePaneInRetainedTabTransitionApplier {
    private let workspacePaneGraphAtom: WorkspacePaneGraphAtom
    private let workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    private let workspacePanePresentationAtom: WorkspacePanePresentationAtom

    init(
        workspacePaneGraphAtom: WorkspacePaneGraphAtom,
        workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom,
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom,
        workspacePanePresentationAtom: WorkspacePanePresentationAtom
    ) {
        self.workspacePaneGraphAtom = workspacePaneGraphAtom
        self.workspaceDrawerCursorAtom = workspaceDrawerCursorAtom
        self.workspaceTabGraphAtom = workspaceTabGraphAtom
        self.workspaceArrangementCursorAtom = workspaceArrangementCursorAtom
        self.workspacePanePresentationAtom = workspacePanePresentationAtom
    }

    func apply(
        _ transition: WorkspaceClosePaneInRetainedTabTransition
    ) -> WorkspaceClosePaneInRetainedTabApplyResult {
        switch preflight(transition) {
        case .ready(let prepared):
            apply(prepared)
            return .applied
        case .rejected(let rejection):
            return .rejected(rejection)
        }
    }

    func preflight(
        _ transition: WorkspaceClosePaneInRetainedTabTransition
    ) -> WorkspaceClosePaneInRetainedTabPreflightResult {
        let paneID = transition.previousPane.id
        let expectedPane = WorkspaceClosePaneWitness.present(transition.previousPane)
        let actualPane = paneWitness(paneID)
        guard actualPane == expectedPane else {
            return .rejected(
                .stalePane(paneID: paneID, expected: expectedPane, actual: actualPane)
            )
        }

        let expectedOwnership = WorkspaceClosePaneOwnershipWitness.owned(
            tabID: transition.previousTab.tabId
        )
        let actualOwnership = ownershipWitness(paneID)
        guard actualOwnership == expectedOwnership else {
            return .rejected(
                .staleOwnership(
                    paneID: paneID,
                    expected: expectedOwnership,
                    actual: actualOwnership
                )
            )
        }

        let actualTab = tabWitness(transition.previousTab.tabId)
        guard actualTab == .present(transition.previousTab) else {
            return .rejected(
                .staleTab(
                    tabID: transition.previousTab.tabId,
                    expected: transition.previousTab,
                    actual: actualTab
                )
            )
        }

        if let rejection = preflightActiveArrangement(transition.activeArrangement) {
            return .rejected(rejection)
        }
        for mutation in transition.activePanes {
            if let rejection = preflightActivePane(mutation) {
                return .rejected(rejection)
            }
        }
        let actualDrawerCursor = WorkspaceDrawerCursorSelection(
            expandedDrawerID: workspaceDrawerCursorAtom.expandedDrawerId
        )
        guard actualDrawerCursor == transition.drawerCursor else {
            return .rejected(
                .staleDrawerCursor(
                    expected: transition.drawerCursor,
                    actual: actualDrawerCursor
                )
            )
        }
        if let rejection = preflightZoom(transition.zoom) {
            return .rejected(rejection)
        }
        return .ready(.init(transition: transition))
    }

    func apply(_ prepared: WorkspacePreparedClosePaneInRetainedTabApplication) {
        guard case .ready = preflight(prepared.transition) else {
            preconditionFailure("prepared retained-tab pane close became stale")
        }
        let transition = prepared.transition
        workspaceTabGraphAtom.replaceTabStateAndOwnership(transition.replacementTab)
        applyActiveArrangement(transition.activeArrangement)
        for mutation in transition.activePanes {
            applyActivePane(mutation)
        }
        applyZoom(transition.zoom)
        let removed = workspacePaneGraphAtom.removeCanonicalPaneState(
            for: transition.previousPane.id
        )
        precondition(removed == transition.previousPane, "preflighted pane close must remove its exact pane")
    }

    private func preflightActiveArrangement(
        _ mutation: WorkspaceClosePaneActiveArrangementMutation
    ) -> WorkspaceClosePaneInRetainedTabApplyRejection? {
        let tabID: UUID
        let expected: WorkspaceActiveArrangementSelection
        switch mutation {
        case .witness(let id, let witness):
            tabID = id
            expected = witness
        case .replace(let id, let previousID, _):
            tabID = id
            expected = .selected(previousID)
        }
        let actual = activeArrangementWitness(tabID)
        return actual == expected
            ? nil
            : .staleActiveArrangement(tabID: tabID, expected: expected, actual: actual)
    }

    private func preflightActivePane(
        _ mutation: WorkspaceClosePaneActivePaneMutation
    ) -> WorkspaceClosePaneInRetainedTabApplyRejection? {
        let arrangementID: UUID
        let expected: WorkspaceActivePaneCursorWitness
        switch mutation {
        case .witness(let id, let witness), .replace(let id, let witness, _):
            arrangementID = id
            expected = witness
        }
        let actual = activePaneWitness(arrangementID)
        return actual == expected
            ? nil
            : .staleActivePane(
                arrangementID: arrangementID,
                expected: expected,
                actual: actual
            )
    }

    private func preflightZoom(
        _ mutation: WorkspaceClosePaneZoomMutation
    ) -> WorkspaceClosePaneInRetainedTabApplyRejection? {
        let tabID: UUID
        let expected: WorkspaceZoomSelection
        switch mutation {
        case .witness(let id, let witness):
            tabID = id
            expected = witness
        case .clear(let id, let previousPaneID):
            tabID = id
            expected = .zoomed(previousPaneID)
        }
        let actual = zoomWitness(tabID)
        return actual == expected
            ? nil
            : .staleZoom(tabID: tabID, expected: expected, actual: actual)
    }

    private func applyActiveArrangement(
        _ mutation: WorkspaceClosePaneActiveArrangementMutation
    ) {
        guard case .replace(let tabID, _, let replacementID) = mutation else { return }
        workspaceArrangementCursorAtom.setActiveArrangementId(replacementID, forTab: tabID)
    }

    private func applyActivePane(_ mutation: WorkspaceClosePaneActivePaneMutation) {
        guard case .replace(let arrangementID, _, let replacement) = mutation else { return }
        let paneID: UUID?
        switch replacement {
        case .noSelection:
            paneID = nil
        case .selected(let selectedPaneID):
            paneID = selectedPaneID
        }
        workspaceArrangementCursorAtom.setPaneCursor(
            .init(activePaneId: paneID),
            forArrangement: arrangementID
        )
    }

    private func applyZoom(_ mutation: WorkspaceClosePaneZoomMutation) {
        guard case .clear(let tabID, _) = mutation else { return }
        workspacePanePresentationAtom.setZoomedPaneId(nil, forTab: tabID)
    }

    private func paneWitness(_ paneID: UUID) -> WorkspaceClosePaneWitness {
        workspacePaneGraphAtom.paneState(paneID).map(WorkspaceClosePaneWitness.present)
            ?? .missing
    }

    private func ownershipWitness(_ paneID: UUID) -> WorkspaceClosePaneOwnershipWitness {
        workspaceTabGraphAtom.tabID(containingPane: paneID)
            .map(WorkspaceClosePaneOwnershipWitness.owned) ?? .absent
    }

    private func tabWitness(_ tabID: UUID) -> WorkspaceClosePaneTabWitness {
        workspaceTabGraphAtom.tabState(tabID).map(WorkspaceClosePaneTabWitness.present)
            ?? .missing
    }

    private func activeArrangementWitness(
        _ tabID: UUID
    ) -> WorkspaceActiveArrangementSelection {
        workspaceArrangementCursorAtom.activeArrangementId(forTab: tabID)
            .map(WorkspaceActiveArrangementSelection.selected) ?? .missing
    }

    private func activePaneWitness(
        _ arrangementID: UUID
    ) -> WorkspaceActivePaneCursorWitness {
        guard workspaceArrangementCursorAtom.hasPaneCursor(arrangementID: arrangementID) else {
            return .missing
        }
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
