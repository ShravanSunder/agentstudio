import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspacePersistenceTransformerTests {
    @Test
    func hydrate_restoresWorktreeBoundPaneWhenTopologyIsPresent() {
        let identityAtom = WorkspaceIdentityAtom()
        let windowMemoryAtom = WorkspaceWindowMemoryAtom()
        let topologyAtom = WorkspaceRepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayoutAtom = WorkspaceTabLayoutAtom()

        let repoId = UUID()
        let worktreeId = UUID()
        let canonicalRepo = CanonicalRepo(
            id: repoId,
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio")
        )
        let canonicalWorktree = CanonicalWorktree(
            id: worktreeId,
            repoId: repoId,
            name: "main",
            path: URL(fileURLWithPath: "/tmp/agent-studio"),
            isMainWorktree: true
        )
        let pane = Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                source: .worktree(
                    worktreeId: worktreeId,
                    repoId: repoId,
                    launchDirectory: URL(fileURLWithPath: "/tmp/agent-studio")
                ),
                title: "Restored"
            )
        )
        let tab = Tab(paneId: pane.id)
        let state = WorkspacePersistor.PersistableState(
            id: UUID(),
            repos: [canonicalRepo],
            worktrees: [canonicalWorktree],
            panes: [pane],
            tabs: [tab],
            activeTabId: tab.id
        )

        WorkspacePersistenceTransformer.hydrate(
            state,
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: topologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom
        )

        #expect(topologyAtom.repo(repoId) != nil)
        #expect(paneAtom.pane(pane.id)?.worktreeId == worktreeId)
        #expect(tabLayoutAtom.tabs.count == 1)
        #expect(tabLayoutAtom.tabs[0].paneIds == [pane.id])
    }

    @Test
    func makePersistableState_prunesTemporaryPanesFromTabs() {
        let identityAtom = WorkspaceIdentityAtom()
        let windowMemoryAtom = WorkspaceWindowMemoryAtom()
        let topologyAtom = WorkspaceRepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayoutAtom = WorkspaceTabLayoutAtom()

        identityAtom.hydrate(
            workspaceId: UUID(),
            workspaceName: "Workspace",
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        windowMemoryAtom.hydrate(
            sidebarWidth: 250,
            windowFrame: nil
        )

        let persistentPane = makePane(title: "Persistent")
        let temporaryPane = makePane(title: "Temporary", lifetime: .temporary)
        paneAtom.addPane(persistentPane)
        paneAtom.addPane(temporaryPane)
        let tab = makeTab(paneIds: [persistentPane.id, temporaryPane.id], activePaneId: temporaryPane.id)
        tabLayoutAtom.appendTab(tab)
        tabLayoutAtom.setActiveTab(tab.id)

        let state = WorkspacePersistenceTransformer.makePersistableState(
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: topologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom,
            persistedAt: Date(timeIntervalSince1970: 2000)
        )

        #expect(state.panes.map(\.id) == [persistentPane.id])
        #expect(state.tabs.count == 1)
        #expect(state.tabs[0].paneIds == [persistentPane.id])
        #expect(state.activeTabId == tab.id)
    }

    @Test
    func makePersistableState_prunesTemporaryPanesFromArrangementMinimizedPaneIds() {
        let identityAtom = WorkspaceIdentityAtom()
        let windowMemoryAtom = WorkspaceWindowMemoryAtom()
        let topologyAtom = WorkspaceRepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayoutAtom = WorkspaceTabLayoutAtom()

        identityAtom.hydrate(
            workspaceId: UUID(),
            workspaceName: "Workspace",
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        windowMemoryAtom.hydrate(
            sidebarWidth: 250,
            windowFrame: nil
        )

        let persistentPane = makePane(title: "Persistent")
        let temporaryPane = makePane(title: "Temporary", lifetime: .temporary)
        paneAtom.addPane(persistentPane)
        paneAtom.addPane(temporaryPane)

        var tab = makeTab(
            paneIds: [persistentPane.id, temporaryPane.id],
            activePaneId: persistentPane.id
        )
        tab.arrangements[tab.activeArrangementIndex].minimizedPaneIds = [persistentPane.id, temporaryPane.id]
        tabLayoutAtom.appendTab(tab)
        tabLayoutAtom.setActiveTab(tab.id)

        let state = WorkspacePersistenceTransformer.makePersistableState(
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: topologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom,
            persistedAt: Date(timeIntervalSince1970: 2000)
        )

        #expect(state.tabs[0].activeMinimizedPaneIds == Set([persistentPane.id]))
        #expect(state.tabs[0].activeArrangement.layout.paneIds == [persistentPane.id])
    }

    @Test
    func makePersistableState_prunesTemporaryPanesFromDrawerViews() throws {
        let identityAtom = WorkspaceIdentityAtom()
        let windowMemoryAtom = WorkspaceWindowMemoryAtom()
        let topologyAtom = WorkspaceRepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayoutAtom = WorkspaceTabLayoutAtom()

        identityAtom.hydrate(
            workspaceId: UUID(),
            workspaceName: "Workspace",
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        windowMemoryAtom.hydrate(
            sidebarWidth: 250,
            windowFrame: nil
        )

        let parentPane = makePane(title: "Parent")
        let persistentDrawerPane = makePane(title: "Persistent Drawer")
        let temporaryDrawerPane = makePane(title: "Temporary Drawer", lifetime: .temporary)
        paneAtom.addPane(parentPane)
        paneAtom.addPane(persistentDrawerPane)
        paneAtom.addPane(temporaryDrawerPane)

        var tab = makeTab(paneIds: [parentPane.id], activePaneId: parentPane.id)
        let drawerId = UUID()
        let drawerLayout = DrawerGridLayout(
            topRow: Layout(paneId: persistentDrawerPane.id)
                .inserting(
                    paneId: temporaryDrawerPane.id,
                    at: persistentDrawerPane.id,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )!
        )
        tab.arrangements[tab.activeArrangementIndex].drawerViews[drawerId] = DrawerView(
            layout: drawerLayout,
            activeChildId: temporaryDrawerPane.id,
            minimizedPaneIds: [temporaryDrawerPane.id]
        )
        tabLayoutAtom.appendTab(tab)
        tabLayoutAtom.setActiveTab(tab.id)

        let state = WorkspacePersistenceTransformer.makePersistableState(
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: topologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom,
            persistedAt: Date(timeIntervalSince1970: 2000)
        )

        let drawerView = try #require(state.tabs[0].arrangements[0].drawerViews[drawerId])
        #expect(drawerView.layout.paneIds == [persistentDrawerPane.id])
        #expect(drawerView.minimizedPaneIds.isEmpty)
        #expect(drawerView.activeChildId == persistentDrawerPane.id)
    }

    @Test
    func makePersistableState_repairSkipsMinimizedRemainingPaneWhenActivePaneWasPruned() {
        let identityAtom = WorkspaceIdentityAtom()
        let windowMemoryAtom = WorkspaceWindowMemoryAtom()
        let topologyAtom = WorkspaceRepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayoutAtom = WorkspaceTabLayoutAtom()

        identityAtom.hydrate(
            workspaceId: UUID(),
            workspaceName: "Workspace",
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        windowMemoryAtom.hydrate(
            sidebarWidth: 250,
            windowFrame: nil
        )

        let persistentPane = makePane(title: "Persistent")
        let temporaryPane = makePane(title: "Temporary", lifetime: .temporary)
        paneAtom.addPane(persistentPane)
        paneAtom.addPane(temporaryPane)

        var tab = makeTab(
            paneIds: [persistentPane.id, temporaryPane.id],
            activePaneId: temporaryPane.id
        )
        tab.arrangements[tab.activeArrangementIndex].minimizedPaneIds = [persistentPane.id]
        tabLayoutAtom.appendTab(tab)
        tabLayoutAtom.setActiveTab(tab.id)

        let state = WorkspacePersistenceTransformer.makePersistableState(
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: topologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom,
            persistedAt: Date(timeIntervalSince1970: 2000)
        )

        #expect(state.tabs.count == 1)
        #expect(state.tabs[0].activePaneId == nil)
    }

    @Test
    func makePersistableState_fallsBackToDefaultWhenActiveCustomArrangementBecomesEmpty() throws {
        let identityAtom = WorkspaceIdentityAtom()
        let windowMemoryAtom = WorkspaceWindowMemoryAtom()
        let topologyAtom = WorkspaceRepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayoutAtom = WorkspaceTabLayoutAtom()

        identityAtom.hydrate(
            workspaceId: UUID(),
            workspaceName: "Workspace",
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        windowMemoryAtom.hydrate(
            sidebarWidth: 250,
            windowFrame: nil
        )

        let persistentPane = makePane(title: "Persistent")
        let temporaryPane = makePane(title: "Temporary", lifetime: .temporary)
        paneAtom.addPane(persistentPane)
        paneAtom.addPane(temporaryPane)

        var tab = makeTab(
            paneIds: [persistentPane.id, temporaryPane.id],
            activePaneId: temporaryPane.id
        )
        let customArrangement = PaneArrangement(
            name: "Temporary Only",
            isDefault: false,
            layout: Layout(paneId: temporaryPane.id),
            activePaneId: temporaryPane.id
        )
        tab.arrangements.append(customArrangement)
        tab.activeArrangementId = customArrangement.id
        tabLayoutAtom.appendTab(tab)
        tabLayoutAtom.setActiveTab(tab.id)

        let state = WorkspacePersistenceTransformer.makePersistableState(
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: topologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom,
            persistedAt: Date(timeIntervalSince1970: 2000)
        )

        #expect(state.tabs.count == 1)
        #expect(state.tabs[0].activeArrangementId == state.tabs[0].defaultArrangement.id)
        #expect(state.tabs[0].activeArrangement.layout.paneIds == [persistentPane.id])
        #expect(state.tabs[0].activePaneId == persistentPane.id)
    }

    @Test
    func makePersistableState_preservesTabWhenDefaultArrangementIsEmptyButCustomArrangementHasPane() {
        let identityAtom = WorkspaceIdentityAtom()
        let windowMemoryAtom = WorkspaceWindowMemoryAtom()
        let topologyAtom = WorkspaceRepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayoutAtom = WorkspaceTabLayoutAtom()

        identityAtom.hydrate(
            workspaceId: UUID(),
            workspaceName: "Workspace",
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        windowMemoryAtom.hydrate(
            sidebarWidth: 250,
            windowFrame: nil
        )

        let pane = makePane(title: "Persistent")
        paneAtom.addPane(pane)
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(),
            activePaneId: nil
        )
        let customArrangement = PaneArrangement(
            name: "Working",
            isDefault: false,
            layout: Layout(paneId: pane.id),
            activePaneId: pane.id
        )
        let tab = Tab(
            name: "Custom only",
            allPaneIds: [pane.id],
            arrangements: [defaultArrangement, customArrangement],
            activeArrangementId: customArrangement.id
        )
        tabLayoutAtom.appendTab(tab)
        tabLayoutAtom.setActiveTab(tab.id)

        let state = WorkspacePersistenceTransformer.makePersistableState(
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: topologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom,
            persistedAt: Date(timeIntervalSince1970: 2000)
        )

        #expect(state.tabs.map(\.id) == [tab.id])
        #expect(state.activeTabId == tab.id)
        #expect(state.tabs[0].activeArrangement.layout.paneIds == [pane.id])
    }
}
