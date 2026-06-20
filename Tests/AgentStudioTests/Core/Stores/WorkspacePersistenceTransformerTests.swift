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
                launchDirectory: URL(fileURLWithPath: "/tmp/agent-studio"),
                title: "Restored",
                facets: PaneContextFacets(
                    repoId: repoId,
                    worktreeId: worktreeId,
                    cwd: URL(fileURLWithPath: "/tmp/agent-studio")
                )
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
    func hydrate_reportsTabMembershipRepair() {
        let identityAtom = WorkspaceIdentityAtom()
        let windowMemoryAtom = WorkspaceWindowMemoryAtom()
        let topologyAtom = WorkspaceRepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayoutAtom = WorkspaceTabLayoutAtom()
        let customPane = makePane(title: "Custom")
        let invalidPaneId = UUID()
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: invalidPaneId),
            activePaneId: invalidPaneId
        )
        let customArrangement = PaneArrangement(
            name: "Custom",
            isDefault: false,
            layout: Layout(paneId: customPane.id),
            activePaneId: customPane.id
        )
        let tab = Tab(
            name: "Broken",
            allPaneIds: [invalidPaneId, customPane.id],
            arrangements: [defaultArrangement, customArrangement],
            activeArrangementId: customArrangement.id
        )
        let state = WorkspacePersistor.PersistableState(
            id: UUID(),
            panes: [customPane],
            tabs: [tab],
            activeTabId: tab.id
        )

        let repairReport = WorkspacePersistenceTransformer.hydrate(
            state,
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: topologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom
        )

        #expect(repairReport.repairedTabIds == [tab.id])
        #expect(!repairReport.activeTabIdChanged)
        #expect(tabLayoutAtom.tab(tab.id)?.allPaneIds == [customPane.id])
        #expect(tabLayoutAtom.tab(tab.id)?.defaultArrangement.id == customArrangement.id)
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
    func makePersistableState_stripsDisplayFacetsWhilePreservingDrawerExpansion() throws {
        let identityAtom = WorkspaceIdentityAtom()
        let windowMemoryAtom = WorkspaceWindowMemoryAtom()
        let topologyAtom = WorkspaceRepositoryTopologyAtom()
        let repoId = UUID()
        let worktreeId = UUID()
        let repoPath = URL(filePath: "/tmp/project-dev/agent-studio")
        let worktreePath = repoPath.appending(path: "sqlite")
        topologyAtom.hydrate(
            runtimeRepos: [
                Repo(
                    id: repoId,
                    name: "agent-studio",
                    repoPath: repoPath,
                    worktrees: [
                        Worktree(id: worktreeId, repoId: repoId, name: "sqlite", path: worktreePath)
                    ]
                )
            ],
            watchedPaths: [],
            unavailableRepoIds: []
        )
        let cacheAtom = RepoEnrichmentCacheAtom()
        cacheAtom.setRepoEnrichment(
            .resolvedRemote(
                repoId: repoId,
                raw: RawRepoOrigin(origin: "origin-url", upstream: "upstream-url"),
                identity: RepoIdentity(
                    groupKey: "org",
                    remoteSlug: "org/agent-studio",
                    organizationName: "org",
                    displayName: "agent-studio"
                ),
                updatedAt: Date(timeIntervalSince1970: 1)
            )
        )
        let paneAtom = WorkspacePaneAtom(
            repositoryTopologyAtom: topologyAtom,
            repoEnrichmentCacheAtom: cacheAtom
        )
        let tabLayoutAtom = WorkspaceTabLayoutAtom()

        identityAtom.hydrate(
            workspaceId: UUID(),
            workspaceName: "Workspace",
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        windowMemoryAtom.hydrate(sidebarWidth: 250, windowFrame: nil)

        let pane = paneAtom.createPane(
            launchDirectory: worktreePath,
            facets: PaneContextFacets(
                repoId: repoId,
                repoName: "stale repo",
                worktreeId: worktreeId,
                worktreeName: "stale worktree",
                cwd: worktreePath,
                parentFolder: "stale parent",
                organizationName: "stale org",
                origin: "stale origin",
                upstream: "stale upstream"
            )
        )
        paneAtom.toggleDrawer(for: pane.id)
        tabLayoutAtom.appendTab(Tab(paneId: pane.id))

        let state = WorkspacePersistenceTransformer.makePersistableState(
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: topologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom,
            persistedAt: Date(timeIntervalSince1970: 2000)
        )

        let persistedPane = try #require(state.panes.first)
        #expect(persistedPane.drawer?.isExpanded == true)
        #expect(persistedPane.metadata.facets.repoId == repoId)
        #expect(persistedPane.metadata.facets.worktreeId == worktreeId)
        #expect(persistedPane.metadata.facets.cwd == worktreePath)
        #expect(persistedPane.metadata.facets.repoName == nil)
        #expect(persistedPane.metadata.facets.worktreeName == nil)
        #expect(persistedPane.metadata.facets.parentFolder == nil)
        #expect(persistedPane.metadata.facets.organizationName == nil)
        #expect(persistedPane.metadata.facets.origin == nil)
        #expect(persistedPane.metadata.facets.upstream == nil)
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

        let drawerId = UUID()
        var parentPane = makePane(title: "Parent")
        let persistentDrawerPane = makePane(title: "Persistent Drawer")
        let temporaryDrawerPane = makePane(title: "Temporary Drawer", lifetime: .temporary)
        parentPane.kind = .layout(
            drawer: Drawer(
                drawerId: drawerId,
                parentPaneId: parentPane.id,
                paneIds: [persistentDrawerPane.id, temporaryDrawerPane.id]
            ))
        paneAtom.addPane(parentPane)
        paneAtom.addPane(persistentDrawerPane)
        paneAtom.addPane(temporaryDrawerPane)

        var tab = makeTab(paneIds: [parentPane.id], activePaneId: parentPane.id)
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

    @Test
    func makeLiveSQLiteSnapshot_addsArrangementPanesMissingFromTabMembership() {
        let fixture = makeSQLiteSnapshotFixture()
        let firstPane = makePane(title: "First")
        let arrangementOnlyPane = makePane(title: "Arrangement Only")
        fixture.paneAtom.addPane(firstPane)
        fixture.paneAtom.addPane(arrangementOnlyPane)

        let layout = Layout(paneId: firstPane.id)
            .inserting(
                paneId: arrangementOnlyPane.id,
                at: firstPane.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )!
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: layout,
            activePaneId: arrangementOnlyPane.id
        )
        let tab = Tab(
            name: "Broken",
            allPaneIds: [firstPane.id],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )
        fixture.tabLayoutAtom.appendTab(tab)
        fixture.tabLayoutAtom.setActiveTab(tab.id)

        let snapshot = makeLiveSQLiteSnapshot(from: fixture)

        #expect(snapshot.tabs.single?.allPaneIds == [firstPane.id, arrangementOnlyPane.id])
    }

    @Test
    func makeLiveSQLiteSnapshot_prunesMembershipOnlyPanes() {
        let fixture = makeSQLiteSnapshotFixture()
        let visiblePane = makePane(title: "Visible")
        let membershipOnlyPane = makePane(title: "Membership Only")
        fixture.paneAtom.addPane(visiblePane)
        fixture.paneAtom.addPane(membershipOnlyPane)

        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: visiblePane.id),
            activePaneId: visiblePane.id
        )
        let tab = Tab(
            name: "Broken",
            allPaneIds: [visiblePane.id, membershipOnlyPane.id],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )
        fixture.tabLayoutAtom.appendTab(tab)
        fixture.tabLayoutAtom.setActiveTab(tab.id)

        let snapshot = makeLiveSQLiteSnapshot(from: fixture)

        #expect(snapshot.tabs.single?.allPaneIds == [visiblePane.id])
    }

    @Test
    func makeLiveSQLiteSnapshot_addsDrawerViewPanesMissingFromTabMembership() throws {
        let fixture = makeSQLiteSnapshotFixture()
        var parentPane = makePane(title: "Parent")
        let drawerId = try #require(parentPane.drawer?.drawerId)
        let drawerPane = Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(title: "Drawer"),
            kind: .drawerChild(parentPaneId: parentPane.id)
        )
        parentPane.withDrawer { drawer in
            drawer.paneIds = [drawerPane.id]
        }
        fixture.paneAtom.addPane(parentPane)
        fixture.paneAtom.addPane(drawerPane)

        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: parentPane.id),
            activePaneId: parentPane.id,
            drawerViews: [
                drawerId: DrawerView(
                    layout: DrawerGridLayout(topRow: Layout(paneId: drawerPane.id)),
                    activeChildId: drawerPane.id
                )
            ]
        )
        let tab = Tab(
            name: "Broken Drawer",
            allPaneIds: [parentPane.id],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )
        fixture.tabLayoutAtom.appendTab(tab)
        fixture.tabLayoutAtom.setActiveTab(tab.id)

        let snapshot = makeLiveSQLiteSnapshot(from: fixture)

        #expect(snapshot.tabs.single?.allPaneIds == [parentPane.id, drawerPane.id])
    }

    @Test
    func normalizeLiveSQLiteTabs_reportsNoRepairsForValidTab() {
        let pane = makePane(title: "Valid")
        let tab = Tab(paneId: pane.id, name: "Valid Tab")

        let result = WorkspacePersistenceTransformer.normalizeLiveSQLiteTabs(
            tabs: [tab],
            validPaneIds: [pane.id],
            activeTabId: tab.id
        )

        #expect(result.tabs == [tab])
        #expect(result.activeTabId == tab.id)
        #expect(!result.repairReport.hasRepairs)
        #expect(result.repairReport.repairedTabIds.isEmpty)
        #expect(!result.repairReport.activeTabIdChanged)
    }

    @Test
    func normalizeLiveSQLiteTabs_promotesCustomArrangementWhenDefaultPrunesEmpty() throws {
        let customPane = makePane(title: "Custom")
        let fallbackPane = makePane(title: "Fallback")
        let invalidPaneId = UUID()
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: invalidPaneId),
            activePaneId: invalidPaneId
        )
        let customArrangement = PaneArrangement(
            name: "Custom",
            isDefault: false,
            layout: Layout(paneId: customPane.id),
            activePaneId: customPane.id
        )
        let brokenTab = Tab(
            name: "Broken",
            allPaneIds: [invalidPaneId, customPane.id],
            arrangements: [defaultArrangement, customArrangement],
            activeArrangementId: customArrangement.id
        )
        let fallbackTab = Tab(paneId: fallbackPane.id, name: "Fallback")

        let result = WorkspacePersistenceTransformer.normalizeLiveSQLiteTabs(
            tabs: [brokenTab, fallbackTab],
            validPaneIds: [customPane.id, fallbackPane.id],
            activeTabId: brokenTab.id
        )

        let normalizedBrokenTab = try #require(result.tabs.first { $0.id == brokenTab.id })
        #expect(result.tabs.map(\.id) == [brokenTab.id, fallbackTab.id])
        #expect(result.activeTabId == brokenTab.id)
        #expect(normalizedBrokenTab.allPaneIds == [customPane.id])
        #expect(normalizedBrokenTab.defaultArrangement.id == customArrangement.id)
        #expect(normalizedBrokenTab.defaultArrangement.layout.paneIds == [customPane.id])
        #expect(normalizedBrokenTab.activeArrangementId == customArrangement.id)
        #expect(result.repairReport.repairedTabIds == [brokenTab.id])
        #expect(!result.repairReport.activeTabIdChanged)
    }

    @Test
    func normalizeLiveSQLiteTabs_dropsDrawerOnlyTabAfterParentPrunesEmpty() throws {
        let parentPane = makePane(title: "Parent")
        let drawerId = try #require(parentPane.drawer?.drawerId)
        let drawerPane = Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(title: "Drawer"),
            kind: .drawerChild(parentPaneId: parentPane.id)
        )
        let fallbackPane = makePane(title: "Fallback")
        let invalidParentPaneId = UUID()
        let drawerOnlyArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: invalidParentPaneId),
            activePaneId: invalidParentPaneId,
            drawerViews: [
                drawerId: DrawerView(
                    layout: DrawerGridLayout(topRow: Layout(paneId: drawerPane.id)),
                    activeChildId: drawerPane.id
                )
            ]
        )
        let brokenTab = Tab(
            name: "Drawer Only",
            allPaneIds: [invalidParentPaneId, drawerPane.id],
            arrangements: [drawerOnlyArrangement],
            activeArrangementId: drawerOnlyArrangement.id
        )
        let fallbackTab = Tab(paneId: fallbackPane.id, name: "Fallback")

        let result = WorkspacePersistenceTransformer.normalizeLiveSQLiteTabs(
            tabs: [brokenTab, fallbackTab],
            validPaneIds: [drawerPane.id, fallbackPane.id],
            activeTabId: brokenTab.id,
            drawerParentPaneIdByDrawerId: [drawerId: parentPane.id]
        )

        #expect(result.tabs.map(\.id) == [fallbackTab.id])
        #expect(result.activeTabId == fallbackTab.id)
        #expect(result.repairReport.repairedTabIds == [brokenTab.id])
        #expect(result.repairReport.activeTabIdChanged)
    }

    @Test
    func normalizeLiveSQLiteTabs_preservesDuplicatePaneOwnershipForRepositoryValidation() {
        let pane = makePane(title: "Shared")
        let firstTab = Tab(paneId: pane.id, name: "First")
        let secondTab = Tab(paneId: pane.id, name: "Second")

        let result = WorkspacePersistenceTransformer.normalizeLiveSQLiteTabs(
            tabs: [firstTab, secondTab],
            validPaneIds: [pane.id],
            activeTabId: firstTab.id
        )

        #expect(result.tabs.map(\.allPaneIds) == [[pane.id], [pane.id]])
        #expect(result.repairReport.repairedTabIds.isEmpty)
    }

    private func makeSQLiteSnapshotFixture() -> SQLiteSnapshotFixture {
        let identityAtom = WorkspaceIdentityAtom()
        let windowMemoryAtom = WorkspaceWindowMemoryAtom()
        let topologyAtom = WorkspaceRepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayoutAtom = WorkspaceTabLayoutAtom()
        identityAtom.hydrate(
            workspaceId: UUID(),
            workspaceName: "SQLite Workspace",
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        windowMemoryAtom.hydrate(sidebarWidth: 250, windowFrame: nil)
        return SQLiteSnapshotFixture(
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            topologyAtom: topologyAtom,
            paneAtom: paneAtom,
            tabLayoutAtom: tabLayoutAtom
        )
    }

    private func makeLiveSQLiteSnapshot(from fixture: SQLiteSnapshotFixture) -> WorkspaceSQLiteSnapshot {
        WorkspacePersistenceTransformer.makeLiveSQLiteSnapshot(
            identityAtom: fixture.identityAtom,
            windowMemoryAtom: fixture.windowMemoryAtom,
            repositoryTopologyAtom: fixture.topologyAtom,
            workspacePaneAtom: fixture.paneAtom,
            workspaceTabLayoutAtom: fixture.tabLayoutAtom,
            persistedAt: Date(timeIntervalSince1970: 2000)
        )
    }
}

private struct SQLiteSnapshotFixture {
    let identityAtom: WorkspaceIdentityAtom
    let windowMemoryAtom: WorkspaceWindowMemoryAtom
    let topologyAtom: WorkspaceRepositoryTopologyAtom
    let paneAtom: WorkspacePaneAtom
    let tabLayoutAtom: WorkspaceTabLayoutAtom
}
