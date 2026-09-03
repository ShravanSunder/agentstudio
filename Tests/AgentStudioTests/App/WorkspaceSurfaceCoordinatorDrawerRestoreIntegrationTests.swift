import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct WorkspaceDrawerRestoreIntegrationTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    private let fixtureSessionConfiguration = SessionConfiguration(
        isEnabled: true,
        zmxPath: "/tmp/fake-zmx",
        zmxDir: "/tmp/fake-zmx-dir",
        healthCheckInterval: 30,
        maxCheckpointAge: 60
    )

    private let trustedBounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

    private struct Harness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let runtime: SessionRuntime
        let coordinator: WorkspaceSurfaceCoordinator
        let windowLifecycleStore: WindowLifecycleAtom
        let surfaceManager: DrawerRestoreCapturingSurfaceManager
        let tempDir: URL
    }

    private struct StartupTabSwitchHarness {
        let harness: Harness
        let startupTabID: UUID
        let selectedTabID: UUID
    }

    private struct RestoredDrawerHarness {
        let sqliteBackend: WorkspaceSQLiteStoreBackend
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let coordinator: WorkspaceSurfaceCoordinator
        let windowLifecycleStore: WindowLifecycleAtom
        let surfaceManager: DrawerRestoreCapturingSurfaceManager
        let tempDir: URL
        let parentPaneID: UUID
        let firstDrawerPaneID: UUID
        let secondDrawerPaneID: UUID
        let tabID: UUID
    }

    private func makeHarness() -> Harness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-drawer-restore-tests-\(UUID().uuidString)")
        let store = WorkspaceStore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let windowLifecycleStore = WindowLifecycleAtom()
        let surfaceManager = DrawerRestoreCapturingSurfaceManager()
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: surfaceManager,
            runtimeRegistry: .shared,
            windowLifecycleStore: windowLifecycleStore,
            bridgePaneAttendance: BridgePaneAttendanceAtom()
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

    private func makeStartupTabSwitchOwner(
        harness: Harness,
        panes: [Pane],
        placements: [TerminalHostPlacementIdentity]
    ) throws -> WorkspacePreparedContentMountCoordinator {
        precondition(panes.count == placements.count)
        let generation = WorkspaceContentMountGeneration()
        let descriptors = try zip(panes, placements).enumerated().map { index, entry in
            try preparedDrawerTerminalDescriptor(
                pane: entry.0,
                visibilityPriority: index == 0 ? .activeVisible : .hidden,
                hostPlacement: entry.1
            )
        }
        return WorkspacePreparedContentMountCoordinator(
            cohort: WorkspacePreparedContentMountCohort(
                generation: generation,
                terminalActivationInput: TerminalActivationInput(entries: descriptors),
                nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
            ),
            viewRegistry: harness.viewRegistry,
            terminalAdmissionPort: PreparedTerminalMountAdmissionPort(
                generation: generation,
                initialFramesByPaneID: [:],
                viewRegistry: harness.viewRegistry,
                mountHandler: harness.coordinator
            ),
            nonterminalAdmissionPort: PreparedNonterminalMountAdmissionPort(
                generation: generation,
                coordinator: harness.coordinator
            )
        )
    }

    private func makeStartupTabSwitchHarness() throws -> StartupTabSwitchHarness {
        let harness = makeHarness()
        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let startupPane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let selectedPane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let selectedSiblingPane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let startupTab = Tab(paneId: startupPane.id, name: "Startup")
        let selectedTab = Tab(paneId: selectedPane.id, name: "Selected during startup")
        harness.store.appendTab(startupTab)
        harness.store.appendTab(selectedTab)
        harness.store.setActiveTab(startupTab.id)
        _ = harness.store.insertPane(
            selectedSiblingPane.id,
            inTab: selectedTab.id,
            at: selectedPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        harness.store.setActivePane(selectedPane.id, inTab: selectedTab.id)
        let firstDrawerPane = try #require(harness.store.addDrawerPane(to: selectedPane.id))
        let secondDrawerPane = try #require(harness.store.addDrawerPane(to: selectedPane.id))
        harness.store.setActiveDrawerPane(secondDrawerPane.id, in: selectedPane.id)
        if harness.store.pane(selectedPane.id)?.drawer?.isExpanded == false {
            harness.store.toggleDrawer(for: selectedPane.id)
        }
        let acceptedSelectedPane = try #require(harness.store.pane(selectedPane.id))
        let acceptedFirstDrawerPane = try #require(harness.store.pane(firstDrawerPane.id))
        let acceptedSecondDrawerPane = try #require(harness.store.pane(secondDrawerPane.id))
        let selectedDrawerID = try #require(acceptedSelectedPane.drawer?.drawerId)
        let owner = try makeStartupTabSwitchOwner(
            harness: harness,
            panes: [
                startupPane,
                acceptedSelectedPane,
                selectedSiblingPane,
                acceptedFirstDrawerPane,
                acceptedSecondDrawerPane,
            ],
            placements: [
                .tab(tabID: startupTab.id),
                .tab(tabID: selectedTab.id),
                .tab(tabID: selectedTab.id),
                .drawer(
                    tabID: selectedTab.id,
                    parentPaneID: PaneId(existingUUID: selectedPane.id),
                    drawerID: selectedDrawerID
                ),
                .drawer(
                    tabID: selectedTab.id,
                    parentPaneID: PaneId(existingUUID: selectedPane.id),
                    drawerID: selectedDrawerID
                ),
            ]
        )
        harness.viewRegistry.beginInitialRestore()
        harness.coordinator.preparedContentVisibilitySignalHandler = { paneIDs in
            owner.handleVisibilitySignals(for: paneIDs)
        }
        harness.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        harness.windowLifecycleStore.recordLaunchLayoutSettled()
        return StartupTabSwitchHarness(
            harness: harness,
            startupTabID: startupTab.id,
            selectedTabID: selectedTab.id
        )
    }

    @Test
    func toggleDrawer_retriesDrawerPaneAfterPreparedActivationLackedTrustedFrame() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let parentPane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: parentPane.id, name: "Collapsed Drawer")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        let installedDrawerID = try #require(harness.store.pane(parentPane.id)?.drawer?.drawerId)
        harness.store.tabArrangementAtom.addDrawerPaneView(
            drawerId: installedDrawerID,
            parentPaneId: parentPane.id,
            drawerPaneId: drawerPane.id,
            inTab: tab.id
        )
        harness.store.toggleDrawer(for: parentPane.id)
        #expect(harness.store.pane(parentPane.id)?.drawer?.isExpanded == false)
        let drawerViewBeforePreparedMount = try #require(harness.store.drawerView(forParent: parentPane.id))
        harness.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)

        let acceptedParentPane = try #require(harness.store.pane(parentPane.id))
        let acceptedDrawerPane = try #require(harness.store.pane(drawerPane.id))
        let drawerID = try #require(acceptedParentPane.drawer?.drawerId)
        try await mountPreparedDrawerCohort(
            coordinator: harness.coordinator,
            viewRegistry: harness.viewRegistry,
            entries: [
                (acceptedParentPane, .activeVisible, .tab(tabID: tab.id)),
                (
                    acceptedDrawerPane,
                    .hidden,
                    .drawer(
                        tabID: tab.id,
                        parentPaneID: PaneId(existingUUID: parentPane.id),
                        drawerID: drawerID
                    )
                ),
            ],
            trustedBounds: trustedBounds
        )
        #expect(harness.surfaceManager.createdPaneIds == [parentPane.id, parentPane.id])
        #expect(harness.viewRegistry.terminalStatusPlaceholderView(for: drawerPane.id) == nil)
        #expect(harness.store.drawerView(forParent: parentPane.id) == drawerViewBeforePreparedMount)
        let creationAttemptsBeforeToggle = harness.surfaceManager.createdPaneIds.count

        harness.coordinator.execute(.toggleDrawer(paneId: parentPane.id))

        #expect(harness.store.pane(parentPane.id)?.drawer?.isExpanded == true)
        #expect(harness.surfaceManager.createdPaneIds.count == creationAttemptsBeforeToggle + 1)
        #expect(harness.surfaceManager.createdPaneIds.last == drawerPane.id)
        let config = try #require(harness.surfaceManager.createdConfigsByPaneId[drawerPane.id])
        #expect(config.initialFrame != nil)
    }

    @Test("opening a deferred drawer restores every visible arranged child")
    func toggleDrawer_restoresEveryVisibleArrangedChild() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let parentPane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: parentPane.id, name: "Deferred multi-pane drawer")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let firstDrawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        let secondDrawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        harness.store.setActiveDrawerPane(secondDrawerPane.id, in: parentPane.id)
        if harness.store.pane(parentPane.id)?.drawer?.isExpanded == true {
            harness.store.toggleDrawer(for: parentPane.id)
        }
        harness.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        harness.windowLifecycleStore.recordLaunchLayoutSettled()

        harness.coordinator.execute(.toggleDrawer(paneId: parentPane.id))

        #expect(harness.store.pane(parentPane.id)?.drawer?.isExpanded == true)
        #expect(
            Set(harness.surfaceManager.createdPaneIds)
                == Set([
                    firstDrawerPane.id,
                    secondDrawerPane.id,
                ])
        )
        #expect(harness.surfaceManager.createdPaneIds.count == 2)
    }

    @Test("tab selection during initial restore does not duplicate prepared terminal mounts")
    func selectTabDuringInitialRestore_doesNotDuplicatePreparedTerminalMounts() throws {
        // Arrange
        let context = try makeStartupTabSwitchHarness()
        let harness = context.harness
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        // Act
        harness.coordinator.execute(.selectTab(tabId: context.selectedTabID))

        // Assert
        #expect(harness.viewRegistry.isInitialRestorePending)
        #expect(harness.surfaceManager.createdPaneIds.isEmpty)
        #expect(harness.store.tabLayoutAtom.activeTab?.id == context.selectedTabID)

        harness.coordinator.execute(.selectTab(tabId: context.startupTabID))

        #expect(harness.viewRegistry.isInitialRestorePending)
        #expect(harness.surfaceManager.createdPaneIds.isEmpty)
    }

    @Test
    func boundsSettlementSignalsPreparingForegroundDrawerWithoutArrangementMutation() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let parentPane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: parentPane.id, name: "Bounds repair")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        harness.store.setActiveDrawerPane(drawerPane.id, in: parentPane.id)
        if harness.store.pane(parentPane.id)?.drawer?.isExpanded == false {
            harness.store.toggleDrawer(for: parentPane.id)
        }
        harness.viewRegistry.beginInitialRestore()
        var signalledPaneIDs: [PaneId] = []
        harness.coordinator.preparedContentVisibilitySignalHandler = { paneIDs in
            signalledPaneIDs = paneIDs
            return Set(paneIDs)
        }

        harness.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        harness.windowLifecycleStore.recordLaunchLayoutSettled()
        harness.coordinator.restoreViewsForActiveTabIfNeeded()

        #expect(signalledPaneIDs == [parentPane.id, drawerPane.id].map(PaneId.init(existingUUID:)))
        #expect(harness.store.drawerView(forParent: parentPane.id)?.activeChildId == drawerPane.id)
    }

    @Test
    func expandDrawerPane_retriesMinimizedPaneAfterPreparedActivationFailure() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let parentPane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: parentPane.id, name: "Minimized Drawer")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let visibleDrawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        let minimizedDrawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        harness.coordinator.execute(
            .minimizeDrawerPane(parentPaneId: parentPane.id, drawerPaneId: minimizedDrawerPane.id)
        )
        let drawerViewBeforePreparedMount = try #require(harness.store.drawerView(forParent: parentPane.id))

        let acceptedParentPane = try #require(harness.store.pane(parentPane.id))
        let acceptedVisibleDrawerPane = try #require(harness.store.pane(visibleDrawerPane.id))
        let acceptedMinimizedDrawerPane = try #require(harness.store.pane(minimizedDrawerPane.id))
        let drawerID = try #require(acceptedParentPane.drawer?.drawerId)
        try await mountPreparedDrawerCohort(
            coordinator: harness.coordinator,
            viewRegistry: harness.viewRegistry,
            entries: [
                (acceptedParentPane, .activeVisible, .tab(tabID: tab.id)),
                (
                    acceptedVisibleDrawerPane,
                    .activeVisible,
                    .drawer(
                        tabID: tab.id,
                        parentPaneID: PaneId(existingUUID: parentPane.id),
                        drawerID: drawerID
                    )
                ),
                (
                    acceptedMinimizedDrawerPane,
                    .hidden,
                    .drawer(
                        tabID: tab.id,
                        parentPaneID: PaneId(existingUUID: parentPane.id),
                        drawerID: drawerID
                    )
                ),
            ],
            trustedBounds: trustedBounds
        )
        #expect(harness.surfaceManager.createdPaneIds.filter { $0 == parentPane.id }.count == 2)
        #expect(harness.surfaceManager.createdPaneIds.filter { $0 == visibleDrawerPane.id }.count == 2)
        #expect(harness.surfaceManager.createdPaneIds.filter { $0 == minimizedDrawerPane.id }.count == 2)
        #expect(
            harness.viewRegistry.terminalStatusPlaceholderView(for: minimizedDrawerPane.id)?.mode
                == .failedToStart
        )
        #expect(harness.store.drawerView(forParent: parentPane.id) == drawerViewBeforePreparedMount)
        harness.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        let creationAttemptsBeforeExpansion = harness.surfaceManager.createdPaneIds.count

        harness.coordinator.execute(
            .expandDrawerPane(parentPaneId: parentPane.id, drawerPaneId: minimizedDrawerPane.id)
        )

        #expect(harness.store.drawerView(forParent: parentPane.id)?.activeChildId == minimizedDrawerPane.id)
        #expect(harness.surfaceManager.createdPaneIds.count == creationAttemptsBeforeExpansion + 1)
        #expect(harness.surfaceManager.createdPaneIds.last == minimizedDrawerPane.id)
        let config = try #require(harness.surfaceManager.createdConfigsByPaneId[minimizedDrawerPane.id])
        #expect(config.initialFrame != nil)
    }

    @Test
    func setActiveDrawerPane_restoresPreviouslySkippedDrawerPane_whenSelectionMakesItVisible() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let parentPane = harness.store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: parentPane.id, name: "Selectable Drawer")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let firstDrawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        let secondDrawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        harness.store.setActiveDrawerPane(firstDrawerPane.id, in: parentPane.id)

        harness.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        let creationAttemptsBeforeSelection = harness.surfaceManager.createdPaneIds.count

        harness.coordinator.execute(
            .setActiveDrawerPane(parentPaneId: parentPane.id, drawerPaneId: secondDrawerPane.id)
        )

        #expect(harness.store.drawerView(forParent: parentPane.id)?.activeChildId == secondDrawerPane.id)
        #expect(harness.surfaceManager.createdPaneIds.count == creationAttemptsBeforeSelection + 1)
        #expect(harness.surfaceManager.createdPaneIds.last == secondDrawerPane.id)
        let config = try #require(harness.surfaceManager.createdConfigsByPaneId[secondDrawerPane.id])
        #expect(config.initialFrame != nil)
    }

    @Test
    func freshStoreReactivationMountsForegroundDrawerFamilyExactlyOnce() async throws {
        let harness = try await makeRestoredDrawerHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        #expect(harness.store.mutationCoordinator.backgroundPane(harness.parentPaneID))
        #expect((await harness.store.flushAsync()).succeeded)

        let restoredStore = WorkspaceStore(
            sqliteDatastore: try await preparedWorkspaceSQLiteDatastore(from: harness.sqliteBackend)
        )
        _ = await restoredStore.loadCanonicalComposition()
        let restoredViewRegistry = ViewRegistry()
        let restoredSurfaceManager = DrawerRestoreCapturingSurfaceManager()
        let restoredWindowLifecycleStore = WindowLifecycleAtom()
        let restoredCoordinator = WorkspaceSurfaceCoordinator(
            store: restoredStore,
            viewRegistry: restoredViewRegistry,
            runtime: SessionRuntime(store: restoredStore),
            surfaceManager: restoredSurfaceManager,
            runtimeRegistry: RuntimeRegistry(),
            windowLifecycleStore: restoredWindowLifecycleStore,
            bridgePaneAttendance: BridgePaneAttendanceAtom()
        )
        restoredCoordinator.sessionConfig = fixtureSessionConfiguration
        restoredCoordinator.terminalRestoreRuntime = TerminalRestoreRuntime(
            sessionConfiguration: fixtureSessionConfiguration
        )
        restoredWindowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        restoredWindowLifecycleStore.recordLaunchLayoutSettled()

        restoredCoordinator.execute(
            .reactivatePane(
                paneId: harness.parentPaneID,
                targetTabId: harness.tabID,
                targetPaneId: harness.parentPaneID,
                direction: .right
            )
        )

        #expect(
            restoredSurfaceManager.createdPaneIds == [
                harness.parentPaneID,
                harness.firstDrawerPaneID,
            ]
        )
        #expect(!restoredSurfaceManager.createdPaneIds.contains(harness.secondDrawerPaneID))
    }

    @Test
    func closeUndoFreshRestoreThenSelectDrawerPane_retriesPreparedFailure() async throws {
        let harness = try await makeRestoredDrawerHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let restoredParentPane = try #require(harness.store.pane(harness.parentPaneID))
        let restoredFirstDrawerPane = try #require(harness.store.pane(harness.firstDrawerPaneID))
        let restoredSecondDrawerPane = try #require(harness.store.pane(harness.secondDrawerPaneID))
        let restoredDrawerID = try #require(restoredParentPane.drawer?.drawerId)
        let drawerViewBeforePreparedMount = try #require(
            harness.store.drawerView(forParent: harness.parentPaneID)
        )
        try await mountPreparedDrawerCohort(
            coordinator: harness.coordinator,
            viewRegistry: harness.viewRegistry,
            entries: [
                (restoredParentPane, .activeVisible, .tab(tabID: harness.tabID)),
                (
                    restoredFirstDrawerPane,
                    .activeVisible,
                    .drawer(
                        tabID: harness.tabID,
                        parentPaneID: PaneId(existingUUID: harness.parentPaneID),
                        drawerID: restoredDrawerID
                    )
                ),
                (
                    restoredSecondDrawerPane,
                    .hidden,
                    .drawer(
                        tabID: harness.tabID,
                        parentPaneID: PaneId(existingUUID: harness.parentPaneID),
                        drawerID: restoredDrawerID
                    )
                ),
            ],
            trustedBounds: trustedBounds
        )
        #expect(harness.surfaceManager.createdPaneIds.filter { $0 == harness.parentPaneID }.count == 2)
        #expect(harness.surfaceManager.createdPaneIds.filter { $0 == harness.firstDrawerPaneID }.count == 2)
        #expect(harness.surfaceManager.createdPaneIds.filter { $0 == harness.secondDrawerPaneID }.count == 2)
        #expect(
            harness.viewRegistry.terminalStatusPlaceholderView(for: harness.secondDrawerPaneID)?.mode
                == .failedToStart
        )
        #expect(harness.store.drawerView(forParent: harness.parentPaneID) == drawerViewBeforePreparedMount)
        harness.windowLifecycleStore.recordTerminalContainerBounds(trustedBounds)
        let creationAttemptsBeforeExpansion = harness.surfaceManager.createdPaneIds.count

        harness.coordinator.execute(
            .expandDrawerPane(
                parentPaneId: harness.parentPaneID,
                drawerPaneId: harness.secondDrawerPaneID
            )
        )

        let restoredTab = try #require(harness.store.tab(harness.tabID))
        let restoredDrawerView = try #require(harness.store.drawerView(forParent: harness.parentPaneID))
        #expect(
            restoredTab.allPaneIds == [
                harness.parentPaneID,
                harness.firstDrawerPaneID,
                harness.secondDrawerPaneID,
            ]
        )
        #expect(restoredDrawerView.activeChildId == harness.secondDrawerPaneID)
        #expect(harness.surfaceManager.createdPaneIds.count == creationAttemptsBeforeExpansion + 1)
        #expect(harness.surfaceManager.createdPaneIds.last == harness.secondDrawerPaneID)
    }

    private func makeRestoredDrawerHarness() async throws -> RestoredDrawerHarness {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-terminal-restore-composed-\(UUID().uuidString)")
        let identityAtom = WorkspaceIdentityAtom(
            workspaceId: workspaceId,
            workspaceName: "Composed Drawer Restore",
            createdAt: Date(timeIntervalSince1970: 1_700_000_089)
        )
        let sqliteDatastore = try await preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        try fixture.coreRepository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: identityAtom.workspaceName,
                createdAt: identityAtom.createdAt,
                updatedAt: identityAtom.createdAt
            )
        )
        let store = WorkspaceStore(
            identityAtom: identityAtom,
            sqliteDatastore: sqliteDatastore
        )
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let windowLifecycleStore = WindowLifecycleAtom()
        let surfaceManager = DrawerRestoreCapturingSurfaceManager()
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: surfaceManager,
            runtimeRegistry: RuntimeRegistry(),
            windowLifecycleStore: windowLifecycleStore,
            bridgePaneAttendance: BridgePaneAttendanceAtom()
        )
        coordinator.sessionConfig = fixtureSessionConfiguration
        coordinator.terminalRestoreRuntime = TerminalRestoreRuntime(
            sessionConfiguration: fixtureSessionConfiguration
        )
        let repo = store.addRepo(at: tempDir)
        let worktree = try #require(repo.worktrees.first)
        let topologyStore = RepositoryTopologyStore(
            atom: store.repositoryTopologyAtom,
            sqliteDatastore: sqliteDatastore
        )
        try await topologyStore.flushAsync()
        let parentPane = store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: parentPane.id, name: "Composed Drawer")
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        let firstDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let secondDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        store.setActiveDrawerPane(firstDrawerPane.id, in: parentPane.id)
        coordinator.execute(
            .minimizeDrawerPane(parentPaneId: parentPane.id, drawerPaneId: secondDrawerPane.id)
        )

        coordinator.execute(.closeTab(tabId: tab.id))
        coordinator.undoCloseTab()
        let flushOutcome = await store.flushAsync()

        #expect(flushOutcome.succeeded)
        let restoredStore = WorkspaceStore(
            sqliteDatastore: try await preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        )
        _ = await restoredStore.loadCanonicalComposition()
        let restoredViewRegistry = ViewRegistry()
        let restoredRuntime = SessionRuntime(store: restoredStore)
        let restoredWindowLifecycleStore = WindowLifecycleAtom()
        let restoredSurfaceManager = DrawerRestoreCapturingSurfaceManager()
        let restoredCoordinator = WorkspaceSurfaceCoordinator(
            store: restoredStore,
            viewRegistry: restoredViewRegistry,
            runtime: restoredRuntime,
            surfaceManager: restoredSurfaceManager,
            runtimeRegistry: RuntimeRegistry(),
            windowLifecycleStore: restoredWindowLifecycleStore,
            bridgePaneAttendance: BridgePaneAttendanceAtom()
        )
        restoredCoordinator.sessionConfig = fixtureSessionConfiguration
        restoredCoordinator.terminalRestoreRuntime = TerminalRestoreRuntime(
            sessionConfiguration: fixtureSessionConfiguration
        )

        return RestoredDrawerHarness(
            sqliteBackend: fixture.backend,
            store: restoredStore,
            viewRegistry: restoredViewRegistry,
            coordinator: restoredCoordinator,
            windowLifecycleStore: restoredWindowLifecycleStore,
            surfaceManager: restoredSurfaceManager,
            tempDir: tempDir,
            parentPaneID: parentPane.id,
            firstDrawerPaneID: firstDrawerPane.id,
            secondDrawerPaneID: secondDrawerPane.id,
            tabID: tab.id
        )
    }
}

