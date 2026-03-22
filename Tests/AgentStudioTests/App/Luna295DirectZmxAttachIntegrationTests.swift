import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct Luna295DirectZmxAttachIntegrationTests {
    private let fixtureSessionConfiguration = SessionConfiguration(
        isEnabled: true,
        backgroundRestorePolicy: .existingSessionsOnly,
        zmxPath: "/tmp/fake-zmx",
        zmxDir: "/tmp/fake-zmx-dir",
        healthCheckInterval: 30,
        maxCheckpointAge: 60
    )

    private struct Harness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let runtime: SessionRuntime
        let coordinator: PaneCoordinator
        let surfaceManager: CapturingSurfaceManager
        let tempDir: URL
    }

    private func makeHarness() -> Harness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-luna295-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore(persistor: persistor)
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let surfaceManager = CapturingSurfaceManager()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: surfaceManager,
            runtimeRegistry: .shared
        )
        coordinator.sessionConfig = fixtureSessionConfiguration
        coordinator.terminalRestoreRuntime = TerminalRestoreRuntime(
            sessionConfiguration: fixtureSessionConfiguration,
            liveSessionIdsProvider: { _ in [] }
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

    @Test
    func newZmxPane_uses_directSurfaceCommand_notDeferredShell() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)

        let pane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            provider: .zmx
        )

        _ = harness.coordinator.createView(for: pane, worktree: worktree, repo: repo)

        let config = try #require(harness.surfaceManager.lastConfig)
        #expect(config.startupStrategy.startupCommandForSurface?.contains(" attach ") == true)
        #expect(config.environmentVariables["ZMX_DIR"] == fixtureSessionConfiguration.zmxDir)
    }

    @Test
    func floatingZmxPane_uses_directSurfaceCommand_notDeferredShell() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(
            source: .floating(workingDirectory: harness.tempDir, title: "Floating"),
            provider: .zmx
        )

        _ = harness.coordinator.createViewForContent(pane: pane)

        let config = try #require(harness.surfaceManager.lastConfig)
        #expect(config.startupStrategy.startupCommandForSurface?.contains(" attach ") == true)
        #expect(config.environmentVariables["ZMX_DIR"] == fixtureSessionConfiguration.zmxDir)
    }

    @Test
    func floatingZmxPane_withoutPersistedCwd_stillUsesDirectSurfaceCommand() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .zmx
        )

        _ = harness.coordinator.createViewForContent(pane: pane)

        let config = try #require(harness.surfaceManager.lastConfig)
        #expect(config.startupStrategy.startupCommandForSurface?.contains(" attach ") == true)
        #expect(config.environmentVariables["ZMX_DIR"] == fixtureSessionConfiguration.zmxDir)
    }

    @Test
    func restoreAllViews_skips_hiddenZmxWithoutLiveSession_underDefaultPolicy() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let visiblePane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            provider: .zmx
        )
        let hiddenPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            provider: .zmx
        )

        let visibleTab = Tab(paneId: visiblePane.id, name: "Visible")
        let hiddenTab = Tab(paneId: hiddenPane.id, name: "Hidden")
        harness.store.appendTab(visibleTab)
        harness.store.appendTab(hiddenTab)
        harness.store.setActiveTab(visibleTab.id)

        let customConfig = SessionConfiguration(
            isEnabled: true,
            backgroundRestorePolicy: .existingSessionsOnly,
            zmxPath: "/tmp/fake-zmx",
            zmxDir: "/tmp/fake-zmx-dir",
            healthCheckInterval: 30,
            maxCheckpointAge: 60
        )
        harness.coordinator.terminalRestoreRuntime = TerminalRestoreRuntime(
            sessionConfiguration: customConfig,
            liveSessionIdsProvider: { _ in [] }
        )

        await harness.coordinator.restoreAllViews()

        #expect(harness.surfaceManager.createdPaneIds == [visiblePane.id])
    }

    @Test
    func restoreAllViews_restores_hiddenZmxWithLiveSession_afterVisiblePane() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let visiblePane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            provider: .zmx
        )
        let hiddenPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            provider: .zmx
        )

        let visibleTab = Tab(paneId: visiblePane.id, name: "Visible")
        let hiddenTab = Tab(paneId: hiddenPane.id, name: "Hidden")
        harness.store.appendTab(visibleTab)
        harness.store.appendTab(hiddenTab)
        harness.store.setActiveTab(visibleTab.id)

        let liveSessionId = ZmxBackend.sessionId(
            repoStableKey: repo.stableKey,
            worktreeStableKey: worktree.stableKey,
            paneId: hiddenPane.id
        )
        let customConfig = SessionConfiguration(
            isEnabled: true,
            backgroundRestorePolicy: .existingSessionsOnly,
            zmxPath: "/tmp/fake-zmx",
            zmxDir: "/tmp/fake-zmx-dir",
            healthCheckInterval: 30,
            maxCheckpointAge: 60
        )
        harness.coordinator.terminalRestoreRuntime = TerminalRestoreRuntime(
            sessionConfiguration: customConfig,
            liveSessionIdsProvider: { _ in [liveSessionId] }
        )

        await harness.coordinator.restoreAllViews()

        #expect(harness.surfaceManager.createdPaneIds == [visiblePane.id, hiddenPane.id])
    }

    @Test
    func restoreAllViews_restores_hiddenZmxWithoutLiveSession_whenPolicyIsAllTerminalPanes() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let visiblePane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            provider: .zmx
        )
        let hiddenPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            provider: .zmx
        )

        let visibleTab = Tab(paneId: visiblePane.id, name: "Visible")
        let hiddenTab = Tab(paneId: hiddenPane.id, name: "Hidden")
        harness.store.appendTab(visibleTab)
        harness.store.appendTab(hiddenTab)
        harness.store.setActiveTab(visibleTab.id)

        let customConfig = SessionConfiguration(
            isEnabled: true,
            backgroundRestorePolicy: .allTerminalPanes,
            zmxPath: "/tmp/fake-zmx",
            zmxDir: "/tmp/fake-zmx-dir",
            healthCheckInterval: 30,
            maxCheckpointAge: 60
        )
        harness.coordinator.terminalRestoreRuntime = TerminalRestoreRuntime(
            sessionConfiguration: customConfig,
            liveSessionIdsProvider: { _ in [] }
        )

        await harness.coordinator.restoreAllViews()

        #expect(harness.surfaceManager.createdPaneIds == [visiblePane.id, hiddenPane.id])
    }

    @Test
    func restoreAllViews_skips_hiddenZmxEvenWithLiveSession_whenPolicyIsOff() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let visiblePane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            provider: .zmx
        )
        let hiddenPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            provider: .zmx
        )

        let visibleTab = Tab(paneId: visiblePane.id, name: "Visible")
        let hiddenTab = Tab(paneId: hiddenPane.id, name: "Hidden")
        harness.store.appendTab(visibleTab)
        harness.store.appendTab(hiddenTab)
        harness.store.setActiveTab(visibleTab.id)

        let liveSessionId = ZmxBackend.sessionId(
            repoStableKey: repo.stableKey,
            worktreeStableKey: worktree.stableKey,
            paneId: hiddenPane.id
        )
        let customConfig = SessionConfiguration(
            isEnabled: true,
            backgroundRestorePolicy: .off,
            zmxPath: "/tmp/fake-zmx",
            zmxDir: "/tmp/fake-zmx-dir",
            healthCheckInterval: 30,
            maxCheckpointAge: 60
        )
        harness.coordinator.terminalRestoreRuntime = TerminalRestoreRuntime(
            sessionConfiguration: customConfig,
            liveSessionIdsProvider: { _ in [liveSessionId] }
        )

        await harness.coordinator.restoreAllViews()

        #expect(harness.surfaceManager.createdPaneIds == [visiblePane.id])
    }

    @Test
    func selectTab_createsPreviouslySkippedHiddenPane_onFirstReveal() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let visiblePane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            provider: .zmx
        )
        let hiddenPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            provider: .zmx
        )

        let visibleTab = Tab(paneId: visiblePane.id, name: "Visible")
        let hiddenTab = Tab(paneId: hiddenPane.id, name: "Hidden")
        harness.store.appendTab(visibleTab)
        harness.store.appendTab(hiddenTab)
        harness.store.setActiveTab(visibleTab.id)

        let customConfig = SessionConfiguration(
            isEnabled: true,
            backgroundRestorePolicy: .existingSessionsOnly,
            zmxPath: "/tmp/fake-zmx",
            zmxDir: "/tmp/fake-zmx-dir",
            healthCheckInterval: 30,
            maxCheckpointAge: 60
        )
        harness.coordinator.terminalRestoreRuntime = TerminalRestoreRuntime(
            sessionConfiguration: customConfig,
            liveSessionIdsProvider: { _ in [] }
        )
        harness.coordinator.terminalContainerBoundsProvider = {
            CGRect(x: 0, y: 0, width: 1000, height: 600)
        }

        await harness.coordinator.restoreAllViews()
        #expect(harness.surfaceManager.createdPaneIds == [visiblePane.id])

        harness.coordinator.execute(.selectTab(tabId: hiddenTab.id))

        #expect(harness.surfaceManager.createdPaneIds == [visiblePane.id, hiddenPane.id])
    }

    @Test
    func restoreAllViews_restores_hiddenDrawerZmxWithLiveSession_underNonZmxParent() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let visiblePane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            provider: .zmx
        )
        let hiddenParentPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            provider: .ghostty
        )
        let hiddenDrawerPane = try #require(harness.store.addDrawerPane(to: hiddenParentPane.id))

        let visibleTab = Tab(paneId: visiblePane.id, name: "Visible")
        let hiddenTab = Tab(paneId: hiddenParentPane.id, name: "Hidden")
        harness.store.appendTab(visibleTab)
        harness.store.appendTab(hiddenTab)
        harness.store.setActiveTab(visibleTab.id)

        let liveSessionId = ZmxBackend.drawerSessionId(
            parentPaneId: hiddenParentPane.id,
            drawerPaneId: hiddenDrawerPane.id
        )
        let customConfig = SessionConfiguration(
            isEnabled: true,
            backgroundRestorePolicy: .existingSessionsOnly,
            zmxPath: "/tmp/fake-zmx",
            zmxDir: "/tmp/fake-zmx-dir",
            healthCheckInterval: 30,
            maxCheckpointAge: 60
        )
        harness.coordinator.terminalRestoreRuntime = TerminalRestoreRuntime(
            sessionConfiguration: customConfig,
            liveSessionIdsProvider: { _ in [liveSessionId] }
        )

        await harness.coordinator.restoreAllViews()

        #expect(
            harness.surfaceManager.createdPaneIds == [visiblePane.id, hiddenParentPane.id, hiddenDrawerPane.id]
        )
    }

    @Test
    func restoreAllViews_restores_hiddenDrawerZmxWithLiveSession_evenWhenHiddenParentZmxIsSkipped() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let visiblePane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            provider: .zmx
        )
        let hiddenParentPane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            provider: .zmx
        )
        let hiddenDrawerPane = try #require(harness.store.addDrawerPane(to: hiddenParentPane.id))

        let visibleTab = Tab(paneId: visiblePane.id, name: "Visible")
        let hiddenTab = Tab(paneId: hiddenParentPane.id, name: "Hidden")
        harness.store.appendTab(visibleTab)
        harness.store.appendTab(hiddenTab)
        harness.store.setActiveTab(visibleTab.id)

        let liveSessionId = ZmxBackend.drawerSessionId(
            parentPaneId: hiddenParentPane.id,
            drawerPaneId: hiddenDrawerPane.id
        )
        let customConfig = SessionConfiguration(
            isEnabled: true,
            backgroundRestorePolicy: .existingSessionsOnly,
            zmxPath: "/tmp/fake-zmx",
            zmxDir: "/tmp/fake-zmx-dir",
            healthCheckInterval: 30,
            maxCheckpointAge: 60
        )
        harness.coordinator.terminalRestoreRuntime = TerminalRestoreRuntime(
            sessionConfiguration: customConfig,
            liveSessionIdsProvider: { _ in [liveSessionId] }
        )

        await harness.coordinator.restoreAllViews()

        #expect(harness.surfaceManager.createdPaneIds == [visiblePane.id, hiddenDrawerPane.id])
    }

    @Test
    func restoreAllViews_passesResolvedInitialFrame_toVisiblePane() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let pane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            provider: .zmx
        )

        let tab = Tab(paneId: pane.id, name: "Visible")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        await harness.coordinator.restoreAllViews(
            in: CGRect(x: 0, y: 0, width: 1000, height: 600)
        )

        let config = try #require(harness.surfaceManager.createdConfigsByPaneId[pane.id])
        #expect(config.initialFrame == CGRect(x: 2, y: 2, width: 996, height: 596))
    }

    @Test
    func restoreAllViews_passesResolvedInitialFrame_toExpandedDrawerPane() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir)
        let worktree = try #require(repo.worktrees.first)
        let pane = harness.store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            provider: .zmx
        )
        let drawerPane = try #require(harness.store.addDrawerPane(to: pane.id))

        let tab = Tab(paneId: pane.id, name: "Visible")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        await harness.coordinator.restoreAllViews(
            in: CGRect(x: 0, y: 0, width: 1000, height: 600)
        )

        let config = try #require(harness.surfaceManager.createdConfigsByPaneId[drawerPane.id])
        let frame = try #require(config.initialFrame)
        #expect(frame.width > 0)
        #expect(frame.height > 0)
        #expect(frame.origin.y > 0)
    }
}

@MainActor
private final class CapturingSurfaceManager: PaneCoordinatorSurfaceManaging {
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
