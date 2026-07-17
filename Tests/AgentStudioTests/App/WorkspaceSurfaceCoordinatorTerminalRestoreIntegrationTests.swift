import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceSurfaceTerminalRestoreIntegrationTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    private let fixtureSessionConfiguration = SessionConfiguration(
        isEnabled: true,
        zmxPath: "/tmp/fake-zmx",
        zmxDir: "/tmp/fake-zmx-dir",
        healthCheckInterval: 30,
        maxCheckpointAge: 60
    )

    private struct Harness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let runtime: SessionRuntime
        let coordinator: WorkspaceSurfaceCoordinator
        let windowLifecycleStore: WindowLifecycleAtom
        let surfaceManager: CapturingSurfaceManager
        let tempDir: URL
    }

    private func makeHarness() -> Harness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-luna295-tests-\(UUID().uuidString)")
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner())
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let windowLifecycleStore = WindowLifecycleAtom()
        let surfaceManager = CapturingSurfaceManager()
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: surfaceManager,
            runtimeRegistry: .shared,
            windowLifecycleStore: windowLifecycleStore
        )
        coordinator.sessionConfig = fixtureSessionConfiguration
        coordinator.terminalRestoreRuntime = TerminalRestoreRuntime(
            sessionConfiguration: fixtureSessionConfiguration
        )
        return Harness(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            coordinator: coordinator,
            windowLifecycleStore: windowLifecycleStore,
            surfaceManager: surfaceManager,
            tempDir: tempDir
        )
    }

    private let trustedBounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

    @Test
    func preparedTerminalMount_rejectsMissingTrustedFrameBeforeSurfaceCreation() throws {
        // Arrange
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let admission = try makePreparedTerminalAdmission(
            pane: makeAcceptedPreparedTerminalPane(launchDirectory: harness.tempDir)
        )

        // Act
        let result = harness.coordinator.mountPreparedTerminalContent(
            admission: admission,
            initialFrame: nil
        )

        // Assert
        #expect(
            result
                == .failed(
                    failure: .surfaceCreationFailed(code: "trusted_initial_frame_unavailable"),
                    retry: .doNotRetry
                )
        )
        #expect(harness.surfaceManager.createdPaneIds.isEmpty)
    }

    @Test
    func preparedTerminalMount_usesAcceptedPaneAndFrozenFrameWithoutTopologyLookup() throws {
        // Arrange
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let pane = makeAcceptedPreparedTerminalPane(launchDirectory: harness.tempDir)
        let admission = try makePreparedTerminalAdmission(pane: pane)
        let frozenFrame = NSRect(x: 12, y: 18, width: 880, height: 540)

        // Act
        let result = harness.coordinator.mountPreparedTerminalContent(
            admission: admission,
            initialFrame: frozenFrame
        )

        // Assert
        #expect(
            result
                == .failed(
                    failure: .surfaceCreationFailed(code: "prepared_mount_failed"),
                    retry: .retry
                )
        )
        #expect(harness.surfaceManager.createdPaneIds == [pane.id])
        #expect(harness.surfaceManager.createdConfigsByPaneId[pane.id]?.initialFrame == frozenFrame)
        let expectedSessionID = try #require(pane.terminalState?.zmxSessionID)
        #expect(
            harness.surfaceManager.createdConfigsByPaneId[pane.id]?
                .startupStrategy.startupCommandForSurface?
                .contains(expectedSessionID.rawValue) == true
        )
    }

    @Test
    func newZmxPane_uses_directSurfaceCommand_notDeferredShell() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)

        let pane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )

        _ = harness.coordinator.createView(
            for: pane,
            worktree: worktree,
            repo: repo,
            initialFrame: NSRect(x: 0, y: 0, width: 1000, height: 600)
        )

        let config = try #require(harness.surfaceManager.lastConfig)
        let generatedSessionID = try #require(pane.terminalState?.zmxSessionID)
        let generatedUUID = try #require(UUID(uuidString: generatedSessionID.rawValue))
        #expect(config.startupStrategy.startupCommandForSurface?.contains(" attach ") == true)
        #expect(
            config.startupStrategy.startupCommandForSurface?
                .contains(ZmxBackend.shellEscape(generatedSessionID.rawValue)) == true
        )
        #expect(UUIDv7.isV7(generatedUUID))
        #expect(config.environmentVariables["ZMX_DIR"] == fixtureSessionConfiguration.zmxDir)
        #expect(config.environmentVariables["ZMX_SESSION"]?.isEmpty == true)
        #expect(config.environmentVariables["ZMX_SESSION_PREFIX"]?.isEmpty == true)
    }

    @Test
    func floatingZmxPane_uses_directSurfaceCommand_notDeferredShell() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(
            launchDirectory: harness.tempDir,
            provider: .zmx
        )

        _ = harness.coordinator.createViewForContent(
            pane: pane,
            initialFrame: NSRect(x: 0, y: 0, width: 1000, height: 600)
        )

        let config = try #require(harness.surfaceManager.lastConfig)
        #expect(config.startupStrategy.startupCommandForSurface?.contains(" attach ") == true)
        #expect(config.environmentVariables["ZMX_DIR"] == fixtureSessionConfiguration.zmxDir)
        #expect(config.environmentVariables["ZMX_SESSION"]?.isEmpty == true)
        #expect(config.environmentVariables["ZMX_SESSION_PREFIX"]?.isEmpty == true)
    }

    @Test
    func floatingZmxPane_withoutPersistedCwd_stillUsesDirectSurfaceCommand() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(
            provider: .zmx
        )

        _ = harness.coordinator.createViewForContent(
            pane: pane,
            initialFrame: NSRect(x: 0, y: 0, width: 1000, height: 600)
        )

        let config = try #require(harness.surfaceManager.lastConfig)
        #expect(config.startupStrategy.startupCommandForSurface?.contains(" attach ") == true)
        #expect(config.environmentVariables["ZMX_DIR"] == fixtureSessionConfiguration.zmxDir)
        #expect(config.environmentVariables["ZMX_SESSION"]?.isEmpty == true)
        #expect(config.environmentVariables["ZMX_SESSION_PREFIX"]?.isEmpty == true)
    }

    @Test
    func preparedContentOwner_restoresHiddenZmxWithoutConsultingDaemonInventory() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let visiblePane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let hiddenPane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )

        let visibleTab = Tab(paneId: visiblePane.id, name: "Visible")
        let hiddenTab = Tab(paneId: hiddenPane.id, name: "Hidden")
        harness.store.appendTab(visibleTab)
        harness.store.appendTab(hiddenTab)
        harness.store.setActiveTab(visibleTab.id)

        try await mountPreparedTerminalCohort(
            coordinator: harness.coordinator,
            viewRegistry: harness.viewRegistry,
            entries: [
                (visiblePane, .activeVisible, .tab(tabID: visibleTab.id)),
                (hiddenPane, .hidden, .tab(tabID: hiddenTab.id)),
            ],
            trustedBounds: trustedBounds
        )

        #expect(harness.surfaceManager.createdPaneIds.filter { $0 == visiblePane.id }.count == 2)
        #expect(harness.surfaceManager.createdPaneIds.filter { $0 == hiddenPane.id }.count == 2)
    }

    @Test
    func preparedContentOwner_attemptsVisibleAndHiddenZmxAttachDuringInitialRestore() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let visiblePane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let hiddenPane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )

        let visibleTab = Tab(paneId: visiblePane.id, name: "Visible")
        let hiddenTab = Tab(paneId: hiddenPane.id, name: "Hidden")
        harness.store.appendTab(visibleTab)
        harness.store.appendTab(hiddenTab)
        harness.store.setActiveTab(visibleTab.id)

        try await mountPreparedTerminalCohort(
            coordinator: harness.coordinator,
            viewRegistry: harness.viewRegistry,
            entries: [
                (visiblePane, .activeVisible, .tab(tabID: visibleTab.id)),
                (hiddenPane, .hidden, .tab(tabID: hiddenTab.id)),
            ],
            trustedBounds: trustedBounds
        )

        let visiblePlaceholder = try #require(harness.viewRegistry.terminalStatusPlaceholderView(for: visiblePane.id))
        let hiddenPlaceholder = try #require(harness.viewRegistry.terminalStatusPlaceholderView(for: hiddenPane.id))
        #expect(visiblePlaceholder.mode == .failedToStart)
        #expect(hiddenPlaceholder.mode == .failedToStart)
        #expect(harness.surfaceManager.createdPaneIds.filter { $0 == visiblePane.id }.count == 2)
        #expect(harness.surfaceManager.createdPaneIds.filter { $0 == hiddenPane.id }.count == 2)
        #expect(harness.viewRegistry.isInitialRestorePending == false)
    }

    @Test
    func selectTabReusesHiddenPaneRestoredDuringStartup() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let visiblePane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let hiddenPane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )

        let visibleTab = Tab(paneId: visiblePane.id, name: "Visible")
        let hiddenTab = Tab(paneId: hiddenPane.id, name: "Hidden")
        harness.store.appendTab(visibleTab)
        harness.store.appendTab(hiddenTab)
        harness.store.setActiveTab(visibleTab.id)

        try await mountPreparedTerminalCohort(
            coordinator: harness.coordinator,
            viewRegistry: harness.viewRegistry,
            entries: [
                (visiblePane, .activeVisible, .tab(tabID: visibleTab.id)),
                (hiddenPane, .hidden, .tab(tabID: hiddenTab.id)),
            ],
            trustedBounds: trustedBounds
        )
        let creationAttemptsBeforeSelection = harness.surfaceManager.createdPaneIds

        harness.coordinator.execute(.selectTab(tabId: hiddenTab.id))

        #expect(harness.surfaceManager.createdPaneIds == creationAttemptsBeforeSelection)
    }

    @Test
    func preparedContentOwner_restoresHiddenDrawerZmxUnderNonZmxParent() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let visiblePane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let hiddenParentPane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .ghostty,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )

        let visibleTab = Tab(paneId: visiblePane.id, name: "Visible")
        let hiddenTab = Tab(paneId: hiddenParentPane.id, name: "Hidden")
        harness.store.appendTab(visibleTab)
        harness.store.appendTab(hiddenTab)
        let hiddenDrawerPane = try #require(harness.store.addDrawerPane(to: hiddenParentPane.id))
        harness.store.setActiveTab(visibleTab.id)

        let acceptedHiddenParent = try #require(harness.store.pane(hiddenParentPane.id))
        let hiddenDrawer = try #require(harness.store.pane(hiddenDrawerPane.id))
        let hiddenDrawerID = try #require(acceptedHiddenParent.drawer?.drawerId)
        try await mountPreparedTerminalCohort(
            coordinator: harness.coordinator,
            viewRegistry: harness.viewRegistry,
            entries: [
                (visiblePane, .activeVisible, .tab(tabID: visibleTab.id)),
                (acceptedHiddenParent, .hidden, .tab(tabID: hiddenTab.id)),
                (
                    hiddenDrawer,
                    .hidden,
                    .drawer(
                        tabID: hiddenTab.id,
                        parentPaneID: PaneId(existingUUID: hiddenParentPane.id),
                        drawerID: hiddenDrawerID
                    )
                ),
            ],
            trustedBounds: trustedBounds
        )

        #expect(harness.surfaceManager.createdPaneIds.filter { $0 == visiblePane.id }.count == 2)
        #expect(harness.surfaceManager.createdPaneIds.filter { $0 == hiddenParentPane.id }.count == 2)
        #expect(harness.surfaceManager.createdPaneIds.filter { $0 == hiddenDrawerPane.id }.count == 2)
    }

    @Test
    func preparedContentOwner_restoresHiddenDrawerAndHiddenZmxParent() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let visiblePane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let hiddenParentPane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )

        let visibleTab = Tab(paneId: visiblePane.id, name: "Visible")
        let hiddenTab = Tab(paneId: hiddenParentPane.id, name: "Hidden")
        harness.store.appendTab(visibleTab)
        harness.store.appendTab(hiddenTab)
        let hiddenDrawerPane = try #require(harness.store.addDrawerPane(to: hiddenParentPane.id))
        harness.store.setActiveTab(visibleTab.id)

        let acceptedHiddenParent = try #require(harness.store.pane(hiddenParentPane.id))
        let hiddenDrawer = try #require(harness.store.pane(hiddenDrawerPane.id))
        let hiddenDrawerID = try #require(acceptedHiddenParent.drawer?.drawerId)
        try await mountPreparedTerminalCohort(
            coordinator: harness.coordinator,
            viewRegistry: harness.viewRegistry,
            entries: [
                (visiblePane, .activeVisible, .tab(tabID: visibleTab.id)),
                (acceptedHiddenParent, .hidden, .tab(tabID: hiddenTab.id)),
                (
                    hiddenDrawer,
                    .hidden,
                    .drawer(
                        tabID: hiddenTab.id,
                        parentPaneID: PaneId(existingUUID: hiddenParentPane.id),
                        drawerID: hiddenDrawerID
                    )
                ),
            ],
            trustedBounds: trustedBounds
        )

        #expect(harness.surfaceManager.createdPaneIds.filter { $0 == visiblePane.id }.count == 2)
        #expect(harness.surfaceManager.createdPaneIds.filter { $0 == hiddenParentPane.id }.count == 2)
        #expect(harness.surfaceManager.createdPaneIds.filter { $0 == hiddenDrawerPane.id }.count == 2)
    }

    @Test
    func preparedContentOwner_passesResolvedInitialFrame_toVisiblePane() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let pane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )

        let tab = Tab(paneId: pane.id, name: "Visible")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        let containerWidth: CGFloat = 1000
        let containerHeight: CGFloat = 600
        try await mountPreparedTerminalCohort(
            coordinator: harness.coordinator,
            viewRegistry: harness.viewRegistry,
            entries: [(pane, .activeVisible, .tab(tabID: tab.id))],
            trustedBounds: CGRect(x: 0, y: 0, width: containerWidth, height: containerHeight)
        )

        let config = try #require(harness.surfaceManager.createdConfigsByPaneId[pane.id])
        let gap = AppStyles.General.Layout.paneGap
        #expect(
            config.initialFrame
                == CGRect(x: gap, y: gap, width: containerWidth - gap * 2, height: containerHeight - gap * 2))
    }

    @Test
    func preparedContentOwner_passesResolvedInitialFrame_toExpandedDrawerPane() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let pane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )

        let tab = Tab(paneId: pane.id, name: "Visible")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: pane.id))

        let acceptedParentPane = try #require(harness.store.pane(pane.id))
        let acceptedDrawerPane = try #require(harness.store.pane(drawerPane.id))
        let drawerID = try #require(acceptedParentPane.drawer?.drawerId)
        try await mountPreparedTerminalCohort(
            coordinator: harness.coordinator,
            viewRegistry: harness.viewRegistry,
            entries: [
                (acceptedParentPane, .activeVisible, .tab(tabID: tab.id)),
                (
                    acceptedDrawerPane,
                    .activeVisible,
                    .drawer(
                        tabID: tab.id,
                        parentPaneID: PaneId(existingUUID: pane.id),
                        drawerID: drawerID
                    )
                ),
            ],
            trustedBounds: CGRect(x: 0, y: 0, width: 1000, height: 600)
        )

        let config = try #require(harness.surfaceManager.createdConfigsByPaneId[drawerPane.id])
        let frame = try #require(config.initialFrame)
        #expect(frame.width > 0)
        #expect(frame.height > 0)
        #expect(frame.origin.y > 0)
    }

    @Test
    func resolveInitialFramesByTabId_ignoresShowMinimizedBarsToggle_forCanonicalMinimizedGeometry() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let firstPane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let secondPane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )

        let tab = Tab(paneId: firstPane.id, name: "Minimized")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        _ = harness.store.insertPane(
            secondPane.id,
            inTab: tab.id,
            at: firstPane.id,
            direction: .horizontal,
            position: .after, sizingMode: .halveTarget
        )
        _ = harness.store.minimizePane(secondPane.id, inTab: tab.id)
        harness.store.tabLayoutAtom.setShowsMinimizedPanes(false, inTab: tab.id)

        let framesByTabId = harness.coordinator.resolveInitialFramesByTabId(
            in: CGRect(x: 0, y: 0, width: 1000, height: 600)
        )
        let minimizedFrame = try #require(framesByTabId[tab.id]?[secondPane.id])

        #expect(
            minimizedFrame.width
                == AppStyles.Shell.PaneChrome.collapsedBarWidth
                - (AppStyles.General.Layout.paneGap * 2)
        )
    }

    @Test
    func splitRight_newZmxPane_usesTrustedInitialFrame_notPlaceholderGeometry() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let existingPane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: existingPane.id, name: "Split")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.windowLifecycleStore.recordTerminalContainerBounds(
            CGRect(x: 0, y: 0, width: 1000, height: 600)
        )

        let existingPaneIds = Set(harness.store.panes.keys)
        harness.coordinator.execute(
            .insertPane(
                source: .newTerminal,
                targetTabId: tab.id,
                targetPaneId: existingPane.id,
                direction: .right,
                sizingMode: .halveTarget
            )
        )

        let newPaneId = try #require(Set(harness.store.panes.keys).subtracting(existingPaneIds).first)
        let config = try #require(harness.surfaceManager.createdConfigsByPaneId[newPaneId])
        let activeTab = try #require(harness.store.activeTab)
        let resolvedFrames = TerminalPaneGeometryResolver.resolveFrames(
            for: activeTab.layout,
            in: harness.windowLifecycleStore.terminalContainerBounds,
            dividerThickness: AppStyles.General.Layout.paneGap,
            minimizedPaneIds: activeTab.activeMinimizedPaneIds,
            collapsedPaneWidth: AppStyles.Shell.PaneChrome.collapsedBarWidth
        )

        #expect(config.initialFrame != nil)
        #expect(config.initialFrame != CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(config.initialFrame == resolvedFrames[newPaneId])
    }

    @Test
    func openNewTerminalTab_usesTrustedInitialFrame_notPlaceholderGeometry() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        harness.windowLifecycleStore.recordTerminalContainerBounds(
            CGRect(x: 0, y: 0, width: 1000, height: 600)
        )

        let pane = try #require(harness.coordinator.openNewTerminal(for: worktree, in: repo))
        let config = try #require(harness.surfaceManager.createdConfigsByPaneId[pane.id])
        let activeTab = try #require(harness.store.activeTab)
        let resolvedFrames = TerminalPaneGeometryResolver.resolveFrames(
            for: activeTab.layout,
            in: harness.windowLifecycleStore.terminalContainerBounds,
            dividerThickness: AppStyles.General.Layout.paneGap,
            minimizedPaneIds: activeTab.activeMinimizedPaneIds,
            collapsedPaneWidth: AppStyles.Shell.PaneChrome.collapsedBarWidth
        )

        #expect(config.initialFrame != nil)
        #expect(config.initialFrame != CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(config.initialFrame == resolvedFrames[pane.id])
    }

    @Test
    func openFloatingTerminal_usesTrustedInitialFrame_notPlaceholderGeometry() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        harness.windowLifecycleStore.recordTerminalContainerBounds(
            CGRect(x: 0, y: 0, width: 1000, height: 600)
        )

        let pane = try #require(
            harness.coordinator.openFloatingTerminal(launchDirectory: harness.tempDir, title: "Floating")
        )
        let config = try #require(harness.surfaceManager.createdConfigsByPaneId[pane.id])
        let activeTab = try #require(harness.store.activeTab)
        let resolvedFrames = TerminalPaneGeometryResolver.resolveFrames(
            for: activeTab.layout,
            in: harness.windowLifecycleStore.terminalContainerBounds,
            dividerThickness: AppStyles.General.Layout.paneGap,
            minimizedPaneIds: activeTab.activeMinimizedPaneIds,
            collapsedPaneWidth: AppStyles.Shell.PaneChrome.collapsedBarWidth
        )

        #expect(config.initialFrame != nil)
        #expect(config.initialFrame != CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(config.initialFrame == resolvedFrames[pane.id])
    }

    @Test
    func openNewTerminalTab_defersSurfaceCreation_untilBoundsExist_thenCreatesWithTrustedFrame() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)

        let pane = try #require(harness.coordinator.openNewTerminal(for: worktree, in: repo))
        #expect(harness.surfaceManager.createdConfigsByPaneId[pane.id] == nil)
        let preparingPlaceholder = try #require(harness.viewRegistry.terminalStatusPlaceholderView(for: pane.id))
        #expect(preparingPlaceholder.mode == .preparing)

        harness.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        harness.coordinator.restoreViewsForActiveTabIfNeeded()

        let config = try #require(harness.surfaceManager.createdConfigsByPaneId[pane.id])
        let failedPlaceholder = try #require(harness.viewRegistry.terminalStatusPlaceholderView(for: pane.id))
        let activeTab = try #require(harness.store.activeTab)
        let resolvedFrames = TerminalPaneGeometryResolver.resolveFrames(
            for: activeTab.layout,
            in: harness.windowLifecycleStore.terminalContainerBounds,
            dividerThickness: AppStyles.General.Layout.paneGap,
            minimizedPaneIds: activeTab.activeMinimizedPaneIds,
            collapsedPaneWidth: AppStyles.Shell.PaneChrome.collapsedBarWidth
        )

        #expect(config.initialFrame == resolvedFrames[pane.id])
        #expect(failedPlaceholder.mode == .failedToStart)
    }

    @Test
    func targetedRepair_retriesFloatingTerminalPreparingPlaceholderWhenBoundsExist() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = try #require(
            harness.coordinator.openFloatingTerminal(launchDirectory: harness.tempDir, title: "Floating")
        )
        #expect(harness.surfaceManager.createdConfigsByPaneId[pane.id] == nil)
        let preparingPlaceholder = try #require(harness.viewRegistry.terminalStatusPlaceholderView(for: pane.id))
        #expect(preparingPlaceholder.mode == .preparing)

        harness.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        harness.coordinator.restoreViewsForActiveTabIfNeeded()

        let config = try #require(harness.surfaceManager.createdConfigsByPaneId[pane.id])
        let failedPlaceholder = try #require(harness.viewRegistry.terminalStatusPlaceholderView(for: pane.id))
        let activeTab = try #require(harness.store.activeTab)
        let resolvedFrames = TerminalPaneGeometryResolver.resolveFrames(
            for: activeTab.layout,
            in: harness.windowLifecycleStore.terminalContainerBounds,
            dividerThickness: AppStyles.General.Layout.paneGap,
            minimizedPaneIds: activeTab.activeMinimizedPaneIds,
            collapsedPaneWidth: AppStyles.Shell.PaneChrome.collapsedBarWidth
        )

        #expect(config.initialFrame == resolvedFrames[pane.id])
        #expect(failedPlaceholder.mode == .failedToStart)
    }

    @Test
    func openNewTerminalTab_failedCreation_keepsFailurePlaceholderVisible() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        harness.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)

        let pane = try #require(harness.coordinator.openNewTerminal(for: worktree, in: repo))

        let placeholder = try #require(harness.viewRegistry.terminalStatusPlaceholderView(for: pane.id))
        #expect(placeholder.mode == .failedToStart)
    }

    @Test
    func failedToStartPlaceholder_doesNotAutoRetryOnLaterBoundsChanges() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        harness.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)

        let pane = try #require(harness.coordinator.openNewTerminal(for: worktree, in: repo))
        let createAttemptsBefore = harness.surfaceManager.createdPaneIds.count
        let placeholder = try #require(harness.viewRegistry.terminalStatusPlaceholderView(for: pane.id))

        #expect(placeholder.mode == .failedToStart)
        #expect(placeholder.shouldRetryCreationWhenBoundsChange == false)

        harness.windowLifecycleStore.recordTerminalContainerBounds(
            CGRect(x: 0, y: 0, width: 1200, height: 700)
        )
        harness.coordinator.restoreViewsForActiveTabIfNeeded()

        #expect(harness.surfaceManager.createdPaneIds.count == createAttemptsBefore)
        #expect(harness.viewRegistry.terminalStatusPlaceholderView(for: pane.id)?.mode == .failedToStart)
    }

    @Test
    func createViewForContentUsingCurrentGeometry_withoutBounds_returnsNil_andDoesNotReachSurfaceManager() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let pane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )

        let view = harness.coordinator.createViewForContentUsingCurrentGeometry(pane: pane)

        #expect(view == nil)
        let placeholder = try #require(harness.viewRegistry.terminalStatusPlaceholderView(for: pane.id))
        #expect(placeholder.mode == .preparing)
        #expect(harness.surfaceManager.lastConfig == nil)
        #expect(harness.surfaceManager.createdPaneIds.isEmpty)
    }
}

