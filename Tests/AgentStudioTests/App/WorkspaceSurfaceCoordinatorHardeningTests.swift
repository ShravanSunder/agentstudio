import AppKit
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceSurfaceCoordinatorHardeningTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    private let trustedBounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

    private struct Harness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let runtime: SessionRuntime
        let coordinator: WorkspaceSurfaceCoordinator
        let surfaceManager: MockWorkspaceSurfaceCoordinatorSurfaceManager
        let tempDir: URL
    }

    private func makeHarness(
        createSurfaceResult: Result<ManagedSurface, SurfaceError> = .failure(.ghosttyNotInitialized)
    ) -> Harness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-hardening-\(UUID().uuidString)")
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner())
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let surfaceManager = MockWorkspaceSurfaceCoordinatorSurfaceManager(createSurfaceResult: createSurfaceResult)
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: surfaceManager,
            runtimeRegistry: RuntimeRegistry(),
            windowLifecycleStore: WindowLifecycleAtom()
        )
        return Harness(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            coordinator: coordinator,
            surfaceManager: surfaceManager,
            tempDir: tempDir
        )
    }

    private func makeRepoAndWorktree(_ store: WorkspaceStore, root: URL) -> (Repo, Worktree) {
        let repoPath = root.appending(path: "repo-\(UUID().uuidString)")
        let worktreePath = repoPath.appending(path: "wt-main")
        try? FileManager.default.createDirectory(at: repoPath, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: worktreePath, withIntermediateDirectories: true)

        let repo = store.addRepo(at: repoPath)
        let worktree = Worktree(repoId: repo.id, name: "wt-main", path: worktreePath)
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        return (repo, worktree)
    }

    private func makeWebviewPane(_ store: WorkspaceStore, title: String) -> Pane {
        let url = URL(string: "https://example.com/\(UUID().uuidString)")!
        return store.createPane(
            content: .webview(WebviewState(url: url, showNavigation: true)),
            metadata: PaneMetadata(title: title)
        )
    }

    private func makeWorktreePane(
        _ store: WorkspaceStore,
        repo: Repo,
        worktree: Worktree,
        title: String
    ) -> Pane {
        store.createPane(
            launchDirectory: worktree.path,
            title: title,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
    }

    @Test("openTerminal keeps pane state and attempts geometry-gated creation when bounds exist")
    func openTerminal_keepsPaneStateWhenSurfaceCreationFails() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        guard let persistedRepo = harness.store.repo(repo.id) else {
            Issue.record("Expected repo to be persisted in WorkspaceStore")
            return
        }
        harness.coordinator.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        let openedPane = harness.coordinator.openTerminal(for: worktree, in: persistedRepo)

        #expect(openedPane != nil)
        #expect(harness.store.tabs.count == 1)
        #expect(harness.store.panes.count == 1)
        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
    }

    @Test("closeTab tears down views for panes hidden by non-active arrangements")
    func closeTab_tearsDownAllOwnedPaneViews() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let paneA = makeWebviewPane(harness.store, title: "A")
        let paneB = makeWebviewPane(harness.store, title: "B")
        let paneC = makeWebviewPane(harness.store, title: "C")
        let tab = Tab(paneId: paneA.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            paneB.id,
            inTab: tab.id,
            at: paneA.id,
            direction: .horizontal,
            position: .after, sizingMode: .halveTarget
        )
        harness.store.insertPane(
            paneC.id,
            inTab: tab.id,
            at: paneB.id,
            direction: .horizontal,
            position: .after, sizingMode: .halveTarget
        )
        guard
            let focusArrangementId = harness.store.createArrangement(
                name: "Focus AB",
                inTab: tab.id
            )
        else {
            Issue.record("Expected arrangement creation to succeed")
            return
        }
        harness.store.switchArrangement(to: focusArrangementId, inTab: tab.id)

        harness.viewRegistry.register(PaneHostView(paneId: paneA.id), for: paneA.id)
        harness.viewRegistry.register(PaneHostView(paneId: paneB.id), for: paneB.id)
        harness.viewRegistry.register(PaneHostView(paneId: paneC.id), for: paneC.id)

        harness.coordinator.execute(.closeTab(tabId: tab.id))

        #expect(harness.store.tab(tab.id) == nil)
        #expect(harness.viewRegistry.registeredPaneIds.isEmpty)
        guard case .tab(let snapshot)? = harness.coordinator.undoStack.last else {
            Issue.record("Expected tab snapshot in undo stack")
            return
        }
        #expect(Set(snapshot.panes.map(\.id)) == Set([paneA.id, paneB.id, paneC.id]))
    }

    @Test("purgeOrphanedPane only purges panes that are backgrounded")
    func purgeOrphanedPane_requiresBackgroundedResidency() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = makeWebviewPane(harness.store, title: "Transient")
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.viewRegistry.register(PaneHostView(paneId: pane.id), for: pane.id)
        harness.viewRegistry.surfaceRenderedIds("tab:\(tab.id)", ids: [pane.id])

        harness.coordinator.execute(.purgeOrphanedPane(paneId: pane.id))
        #expect(harness.store.pane(pane.id) != nil)
        #expect(harness.viewRegistry.view(for: pane.id) != nil)

        harness.coordinator.execute(.backgroundPane(paneId: pane.id))
        harness.coordinator.execute(.purgeOrphanedPane(paneId: pane.id))
        #expect(harness.store.pane(pane.id) == nil)
        #expect(harness.viewRegistry.view(for: pane.id) == nil)
        #expect(harness.viewRegistry.isRetiredForTesting(pane.id))
        #expect(harness.viewRegistry.peekSlotForTesting(pane.id) != nil)
    }

    @Test("insertPane newTerminal keeps inserted pane state when terminal view creation fails")
    func insertPaneNewTerminal_keepsPaneStateOnSurfaceCreationFailure() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let targetPane = harness.store.createPane(
            launchDirectory: worktree.path,
            title: "Target",
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: targetPane.id)
        harness.store.appendTab(tab)
        harness.coordinator.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        let initialPaneIds = Set(harness.store.panes.keys)

        harness.coordinator.execute(
            .insertPane(
                source: .newTerminal,
                targetTabId: tab.id,
                targetPaneId: targetPane.id,
                direction: .right,
                sizingMode: .halveTarget
            )
        )

        #expect(Set(harness.store.panes.keys).count == initialPaneIds.count + 1)
        #expect(harness.store.tab(tab.id)?.paneIds.count == 2)
        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
    }

    @Test("insertPane newTerminal resolves worktree context from floating target cwd before surface creation")
    func insertPaneNewTerminal_resolvesWorktreeContextFromFloatingCwd() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let targetPane = harness.store.createPane(
            launchDirectory: worktree.path.appending(path: "nested"),
            title: "Target",
            provider: .zmx,
            facets: PaneContextFacets(cwd: worktree.path.appending(path: "nested"))
        )
        let tab = Tab(paneId: targetPane.id)
        harness.store.appendTab(tab)
        harness.coordinator.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        let initialPaneIds = Set(harness.store.panes.keys)

        harness.coordinator.execute(
            .insertPane(
                source: .newTerminal,
                targetTabId: tab.id,
                targetPaneId: targetPane.id,
                direction: .right,
                sizingMode: .halveTarget
            )
        )

        #expect(Set(harness.store.panes.keys).count == initialPaneIds.count + 1)
        #expect(harness.store.tab(tab.id)?.paneIds.count == 2)
        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
        #expect(harness.store.repo(repo.id) != nil)
        #expect(
            harness.surfaceManager.lastCreatedSurfaceMetadata?.cwd
                == worktree.path.appending(path: "nested"))
    }

    @Test("insertPane newTerminal falls back to floating context when target cwd does not map to a worktree")
    func insertPaneNewTerminal_fallsBackToFloatingContext() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let unknownCwd = harness.tempDir.appending(path: "outside-known-repos")
        try? FileManager.default.createDirectory(at: unknownCwd, withIntermediateDirectories: true)
        let targetPane = harness.store.createPane(
            launchDirectory: unknownCwd,
            title: "Target",
            provider: .zmx,
            facets: PaneContextFacets(cwd: unknownCwd)
        )
        let tab = Tab(paneId: targetPane.id)
        harness.store.appendTab(tab)
        harness.coordinator.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        let initialPaneIds = Set(harness.store.panes.keys)

        harness.coordinator.execute(
            .insertPane(
                source: .newTerminal,
                targetTabId: tab.id,
                targetPaneId: targetPane.id,
                direction: .right,
                sizingMode: .halveTarget
            )
        )

        #expect(Set(harness.store.panes.keys).count == initialPaneIds.count + 1)
        #expect(harness.store.tab(tab.id)?.paneIds.count == 2)
        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
        #expect(harness.surfaceManager.lastCreatedSurfaceMetadata?.cwd == unknownCwd)
    }

    @Test("expandPane restores a missing visible terminal view when the minimized pane had no host")
    func expandPane_restoresMissingVisibleTerminalView() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let firstPane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Visible")
        let secondPane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Minimized")
        let tab = Tab(paneId: firstPane.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            secondPane.id,
            inTab: tab.id,
            at: firstPane.id,
            direction: .horizontal,
            position: .after, sizingMode: .halveTarget
        )
        _ = harness.store.minimizePane(secondPane.id, inTab: tab.id)

        harness.coordinator.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        harness.coordinator.windowLifecycleStore.recordLaunchLayoutSettled()

        #expect(harness.viewRegistry.view(for: secondPane.id) == nil)

        harness.coordinator.execute(.expandPane(tabId: tab.id, paneId: secondPane.id))

        #expect(harness.viewRegistry.view(for: secondPane.id) != nil)
    }

    @Test("reactivatePane keeps reactivated pane in canonical state if view creation fails")
    func reactivatePane_keepsCanonicalStateWhenViewCreationFails() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let targetPane = makeWebviewPane(harness.store, title: "Target")
        let tab = Tab(paneId: targetPane.id)
        harness.store.appendTab(tab)

        let backgroundPane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Background")
        harness.store.setResidency(.backgrounded, for: backgroundPane.id)
        harness.coordinator.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)

        harness.coordinator.execute(
            .reactivatePane(
                paneId: backgroundPane.id,
                targetTabId: tab.id,
                targetPaneId: targetPane.id,
                direction: .right
            )
        )

        #expect(harness.store.pane(backgroundPane.id)?.residency == .active)
        #expect(harness.store.tab(tab.id)?.paneIds.contains(backgroundPane.id) == true)
        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
    }

    @Test("addDrawerPane keeps drawer pane state when view creation fails")
    func addDrawerPane_keepsDrawerStateOnViewCreationFailure() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let parentPane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Parent")
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.coordinator.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)

        let paneIdsBefore = Set(harness.store.panes.keys)
        harness.coordinator.execute(.addDrawerPane(parentPaneId: parentPane.id))

        #expect(Set(harness.store.panes.keys).count == paneIdsBefore.count + 1)
        #expect(harness.store.pane(parentPane.id)?.drawer?.paneIds.count == 1)
        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
    }

    @Test("insertDrawerPane keeps drawer pane state when view creation fails")
    func insertDrawerPane_keepsDrawerStateOnViewCreationFailure() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let parentPane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Parent")
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        guard let existingDrawerPane = harness.store.addDrawerPane(to: parentPane.id) else {
            Issue.record("Expected initial drawer pane creation")
            return
        }
        harness.coordinator.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)

        let paneIdsBefore = Set(harness.store.panes.keys)
        harness.coordinator.execute(
            .insertDrawerPane(
                parentPaneId: parentPane.id,
                targetDrawerPaneId: existingDrawerPane.id,
                direction: .right,
                sizingMode: .halveTarget
            )
        )

        #expect(Set(harness.store.panes.keys).count == paneIdsBefore.count + 1)
        #expect(harness.store.pane(parentPane.id)?.drawer?.paneIds.count == 2)
        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
    }

    @Test("toggleDrawer collapse hands focus back to the parent pane host")
    func toggleDrawer_collapseFocusesParentPaneHost() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let parentPane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Parent")
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))

        let parentHost = PaneHostView(paneId: parentPane.id)
        let drawerHost = PaneHostView(paneId: drawerPane.id)
        let parentMountedContent = FocusableMountedContentView()
        let drawerMountedContent = FocusableMountedContentView()
        parentHost.mountContentView(parentMountedContent)
        drawerHost.mountContentView(drawerMountedContent)
        harness.viewRegistry.register(parentHost, for: parentPane.id)
        harness.viewRegistry.register(drawerHost, for: drawerPane.id)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let contentView = try #require(window.contentView)
        contentView.addSubview(parentHost)
        contentView.addSubview(drawerHost)
        window.makeFirstResponder(drawerHost)

        harness.coordinator.execute(.toggleDrawer(paneId: parentPane.id))

        #expect(harness.store.pane(parentPane.id)?.drawer?.isExpanded == false)
        #expect(window.firstResponder === parentMountedContent)
    }

    @Test("removeDrawerPane closing the last drawer pane lands in empty drawer context")
    func removeDrawerPane_lastDrawerPaneClearsResponderToEmptyDrawerContext() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let parentPane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Parent")
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))

        let parentHost = PaneHostView(paneId: parentPane.id)
        let drawerHost = PaneHostView(paneId: drawerPane.id)
        let parentMountedContent = FocusableMountedContentView()
        let drawerMountedContent = FocusableMountedContentView()
        parentHost.mountContentView(parentMountedContent)
        drawerHost.mountContentView(drawerMountedContent)
        harness.viewRegistry.register(parentHost, for: parentPane.id)
        harness.viewRegistry.register(drawerHost, for: drawerPane.id)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let contentView = try #require(window.contentView)
        contentView.addSubview(parentHost)
        contentView.addSubview(drawerHost)
        window.makeFirstResponder(drawerHost)

        harness.coordinator.execute(.removeDrawerPane(parentPaneId: parentPane.id, drawerPaneId: drawerPane.id))

        #expect(harness.store.pane(parentPane.id)?.drawer?.paneIds.isEmpty == true)
        #expect(window.firstResponder !== drawerMountedContent)
        #expect(window.firstResponder !== drawerHost)
        #expect(window.firstResponder === contentView)
    }

    @Test(
        "closing a main pane with drawer children retires child slots so drawer panel renders safely during transition"
    )
    func closeMainPane_withDrawerChildren_retiresChildSlots() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = harness.store.createPane()
        let tab = Tab(paneId: parent.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let child = try #require(harness.store.addDrawerPane(to: parent.id))
        _ = harness.viewRegistry.ensureSlot(for: parent.id)
        _ = harness.viewRegistry.ensureSlot(for: child.id)

        // Phase 1 still goes through the current close path, including the
        // validator's canonicalization of single-pane tabs to .closeTab. To
        // isolate the retire behavior, drive the main-pane close via the
        // coordinator directly with a non-canonicalized closePane call for a
        // multi-pane test state.
        let sibling = harness.store.createPane()
        harness.store.insertPane(
            sibling.id,
            inTab: tab.id,
            at: parent.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        harness.viewRegistry.surfaceRenderedIds("tab:\(tab.id)", ids: [parent.id, sibling.id])
        harness.viewRegistry.surfaceRenderedIds("drawer:\(parent.id)", ids: [child.id])

        harness.coordinator.execute(.closePane(tabId: tab.id, paneId: parent.id))

        #expect(harness.store.tab(tab.id)?.allPaneIds.contains(child.id) == false)
        #expect(harness.viewRegistry.isRetiredForTesting(parent.id))
        #expect(harness.viewRegistry.isRetiredForTesting(child.id))
        #expect(harness.viewRegistry.peekSlotForTesting(parent.id) != nil)
        #expect(harness.viewRegistry.peekSlotForTesting(child.id) != nil)
    }

    @Test(".removeDrawerPane retires the slot rather than deleting it immediately")
    func removeDrawerPane_retiresSlot() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = harness.store.createPane()
        let tab = Tab(paneId: parent.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let child = try #require(harness.store.addDrawerPane(to: parent.id))
        let survivor = try #require(harness.store.addDrawerPane(to: parent.id))
        harness.store.setActiveDrawerPane(survivor.id, in: parent.id)
        _ = harness.viewRegistry.ensureSlot(for: child.id)
        harness.viewRegistry.surfaceRenderedIds("drawer:\(parent.id)", ids: [child.id])

        harness.coordinator.execute(.removeDrawerPane(parentPaneId: parent.id, drawerPaneId: child.id))

        #expect(harness.viewRegistry.isRetiredForTesting(child.id))
        #expect(harness.viewRegistry.peekSlotForTesting(child.id) != nil)
    }

    @Test(".removeDrawerPane stale segment reads the retired slot instead of creating a lazy fallback")
    func removeDrawerPane_staleSegmentSlotRead_returnsRetiredSlot() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = harness.store.createPane()
        let tab = Tab(paneId: parent.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let child = try #require(harness.store.addDrawerPane(to: parent.id))
        let survivor = try #require(harness.store.addDrawerPane(to: parent.id))
        harness.store.setActiveDrawerPane(survivor.id, in: parent.id)
        let originalSlot = harness.viewRegistry.ensureSlot(for: child.id)
        harness.viewRegistry.surfaceRenderedIds("drawer:\(parent.id)", ids: [child.id])

        harness.coordinator.execute(.removeDrawerPane(parentPaneId: parent.id, drawerPaneId: child.id))
        let staleSegmentSlot = harness.viewRegistry.slot(for: child.id)

        #expect(staleSegmentSlot === originalSlot)
        #expect(harness.viewRegistry.isRetiredForTesting(child.id))
    }

    @Test(".removeDrawerPane finalizes retired slots only after every rendering surface drops the pane id")
    func removeDrawerPane_surfaceUnionFinalizesOnlyAfterAllSurfacesDropPaneId() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = harness.store.createPane()
        let tab = Tab(paneId: parent.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let child = try #require(harness.store.addDrawerPane(to: parent.id))
        let survivor = try #require(harness.store.addDrawerPane(to: parent.id))
        harness.store.setActiveDrawerPane(survivor.id, in: parent.id)
        let originalSlot = harness.viewRegistry.ensureSlot(for: child.id)

        harness.viewRegistry.surfaceRenderedIds("tab:\(tab.id)", ids: [parent.id, child.id])
        harness.viewRegistry.surfaceRenderedIds("drawer:\(parent.id)", ids: [child.id])

        harness.coordinator.execute(.removeDrawerPane(parentPaneId: parent.id, drawerPaneId: child.id))

        #expect(harness.viewRegistry.isRetiredForTesting(child.id))
        #expect(harness.viewRegistry.peekSlotForTesting(child.id) === originalSlot)

        harness.viewRegistry.surfaceRenderedIds("drawer:\(parent.id)", ids: [])

        #expect(harness.viewRegistry.isRetiredForTesting(child.id))
        #expect(harness.viewRegistry.peekSlotForTesting(child.id) === originalSlot)

        harness.viewRegistry.surfaceRenderedIds("tab:\(tab.id)", ids: [parent.id])

        #expect(!harness.viewRegistry.isRetiredForTesting(child.id))
        #expect(harness.viewRegistry.peekSlotForTesting(child.id) == nil)
    }

    @Test("closePane on the final drawer child leaves an empty expanded drawer")
    func closePane_lastDrawerChild_leavesEmptyExpandedDrawer() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = harness.store.createPane()
        let tab = Tab(paneId: parent.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let child = try #require(harness.store.addDrawerPane(to: parent.id))

        harness.coordinator.execute(.closePane(tabId: tab.id, paneId: child.id))

        let drawer = try #require(harness.store.pane(parent.id)?.drawer)
        #expect(drawer.isExpanded)
        #expect(drawer.paneIds.isEmpty)
        #expect(harness.store.drawerView(forParent: parent.id) == nil)
    }

    @Test("repair recreateSurface registers preparing placeholder when geometry is unavailable")
    func repairRecreateSurface_registersPreparingPlaceholderWhenGeometryUnavailable() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let pane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Repair")
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.coordinator.execute(.repair(.recreateSurface(paneId: pane.id)))

        let placeholder = harness.viewRegistry.terminalStatusPlaceholderView(for: pane.id)
        #expect(placeholder?.mode == .preparing)
    }

    @Test("repair createMissingView retries from failed placeholder instead of treating it as an existing live view")
    func repairCreateMissingView_failedPlaceholderRetriesCreation() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let pane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Retry")
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.coordinator.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        _ = harness.coordinator.registerTerminalPlaceholderIfNeeded(for: pane, mode: .failedToStart)

        harness.coordinator.execute(.repair(.createMissingView(paneId: pane.id)))

        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
        let placeholder = harness.viewRegistry.terminalStatusPlaceholderView(for: pane.id)
        #expect(placeholder?.mode == .failedToStart)
    }

    @Test("undo GC removes orphaned panes after stack overflows max entries")
    func undoGc_removesExpiredPaneResources() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        var closedPaneIds: [UUID] = []
        var oldestClosedSlot: ViewRegistry.PaneViewSlot?
        for index in 0...(harness.coordinator.maxUndoStackSize) {
            let pane = makeWebviewPane(harness.store, title: "Pane \(index)")
            let tab = Tab(paneId: pane.id)
            harness.store.appendTab(tab)
            let slot = harness.viewRegistry.ensureSlot(for: pane.id)
            if index == 0 {
                oldestClosedSlot = slot
                harness.viewRegistry.surfaceRenderedIds("tab:\(tab.id)", ids: [pane.id])
            }
            harness.coordinator.execute(.closeTab(tabId: tab.id))
            closedPaneIds.append(pane.id)
        }

        #expect(harness.coordinator.undoStack.count == harness.coordinator.maxUndoStackSize)
        guard let oldestClosedPaneId = closedPaneIds.first else {
            Issue.record("Expected at least one closed pane id")
            return
        }
        #expect(harness.store.pane(oldestClosedPaneId) == nil)
        #expect(harness.viewRegistry.isRetiredForTesting(oldestClosedPaneId))
        #expect(harness.viewRegistry.peekSlotForTesting(oldestClosedPaneId) === oldestClosedSlot)
    }

    @Test("undo GC deletes expired pane slot immediately when no surface renders it")
    func undoGc_expiredPaneWithoutRenderedSurfaceDeletesSlot() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        var oldestClosedPaneId: UUID?
        for index in 0...(harness.coordinator.maxUndoStackSize) {
            let pane = makeWebviewPane(harness.store, title: "Pane \(index)")
            let tab = Tab(paneId: pane.id)
            harness.store.appendTab(tab)
            _ = harness.viewRegistry.ensureSlot(for: pane.id)
            if index == 0 { oldestClosedPaneId = pane.id }
            harness.coordinator.execute(.closeTab(tabId: tab.id))
        }
        #expect(harness.coordinator.undoStack.count == harness.coordinator.maxUndoStackSize)
        let oldestPaneId = try #require(oldestClosedPaneId)
        #expect(harness.store.pane(oldestPaneId) == nil)
        #expect(!harness.viewRegistry.isRetiredForTesting(oldestPaneId))
        #expect(harness.viewRegistry.peekSlotForTesting(oldestPaneId) == nil)
    }

    @Test("restoreView defers runtime registration until after undo lookup")
    func restoreView_defersRuntimeRegistrationUntilAfterUndoLookup() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let pane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Restore")
        let runtimePaneId = PaneId(existingUUID: pane.id)

        var runtimeWasRegisteredDuringUndoLookup = false
        harness.surfaceManager.onUndoClose = {
            runtimeWasRegisteredDuringUndoLookup = harness.coordinator.runtimeForPane(runtimePaneId) != nil
        }

        let restored = harness.coordinator.restoreView(for: pane, worktree: worktree, repo: repo)

        #expect(restored == nil)
        #expect(!runtimeWasRegisteredDuringUndoLookup)
        #expect(harness.coordinator.runtimeForPane(runtimePaneId) == nil)
    }

    @Test("fresh createView registers runtime before createSurface")
    func freshCreateView_registersRuntimeBeforeCreateSurface() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let pane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Fresh")
        let runtimePaneId = PaneId(existingUUID: pane.id)

        var runtimeWasRegisteredDuringCreateSurface = false
        harness.surfaceManager.onCreateSurface = { _ in
            runtimeWasRegisteredDuringCreateSurface = harness.coordinator.runtimeForPane(runtimePaneId) != nil
        }

        let created = harness.coordinator.createView(
            for: pane,
            worktree: worktree,
            repo: repo,
            initialFrame: NSRect(x: 0, y: 0, width: 1000, height: 600)
        )

        #expect(created == nil)
        #expect(runtimeWasRegisteredDuringCreateSurface)
    }

    @Test("fresh createView rolls back newly created runtime when createSurface fails")
    func freshCreateView_rollsBackNewRuntimeWhenCreateSurfaceFails() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let pane = makeWorktreePane(harness.store, repo: repo, worktree: worktree, title: "Rollback")
        let runtimePaneId = PaneId(existingUUID: pane.id)

        let created = harness.coordinator.createView(
            for: pane,
            worktree: worktree,
            repo: repo,
            initialFrame: NSRect(x: 0, y: 0, width: 1000, height: 600)
        )

        #expect(created == nil)
        #expect(harness.coordinator.runtimeForPane(runtimePaneId) == nil)
    }
}

