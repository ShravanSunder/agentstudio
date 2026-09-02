import Foundation

@MainActor
package struct WorkspaceFocusedPaneResolver {
    package init() {}

    package func resolve(
        workspaceTab: WorkspaceTabLayoutDerived,
        workspacePane: WorkspacePaneAtom,
        requestedOwner: WorkspaceFocusOwner
    ) -> WorkspaceFocusedPane? {
        guard
            let activeTabId = workspaceTab.shellAtom.activeTabId,
            let activeTab = workspaceTab.tab(activeTabId),
            let activeMainPaneId = workspacePane.activeResidencyPaneId(
                preferred: activeTab.activePaneId,
                in: activeTab.activeArrangement.layout.paneIds
            ),
            let activeMainPane = workspacePane.pane(activeMainPaneId)
        else {
            return nil
        }

        let drawer = activeMainPane.drawer
        let drawerView = drawer.flatMap { activeTab.activeArrangement.drawerViews[$0.drawerId] }
        let activeDrawerPaneIds = workspacePane.activeResidencyPaneIds(in: drawer?.paneIds ?? [])
        let activeDrawerPaneId = drawerView?.activeChildId.flatMap { activeChildId in
            activeDrawerPaneIds.contains(activeChildId) ? activeChildId : nil
        }
        let normalizedOwner = WorkspaceFocusOwnerNormalizer.normalize(
            requested: requestedOwner,
            context: .init(
                activeMainPaneId: activeMainPaneId,
                expandedDrawerParentPaneId: drawer?.isExpanded == true ? activeMainPaneId : nil,
                paneIds: activeDrawerPaneIds,
                activeDrawerPaneId: activeDrawerPaneId,
                minimizedDrawerPaneIds: drawerView?.minimizedPaneIds ?? []
            )
        )

        let focusedPane: Pane
        switch normalizedOwner {
        case .mainPane:
            focusedPane = activeMainPane
        case .emptyDrawer:
            focusedPane = activeMainPane
        case .drawerPane(_, let paneId):
            focusedPane = workspacePane.pane(paneId) ?? activeMainPane
        }

        return WorkspaceFocusedPane(
            owner: normalizedOwner,
            activeMainPaneId: activeMainPaneId,
            paneId: focusedPane.id,
            repoId: focusedPane.repoId,
            worktreeId: focusedPane.worktreeId,
            contentType: Self.contentType(for: focusedPane.content)
        )
    }

    private static func contentType(for content: PaneContent) -> WorkspaceFocusedPane.ContentType {
        switch content {
        case .terminal:
            return .terminal
        case .webview:
            return .webview
        case .bridgePanel:
            return .bridge
        case .codeViewer:
            return .codeViewer
        case .unsupported:
            return .unsupported
        }
    }
}