@MainActor
private func mountPreparedTerminalCohort(
    coordinator: WorkspaceSurfaceCoordinator,
    viewRegistry: ViewRegistry,
    entries: [(Pane, TerminalActivationVisibilityPriority, TerminalHostPlacementIdentity)],
    trustedBounds: CGRect
) async throws {
    let generation = try preparedTerminalCohortGeneration()
    let descriptors = try entries.map { pane, priority, placement in
        try preparedTerminalCohortDescriptor(
            pane: pane,
            visibilityPriority: priority,
            hostPlacement: placement
        )
    }
    let resolvedFramesByTabID = coordinator.resolveInitialFramesByTabId(in: trustedBounds)
    let initialFramesByPaneID = nonEmptyInitialFramesByPaneID(resolvedFramesByTabID)
    let cohort = WorkspacePreparedContentMountCohort(
        generation: generation,
        terminalActivationInput: TerminalActivationInput(entries: descriptors),
        nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
    )
    viewRegistry.beginInitialRestore()
    let owner = WorkspacePreparedContentMountCoordinator(
        cohort: cohort,
        viewRegistry: viewRegistry,
        terminalAdmissionPort: PreparedTerminalMountAdmissionPort(
            generation: generation,
            initialFramesByPaneID: initialFramesByPaneID,
            viewRegistry: viewRegistry,
            mountHandler: coordinator
        ),
        nonterminalAdmissionPort: PreparedNonterminalMountAdmissionPort(
            generation: generation,
            coordinator: coordinator
        )
    )
    _ = await owner.mount()
}

