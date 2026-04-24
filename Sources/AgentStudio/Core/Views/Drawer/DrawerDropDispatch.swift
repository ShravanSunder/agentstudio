import Foundation

/// Validation + dispatch for drawer-child rearrange drops.
///
/// Extracted from `DrawerPanel` so the drop-capture NSView can be mounted at
/// `FlatTabStripContainer` level (above the drawer subtree) while the dispatch
/// logic stays independent of view placement. AppKit's drag destination
/// traversal does not reach the original nested capture; the destination must
/// sit at tab depth.
@MainActor
enum DrawerDropDispatch {
    static func shouldAcceptDrop(
        payload: SplitDropPayload,
        target: DrawerRearrangeTarget,
        sizingMode: DropSizingMode,
        parentPaneId: UUID,
        store: WorkspaceStore
    ) -> Bool {
        guard case .existingPane(let sourcePaneId, _) = payload.kind else { return false }
        guard let sourcePane = store.paneAtom.pane(sourcePaneId) else { return false }
        guard sourcePane.parentPaneId == parentPaneId else { return false }

        let snapshot = WorkspaceCommandResolver.snapshot(
            from: store.tabLayoutAtom.tabs,
            activeTabId: store.tabLayoutAtom.activeTabId,
            isManagementLayerActive: atom(\.managementLayer).isActive,
            knownWorktreeIds: Set(store.repositoryTopologyAtom.repos.flatMap(\.worktrees).map(\.id)),
            drawerParentByPaneId: drawerParentByPaneId(store: store),
            drawerLayoutByParentPaneId: drawerLayoutByParentPaneId(store: store)
        )
        let moveAction = PaneActionCommand.moveDrawerPane(
            parentPaneId: parentPaneId,
            drawerPaneId: sourcePaneId,
            target: target,
            sizingMode: sizingMode
        )
        let validation = WorkspaceCommandValidator.validate(moveAction, state: snapshot)
        RestoreTrace.log(
            "DrawerDropDispatch.shouldAcceptDrop parent=\(parentPaneId) source=\(sourcePaneId) target=\(String(describing: target)) validation=\(String(describing: validation))"
        )
        if case .success = validation {
            return true
        }
        return false
    }

    static func handleDrop(
        payload: SplitDropPayload,
        target: DrawerRearrangeTarget,
        sizingMode: DropSizingMode,
        parentPaneId: UUID,
        actionDispatcher: PaneActionDispatching,
        store: WorkspaceStore
    ) {
        guard case .existingPane(let sourcePaneId, _) = payload.kind else { return }
        guard let sourcePane = store.paneAtom.pane(sourcePaneId) else { return }
        guard sourcePane.parentPaneId == parentPaneId else { return }

        actionDispatcher.dispatch(
            .moveDrawerPane(
                parentPaneId: parentPaneId,
                drawerPaneId: sourcePaneId,
                target: target,
                sizingMode: sizingMode
            )
        )
    }

    private static func drawerParentByPaneId(store: WorkspaceStore) -> [UUID: UUID] {
        Dictionary(
            uniqueKeysWithValues: store.paneAtom.panes.values.compactMap { pane in
                guard let drawerParentPaneId = pane.parentPaneId else { return nil }
                return (pane.id, drawerParentPaneId)
            }
        )
    }

    private static func drawerLayoutByParentPaneId(store: WorkspaceStore) -> [UUID: DrawerGridLayout] {
        Dictionary(
            uniqueKeysWithValues: store.paneAtom.panes.values.compactMap { pane in
                guard let drawer = pane.drawer else { return nil }
                return (pane.id, drawer.layout)
            }
        )
    }
}
