import AgentStudioCore
import Foundation

/// Applies one already-admitted explicit pane focus without submitting another gesture.
@MainActor
struct PaneCommittedFocusOperation {
    typealias ExecuteAction = @MainActor (WorkspaceActionCommand) async -> Bool
    typealias ApplyFocus = @MainActor (PaneFocusTrigger) -> Bool

    let store: WorkspaceStore
    let applyFocus: ApplyFocus

    func prepareAndApplyTargetFocus(
        paneID: UUID,
        execute: ExecuteAction,
        beforeFocus: @MainActor () -> Void = {}
    ) async -> Bool {
        guard let resolvedTarget = resolveTarget(paneID: paneID),
            let snapshot = store.tabArrangementAtom.capturePaneArrangementRevealSnapshot(
                tabID: resolvedTarget.tabID
            ),
            let selection = await PaneArrangementRevealPolicy.resolve(
                target: resolvedTarget.target,
                from: snapshot
            ),
            selection.target == resolvedTarget.target,
            store.tabArrangementAtom.validatesPaneArrangementRevealSelection(selection),
            targetRelationshipIsCurrent(resolvedTarget)
        else { return false }

        if store.tabLayoutAtom.activeTabId != selection.tabID {
            guard await execute(.selectTab(tabId: selection.tabID)),
                store.tabLayoutAtom.activeTabId == selection.tabID,
                store.tabArrangementAtom.validatesPaneArrangementRevealSelection(selection),
                targetRelationshipIsCurrent(resolvedTarget)
            else { return false }
        }

        if selection.arrangementID != snapshot.activeArrangementID {
            guard
                await execute(
                    .switchArrangement(tabId: selection.tabID, arrangementId: selection.arrangementID)
                )
            else { return false }
        }

        guard await validatesCurrentSelection(selection, resolvedTarget: resolvedTarget) else { return false }

        switch resolvedTarget.target {
        case .mainPane(let targetPaneID):
            beforeFocus()
            return applyFocus(.command(.focusPane(tabId: selection.tabID, paneId: targetPaneID)))

        case .drawerChild(let drawerPaneID, let parentPaneID, _):
            if !store.paneAtom.isDrawerExpanded(for: parentPaneID) {
                guard await execute(.toggleDrawer(paneId: parentPaneID)),
                    await validatesCurrentSelection(selection, resolvedTarget: resolvedTarget),
                    store.paneAtom.isDrawerExpanded(for: parentPaneID)
                else { return false }
            }

            if selection.requiresDrawerChildExpansion
                || selection.arrangementID != snapshot.activeArrangementID
            {
                guard
                    await execute(
                        .expandDrawerPane(parentPaneId: parentPaneID, drawerPaneId: drawerPaneID)
                    ),
                    await validatesCurrentSelection(
                        selection,
                        resolvedTarget: resolvedTarget,
                        requireDrawerChildExpanded: true
                    )
                else { return false }
            }

            beforeFocus()
            guard applyFocus(.command(.focusPane(tabId: selection.tabID, paneId: parentPaneID))) else {
                return false
            }
            return applyFocus(
                .drawer(.selectPane(parentPaneId: parentPaneID, drawerPaneId: drawerPaneID))
            )
        }
    }

    private func resolveTarget(paneID: UUID) -> ResolvedTarget? {
        let paneGraph = store.paneAtom.graphAtom
        guard let paneState = paneGraph.paneState(paneID) else { return nil }
        if let parentPaneID = paneState.parentPaneId {
            guard let parentState = paneGraph.paneState(parentPaneID),
                let drawerID = parentState.ownedDrawerId,
                paneGraph.parentPaneID(containingDrawer: drawerID) == parentPaneID,
                let tabID = store.tabLayoutAtom.tabID(containingPane: parentPaneID),
                store.tabLayoutAtom.tabID(containingPane: paneID) == tabID
            else { return nil }
            return ResolvedTarget(
                tabID: tabID,
                target: .drawerChild(
                    paneID: paneID,
                    parentPaneID: parentPaneID,
                    drawerID: drawerID
                )
            )
        }

        guard let tabID = store.tabLayoutAtom.tabID(containingPane: paneID) else { return nil }
        return ResolvedTarget(tabID: tabID, target: .mainPane(paneID))
    }

    private func targetRelationshipIsCurrent(_ resolvedTarget: ResolvedTarget) -> Bool {
        let paneGraph = store.paneAtom.graphAtom
        switch resolvedTarget.target {
        case .mainPane(let paneID):
            guard let paneState = paneGraph.paneState(paneID) else { return false }
            return paneState.parentPaneId == nil
                && store.tabLayoutAtom.tabID(containingPane: paneID) == resolvedTarget.tabID
        case .drawerChild(let paneID, let parentPaneID, let drawerID):
            guard paneGraph.paneState(paneID)?.parentPaneId == parentPaneID,
                paneGraph.paneState(parentPaneID)?.ownedDrawerId == drawerID
            else { return false }
            return paneGraph.parentPaneID(containingDrawer: drawerID) == parentPaneID
                && store.tabLayoutAtom.tabID(containingPane: parentPaneID) == resolvedTarget.tabID
                && store.tabLayoutAtom.tabID(containingPane: paneID) == resolvedTarget.tabID
        }
    }

    private func validatesCurrentSelection(
        _ originalSelection: PaneArrangementRevealSelection,
        resolvedTarget: ResolvedTarget,
        requireDrawerChildExpanded: Bool = false
    ) async -> Bool {
        guard store.tabLayoutAtom.activeTabId == originalSelection.tabID,
            targetRelationshipIsCurrent(resolvedTarget),
            let freshSnapshot = store.tabArrangementAtom.capturePaneArrangementRevealSnapshot(
                tabID: originalSelection.tabID
            ),
            freshSnapshot.activeArrangementID == originalSelection.arrangementID
        else { return false }

        guard
            let freshSelection = await PaneArrangementRevealPolicy.resolve(
                target: originalSelection.target,
                from: freshSnapshot
            )
        else { return false }

        guard store.tabLayoutAtom.activeTabId == originalSelection.tabID,
            targetRelationshipIsCurrent(resolvedTarget),
            freshSelection.tabID == originalSelection.tabID,
            freshSelection.arrangementID == originalSelection.arrangementID,
            freshSelection.target == originalSelection.target,
            store.tabArrangementAtom.validatesPaneArrangementRevealSelection(freshSelection)
        else { return false }

        return !requireDrawerChildExpanded || !freshSelection.requiresDrawerChildExpansion
    }
}

private struct ResolvedTarget {
    let tabID: UUID
    let target: PaneArrangementRevealTarget
}