@MainActor
private func mountPreparedDrawerCohort(
    coordinator: WorkspaceSurfaceCoordinator,
    viewRegistry: ViewRegistry,
    entries: [(Pane, TerminalActivationVisibilityPriority, TerminalHostPlacementIdentity)],
    trustedBounds: CGRect
) async throws {
    let generation = try preparedDrawerCohortGeneration()
    let descriptors = try entries.map { pane, priority, placement in
        try preparedDrawerTerminalDescriptor(
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
private func preparedDrawerCohortGeneration() throws -> WorkspaceContentMountGeneration {
    WorkspaceContentMountGeneration()
}

private func preparedDrawerTerminalDescriptor(
    pane: Pane,
    visibilityPriority: TerminalActivationVisibilityPriority,
    hostPlacement: TerminalHostPlacementIdentity
) throws -> TerminalActivationDescriptor {
    guard case .terminal = pane.content else {
        preconditionFailure("prepared drawer cohort requires terminal content")
    }
    return TerminalActivationDescriptor(
        pane: pane,
        visibilityPriority: visibilityPriority,
        hostPlacement: hostPlacement
    )
}

@MainActor
private final class DrawerRestoreCapturingSurfaceManager: WorkspaceSurfaceManaging {
    private(set) var createdPaneIds: [UUID] = []
    private(set) var createdConfigsByPaneId: [UUID: Ghostty.SurfaceConfiguration] = [:]

    func syncFocus(activeSurfaceId _: UUID?) {}

    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
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
