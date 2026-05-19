import AppKit
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerCommandTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("execute newTab uses first watched folder as cwd fallback")
    func executeNewTab_usesFirstWatchedFolderAsFallback() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let watchedFolder = harness.tempDir.appending(path: "watched-root")
        try? FileManager.default.createDirectory(at: watchedFolder, withIntermediateDirectories: true)
        _ = harness.store.repositoryTopologyAtom.addWatchedPath(watchedFolder)
        harness.windowLifecycleStore.recordTerminalContainerBounds(CGRect(x: 0, y: 0, width: 1000, height: 600))
        let initialPaneIds = Set(harness.store.panes.keys)

        harness.controller.execute(.newTab)

        #expect(Set(harness.store.panes.keys).count == initialPaneIds.count + 1)
        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
        #expect(
            harness.surfaceManager.lastCreatedSurfaceMetadata?.cwd?.standardizedFileURL
                == watchedFolder.standardizedFileURL
        )
    }

    @Test("execute newTab falls back to user home when no watched folder exists")
    func executeNewTab_fallsBackToUserHome() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        harness.windowLifecycleStore.recordTerminalContainerBounds(CGRect(x: 0, y: 0, width: 1000, height: 600))
        let initialPaneIds = Set(harness.store.panes.keys)

        harness.controller.execute(.newTab)

        #expect(Set(harness.store.panes.keys).count == initialPaneIds.count + 1)
        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
        #expect(
            harness.surfaceManager.lastCreatedSurfaceMetadata?.cwd
                == FileManager.default.homeDirectoryForCurrentUser
        )
    }

    @Test("targeted renameTab presents the anchored popover for the selected tab")
    func executeRenameTab_targetedTab_presentsRenamePopoverForSelectedTab() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let firstPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "First"))
        let secondPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Second"))
        let firstTab = Tab(paneId: firstPane.id, name: "First Tab")
        let secondTab = Tab(paneId: secondPane.id, name: "Second Tab")
        harness.store.appendTab(firstTab)
        harness.store.appendTab(secondTab)
        harness.store.setActiveTab(firstTab.id)

        harness.controller.execute(.renameTab, target: secondTab.id, targetType: .tab)

        #expect(harness.tabRenamePopoverState.presentedTabId == secondTab.id)
        #expect(harness.store.activeTabId == secondTab.id)
        #expect(harness.store.tab(secondTab.id)?.name == "Second Tab")
    }

    @Test("targeted renameTab ignores stale tab targets")
    func executeRenameTab_missingTarget_doesNotPresentRenamePopover() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Only"))
        let tab = Tab(paneId: pane.id, name: "Only Tab")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let missingTabId = UUID()

        harness.controller.execute(.renameTab, target: missingTabId, targetType: .tab)

        #expect(harness.tabRenamePopoverState.presentedTabId == nil)
        #expect(harness.store.activeTabId == tab.id)
    }

    @Test("targeted renameArrangement begins inline edit on arrangement in the active tab")
    func executeRenameArrangement_activeTabArrangement_beginsInlineEdit() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let firstPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "First"))
        let secondPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Second"))
        let tab = Tab(paneId: firstPane.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            secondPane.id,
            inTab: tab.id,
            at: firstPane.id,
            direction: .horizontal,
            position: .after, sizingMode: .halveTarget
        )
        harness.store.setActiveTab(tab.id)
        guard
            let customArrangementId = harness.store.createArrangement(
                name: "Layout 1",
                paneIds: [firstPane.id],
                inTab: tab.id
            )
        else {
            Issue.record("expected arrangement to be created")
            return
        }

        harness.controller.execute(.renameArrangement, target: customArrangementId, targetType: .tab)

        #expect(harness.arrangementInlineRenameState.editingArrangementId == customArrangementId)
        #expect(harness.arrangementInlineRenameState.draftName == "Layout 1")
        #expect(harness.store.activeTabId == tab.id)
    }

    @Test("targeted renameArrangement switches to the owning tab before beginning inline edit")
    func executeRenameArrangement_crossTabArrangement_switchesTabFirst() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let firstTabPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "First"))
        let secondTabPaneA = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Second A"))
        let secondTabPaneB = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Second B"))
        let firstTab = Tab(paneId: firstTabPane.id, name: "First")
        let secondTab = Tab(paneId: secondTabPaneA.id, name: "Second")
        harness.store.appendTab(firstTab)
        harness.store.appendTab(secondTab)
        harness.store.insertPane(
            secondTabPaneB.id,
            inTab: secondTab.id,
            at: secondTabPaneA.id,
            direction: .horizontal,
            position: .after, sizingMode: .halveTarget
        )
        harness.store.setActiveTab(firstTab.id)
        guard
            let customArrangementId = harness.store.createArrangement(
                name: "Layout 1",
                paneIds: [secondTabPaneA.id],
                inTab: secondTab.id
            )
        else {
            Issue.record("expected arrangement to be created")
            return
        }

        harness.controller.execute(.renameArrangement, target: customArrangementId, targetType: .tab)

        #expect(harness.store.activeTabId == secondTab.id)
        #expect(harness.arrangementInlineRenameState.editingArrangementId == customArrangementId)
        #expect(harness.arrangementInlineRenameState.draftName == "Layout 1")
    }

    @Test("cycleArrangement switches active tab to next arrangement and wraps")
    func executeCycleArrangement_cyclesActiveTabArrangement() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let firstPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "First"))
        let secondPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Second"))
        let tab = Tab(paneId: firstPane.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            secondPane.id,
            inTab: tab.id,
            at: firstPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        harness.store.setActiveTab(tab.id)
        let defaultArrangementId = tab.activeArrangementId
        let customArrangementId = try #require(
            harness.store.createArrangement(name: "Focus", paneIds: [firstPane.id], inTab: tab.id)
        )

        harness.controller.execute(.cycleArrangement)

        #expect(harness.store.tab(tab.id)?.activeArrangementId == customArrangementId)

        harness.controller.execute(.cycleArrangement)

        #expect(harness.store.tab(tab.id)?.activeArrangementId == defaultArrangementId)
    }

    @Test("openPaneLocationInBookmarkedEditor without bookmark uses the implicit default order")
    func executeOpenPaneLocationInBookmarkedEditor_withoutBookmark_usesImplicitDefaultOrder() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let parentPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        guard let drawerPane = harness.store.addDrawerPane(to: parentPane.id) else {
            Issue.record("Expected drawer pane creation")
            return
        }

        harness.store.setActiveDrawerPane(drawerPane.id, in: parentPane.id)

        harness.controller.execute(.openPaneLocationInBookmarkedEditor)
        #expect(harness.launchRecorder.openedEditors.count == 1)
        #expect(harness.launchRecorder.openedEditors.first?.id == ExternalEditorTarget.cursor.id)
        #expect(
            harness.launchRecorder.openedEditors.first?.path.standardizedFileURL
                == worktree.path.standardizedFileURL
        )
    }

    @Test("openPaneLocationInBookmarkedEditor with stale bookmark clears bookmark and uses default order")
    func executeOpenPaneLocationInBookmarkedEditor_staleBookmark_clearsBookmarkAndUsesDefaultOrder() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let parentPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        guard let drawerPane = harness.store.addDrawerPane(to: parentPane.id) else {
            Issue.record("Expected drawer pane creation")
            return
        }

        harness.store.setActiveDrawerPane(drawerPane.id, in: parentPane.id)
        atom(\.editorChooser).setBookmarkedEditor("missing-editor")

        harness.controller.execute(.openPaneLocationInBookmarkedEditor)
        #expect(atom(\.editorChooser).state.bookmarkedEditorId == nil)
        #expect(harness.launchRecorder.openedEditors.count == 1)
        #expect(harness.launchRecorder.openedEditors.first?.id == ExternalEditorTarget.cursor.id)
        #expect(
            harness.launchRecorder.openedEditors.first?.path.standardizedFileURL
                == worktree.path.standardizedFileURL
        )
    }

    @Test("openPaneLocationInEditorMenu uses the selected drawer pane for ownership")
    func executeOpenPaneLocationInEditorMenu_usesDrawerPaneForOwnership() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let parentPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        guard let drawerPane = harness.store.addDrawerPane(to: parentPane.id) else {
            Issue.record("Expected drawer pane creation")
            return
        }

        harness.store.setActiveDrawerPane(drawerPane.id, in: parentPane.id)

        harness.controller.execute(.openPaneLocationInEditorMenu)

        #expect(atom(\.editorChooser).state.openForPaneId == drawerPane.id)
    }

    @Test("targeted focusPane opens owning drawer and selects drawer child")
    func executeFocusPane_targetedDrawerChildOpensOwningDrawer() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let parentTab = Tab(paneId: parentPane.id)
        harness.store.appendTab(parentTab)
        let otherPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Other"))
        let otherTab = Tab(paneId: otherPane.id)
        harness.store.appendTab(otherTab)
        harness.store.setActiveTab(otherTab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        harness.store.toggleDrawer(for: parentPane.id)
        #expect(harness.store.pane(parentPane.id)?.drawer?.isExpanded == false)

        harness.controller.execute(.focusPane, target: drawerPane.id, targetType: .pane)

        #expect(harness.store.activeTabId == parentTab.id)
        #expect(harness.store.tab(parentTab.id)?.activePaneId == parentPane.id)
        #expect(harness.store.pane(parentPane.id)?.drawer?.isExpanded == true)
        #expect(harness.store.pane(parentPane.id)?.drawer?.activeChildId == drawerPane.id)
        #expect(atom(\.workspaceFocusOwner).owner == .drawerPane(parentPaneId: parentPane.id, paneId: drawerPane.id))
    }

    @Test("openPaneLocationInFinder forwards the selected pane path to Finder")
    func executeOpenPaneLocationInFinder_revealsSelectedPanePath() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let parentPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        harness.controller.execute(.openPaneLocationInFinder)

        #expect(harness.launchRecorder.revealedPaths == [worktree.path])
    }

    @Test("location commands are unavailable when no pane target exists")
    func locationCommands_withoutTargetPath_areUnavailable() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        #expect(!harness.controller.canExecute(.openPaneLocationInBookmarkedEditor))
        #expect(!harness.controller.canExecute(.openPaneLocationInFinder))
        #expect(!harness.controller.canExecute(.openPaneLocationInEditorMenu))
    }

    @Test("targeted renameArrangement ignores the default arrangement")
    func executeRenameArrangement_defaultArrangement_isIgnored() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Only"))
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let defaultArrangementId = harness.store.tab(tab.id)?.defaultArrangement.id ?? UUID()

        harness.controller.execute(.renameArrangement, target: defaultArrangementId, targetType: .tab)

        #expect(harness.arrangementInlineRenameState.editingArrangementId == nil)
        #expect(harness.arrangementInlineRenameState.draftName.isEmpty)
    }

    @Test("targeted renameArrangement ignores a stale arrangement id")
    func executeRenameArrangement_unknownArrangement_isIgnored() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Only"))
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        harness.controller.execute(.renameArrangement, target: UUID(), targetType: .tab)

        #expect(harness.arrangementInlineRenameState.editingArrangementId == nil)
        #expect(harness.store.activeTabId == tab.id)
    }

    @Test("terminated pane closes only the matching split pane")
    func handleTerminalProcessTerminated_closesOnlyMatchingSplitPane() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let primaryPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Primary",
            provider: .zmx
        )
        let terminatingPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Terminating",
            provider: .zmx
        )
        let tab = Tab(paneId: primaryPane.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            terminatingPane.id,
            inTab: tab.id,
            at: primaryPane.id,
            direction: .horizontal,
            position: .after, sizingMode: .halveTarget
        )

        harness.controller.handleTerminalProcessTerminated(paneId: terminatingPane.id)

        #expect(harness.store.tab(tab.id)?.paneIds == [primaryPane.id])
        #expect(harness.store.pane(primaryPane.id) != nil)
        #expect(harness.store.pane(terminatingPane.id) == nil)
        #expect(harness.viewRegistry.terminalStatusPlaceholderView(for: terminatingPane.id) == nil)
    }

    @Test("terminated pane closes only the matching tab when multiple tabs share a worktree")
    func handleTerminalProcessTerminated_closesOnlyMatchingTab() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let survivingPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Surviving",
            provider: .zmx
        )
        let terminatingPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Terminating",
            provider: .zmx
        )
        let survivingTab = Tab(paneId: survivingPane.id, name: "Surviving")
        let terminatingTab = Tab(paneId: terminatingPane.id, name: "Terminating")
        harness.store.appendTab(survivingTab)
        harness.store.appendTab(terminatingTab)
        harness.store.setActiveTab(terminatingTab.id)

        harness.controller.handleTerminalProcessTerminated(paneId: terminatingPane.id)

        #expect(harness.store.tab(survivingTab.id) != nil)
        #expect(harness.store.tab(terminatingTab.id) == nil)
        #expect(harness.store.pane(survivingPane.id) != nil)
    }

    @Test("terminated hidden pane closes without removing visible sibling or creating undo")
    func handleTerminalProcessTerminated_hiddenPaneClosesWithoutUndoEntry() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let visiblePane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Visible",
            provider: .zmx
        )
        let hiddenPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Hidden",
            provider: .zmx
        )
        let tab = Tab(paneId: visiblePane.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            hiddenPane.id,
            inTab: tab.id,
            at: visiblePane.id,
            direction: .horizontal,
            position: .after, sizingMode: .halveTarget
        )
        let focusArrangementId = harness.store.createArrangement(
            name: "Focus Visible",
            paneIds: [visiblePane.id],
            inTab: tab.id
        )!
        harness.store.switchArrangement(to: focusArrangementId, inTab: tab.id)

        harness.controller.handleTerminalProcessTerminated(paneId: hiddenPane.id)

        #expect(harness.store.pane(visiblePane.id) != nil)
        #expect(harness.store.pane(hiddenPane.id) == nil)
        #expect(harness.store.tab(tab.id)?.visiblePaneIds == [visiblePane.id])
        #expect(harness.executor.undoStack.isEmpty)
    }

    @Test("terminated pane in a background tab does not create undo")
    func handleTerminalProcessTerminated_backgroundTabPaneClosesWithoutUndoEntry() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let firstPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "First"),
            title: "First",
            provider: .zmx
        )
        let secondPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Second"),
            title: "Second",
            provider: .zmx
        )
        let foregroundPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Foreground"),
            title: "Foreground",
            provider: .zmx
        )
        let backgroundTab = Tab(paneId: firstPane.id, name: "Background")
        let foregroundTab = Tab(paneId: foregroundPane.id, name: "Foreground")
        harness.store.appendTab(backgroundTab)
        harness.store.insertPane(
            secondPane.id,
            inTab: backgroundTab.id,
            at: firstPane.id,
            direction: .horizontal,
            position: .after, sizingMode: .halveTarget
        )
        harness.store.appendTab(foregroundTab)
        harness.store.setActiveTab(foregroundTab.id)

        harness.controller.handleTerminalProcessTerminated(paneId: firstPane.id)

        #expect(harness.store.pane(firstPane.id) == nil)
        #expect(harness.store.tab(backgroundTab.id) != nil)
        #expect(harness.executor.undoStack.isEmpty)
    }

    @Test("terminated drawer child under a hidden parent does not create undo")
    func handleTerminalProcessTerminated_hiddenDrawerChildClosesWithoutUndoEntry() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Parent"),
            title: "Parent",
            provider: .zmx
        )
        let visiblePane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Visible"),
            title: "Visible",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            visiblePane.id,
            inTab: tab.id,
            at: parentPane.id,
            direction: .horizontal,
            position: .after, sizingMode: .halveTarget
        )
        guard let drawerPane = harness.store.addDrawerPane(to: parentPane.id) else {
            Issue.record("Expected drawer pane creation")
            return
        }
        let focusedVisibleArrangementId = harness.store.createArrangement(
            name: "Visible only",
            paneIds: Set([visiblePane.id]),
            inTab: tab.id
        )!
        harness.store.switchArrangement(to: focusedVisibleArrangementId, inTab: tab.id)

        harness.controller.handleTerminalProcessTerminated(paneId: drawerPane.id)

        #expect(harness.store.pane(drawerPane.id) == nil)
        #expect(harness.store.pane(parentPane.id) != nil)
        #expect(harness.executor.undoStack.isEmpty)
    }

    @Test("terminated drawer child is ignored while close transition is already in flight")
    func handleTerminalProcessTerminated_drawerChildClosingTransitionInFlight_isIgnored() {
        let closeClock = TestPushClock()
        let closeTransitionCoordinator = PaneCloseTransitionCoordinator(clock: closeClock)
        let harness = makeHarness(closeTransitionCoordinator: closeTransitionCoordinator)
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Parent"),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        guard let drawerPane = harness.store.addDrawerPane(to: parentPane.id) else {
            Issue.record("Expected drawer pane creation")
            return
        }

        closeTransitionCoordinator.beginClosingPane(drawerPane.id, delay: .seconds(10)) {}

        harness.controller.handleTerminalProcessTerminated(paneId: drawerPane.id)

        #expect(harness.store.pane(drawerPane.id) != nil)
        #expect(harness.store.pane(parentPane.id)?.drawer?.paneIds == [drawerPane.id])
    }

    @Test("command harness shares window lifecycle store across monitor and coordinator")
    func makeHarness_sharesWindowLifecycleStoreAcrossLifecycleBoundaries() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        #expect(
            harness.coordinator.windowLifecycleStore === harness.windowLifecycleStore
        )
    }

    @Test("toggleManagementLayer preserves drawer scope while exiting management layer")
    func executeToggleManagementLayer_preservesDrawerScopeOnExit() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Parent"),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        _ = harness.store.addDrawerPane(to: parentPane.id)

        // Intentional: this covers the path where drawer pane selection
        // establishes the management navigation scope after mode is already active.
        atom(\.managementLayer).activate()
        harness.controller.setManagementNavigationScopeToDrawerForTesting(parentPaneId: parentPane.id)

        harness.controller.execute(.toggleManagementLayer)

        #expect(!atom(\.managementLayer).isActive)
        #expect(
            harness.controller.managementNavigationScopeDescriptionForTesting
                == "drawer:\(parentPane.id.uuidString)"
        )
    }

    @Test("managementLayerCreateTerminal targets drawer after drawer pane selection")
    func executeManagementCreateTerminal_selectedDrawerTargetsDrawer() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Parent"),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        guard let drawerPane = harness.store.addDrawerPane(to: parentPane.id) else {
            Issue.record("Expected drawer pane creation")
            return
        }

        atom(\.managementLayer).activate()

        harness.controller.handlePaneFocusTrigger(
            .drawer(.selectPane(parentPaneId: parentPane.id, drawerPaneId: drawerPane.id))
        )

        let paneIdsBefore = Set(harness.store.panes.keys)
        let tabPaneIdsBefore = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsBefore = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        harness.controller.execute(.managementLayerCreateTerminal)

        let paneIdsAfter = Set(harness.store.panes.keys)
        let createdPaneIds = paneIdsAfter.subtracting(paneIdsBefore)
        #expect(createdPaneIds.count == 1)
        let createdPaneId = try #require(createdPaneIds.first)

        let tabPaneIdsAfter = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsAfter = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        #expect(tabPaneIdsAfter == tabPaneIdsBefore)
        #expect(drawerPaneIdsAfter == drawerPaneIdsBefore.union([createdPaneId]))
        #expect(
            harness.controller.managementNavigationScopeDescriptionForTesting
                == "drawer:\(parentPane.id.uuidString)"
        )
    }

    @Test("managementLayerCreateTerminal in main row adds a split pane to the active tab")
    func executeManagementCreateTerminal_mainRowTargetsActiveTab() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Parent"),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        harness.controller.execute(.toggleManagementLayer)

        let paneIdsBefore = Set(harness.store.panes.keys)
        let tabPaneIdsBefore = Set(harness.store.tab(tab.id)?.paneIds ?? [])

        harness.controller.execute(.managementLayerCreateTerminal)

        let paneIdsAfter = Set(harness.store.panes.keys)
        let createdPaneIds = paneIdsAfter.subtracting(paneIdsBefore)
        #expect(createdPaneIds.count == 1)
        let createdPaneId = try #require(createdPaneIds.first)
        let tabPaneIdsAfter = Set(harness.store.tab(tab.id)?.paneIds ?? [])

        #expect(tabPaneIdsAfter == tabPaneIdsBefore.union([createdPaneId]))
        #expect(harness.store.pane(parentPane.id)?.drawer?.paneIds.isEmpty ?? true)
        #expect(harness.controller.managementNavigationScopeDescriptionForTesting == "mainRow")
    }

    @Test("option-j and option-l stay main-row movement outside drawers")
    func executeFocusPaneLeftRight_outsideDrawerStaysInMainRow() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let first = harness.store.createPane(source: .floating(launchDirectory: nil, title: "First"))
        let second = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Second"))
        let tab = Tab(paneId: first.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            second.id, inTab: tab.id, at: first.id, direction: .horizontal, position: .after, sizingMode: .halveTarget)
        harness.store.setActiveTab(tab.id)
        harness.store.setActivePane(second.id, inTab: tab.id)

        harness.controller.execute(.focusPaneLeft)

        #expect(harness.store.tab(tab.id)?.activePaneId == first.id)
    }

    @Test("focusPane1 focuses first active arrangement pane")
    func executeFocusPane1_focusesFirstActiveArrangementPane() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let (tab, panes) = try makeOrdinalTab(in: harness, paneCount: 3)
        harness.store.setActivePane(panes[2].id, inTab: tab.id)

        harness.controller.execute(.focusPane1)

        #expect(harness.store.tab(tab.id)?.activePaneId == panes[0].id)
        #expect(atom(\.workspaceFocusOwner).owner == .mainPane(paneId: panes[0].id))
    }

    @Test("focusPane3 focuses third active arrangement pane")
    func executeFocusPane3_focusesThirdActiveArrangementPane() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let (tab, panes) = try makeOrdinalTab(in: harness, paneCount: 3)

        harness.controller.execute(.focusPane3)

        #expect(harness.store.tab(tab.id)?.activePaneId == panes[2].id)
        #expect(atom(\.workspaceFocusOwner).owner == .mainPane(paneId: panes[2].id))
    }

    @Test("out-of-range focusPane ordinal is unavailable and no-ops")
    func executeFocusPane4_outOfRangeIsUnavailableAndNoOps() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let (tab, panes) = try makeOrdinalTab(in: harness, paneCount: 3)

        #expect(harness.controller.canExecute(.focusPane4) == false)

        harness.controller.execute(.focusPane4)

        #expect(harness.store.tab(tab.id)?.activePaneId == panes[0].id)
    }

    @Test("focusPane ordinal expands minimized target before focusing")
    func executeFocusPane2_expandsMinimizedTargetBeforeFocusing() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let (tab, panes) = try makeOrdinalTab(in: harness, paneCount: 3)
        _ = harness.store.tabLayoutAtom.minimizePane(panes[1].id, inTab: tab.id)

        harness.controller.execute(.focusPane2)

        let updatedTab = try #require(harness.store.tab(tab.id))
        #expect(updatedTab.activePaneId == panes[1].id)
        #expect(!updatedTab.activeMinimizedPaneIds.contains(panes[1].id))
    }

    @Test("focusPane ordinal moves split zoom to requested pane")
    func executeFocusPane2_movesSplitZoomToRequestedPane() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let (tab, panes) = try makeOrdinalTab(in: harness, paneCount: 3)
        harness.store.tabLayoutAtom.toggleZoom(paneId: panes[0].id, inTab: tab.id)

        harness.controller.execute(.focusPane2)

        let updatedTab = try #require(harness.store.tab(tab.id))
        #expect(updatedTab.zoomedPaneId == panes[1].id)
        #expect(updatedTab.activePaneId == panes[1].id)
    }

    private func makeOrdinalTab(
        in harness: PaneTabViewControllerCommandHarness,
        paneCount: Int
    ) throws -> (tab: Tab, panes: [Pane]) {
        let panes = (0..<paneCount).map { index in
            harness.store.createPane(source: .floating(launchDirectory: nil, title: "Pane \(index + 1)"))
        }
        let tab = Tab(paneId: panes[0].id)
        harness.store.appendTab(tab)
        for pane in panes.dropFirst() {
            harness.store.insertPane(
                pane.id,
                inTab: tab.id,
                at: try #require(harness.store.tab(tab.id)?.activePaneIds.last),
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )
        }
        harness.store.setActiveTab(tab.id)
        harness.store.setActivePane(panes[0].id, inTab: tab.id)
        atom(\.workspaceFocusOwner).focusMainPane(panes[0].id)
        return (tab, panes)
    }

}
