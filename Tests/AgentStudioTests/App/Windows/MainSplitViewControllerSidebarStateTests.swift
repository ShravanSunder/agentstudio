import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioRepoExplorer
import AppKit
import Testing

@testable import AgentStudio
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct MainSplitViewControllerSidebarStateTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("viewDidLoad with sidebarCollapsed true collapses the sidebar")
    func respectsSidebarCollapsedAtomOnLoad() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            configureUIState: { $0.setSidebarCollapsed(true) },
            body: { harness in
                #expect(harness.controller.isSidebarCollapsed == true)
            }
        )
    }

    @Test("viewDidLoad with no repos force-collapses the sidebar")
    func noReposForceCollapseSidebar() async {
        await withMainSplitViewControllerHarness(
            withRepos: false,
            body: { harness in
                #expect(harness.controller.isSidebarCollapsed == true)
            }
        )
    }

    @Test("toggleSidebarFromCommand writes collapsed state back into WorkspaceSidebarState")
    func toggleSidebarWritesBackIntoAtom() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                #expect(harness.atoms.core.workspaceSidebarState.sidebarCollapsed == false)

                harness.controller.toggleSidebarFromCommand()
                await Task.yield()
                #expect(harness.atoms.core.workspaceSidebarState.sidebarCollapsed == true)

                harness.controller.toggleSidebarFromCommand()
                await Task.yield()
                #expect(harness.atoms.core.workspaceSidebarState.sidebarCollapsed == false)
            }
        )
    }

    @Test("resize persistence writes current collapsed state into WorkspaceSidebarState")
    func resizePersistsSidebarCollapsedState() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                harness.controller.toggleSidebarFromCommand()
                await Task.yield()
                #expect(harness.controller.isSidebarCollapsed == true)
                #expect(harness.atoms.core.workspaceSidebarState.sidebarCollapsed == true)

                harness.atoms.core.workspaceSidebarState.setSidebarCollapsed(false)
                #expect(harness.atoms.core.workspaceSidebarState.sidebarCollapsed == false)

                harness.controller.splitViewDidResizeSubviews(Notification(name: .init("test")))
                #expect(harness.atoms.core.workspaceSidebarState.sidebarCollapsed == true)
            }
        )
    }

    @Test("viewDidLoad restores sidebar width from workspace metadata")
    func viewDidLoadRestoresSidebarWidthFromWorkspaceMetadata() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            configureWorkspaceWindowMemory: { $0.setSidebarWidth(320) },
            body: { harness in
                layOutMainSplitViewController(harness)
                await eventually("sidebar should restore persisted workspace width") {
                    let sidebarWidth = harness.controller.splitViewItems.first?.viewController.view.frame.width ?? 0
                    return abs(sidebarWidth - 320) <= 5
                }
            }
        )
    }

    @Test("initial split resize before restore does not overwrite persisted sidebar width")
    func initialResizeBeforeRestoreDoesNotOverwritePersistedSidebarWidth() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            configureWorkspaceWindowMemory: { $0.setSidebarWidth(320) },
            body: { harness in
                harness.controller.splitViewDidResizeSubviews(Notification(name: .init("test")))
                #expect(harness.store.windowMemoryAtom.sidebarWidth == 320)

                layOutMainSplitViewController(harness)
                await eventually("sidebar should still restore persisted workspace width") {
                    let sidebarWidth = harness.controller.splitViewItems.first?.viewController.view.frame.width ?? 0
                    return abs(sidebarWidth - 320) <= 5
                }
            }
        )
    }

    @Test("resize persistence writes sidebar width into workspace metadata")
    func resizePersistsSidebarWidthIntoWorkspaceMetadata() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                layOutMainSplitViewController(harness)
                harness.controller.splitView.setPosition(330, ofDividerAt: 0)
                harness.controller.splitView.layoutSubtreeIfNeeded()
                harness.controller.splitViewDidResizeSubviews(Notification(name: .init("test")))

                let sidebarWidth = harness.controller.splitViewItems.first?.viewController.view.frame.width ?? 0
                #expect(sidebarWidth > 300)
                #expect(abs(harness.store.windowMemoryAtom.sidebarWidth - sidebarWidth) <= 1)
            }
        )
    }

    @Test("sidebar view fills the split height below shell chrome")
    func sidebarViewFillsSplitHeightBelowShellChrome() async throws {
        try await withUnloadedMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                harness.window.styleMask.insert(.fullSizeContentView)
                harness.window.titlebarAppearsTransparent = true
                harness.window.titleVisibility = .hidden
                harness.window.contentViewController = harness.controller
                _ = harness.controller.view
                harness.window.makeKeyAndOrderFront(nil)

                layOutMainSplitViewControllerShell(harness)

                let sidebarView = try #require(harness.controller.splitViewItems.first?.viewController.view)
                let topGapWithinSplit = harness.controller.splitView.bounds.maxY - sidebarView.frame.maxY
                #expect(
                    topGapWithinSplit <= 1,
                    "sidebar top should align to split top below shell chrome; top gap was \(topGapWithinSplit)"
                )
            }
        )
    }

    @Test("shell split view does not draw a full-height sidebar divider")
    func shellSplitViewDoesNotDrawFullHeightSidebarDivider() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                #expect(harness.controller.splitView is ShellSplitView)
                #expect(harness.controller.splitView.dividerThickness == 0)
            }
        )
    }

    @Test("showWorktreeSidebar expands a restored legacy Inbox selection as Repo Explorer")
    func showWorktreeSidebarExpandsNormalizedLegacyInboxSurface() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            configureUIState: {
                $0.setSidebarCollapsed(true)
                $0.setSidebarSurface(.inbox)
            },
            body: { harness in
                #expect(harness.controller.isSidebarCollapsed == true)
                #expect(harness.atoms.core.workspaceSidebarState.sidebarSurface == .repos)

                harness.controller.showWorktreeSidebar()

                await eventually("showWorktreeSidebar should expand collapsed inbox state") {
                    harness.controller.isSidebarCollapsed == false
                        && harness.atoms.core.workspaceSidebarState.sidebarCollapsed == false
                        && harness.atoms.core.workspaceSidebarState.sidebarSurface == .repos
                }
            }
        )
    }

    @Test("collapseSidebar before viewDidLoad records collapsed shell state for restore")
    func collapseSidebarBeforeViewLoadPersistsIntent() async {
        await withUnloadedMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                #expect(harness.controller.isViewLoaded == false)
                #expect(harness.atoms.core.workspaceSidebarState.sidebarCollapsed == false)

                harness.controller.collapseSidebar()

                #expect(harness.atoms.core.workspaceSidebarState.sidebarCollapsed == true)
                #expect(harness.atoms.core.workspaceSidebarState.sidebarHasFocus == false)
            }
        )
    }

    @Test("collapseSidebar immediately records collapsed state for loaded sidebar")
    func collapseSidebarLoadedPersistsIntentImmediately() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                #expect(harness.controller.isSidebarCollapsed == false)
                #expect(harness.atoms.core.workspaceSidebarState.sidebarCollapsed == false)

                harness.controller.collapseSidebar()

                #expect(harness.atoms.core.workspaceSidebarState.sidebarCollapsed == true)
            }
        )
    }

    @Test("management takeover cancels held preview through the existing pane observation")
    func managementTakeoverCancelsHeldPreviewWithoutAnotherKey() async throws {
        try await withMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                let state = try #require(harness.controller.heldPanePreviewState)
                #expect(state.beginSpaceHold(requestedTarget: nil))

                harness.atoms.core.managementLayer.toggle()

                await eventually("management takeover should cancel held preview") {
                    if case .idle(nextGeneration: 2) = state.lifecycle {
                        return true
                    }
                    return false
                }

                harness.atoms.core.managementLayer.deactivate()
            }
        )
    }

    @Test("transient takeover cancels held preview without another key")
    func transientTakeoverCancelsHeldPreviewWithoutAnotherKey() async throws {
        try await withMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                let workspaceWindowId = UUIDv7.generate()
                harness.atoms.core.windowLifecycle.recordWindowRegistered(workspaceWindowId)
                harness.atoms.core.windowLifecycle.recordWindowBecameKey(workspaceWindowId)
                harness.atoms.core.workspaceSidebarState.setSidebarHasFocus(true)

                await eventually("sidebar routing should become eligible") {
                    KeyboardRoutingContext.current(
                        windowLifecycle: harness.atoms.core.windowLifecycle,
                        managementLayer: harness.atoms.core.managementLayer,
                        uiState: harness.atoms.core.workspaceSidebarState,
                        commandBarSurface: harness.atoms.core.commandBarSurface,
                        transientKeyboardSurface: harness.atoms.core.transientKeyboardSurface,
                        workspaceWindowId: nil
                    ).isStableSidebar
                }

                let state = try #require(harness.controller.heldPanePreviewState)
                #expect(state.beginSpaceHold(requestedTarget: nil))
                let token = harness.atoms.core.transientKeyboardSurface.present(
                    .arrangementPanel(tabId: UUIDv7.generate()),
                    workspaceWindowId: workspaceWindowId
                )

                await eventually("transient takeover should cancel held preview") {
                    if case .idle(nextGeneration: 2) = state.lifecycle {
                        return true
                    }
                    return false
                }

                harness.atoms.core.transientKeyboardSurface.dismiss(token)
            }
        )
    }

    @Test("returning to an eligible sidebar does not cancel a new held preview")
    func returningToEligibleSidebarPreservesNewHeldPreview() async throws {
        try await withMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                let workspaceWindowId = UUIDv7.generate()
                harness.atoms.core.windowLifecycle.recordWindowRegistered(workspaceWindowId)
                harness.atoms.core.windowLifecycle.recordWindowBecameKey(workspaceWindowId)
                harness.atoms.core.workspaceSidebarState.setSidebarHasFocus(true)

                await eventually("sidebar routing should become eligible") {
                    KeyboardRoutingContext.current(
                        windowLifecycle: harness.atoms.core.windowLifecycle,
                        managementLayer: harness.atoms.core.managementLayer,
                        uiState: harness.atoms.core.workspaceSidebarState,
                        commandBarSurface: harness.atoms.core.commandBarSurface,
                        transientKeyboardSurface: harness.atoms.core.transientKeyboardSurface,
                        workspaceWindowId: nil
                    ).isStableSidebar
                }

                let state = try #require(harness.controller.heldPanePreviewState)
                #expect(state.beginSpaceHold(requestedTarget: nil))
                let token = harness.atoms.core.transientKeyboardSurface.present(
                    .arrangementPanel(tabId: UUIDv7.generate()),
                    workspaceWindowId: workspaceWindowId
                )
                await eventually("transient takeover should end the first hold") {
                    if case .idle(nextGeneration: 2) = state.lifecycle {
                        return true
                    }
                    return false
                }

                harness.atoms.core.transientKeyboardSurface.dismiss(token)
                harness.atoms.core.workspaceSidebarState.setSidebarHasFocus(true)
                await eventually("sidebar should be eligible after transient dismissal") {
                    let context = KeyboardRoutingContext.current(
                        windowLifecycle: harness.atoms.core.windowLifecycle,
                        managementLayer: harness.atoms.core.managementLayer,
                        uiState: harness.atoms.core.workspaceSidebarState,
                        commandBarSurface: harness.atoms.core.commandBarSurface,
                        transientKeyboardSurface: harness.atoms.core.transientKeyboardSurface,
                        workspaceWindowId: nil
                    )
                    if case .idle(nextGeneration: 2) = state.lifecycle {
                        return context.isStableSidebar
                    }
                    return false
                }

                #expect(state.beginSpaceHold(requestedTarget: nil))
                await eventually("a fresh hold should remain active while sidebar stays eligible") {
                    state.lifecycle == .held(generation: 2, requestedTarget: nil)
                }
            }
        )
    }

    @Test("drawer child preview keeps child identity while resolving its parent tab")
    func drawerChildPreviewResolvesOwningTabThroughParent() async throws {
        var onSpaceKeyDown: (@MainActor (Bool, RepoExplorerSelectedPaneTarget?) -> Void)?
        var onSelectedPaneTargetChange: (@MainActor (RepoExplorerSelectedPaneTarget?) -> Void)?
        try await withMainSplitViewControllerHarness(
            withRepos: false,
            configureSidebarDependencies: { dependencies in
                onSpaceKeyDown = dependencies.onSpaceKeyDown
                onSelectedPaneTargetChange = dependencies.onSelectedPaneTargetChange
            },
            body: { harness in
                let parentPane = harness.store.createPane()
                let tab = Tab(paneId: parentPane.id)
                harness.store.appendTab(tab)
                harness.store.setActiveTab(tab.id)
                let drawerPane = try #require(
                    harness.store.paneAtom.addDrawerPane(
                        to: parentPane.id,
                        parentFallbackCWD: nil,
                        zmxSessionID: .generateUUIDv7()
                    )
                )

                #expect(harness.store.tabLayoutAtom.tabID(containingPane: drawerPane.id) == nil)
                #expect(drawerPane.parentPaneId == parentPane.id)

                let selectedTarget = RepoExplorerSelectedPaneTarget(
                    paneID: drawerPane.id,
                    owningTabID: tab.id
                )
                onSpaceKeyDown?(false, selectedTarget)

                let state = try #require(harness.controller.heldPanePreviewState)
                #expect(state.requestedTarget?.paneID == drawerPane.id)
                #expect(state.requestedTarget?.owningTabID == tab.id)
                #expect(state.requestedTarget?.provider == drawerPane.provider)
                #expect(state.requestedTarget?.sessionID == drawerPane.terminalState?.zmxSessionID)

                let wrongOwnerTarget = RepoExplorerSelectedPaneTarget(
                    paneID: drawerPane.id,
                    owningTabID: UUIDv7.generate()
                )
                onSelectedPaneTargetChange?(wrongOwnerTarget)
                #expect(state.requestedTarget == nil)
            }
        )
    }

    @Test("ready held preview reveals its owning tab without changing durable selection")
    func readyHeldPreviewRevealsOwningTabWithoutChangingDurableSelection() async throws {
        try await withUnloadedMainSplitViewControllerHarness(
            withRepos: true,
            configureUIState: { $0.setSidebarCollapsed(false) },
            body: { harness in
                let activePane = harness.store.createPane()
                let previewPane = harness.store.createPane()
                let activeTab = Tab(paneId: activePane.id)
                let previewTab = Tab(paneId: previewPane.id)
                harness.store.appendTab(activeTab)
                harness.store.appendTab(previewTab)
                harness.store.setActiveTab(activeTab.id)

                let previewHost = PaneHostView(paneId: previewPane.id)
                harness.coordinator.viewRegistry.register(previewHost, for: previewPane.id)

                harness.window.contentViewController = harness.controller
                _ = harness.controller.view
                harness.window.makeKeyAndOrderFront(nil)
                #expect(harness.controller.focusSidebarHostIfReady())
                let sidebarResponder = harness.window.firstResponder

                let target = ValidatedPanePreviewTarget(
                    paneID: previewPane.id,
                    owningTabID: previewTab.id,
                    provider: previewPane.provider,
                    sessionID: previewPane.terminalState?.zmxSessionID
                )
                let state = try #require(harness.controller.heldPanePreviewState)
                #expect(state.beginSpaceHold(requestedTarget: target))
                #expect(state.acceptPresentedTarget(target, generation: 1))

                await eventually("owning tab host should become visible for a ready preview") {
                    let previewTabHost = firstPersistentTabHost(
                        tabId: previewTab.id,
                        in: harness.controller.view
                    )
                    return previewTabHost?.isHidden == false
                }
                #expect(harness.store.tabLayoutAtom.activeTabId == activeTab.id)
                #expect(harness.window.firstResponder === sidebarResponder)
            }
        )
    }

    @Test("ready held preview reveals its owning tab after a late host registration")
    func readyHeldPreviewRevealsOwningTabAfterLateHostRegistration() async throws {
        try await withUnloadedMainSplitViewControllerHarness(
            withRepos: true,
            configureUIState: { $0.setSidebarCollapsed(false) },
            body: { harness in
                let activePane = harness.store.createPane()
                let previewPane = harness.store.createPane()
                let activeTab = Tab(paneId: activePane.id)
                let previewTab = Tab(paneId: previewPane.id)
                harness.store.appendTab(activeTab)
                harness.store.appendTab(previewTab)
                harness.store.setActiveTab(activeTab.id)

                harness.window.contentViewController = harness.controller
                _ = harness.controller.view
                harness.window.makeKeyAndOrderFront(nil)
                #expect(harness.controller.focusSidebarHostIfReady())

                let target = ValidatedPanePreviewTarget(
                    paneID: previewPane.id,
                    owningTabID: previewTab.id,
                    provider: previewPane.provider,
                    sessionID: previewPane.terminalState?.zmxSessionID
                )
                let state = try #require(harness.controller.heldPanePreviewState)
                #expect(state.beginSpaceHold(requestedTarget: target))
                #expect(state.acceptPresentedTarget(target, generation: 1))

                await eventually("canonical tab remains visible until the preview host is registered") {
                    firstPersistentTabHost(
                        tabId: activeTab.id,
                        in: harness.controller.view
                    )?.isHidden == false
                        && firstPersistentTabHost(
                            tabId: previewTab.id,
                            in: harness.controller.view
                        )?.isHidden == true
                }

                let previewHost = PaneHostView(paneId: previewPane.id)
                harness.coordinator.viewRegistry.register(previewHost, for: previewPane.id)

                await eventually("late host registration should reveal the owning tab") {
                    firstPersistentTabHost(
                        tabId: activeTab.id,
                        in: harness.controller.view
                    )?.isHidden == true
                        && firstPersistentTabHost(
                            tabId: previewTab.id,
                            in: harness.controller.view
                        )?.isHidden == false
                }
            }
        )
    }

    @Test("stale held preview provider or session keeps the durable tab visible")
    func staleHeldPreviewIdentityKeepsDurableTabVisible() async throws {
        try await withUnloadedMainSplitViewControllerHarness(
            withRepos: true,
            configureUIState: { $0.setSidebarCollapsed(false) },
            body: { harness in
                let activePane = harness.store.createPane()
                let previewPane = harness.store.createPane()
                let activeTab = Tab(paneId: activePane.id)
                let previewTab = Tab(paneId: previewPane.id)
                harness.store.appendTab(activeTab)
                harness.store.appendTab(previewTab)
                harness.store.setActiveTab(activeTab.id)

                let previewHost = PaneHostView(paneId: previewPane.id)
                harness.coordinator.viewRegistry.register(previewHost, for: previewPane.id)

                harness.window.contentViewController = harness.controller
                _ = harness.controller.view
                harness.window.makeKeyAndOrderFront(nil)

                let currentProvider = try #require(previewPane.provider)
                let staleProvider: SessionProvider = currentProvider == .zmx ? .ghostty : .zmx
                let staleTarget = ValidatedPanePreviewTarget(
                    paneID: previewPane.id,
                    owningTabID: previewTab.id,
                    provider: staleProvider,
                    sessionID: .generateUUIDv7()
                )
                let state = try #require(harness.controller.heldPanePreviewState)
                #expect(state.beginSpaceHold(requestedTarget: staleTarget))
                #expect(state.acceptPresentedTarget(staleTarget, generation: 1))

                await eventually("stale preview identity should not reveal its owning tab") {
                    firstPersistentTabHost(
                        tabId: activeTab.id,
                        in: harness.controller.view
                    )?.isHidden == false
                        && firstPersistentTabHost(
                            tabId: previewTab.id,
                            in: harness.controller.view
                        )?.isHidden == true
                }
            }
        )
    }

    private func layOutMainSplitViewController(_ harness: MainSplitViewControllerHarness) {
        harness.window.setContentSize(NSSize(width: 1000, height: 700))
        harness.controller.view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        harness.controller.splitView.frame = harness.controller.view.bounds
        harness.controller.view.layoutSubtreeIfNeeded()
        harness.controller.viewDidLayout()
    }

    private func layOutMainSplitViewControllerShell(_ harness: MainSplitViewControllerHarness) {
        harness.window.setContentSize(NSSize(width: 1000, height: 700))
        harness.controller.view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        harness.controller.view.layoutSubtreeIfNeeded()
        harness.controller.splitView.layoutSubtreeIfNeeded()
        harness.controller.viewDidLayout()
    }
}

@MainActor
private func firstPersistentTabHost(
    tabId: UUID,
    in view: NSView
) -> PersistentTabHostView? {
    if let host = view as? PersistentTabHostView, host.tabId == tabId {
        return host
    }
    for subview in view.subviews {
        if let host = firstPersistentTabHost(tabId: tabId, in: subview) {
            return host
        }
    }
    return nil
}