private func nonEmptyInitialFramesByPaneID(
    _ framesByTabID: [UUID: [UUID: CGRect]]
) -> [PaneId: NSRect] {
    var framesByPaneID: [PaneId: NSRect] = [:]
    for tabFrames in framesByTabID.values {
        for (paneID, frame) in tabFrames where !frame.isEmpty {
            framesByPaneID[PaneId(existingUUID: paneID)] = frame
        }
    }
    return framesByPaneID
}

@MainActor
private func preparedTerminalCohortGeneration() throws -> WorkspaceContentMountGeneration {
    let revisionOwner = WorkspacePersistenceRevisionOwner()
    let revision = try revisionOwner.performSynchronousTransaction { preparation in
        preparation.commit { preparation.transaction.proposedRevision }
    }
    return WorkspaceContentMountGeneration(
        processGeneration: revisionOwner.processGeneration,
        revision: revision
    )
}

private func preparedTerminalCohortDescriptor(
    pane: Pane,
    visibilityPriority: TerminalActivationVisibilityPriority,
    hostPlacement: TerminalHostPlacementIdentity
) throws -> TerminalActivationDescriptor {
    guard case .terminal(let terminalState) = pane.content else {
        preconditionFailure("prepared terminal cohort requires terminal content")
    }
    let provider: TerminalActivationProvider =
        switch terminalState.provider {
        case .ghostty: .ghostty
        case .zmx: .zmx
        }
    return TerminalActivationDescriptor(
        pane: pane,
        zmxSessionID: terminalState.zmxSessionID,
        provider: provider,
        launchConfiguration: TerminalActivationLaunchConfiguration(
            launchDirectory: pane.metadata.launchDirectory.map(TerminalActivationLaunchDirectory.stored)
                ?? .userHomeDefault,
            executionBackend: pane.metadata.executionBackend,
            lifetime: terminalState.lifetime,
            displayTitle: pane.metadata.title
        ),
        visibilityPriority: visibilityPriority,
        hostPlacement: hostPlacement
    )
}

