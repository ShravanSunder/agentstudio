import Foundation
import Testing

@testable import AgentStudio

@MainActor
struct PaneTabViewControllerPaneInboxCommandTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("showPaneInboxNotifications opens for parent pane plus drawer children")
    func executeShowPaneInboxNotifications_opensPaneInboxPresenter() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let parentPane = harness.store.createPane(
            launchDirectory: worktree.path,
            title: "Parent",
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))

        harness.controller.execute(.showPaneInboxNotifications)

        #expect(harness.paneInboxPresenter.request?.parentPaneId == parentPane.id)
        #expect(harness.paneInboxPresenter.request?.paneIds == [parentPane.id, drawerPane.id])
    }

    @Test("showPaneInboxNotifications resolves drawer child focus to parent pane scope")
    func executeShowPaneInboxNotifications_fromPaneInboxChildFocusOpensParentPaneInbox() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let parentPane = harness.store.createPane(
            launchDirectory: worktree.path,
            title: "Parent",
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let firstDrawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        let secondDrawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        harness.store.setActivePane(firstDrawerPane.id, inTab: tab.id)

        harness.controller.execute(.showPaneInboxNotifications)

        #expect(harness.paneInboxPresenter.request?.parentPaneId == parentPane.id)
        #expect(
            harness.paneInboxPresenter.request?.paneIds == [parentPane.id, firstDrawerPane.id, secondDrawerPane.id])
    }

    @Test("showPaneInboxNotifications opens for parent pane without drawer children")
    func executeShowPaneInboxNotifications_withoutDrawerChildrenOpensForParentPane() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane()
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        harness.controller.execute(.showPaneInboxNotifications)

        #expect(harness.paneInboxPresenter.request?.parentPaneId == pane.id)
        #expect(harness.paneInboxPresenter.request?.paneIds == [pane.id])
    }

    @Test("showPaneInboxNotifications toggles an already-open pane inbox closed")
    func executeShowPaneInboxNotifications_togglesOpenPaneInboxClosed() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane()
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        harness.controller.execute(.showPaneInboxNotifications)
        #expect(harness.paneInboxPresenter.request?.parentPaneId == pane.id)

        harness.controller.execute(.showPaneInboxNotifications)
        #expect(harness.paneInboxPresenter.request == nil)
    }

    @Test("clearPaneInboxNotifications clears active parent pane scope")
    func executeClearPaneInboxNotificationsClearsActiveParentPaneScope() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane()
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))

        harness.controller.execute(.clearPaneInboxNotifications)

        #expect(harness.launchRecorder.clearedPaneInboxRequests.count == 1)
        #expect(harness.launchRecorder.clearedPaneInboxRequests.first?.parentPaneId == parentPane.id)
        #expect(harness.launchRecorder.clearedPaneInboxRequests.first?.paneIds == [parentPane.id, drawerPane.id])
    }

    @Test("targeted clearPaneInboxNotifications resolves inactive drawer child to parent scope")
    func executeClearPaneInboxNotificationsTargetedDrawerChildClearsRequestedParentScope() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane()
        let parentTab = Tab(paneId: parentPane.id)
        harness.store.appendTab(parentTab)
        let unrelatedPane = harness.store.createPane()
        let unrelatedTab = Tab(paneId: unrelatedPane.id)
        harness.store.appendTab(unrelatedTab)
        harness.store.setActiveTab(unrelatedTab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))

        #expect(
            harness.controller.canExecute(
                .clearPaneInboxNotifications,
                target: drawerPane.id,
                targetType: .pane
            )
        )

        harness.controller.execute(.clearPaneInboxNotifications, target: drawerPane.id, targetType: .pane)

        #expect(harness.launchRecorder.clearedPaneInboxRequests.count == 1)
        #expect(harness.launchRecorder.clearedPaneInboxRequests.first?.parentPaneId == parentPane.id)
        #expect(harness.launchRecorder.clearedPaneInboxRequests.first?.paneIds == [parentPane.id, drawerPane.id])
    }

    @Test("targeted showPaneInboxNotifications opens requested inactive pane scope")
    func executeShowPaneInboxNotificationsTargetedOpensRequestedInactivePaneScope() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane()
        let parentTab = Tab(paneId: parentPane.id)
        harness.store.appendTab(parentTab)
        let unrelatedPane = harness.store.createPane()
        let unrelatedTab = Tab(paneId: unrelatedPane.id)
        harness.store.appendTab(unrelatedTab)
        harness.store.setActiveTab(unrelatedTab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))

        #expect(harness.store.activeTabId == unrelatedTab.id)
        harness.controller.execute(.showPaneInboxNotifications, target: parentPane.id, targetType: .pane)

        #expect(harness.store.activeTabId == parentTab.id)
        #expect(harness.store.tab(parentTab.id)?.activePaneId == parentPane.id)
        #expect(harness.paneInboxPresenter.request?.parentPaneId == parentPane.id)
        #expect(harness.paneInboxPresenter.request?.paneIds == [parentPane.id, drawerPane.id])
    }

    @Test("targeted pane inbox commands accept panes hidden by active arrangement visibility")
    func executePaneInboxNotificationsTargetedAcceptsArrangementHiddenPane() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let visiblePane = harness.store.createPane()
        let hiddenPane = harness.store.createPane()
        let tab = Tab(paneId: visiblePane.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            hiddenPane.id,
            inTab: tab.id,
            at: visiblePane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        let visibleArrangementId = try #require(
            harness.store.createArrangement(
                name: "Visible Only",
                inTab: tab.id
            )
        )
        harness.store.switchArrangement(to: visibleArrangementId, inTab: tab.id)
        #expect(harness.store.minimizePane(hiddenPane.id, inTab: tab.id))
        harness.store.tabLayoutAtom.setShowsMinimizedPanes(false, inTab: tab.id)

        #expect(harness.store.tab(tab.id)?.activePaneIds == [visiblePane.id, hiddenPane.id])
        #expect(harness.store.tab(tab.id)?.activeMinimizedPaneIds == [hiddenPane.id])
        #expect(harness.store.tab(tab.id)?.activeArrangementId == visibleArrangementId)
        #expect(harness.store.tab(tab.id)?.allPaneIds.contains(hiddenPane.id) == true)
        #expect(
            harness.controller.canExecute(
                .showPaneInboxNotifications,
                target: hiddenPane.id,
                targetType: .pane
            )
        )
        #expect(
            harness.controller.canExecute(
                .clearPaneInboxNotifications,
                target: hiddenPane.id,
                targetType: .pane
            )
        )

        harness.controller.execute(.clearPaneInboxNotifications, target: hiddenPane.id, targetType: .pane)
        #expect(harness.store.tab(tab.id)?.activeArrangementId == visibleArrangementId)

        harness.controller.execute(.showPaneInboxNotifications, target: hiddenPane.id, targetType: .pane)

        let focusedTab = try #require(harness.store.tab(tab.id))
        #expect(focusedTab.activeArrangementId == visibleArrangementId)
        #expect(focusedTab.activePaneIds.contains(hiddenPane.id))
        #expect(focusedTab.activePaneId == hiddenPane.id)
        #expect(harness.launchRecorder.clearedPaneInboxRequests.count == 1)
        #expect(harness.launchRecorder.clearedPaneInboxRequests.first?.parentPaneId == hiddenPane.id)
        #expect(harness.launchRecorder.clearedPaneInboxRequests.first?.paneIds == [hiddenPane.id])
        #expect(harness.paneInboxPresenter.request?.parentPaneId == hiddenPane.id)
        #expect(harness.paneInboxPresenter.request?.paneIds == [hiddenPane.id])
    }

    @Test("targeted showPaneInboxNotifications resolves drawer child and focuses owner")
    func executeShowPaneInboxNotificationsTargetedDrawerChildFocusesOwningScope() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane()
        let parentTab = Tab(paneId: parentPane.id)
        harness.store.appendTab(parentTab)
        let unrelatedPane = harness.store.createPane()
        let unrelatedTab = Tab(paneId: unrelatedPane.id)
        harness.store.appendTab(unrelatedTab)
        harness.store.setActiveTab(unrelatedTab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        harness.store.toggleDrawer(for: parentPane.id)
        #expect(harness.store.pane(parentPane.id)?.drawer?.isExpanded == false)

        #expect(
            harness.controller.canExecute(
                .showPaneInboxNotifications,
                target: drawerPane.id,
                targetType: .pane
            )
        )
        harness.controller.execute(.showPaneInboxNotifications, target: drawerPane.id, targetType: .pane)

        #expect(harness.store.activeTabId == parentTab.id)
        #expect(harness.store.tab(parentTab.id)?.activePaneId == parentPane.id)
        #expect(harness.store.pane(parentPane.id)?.drawer?.isExpanded == true)
        #expect(harness.store.drawerView(forParent: parentPane.id)?.activeChildId == drawerPane.id)
        #expect(harness.paneInboxPresenter.request?.parentPaneId == parentPane.id)
        #expect(harness.paneInboxPresenter.request?.paneIds == [parentPane.id, drawerPane.id])
    }

    @Test("targeted pane inbox commands reject unattached pane objects")
    func executePaneInboxNotificationsTargetedUnattachedPaneDoesNotFallbackToActiveScope() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let activePane = harness.store.createPane()
        let activeTab = Tab(paneId: activePane.id)
        harness.store.appendTab(activeTab)
        harness.store.setActiveTab(activeTab.id)
        let unattachedPane = harness.store.createPane()

        #expect(
            !harness.controller.canExecute(
                .showPaneInboxNotifications,
                target: unattachedPane.id,
                targetType: .pane
            )
        )
        #expect(
            !harness.controller.canExecute(
                .clearPaneInboxNotifications,
                target: unattachedPane.id,
                targetType: .pane
            )
        )

        harness.controller.execute(.showPaneInboxNotifications, target: unattachedPane.id, targetType: .pane)
        harness.controller.execute(.clearPaneInboxNotifications, target: unattachedPane.id, targetType: .pane)

        #expect(harness.paneInboxPresenter.request == nil)
        #expect(harness.launchRecorder.clearedPaneInboxRequests.isEmpty)
    }

    @Test("targeted pane inbox commands ignore stale pane targets without active fallback")
    func executePaneInboxNotificationsTargetedStalePaneDoesNotFallbackToActiveScope() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let activePane = harness.store.createPane()
        let activeTab = Tab(paneId: activePane.id)
        harness.store.appendTab(activeTab)
        harness.store.setActiveTab(activeTab.id)
        let stalePaneId = UUID()

        #expect(
            !harness.controller.canExecute(
                .showPaneInboxNotifications,
                target: stalePaneId,
                targetType: .pane
            )
        )
        #expect(
            !harness.controller.canExecute(
                .clearPaneInboxNotifications,
                target: stalePaneId,
                targetType: .pane
            )
        )

        harness.controller.execute(.showPaneInboxNotifications, target: stalePaneId, targetType: .pane)
        harness.controller.execute(.clearPaneInboxNotifications, target: stalePaneId, targetType: .pane)

        #expect(harness.paneInboxPresenter.request == nil)
        #expect(harness.launchRecorder.clearedPaneInboxRequests.isEmpty)
    }
}
