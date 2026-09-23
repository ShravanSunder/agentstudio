import Foundation

extension WorkspaceTabArrangementAtom {
    package func capturePaneArrangementRevealSnapshot(
        tabID: UUID
    ) -> PaneArrangementRevealSnapshot? {
        guard let graphState = graphAtom.tabState(tabID),
            let activeArrangementID = cursorAtom.activeArrangementId(forTab: tabID)
        else { return nil }
        return PaneArrangementRevealSnapshot(
            graphState: graphState,
            graphRevision: graphAtom.tabGraphAcceptedCommitRevision,
            activeArrangementID: activeArrangementID
        )
    }

    package func validatesPaneArrangementRevealSelection(
        _ selection: PaneArrangementRevealSelection
    ) -> Bool {
        guard graphAtom.tabGraphAcceptedCommitRevision == selection.capturedGraphRevision,
            cursorAtom.activeArrangementId(forTab: selection.tabID)
                == selection.capturedActiveArrangementID,
            graphAtom.tabID(containingArrangement: selection.arrangementID) == selection.tabID,
            graphAtom.tabID(containingPane: selection.target.paneID) == selection.tabID
        else { return false }

        if case .drawerChild(_, let parentPaneID, _) = selection.target {
            return graphAtom.tabID(containingPane: parentPaneID) == selection.tabID
        }
        return true
    }
}
