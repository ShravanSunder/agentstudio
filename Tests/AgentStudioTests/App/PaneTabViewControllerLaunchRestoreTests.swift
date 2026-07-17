import AppKit
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerLaunchRestoreTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }
    private struct Harness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let runtime: SessionRuntime
        let coordinator: WorkspaceSurfaceCoordinator
        let executor: WorkspaceActionExecutor
        let appLifecycleStore: AppLifecycleAtom
        let windowLifecycleStore: WindowLifecycleAtom
        let applicationLifecycleMonitor: ApplicationLifecycleMonitor
        let controller: PaneTabViewController
        let surfaceManager: LaunchCapturingSurfaceManager
        let window: NSWindow
        let tempDir: URL
    }

    private func makeHarness() -> Harness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-tab-launch-tests-\(UUID().uuidString)")
        let store = WorkspaceStore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let appLifecycleStore = AppLifecycleAtom()
        let windowLifecycleStore = WindowLifecycleAtom()
        let applicationLifecycleMonitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appLifecycleStore,
            windowLifecycleStore: windowLifecycleStore
        )
        let surfaceManager = LaunchCapturingSurfaceManager()
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: surfaceManager,
            runtimeRegistry: .shared,
            windowLifecycleStore: windowLifecycleStore
        )
        let executor = WorkspaceActionExecutor(coordinator: coordinator, store: store)
        let controller = PaneTabViewController(
            store: store,
            repoCache: RepoCacheAtom(),
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            executor: executor,
            runtimeCommandDispatcher: coordinator,
            tabBarAdapter: TabBarAdapter(store: store, repoCache: RepoCacheAtom()),
            viewRegistry: viewRegistry,
            registersAsCommandHandler: false
        )
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 1200, height: 800),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()

        return Harness(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            coordinator: coordinator,
            executor: executor,
            appLifecycleStore: appLifecycleStore,
            windowLifecycleStore: windowLifecycleStore,
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            controller: controller,
            surfaceManager: surfaceManager,
            window: window,
            tempDir: tempDir
        )
    }

    @Test
    func layout_writesNonEmptyBoundsToWindowLifecycleStore() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        harness.controller.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        harness.controller.view.layoutSubtreeIfNeeded()

        #expect(harness.windowLifecycleStore.terminalContainerBounds.width > 0)
        #expect(harness.windowLifecycleStore.terminalContainerBounds.height > 0)
        #expect(harness.windowLifecycleStore.isReadyForLaunchRestore == false)
    }

    @Test
    func settledLayoutWithRecordedBounds_makesStoreReadyForLaunchRestore() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        harness.controller.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        harness.controller.view.layoutSubtreeIfNeeded()
        harness.applicationLifecycleMonitor.handleLaunchLayoutSettled()

        #expect(harness.windowLifecycleStore.isLaunchLayoutSettled == true)
        #expect(harness.windowLifecycleStore.isReadyForLaunchRestore == true)
    }

    @Test
    func restoreViewsForActiveTabIfNeeded_doesNotCreateViewsBeforeLaunchLayoutSettles() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(
            launchDirectory: harness.tempDir,
            provider: .zmx
        )
        let tab = Tab(paneId: pane.id, name: "Early Restore")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        harness.windowLifecycleStore.recordTerminalContainerBounds(
            CGRect(x: 0, y: 0, width: 512, height: 552)
        )
        #expect(harness.windowLifecycleStore.isReadyForLaunchRestore == false)

        harness.coordinator.restoreViewsForActiveTabIfNeeded()

        #expect(harness.surfaceManager.createdPaneIds.isEmpty)
    }

    @Test
    func settledLayout_defersSurfaceCreationUntilLayoutCallbackUnwinds() async {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(
            launchDirectory: harness.tempDir,
            provider: .zmx
        )
        let tab = Tab(paneId: pane.id, name: "Deferred Restore")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        harness.applicationLifecycleMonitor.handleLaunchLayoutSettled()
        harness.controller.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        harness.controller.view.layoutSubtreeIfNeeded()

        #expect(harness.surfaceManager.createdPaneIds.isEmpty)

        await Task.yield()

        #expect(harness.surfaceManager.createdPaneIds == [pane.id])
    }

    @Test
    func initialLaunchRestore_attemptsVisibleZmxSurfaceCreation() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(
            launchDirectory: harness.tempDir,
            provider: .zmx
        )
        let tab = Tab(paneId: pane.id, name: "Initial Placeholder")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let frame = NSRect(x: 8, y: 8, width: 1184, height: 784)
        try await mountPreparedContent(
            coordinator: harness.coordinator,
            viewRegistry: harness.viewRegistry,
            terminalDescriptors: [
                try preparedTerminalDescriptor(
                    pane: pane,
                    visibilityPriority: .activeVisible,
                    hostPlacement: .tab(tabID: tab.id)
                )
            ],
            nonterminalDescriptors: [],
            initialFramesByPaneID: [PaneId(existingUUID: pane.id): frame]
        )

        let placeholder = try #require(harness.viewRegistry.terminalStatusPlaceholderView(for: pane.id))
        #expect(placeholder.mode == .failedToStart)
        #expect(placeholder.shouldRetryCreationWhenBoundsChange == false)
        #expect(harness.surfaceManager.createdPaneIds == [pane.id, pane.id])
        #expect(harness.viewRegistry.isInitialRestorePending == false)
    }

    @Test
    func initialLaunchRestore_mountsNonTerminalVisiblePane() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(
            content: .webview(
                WebviewState(
                    url: try #require(URL(string: "https://example.com/initial-webview")),
                    showNavigation: true
                )
            ),
            metadata: PaneMetadata(
                title: "Initial Webview"
            )
        )
        let tab = Tab(paneId: pane.id, name: "Initial Webview")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        try await mountPreparedContent(
            coordinator: harness.coordinator,
            viewRegistry: harness.viewRegistry,
            terminalDescriptors: [],
            nonterminalDescriptors: [
                NonterminalContentMountDescriptor(
                    content: .webview(pane),
                    visibilityPriority: .activeVisible,
                    hostPlacement: .tab(tabID: tab.id)
                )
            ],
            initialFramesByPaneID: [:]
        )

        #expect(harness.viewRegistry.webviewView(for: pane.id) != nil)
        #expect(harness.surfaceManager.createdPaneIds.isEmpty)
        #expect(harness.viewRegistry.isInitialRestorePending == false)
    }

    @Test
    func preparedContentOwner_initialRestoreAttemptsZmxTerminalSurfaceCreation() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(
            launchDirectory: harness.tempDir,
            provider: .zmx
        )
        let tab = Tab(paneId: pane.id, name: "Initial Full Restore")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        try await mountPreparedContent(
            coordinator: harness.coordinator,
            viewRegistry: harness.viewRegistry,
            terminalDescriptors: [
                try preparedTerminalDescriptor(
                    pane: pane,
                    visibilityPriority: .activeVisible,
                    hostPlacement: .tab(tabID: tab.id)
                )
            ],
            nonterminalDescriptors: [],
            initialFramesByPaneID: [
                PaneId(existingUUID: pane.id): CGRect(x: 8, y: 8, width: 1184, height: 784)
            ]
        )

        let placeholder = try #require(harness.viewRegistry.terminalStatusPlaceholderView(for: pane.id))
        #expect(placeholder.mode == .failedToStart)
        #expect(placeholder.shouldRetryCreationWhenBoundsChange == false)
        #expect(harness.surfaceManager.createdPaneIds == [pane.id, pane.id])
        #expect(harness.viewRegistry.isInitialRestorePending == false)
    }

    @Test
    func terminalRestoreDoesNotExposeManualPausedStartupState() throws {
        let sourcePaths = [
            "Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ActiveTabRestore.swift",
            "Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ViewLifecycle.swift",
            "Sources/AgentStudio/Features/Terminal/Hosting/TerminalStatusPlaceholderView.swift",
            "Sources/AgentStudio/Features/Terminal/Views/SurfaceErrorOverlay.swift",
        ]

        for sourcePath in sourcePaths {
            let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appending(path: sourcePath)
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            #expect(!source.contains("restorationPaused"))
            #expect(!source.contains("Terminal Restore Paused"))
            #expect(!source.contains("Start Terminal"))
        }
    }

    @Test
    func preparedContentOwner_usesFrozenLifecycleStoreBounds() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(
            launchDirectory: harness.tempDir,
            provider: .zmx
        )
        let tab = Tab(paneId: pane.id, name: "Launch Restore")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        let containerWidth: CGFloat = 1000
        let containerHeight: CGFloat = 600
        harness.windowLifecycleStore.recordTerminalContainerBounds(
            CGRect(x: 0, y: 0, width: containerWidth, height: containerHeight)
        )

        let resolvedFramesByTabID = harness.coordinator.resolveInitialFramesByTabId(
            in: harness.windowLifecycleStore.terminalContainerBounds
        )
        let initialFrame = try #require(resolvedFramesByTabID[tab.id]?[pane.id])
        try await mountPreparedContent(
            coordinator: harness.coordinator,
            viewRegistry: harness.viewRegistry,
            terminalDescriptors: [
                try preparedTerminalDescriptor(
                    pane: pane,
                    visibilityPriority: .activeVisible,
                    hostPlacement: .tab(tabID: tab.id)
                )
            ],
            nonterminalDescriptors: [],
            initialFramesByPaneID: [PaneId(existingUUID: pane.id): initialFrame]
        )

        let config = try #require(harness.surfaceManager.createdConfigsByPaneId[pane.id])
        let gap = AppStyles.General.Layout.paneGap
        #expect(
            config.initialFrame
                == CGRect(x: gap, y: gap, width: containerWidth - gap * 2, height: containerHeight - gap * 2))
    }

    @Test
    func appLifecycleChanges_doNotReplaceActiveTabHost() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(
            launchDirectory: harness.tempDir,
            provider: .zmx
        )
        let tab = Tab(paneId: pane.id, name: "Lifecycle")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.controller.view.layoutSubtreeIfNeeded()

        let originalTabHost = try #require(harness.controller.tabHostViewForTesting(tabId: tab.id))
        #expect(harness.controller.appLifecycleStoreForTesting === harness.appLifecycleStore)

        harness.applicationLifecycleMonitor.handleApplicationDidBecomeActive()
        harness.controller.view.layoutSubtreeIfNeeded()

        let updatedTabHost = try #require(harness.controller.tabHostViewForTesting(tabId: tab.id))
        #expect(updatedTabHost === originalTabHost)

        harness.applicationLifecycleMonitor.handleApplicationDidResignActive()
        harness.controller.view.layoutSubtreeIfNeeded()

        let tabHostAfterResign = try #require(harness.controller.tabHostViewForTesting(tabId: tab.id))
        #expect(tabHostAfterResign === originalTabHost)
    }
}

