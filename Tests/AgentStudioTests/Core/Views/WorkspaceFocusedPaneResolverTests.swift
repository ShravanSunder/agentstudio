import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite(.serialized)
struct WorkspaceFocusedPaneResolverTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test
    func missingActivePaneProducesNoFocusedPane() {
        withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let pane = store.createPane()
            let tab = Tab(paneId: pane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            store.setActivePane(nil, inTab: tab.id)

            let focusedPane = WorkspaceFocusedPaneResolver().resolve(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                requestedOwner: atom(\.workspaceFocusOwner).owner
            )

            #expect(focusedPane == nil)
        }
    }

    @Test
    func mainPaneFocusResolvesActiveMainPaneIdentityAndContent() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let activePane = store.createPane()
            let tab = Tab(paneId: activePane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            atoms.workspaceFocusOwner.focusMainPane(UUID())

            let focusedPane = try #require(
                WorkspaceFocusedPaneResolver().resolve(
                    workspaceTab: atom(\.workspaceTab),
                    workspacePane: atom(\.workspacePane),
                    requestedOwner: atoms.workspaceFocusOwner.owner
                )
            )

            #expect(focusedPane.owner == .mainPane(paneId: activePane.id))
            #expect(focusedPane.activeMainPaneId == activePane.id)
            #expect(focusedPane.paneId == activePane.id)
            #expect(focusedPane.contentType == .terminal)
        }
    }

    @Test
    func expandedDrawerWithoutChildrenRetainsEmptyDrawerFocusAndParentContext() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let parentRepoId = UUID()
            let parentWorktreeId = UUID()
            let parentPane = store.createPane(
                launchDirectory: URL(filePath: "/tmp/empty-drawer"),
                title: "Parent",
                facets: PaneContextFacets(
                    repoId: parentRepoId,
                    worktreeId: parentWorktreeId,
                    cwd: URL(filePath: "/tmp/empty-drawer")
                )
            )
            let tab = Tab(paneId: parentPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            store.toggleDrawer(for: parentPane.id)
            atoms.workspaceFocusOwner.focusEmptyDrawer(parentPaneId: parentPane.id)

            let focusedPane = try #require(
                WorkspaceFocusedPaneResolver().resolve(
                    workspaceTab: atom(\.workspaceTab),
                    workspacePane: atom(\.workspacePane),
                    requestedOwner: atoms.workspaceFocusOwner.owner
                )
            )

            #expect(focusedPane.owner == .emptyDrawer(parentPaneId: parentPane.id))
            #expect(focusedPane.activeMainPaneId == parentPane.id)
            #expect(focusedPane.paneId == parentPane.id)
            #expect(focusedPane.repoId == parentRepoId)
            #expect(focusedPane.worktreeId == parentWorktreeId)
            #expect(focusedPane.contentType == .terminal)
        }
    }

    @Test
    func validDrawerChildFocusResolvesRequestedChild() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let parentPane = store.createPane()
            let tab = Tab(paneId: parentPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            let drawerPane = try #require(store.addDrawerPane(to: parentPane.id))
            atoms.workspaceFocusOwner.focusDrawerPane(
                parentPaneId: parentPane.id,
                paneId: drawerPane.id
            )

            let focusedPane = try #require(
                WorkspaceFocusedPaneResolver().resolve(
                    workspaceTab: atom(\.workspaceTab),
                    workspacePane: atom(\.workspacePane),
                    requestedOwner: atoms.workspaceFocusOwner.owner
                )
            )

            #expect(focusedPane.owner == .drawerPane(parentPaneId: parentPane.id, paneId: drawerPane.id))
            #expect(focusedPane.activeMainPaneId == parentPane.id)
            #expect(focusedPane.paneId == drawerPane.id)
        }
    }

    @Test
    func focusedDrawerChildOwnsResolvedIdentityAndContent() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let parentPane = store.createPane()
            let tab = Tab(paneId: parentPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            store.setActivePane(parentPane.id, inTab: tab.id)

            let drawerRepoId = UUID()
            let drawerWorktreeId = UUID()
            let drawerPane = try #require(
                atoms.workspacePane.addDrawerPane(
                    to: parentPane.id,
                    content: .webview(WebviewState(url: URL(string: "https://drawer.example")!)),
                    metadata: PaneMetadata(
                        launchDirectory: URL(filePath: "/tmp/drawer"),
                        title: "Drawer",
                        facets: PaneContextFacets(
                            repoId: drawerRepoId,
                            worktreeId: drawerWorktreeId,
                            cwd: URL(filePath: "/tmp/drawer")
                        )
                    )
                )
            )
            atoms.workspaceFocusOwner.focusDrawerPane(
                parentPaneId: parentPane.id,
                paneId: drawerPane.id
            )

            let focusedPane = try #require(
                WorkspaceFocusedPaneResolver().resolve(
                    workspaceTab: atom(\.workspaceTab),
                    workspacePane: atom(\.workspacePane),
                    requestedOwner: atoms.workspaceFocusOwner.owner
                )
            )

            #expect(focusedPane.owner == .drawerPane(parentPaneId: parentPane.id, paneId: drawerPane.id))
            #expect(focusedPane.activeMainPaneId == parentPane.id)
            #expect(focusedPane.paneId == drawerPane.id)
            #expect(focusedPane.repoId == drawerRepoId)
            #expect(focusedPane.worktreeId == drawerWorktreeId)
            #expect(focusedPane.contentType == .webview)
        }
    }

    @Test
    func collapsedDrawerNormalizesRequestedDrawerFocusToMainPane() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let parentPane = store.createPane()
            let tab = Tab(paneId: parentPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            atoms.workspaceFocusOwner.focusEmptyDrawer(parentPaneId: parentPane.id)

            let focusedPane = try #require(
                WorkspaceFocusedPaneResolver().resolve(
                    workspaceTab: atom(\.workspaceTab),
                    workspacePane: atom(\.workspacePane),
                    requestedOwner: atoms.workspaceFocusOwner.owner
                )
            )

            #expect(focusedPane.owner == .mainPane(paneId: parentPane.id))
            #expect(focusedPane.paneId == parentPane.id)
        }
    }

    @Test
    func mismatchedDrawerParentFallsBackToActiveMainPane() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let parentPane = store.createPane()
            let tab = Tab(paneId: parentPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            let drawerPane = try #require(store.addDrawerPane(to: parentPane.id))
            atoms.workspaceFocusOwner.focusDrawerPane(
                parentPaneId: UUID(),
                paneId: drawerPane.id
            )

            let focusedPane = try #require(
                WorkspaceFocusedPaneResolver().resolve(
                    workspaceTab: atom(\.workspaceTab),
                    workspacePane: atom(\.workspacePane),
                    requestedOwner: atoms.workspaceFocusOwner.owner
                )
            )

            #expect(focusedPane.owner == .mainPane(paneId: parentPane.id))
            #expect(focusedPane.activeMainPaneId == parentPane.id)
            #expect(focusedPane.paneId == parentPane.id)
        }
    }

    @Test
    func staleDrawerChildFallsBackToCurrentVisibleChild() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let parentPane = store.createPane()
            let tab = Tab(paneId: parentPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            _ = try #require(store.addDrawerPane(to: parentPane.id))
            let activeDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
            atoms.workspaceFocusOwner.focusDrawerPane(
                parentPaneId: parentPane.id,
                paneId: UUID()
            )

            let focusedPane = try #require(
                WorkspaceFocusedPaneResolver().resolve(
                    workspaceTab: atom(\.workspaceTab),
                    workspacePane: atom(\.workspacePane),
                    requestedOwner: atoms.workspaceFocusOwner.owner
                )
            )

            #expect(
                focusedPane.owner
                    == .drawerPane(parentPaneId: parentPane.id, paneId: activeDrawerPane.id)
            )
            #expect(focusedPane.paneId == activeDrawerPane.id)
        }
    }

    @Test
    func minimizedDrawerChildFallsBackToVisibleChild() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let parentPane = store.createPane()
            let tab = Tab(paneId: parentPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            let minimizedDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
            let visibleDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
            store.setActiveDrawerPane(minimizedDrawerPane.id, in: parentPane.id)
            #expect(store.minimizeDrawerPane(minimizedDrawerPane.id, in: parentPane.id))
            atoms.workspaceFocusOwner.focusDrawerPane(
                parentPaneId: parentPane.id,
                paneId: minimizedDrawerPane.id
            )

            let focusedPane = try #require(
                WorkspaceFocusedPaneResolver().resolve(
                    workspaceTab: atom(\.workspaceTab),
                    workspacePane: atom(\.workspacePane),
                    requestedOwner: atoms.workspaceFocusOwner.owner
                )
            )

            #expect(
                focusedPane.owner
                    == .drawerPane(parentPaneId: parentPane.id, paneId: visibleDrawerPane.id)
            )
            #expect(focusedPane.paneId == visibleDrawerPane.id)
        }
    }
}