private func makeAcceptedPreparedTerminalPane(launchDirectory: URL) -> Pane {
    Pane(
        id: UUIDv7.generate(),
        content: .terminal(
            TerminalState(
                provider: .zmx,
                lifetime: .persistent,
                zmxSessionID: .generateUUIDv7()
            )
        ),
        metadata: PaneMetadata(
            launchDirectory: launchDirectory,
            title: "Accepted Prepared Terminal"
        )
    )
}

@MainActor
private func makePreparedTerminalAdmission(pane: Pane) throws -> TerminalActivationAdmission {
    let revisionOwner = WorkspacePersistenceRevisionOwner()
    let revision = try revisionOwner.performSynchronousTransaction { preparation in
        preparation.commit { preparation.transaction.proposedRevision }
    }
    let generation = WorkspaceContentMountGeneration(
        processGeneration: revisionOwner.processGeneration,
        revision: revision
    )
    guard case .terminal(let terminalState) = pane.content else {
        preconditionFailure("prepared terminal admission requires terminal content")
    }
    let launchDirectory = try #require(pane.metadata.launchDirectory)
    return TerminalActivationAdmission(
        generation: generation,
        descriptor: TerminalActivationDescriptor(
            pane: pane,
            zmxSessionID: terminalState.zmxSessionID,
            provider: .zmx,
            launchConfiguration: TerminalActivationLaunchConfiguration(
                launchDirectory: .stored(launchDirectory),
                executionBackend: .local,
                lifetime: terminalState.lifetime,
                displayTitle: pane.metadata.title
            ),
            visibilityPriority: .activeVisible,
            hostPlacement: .tab(tabID: UUIDv7.generate())
        ),
        attempt: 1
    )
}

@MainActor
private final class CapturingSurfaceManager: WorkspaceSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>

    private(set) var lastConfig: Ghostty.SurfaceConfiguration?
    private(set) var lastMetadata: SurfaceMetadata?
    private(set) var createdPaneIds: [UUID] = []
    private(set) var createdConfigsByPaneId: [UUID: Ghostty.SurfaceConfiguration] = [:]

    init() {
        self.cwdStream = AsyncStream { continuation in
            continuation.onTermination = { _ in }
        }
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { cwdStream }

    func syncFocus(activeSurfaceId _: UUID?) {}

    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        lastConfig = config
        lastMetadata = metadata
        if let paneId = metadata.paneId {
            createdPaneIds.append(paneId)
            createdConfigsByPaneId[paneId] = config
        }
        return .failure(.operationFailed("capture only"))
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        _ = surfaceId
        _ = paneId
        return nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {
        _ = surfaceId
        _ = reason
    }

    func undoClose() -> ManagedSurface? { nil }

    func requeueUndo(_ surfaceId: UUID) {
        _ = surfaceId
    }

    func destroy(_ surfaceId: UUID) {
        _ = surfaceId
    }
}