@MainActor
private func mountPreparedContent(
    coordinator: WorkspaceSurfaceCoordinator,
    viewRegistry: ViewRegistry,
    terminalDescriptors: [TerminalActivationDescriptor],
    nonterminalDescriptors: [NonterminalContentMountDescriptor],
    initialFramesByPaneID: [PaneId: NSRect]
) async throws {
    let generation = try preparedContentGeneration()
    let cohort = WorkspacePreparedContentMountCohort(
        generation: generation,
        terminalActivationInput: TerminalActivationInput(entries: terminalDescriptors),
        nonterminalContentMountInput: NonterminalContentMountInput(entries: nonterminalDescriptors)
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

@MainActor
private func preparedContentGeneration() throws -> WorkspaceContentMountGeneration {
    WorkspaceContentMountGeneration()
}

private func preparedTerminalDescriptor(
    pane: Pane,
    visibilityPriority: TerminalActivationVisibilityPriority,
    hostPlacement: TerminalHostPlacementIdentity
) throws -> TerminalActivationDescriptor {
    guard case .terminal = pane.content else {
        preconditionFailure("prepared terminal descriptor requires terminal content")
    }
    return TerminalActivationDescriptor(
        pane: pane,
        visibilityPriority: visibilityPriority,
        hostPlacement: hostPlacement
    )
}

@MainActor
private final class LaunchCapturingSurfaceManager: WorkspaceSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>

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
