import Foundation

@testable import AgentStudio

extension WorkspaceSQLiteSnapshot {
    static func emptyFixture(
        id: UUID = UUID(),
        name: String = "Workspace",
        createdAt: Date = Date(timeIntervalSince1970: 1),
        updatedAt: Date = Date(timeIntervalSince1970: 2)
    ) -> Self {
        Self(
            id: id,
            name: name,
            repos: [],
            worktrees: [],
            unavailableRepoIds: [],
            panes: [],
            tabs: [],
            activeTabId: nil,
            sidebarWidth: 250,
            windowFrame: nil,
            watchedPaths: [],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func snapshotWithArrangementPaneMissingFromTab(workspaceId: UUID = UUID()) -> Self {
        let tabPaneId = UUIDv7.generate()
        let arrangementOnlyPaneId = UUIDv7.generate()
        let tabPane = makePane(id: tabPaneId)
        let arrangementOnlyPane = makePane(id: arrangementOnlyPaneId)
        let arrangement = PaneArrangement(
            layout: Layout.autoTiled([tabPaneId, arrangementOnlyPaneId]),
            activePaneId: tabPaneId
        )
        let tab = Tab(
            name: "Invalid Tab Graph",
            allPaneIds: [tabPaneId],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )

        return Self(
            id: workspaceId,
            name: "Invalid Workspace Graph",
            panes: [tabPane, arrangementOnlyPane],
            tabs: [tab],
            activeTabId: tab.id,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
    }

    static func snapshotWithDrawerViewPaneMissingFromTab(workspaceId: UUID = UUID()) -> Self {
        let parentPaneId = UUIDv7.generate()
        let drawerPaneId = UUIDv7.generate()
        let drawerId = UUIDv7.generate()
        let parentPane = makePane(id: parentPaneId)
        let drawerPane = makePane(id: drawerPaneId)
        let arrangement = PaneArrangement(
            layout: Layout(paneId: parentPaneId),
            activePaneId: parentPaneId,
            drawerViews: [
                drawerId: DrawerView(layout: DrawerGridLayout(topRow: Layout(paneId: drawerPaneId)))
            ]
        )
        let tab = Tab(
            name: "Invalid Drawer View Graph",
            allPaneIds: [parentPaneId],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )

        return Self(
            id: workspaceId,
            name: "Invalid Drawer Workspace Graph",
            panes: [parentPane, drawerPane],
            tabs: [tab],
            activeTabId: tab.id,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
    }

    static func snapshotWithMembershipPaneMissingFromArrangements(workspaceId: UUID = UUID()) -> Self {
        let layoutPaneId = UUIDv7.generate()
        let orphanPaneId = UUIDv7.generate()
        let layoutPane = makePane(id: layoutPaneId)
        let orphanPane = makePane(id: orphanPaneId)
        let arrangement = PaneArrangement(
            layout: Layout(paneId: layoutPaneId),
            activePaneId: layoutPaneId
        )
        let tab = Tab(
            name: "Invalid Membership Graph",
            allPaneIds: [layoutPaneId, orphanPaneId],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )

        return Self(
            id: workspaceId,
            name: "Invalid Membership Workspace Graph",
            panes: [layoutPane, orphanPane],
            tabs: [tab],
            activeTabId: tab.id,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
    }

    static func snapshotWithPaneSourceFacetRepoMismatch(workspaceId: UUID = UUID()) -> Self {
        let sourceRepoId = UUID()
        let facetRepoId = UUID()
        let worktreeId = UUID()
        var pane = makePane(
            source: .worktree(
                worktreeId: worktreeId,
                repoId: sourceRepoId,
                launchDirectory: URL(fileURLWithPath: "/tmp/repo")
            )
        )
        pane.metadata.updateFacets(
            PaneContextFacets(
                repoId: facetRepoId,
                worktreeId: worktreeId,
                cwd: URL(fileURLWithPath: "/tmp/repo")
            )
        )

        return Self(
            id: workspaceId,
            name: "Invalid Pane Facets",
            panes: [pane],
            tabs: [Tab(paneId: pane.id)],
            activeTabId: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
    }
}
