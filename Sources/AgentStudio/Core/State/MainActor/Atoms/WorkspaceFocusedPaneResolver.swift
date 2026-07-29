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
            let activeMainPaneId = activeTab.activePaneId,
            let activeMainPane = workspacePane.pane(activeMainPaneId)
        else {
            return nil
        }

        let drawer = activeMainPane.drawer
        let drawerView = drawer.flatMap { activeTab.activeArrangement.drawerViews[$0.drawerId] }
        let normalizedOwner = WorkspaceFocusOwnerNormalizer.normalize(
            requested: requestedOwner,
            context: .init(
                activeMainPaneId: activeMainPaneId,
                expandedDrawerParentPaneId: drawer?.isExpanded == true ? activeMainPaneId : nil,
                paneIds: drawer?.paneIds ?? [],
                activeDrawerPaneId: drawerView?.activeChildId,
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