@MainActor
private final class MockWorkspaceSurfaceCoordinatorSurfaceManager: WorkspaceSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>
    private let createSurfaceResult: Result<ManagedSurface, SurfaceError>

    private(set) var createSurfaceCallCount = 0
    private(set) var lastCreatedSurfaceMetadata: SurfaceMetadata?
    var onCreateSurface: ((SurfaceMetadata) -> Void)?
    var onUndoClose: (() -> Void)?
    var undoCloseResult: ManagedSurface?

    init(
        createSurfaceResult: Result<ManagedSurface, SurfaceError>,
        undoCloseResult: ManagedSurface? = nil,
        onUndoClose: (() -> Void)? = nil
    ) {
        self.createSurfaceResult = createSurfaceResult
        self.undoCloseResult = undoCloseResult
        self.onUndoClose = onUndoClose
        self.cwdStream = AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { continuation in
            continuation.finish()
        }
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { cwdStream }

    func syncFocus(activeSurfaceId: UUID?) {}

    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        createSurfaceCallCount += 1
        lastCreatedSurfaceMetadata = metadata
        onCreateSurface?(metadata)
        return createSurfaceResult
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {}

    func undoClose() -> ManagedSurface? {
        onUndoClose?()
        return undoCloseResult
    }

    func requeueUndo(_ surfaceId: UUID) {}

    func destroy(_ surfaceId: UUID) {}
}

@MainActor
private final class FocusableMountedContentView: NSView, PaneMountedContent {
    override var acceptsFirstResponder: Bool { true }

    func setContentInteractionEnabled(_: Bool) {}
}
