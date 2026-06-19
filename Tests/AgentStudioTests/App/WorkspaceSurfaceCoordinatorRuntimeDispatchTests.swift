import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceSurfaceCoordinatorRuntimeDispatchTests {
    @Test("coordinator injects its runtime registry into Ghostty action routing")
    func coordinatorInjectsGhosttyRuntimeRegistry() {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-registry-injection-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let mockSurfaceManager = MockWorkspaceSurfaceCoordinatorSurfaceManager()
        let runtimeRegistry = RuntimeRegistry()
        _ = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: runtimeRegistry
        )

        #expect(ObjectIdentifier(Ghostty.App.runtimeRegistryForActionRouting) == ObjectIdentifier(runtimeRegistry))

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("dispatchRuntimeCommand resolves pane target centrally")
    func dispatchUsesResolver() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let mockSurfaceManager = MockWorkspaceSurfaceCoordinatorSurfaceManager()
        let runtimeRegistry = RuntimeRegistry()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: runtimeRegistry
        )

        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/runtime-dispatch")!)),
            metadata: PaneMetadata(title: "Runtime")
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let fakeRuntime = FakePaneRuntime(paneId: PaneId(uuid: pane.id))
        coordinator.registerRuntime(fakeRuntime)

        let result = await coordinator.dispatchRuntimeCommand(.activate, target: .activePane)
        #expect(result == .success(commandId: fakeRuntime.receivedCommandIds.first!))
        #expect(fakeRuntime.receivedCommands.count == 1)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("dispatchRuntimeCommand fails for unresolved target")
    func dispatchFailsForMissingTarget() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-missing-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let mockSurfaceManager = MockWorkspaceSurfaceCoordinatorSurfaceManager()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )

        let result = await coordinator.dispatchRuntimeCommand(.activate, target: .activePane)
        #expect(result == .failure(.invalidPayload(description: "Unable to resolve pane target")))

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("dispatchRuntimeCommand rejects dispatch when runtime lifecycle is not ready")
    func dispatchFailsWhenRuntimeNotReady() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-not-ready-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let mockSurfaceManager = MockWorkspaceSurfaceCoordinatorSurfaceManager()
        let runtimeRegistry = RuntimeRegistry()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: runtimeRegistry
        )

        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/runtime-not-ready")!)),
            metadata: PaneMetadata(title: "Runtime")
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let fakeRuntime = FakePaneRuntime(paneId: PaneId(uuid: pane.id))
        fakeRuntime.lifecycle = .created
        coordinator.registerRuntime(fakeRuntime)

        let result = await coordinator.dispatchRuntimeCommand(.activate, target: .activePane)
        #expect(result == .failure(.runtimeNotReady(lifecycle: .created)))
        #expect(fakeRuntime.receivedCommands.isEmpty)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("dispatchRuntimeCommand surfaces runtime capability failures")
    func dispatchFailsWhenCapabilityMissing() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-capability-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let mockSurfaceManager = MockWorkspaceSurfaceCoordinatorSurfaceManager()
        let runtimeRegistry = RuntimeRegistry()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: runtimeRegistry
        )

        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/runtime-capability")!)),
            metadata: PaneMetadata(title: "Runtime")
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let fakeRuntime = FakePaneRuntime(paneId: PaneId(uuid: pane.id))
        fakeRuntime.capabilities = [.input]
        coordinator.registerRuntime(fakeRuntime)

        let result = await coordinator.dispatchRuntimeCommand(.browser(.reload(hard: false)), target: .activePane)
        switch result {
        case .failure(.unsupportedCommand(_, .navigation)):
            break
        default:
            #expect(Bool(false), "Expected unsupportedCommand requiring navigation capability")
        }
        #expect(fakeRuntime.receivedCommands.isEmpty)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("dispatchRuntimeCommand rejects diff artifact worktree mismatch")
    func dispatchRejectsDiffWorktreeMismatch() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-diff-worktree-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let mockSurfaceManager = MockWorkspaceSurfaceCoordinatorSurfaceManager()
        let runtimeRegistry = RuntimeRegistry()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: runtimeRegistry
        )

        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/runtime-diff")!)),
            metadata: PaneMetadata(title: "Runtime")
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let fakeRuntime = FakePaneRuntime(paneId: PaneId(uuid: pane.id))
        fakeRuntime.capabilities = [.diffReview]
        var facets = fakeRuntime.metadata.facets
        facets.worktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        fakeRuntime.metadata.updateFacets(facets)
        coordinator.registerRuntime(fakeRuntime)

        let artifact = DiffArtifact(
            diffId: UUID(),
            worktreeId: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            patchData: Data("diff".utf8)
        )
        let result = await coordinator.dispatchRuntimeCommand(.diff(.loadDiff(artifact)), target: .activePane)
        switch result {
        case .failure(.invalidPayload(let description)):
            #expect(description.contains("worktree"))
        default:
            #expect(Bool(false), "Expected invalidPayload for mismatched diff worktree routing")
        }
        #expect(fakeRuntime.receivedCommands.isEmpty)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("closeTab teardown unregisters runtime from registry")
    func closeTab_unregistersRuntime() {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-close-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let mockSurfaceManager = MockWorkspaceSurfaceCoordinatorSurfaceManager()
        let runtimeRegistry = RuntimeRegistry()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: runtimeRegistry
        )

        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/runtime-close")!)),
            metadata: PaneMetadata(
                contentType: .browser,
                title: "RuntimeClose"
            )
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        let fakeRuntime = FakePaneRuntime(paneId: PaneId(uuid: pane.id))
        coordinator.registerRuntime(fakeRuntime)
        #expect(coordinator.runtimeForPane(PaneId(uuid: pane.id)) != nil)

        coordinator.execute(.closeTab(tabId: tab.id))

        #expect(coordinator.runtimeForPane(PaneId(uuid: pane.id)) == nil)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("runtime terminal closeTab(otherTabs) event closes non-source tabs")
    func runtimeEventCloseOtherTabs() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-events-close-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let mockSurfaceManager = MockWorkspaceSurfaceCoordinatorSurfaceManager()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )

        let sourcePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/source")!)),
            metadata: PaneMetadata(title: "Source")
        )
        let otherPane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/other")!)),
            metadata: PaneMetadata(title: "Other")
        )
        let sourceTab = Tab(paneId: sourcePane.id)
        let otherTab = Tab(paneId: otherPane.id)
        store.appendTab(sourceTab)
        store.appendTab(otherTab)
        store.setActiveTab(sourceTab.id)

        let fakeRuntime = FakePaneRuntime(paneId: PaneId(uuid: sourcePane.id))
        coordinator.registerRuntime(fakeRuntime)

        fakeRuntime.emit(
            makeRuntimeEnvelope(
                source: .pane(PaneId(uuid: sourcePane.id)),
                paneKind: .terminal,
                seq: 1,
                commandId: nil,
                correlationId: nil,
                timestamp: ContinuousClock().now,
                epoch: 0,
                event: .terminal(.closeTab(mode: .otherTabs))
            )
        )

        await eventually("other tabs close after runtime event") {
            store.tabs.count == 1
        }

        #expect(store.tabs.count == 1)
        #expect(store.tabs.first?.id == sourceTab.id)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("runtime terminal gotoTab(next) event selects next tab")
    func runtimeEventGotoNextTab() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-events-goto-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let mockSurfaceManager = MockWorkspaceSurfaceCoordinatorSurfaceManager()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )

        let sourcePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/source-next")!)),
            metadata: PaneMetadata(title: "Source")
        )
        let nextPane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/next")!)),
            metadata: PaneMetadata(title: "Next")
        )
        let sourceTab = Tab(paneId: sourcePane.id)
        let nextTab = Tab(paneId: nextPane.id)
        store.appendTab(sourceTab)
        store.appendTab(nextTab)
        store.setActiveTab(sourceTab.id)

        let fakeRuntime = FakePaneRuntime(paneId: PaneId(uuid: sourcePane.id))
        coordinator.registerRuntime(fakeRuntime)

        fakeRuntime.emit(
            makeRuntimeEnvelope(
                source: .pane(PaneId(uuid: sourcePane.id)),
                paneKind: .terminal,
                seq: 1,
                commandId: nil,
                correlationId: nil,
                timestamp: ContinuousClock().now,
                epoch: 0,
                event: .terminal(.gotoTab(target: .next))
            )
        )

        await eventually("next tab becomes active after runtime event") {
            store.activeTabId == nextTab.id
        }

        #expect(store.activeTabId == nextTab.id)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("runtime terminal title/cwd events update pane metadata")
    func runtimeEventMetadataUpdatesPaneStore() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-events-metadata-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let mockSurfaceManager = MockWorkspaceSurfaceCoordinatorSurfaceManager()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )

        let sourcePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/source-metadata")!)),
            metadata: PaneMetadata(title: "Source")
        )
        let sourceTab = Tab(paneId: sourcePane.id)
        store.appendTab(sourceTab)
        store.setActiveTab(sourceTab.id)

        let fakeRuntime = FakePaneRuntime(paneId: PaneId(uuid: sourcePane.id))
        coordinator.registerRuntime(fakeRuntime)

        fakeRuntime.emit(
            makeRuntimeEnvelope(
                source: .pane(PaneId(uuid: sourcePane.id)),
                paneKind: .terminal,
                seq: 1,
                commandId: nil,
                correlationId: nil,
                timestamp: ContinuousClock().now,
                epoch: 0,
                event: .terminal(.titleChanged("Updated Title"))
            )
        )
        fakeRuntime.emit(
            makeRuntimeEnvelope(
                source: .pane(PaneId(uuid: sourcePane.id)),
                paneKind: .terminal,
                seq: 2,
                commandId: nil,
                correlationId: nil,
                timestamp: ContinuousClock().now,
                epoch: 0,
                event: .terminal(.cwdChanged("/tmp/updated-cwd"))
            )
        )

        await eventually("runtime metadata updates are reflected in workspace store") {
            store.pane(sourcePane.id)?.metadata.title == "Updated Title"
                && store.pane(sourcePane.id)?.metadata.cwd == URL(fileURLWithPath: "/tmp/updated-cwd")
        }

        #expect(store.pane(sourcePane.id)?.metadata.title == "Updated Title")
        #expect(store.pane(sourcePane.id)?.metadata.cwd == URL(fileURLWithPath: "/tmp/updated-cwd"))

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("runtime cwd changed updates pane worktree identity")
    func runtimeCwdChangedUpdatesPaneWorktreeIdentity() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-runtime-cwd-identity-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: MockWorkspaceSurfaceCoordinatorSurfaceManager(),
            runtimeRegistry: RuntimeRegistry()
        )

        let repo = store.addRepo(at: URL(filePath: "/tmp/cwd-identity-repo"))
        let main = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/cwd-identity-repo"),
            isMainWorktree: true
        )
        let feature = Worktree(
            repoId: repo.id,
            name: "feature",
            path: URL(filePath: "/tmp/cwd-identity-repo-feature")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [main, feature])

        let pane = store.createPane(
            launchDirectory: main.path,
            title: "Terminal",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: main.id, cwd: main.path),
        )
        store.appendTab(Tab(paneId: pane.id))

        let fakeRuntime = FakePaneRuntime(paneId: PaneId(uuid: pane.id))
        coordinator.registerRuntime(fakeRuntime)
        fakeRuntime.emit(
            makeRuntimeEnvelope(
                source: .pane(PaneId(uuid: pane.id)),
                paneKind: .terminal,
                seq: 1,
                commandId: nil,
                correlationId: nil,
                timestamp: ContinuousClock().now,
                epoch: 0,
                event: .terminal(.cwdChanged(feature.path.appending(path: "Sources").path))
            )
        )

        await eventually("runtime cwd should refresh pane identity") {
            store.pane(pane.id)?.worktreeId == feature.id
        }

        let updated = store.pane(pane.id)
        #expect(updated?.metadata.cwd == feature.path.appending(path: "Sources"))
        #expect(updated?.repoId == repo.id)
        #expect(updated?.worktreeId == feature.id)
        #expect(updated?.metadata.worktreeName == "feature")

        #expect(updated?.metadata.launchDirectory == main.path)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("runtime terminal closeTab(rightTabs) closes tabs strictly to the right of source")
    func runtimeEventCloseRightTabs() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-events-close-right-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let mockSurfaceManager = MockWorkspaceSurfaceCoordinatorSurfaceManager()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )

        let leftPane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/left")!)),
            metadata: PaneMetadata(title: "Left")
        )
        let sourcePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/source-right")!)),
            metadata: PaneMetadata(title: "Source")
        )
        let rightPane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/right")!)),
            metadata: PaneMetadata(title: "Right")
        )
        let leftTab = Tab(paneId: leftPane.id)
        let sourceTab = Tab(paneId: sourcePane.id)
        let rightTab = Tab(paneId: rightPane.id)
        store.appendTab(leftTab)
        store.appendTab(sourceTab)
        store.appendTab(rightTab)
        store.setActiveTab(sourceTab.id)

        let fakeRuntime = FakePaneRuntime(paneId: PaneId(uuid: sourcePane.id))
        coordinator.registerRuntime(fakeRuntime)

        fakeRuntime.emit(
            makeRuntimeEnvelope(
                source: .pane(PaneId(uuid: sourcePane.id)),
                paneKind: .terminal,
                seq: 1,
                commandId: nil,
                correlationId: nil,
                timestamp: ContinuousClock().now,
                epoch: 0,
                event: .terminal(.closeTab(mode: .rightTabs))
            )
        )

        await eventually("tabs to the right close and left/source remain") {
            store.tabs.count == 2
        }

        #expect(store.tabs.count == 2)
        #expect(store.tabs.contains(where: { $0.id == leftTab.id }))
        #expect(store.tabs.contains(where: { $0.id == sourceTab.id }))
        #expect(!store.tabs.contains(where: { $0.id == rightTab.id }))

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("runtime terminal closeTab(rightTabs) from first tab closes all tabs to the right")
    func runtimeEventCloseRightTabsFromFirstTab() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-events-close-right-first-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let mockSurfaceManager = MockWorkspaceSurfaceCoordinatorSurfaceManager()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )

        let sourcePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/source-first")!)),
            metadata: PaneMetadata(title: "Source")
        )
        let rightOnePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/right-one")!)),
            metadata: PaneMetadata(title: "RightOne")
        )
        let rightTwoPane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/right-two")!)),
            metadata: PaneMetadata(title: "RightTwo")
        )
        let sourceTab = Tab(paneId: sourcePane.id)
        let rightOneTab = Tab(paneId: rightOnePane.id)
        let rightTwoTab = Tab(paneId: rightTwoPane.id)
        store.appendTab(sourceTab)
        store.appendTab(rightOneTab)
        store.appendTab(rightTwoTab)
        store.setActiveTab(sourceTab.id)

        let fakeRuntime = FakePaneRuntime(paneId: PaneId(uuid: sourcePane.id))
        coordinator.registerRuntime(fakeRuntime)

        fakeRuntime.emit(
            makeRuntimeEnvelope(
                source: .pane(PaneId(uuid: sourcePane.id)),
                paneKind: .terminal,
                seq: 1,
                commandId: nil,
                correlationId: nil,
                timestamp: ContinuousClock().now,
                epoch: 0,
                event: .terminal(.closeTab(mode: .rightTabs))
            )
        )

        await eventually("all tabs to the right close when source is first") {
            store.tabs.count == 1
        }

        #expect(store.tabs.count == 1)
        #expect(store.tabs.first?.id == sourceTab.id)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("runtime terminal closeTab(rightTabs) from last tab closes no tabs")
    func runtimeEventCloseRightTabsFromLastTab() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-events-close-right-last-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let mockSurfaceManager = MockWorkspaceSurfaceCoordinatorSurfaceManager()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )

        let leftPane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/left-last")!)),
            metadata: PaneMetadata(title: "Left")
        )
        let sourcePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/source-last")!)),
            metadata: PaneMetadata(title: "Source")
        )
        let leftTab = Tab(paneId: leftPane.id)
        let sourceTab = Tab(paneId: sourcePane.id)
        store.appendTab(leftTab)
        store.appendTab(sourceTab)
        store.setActiveTab(sourceTab.id)

        let fakeRuntime = FakePaneRuntime(paneId: PaneId(uuid: sourcePane.id))
        coordinator.registerRuntime(fakeRuntime)

        fakeRuntime.emit(
            makeRuntimeEnvelope(
                source: .pane(PaneId(uuid: sourcePane.id)),
                paneKind: .terminal,
                seq: 1,
                commandId: nil,
                correlationId: nil,
                timestamp: ContinuousClock().now,
                epoch: 0,
                event: .terminal(.closeTab(mode: .rightTabs))
            )
        )

        await eventually("no tabs close when source is last") {
            store.tabs.count == 2
        }

        #expect(store.tabs.count == 2)
        #expect(store.tabs.contains(where: { $0.id == leftTab.id }))
        #expect(store.tabs.contains(where: { $0.id == sourceTab.id }))

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("runtime terminal gotoTab(index) clamps to valid tab bounds")
    func runtimeEventGotoTabIndexClampsBounds() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-events-goto-index-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let mockSurfaceManager = MockWorkspaceSurfaceCoordinatorSurfaceManager()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )

        let sourcePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/source-index")!)),
            metadata: PaneMetadata(title: "Source")
        )
        let middlePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/middle-index")!)),
            metadata: PaneMetadata(title: "Middle")
        )
        let lastPane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/last-index")!)),
            metadata: PaneMetadata(title: "Last")
        )
        let sourceTab = Tab(paneId: sourcePane.id)
        let middleTab = Tab(paneId: middlePane.id)
        let lastTab = Tab(paneId: lastPane.id)
        store.appendTab(sourceTab)
        store.appendTab(middleTab)
        store.appendTab(lastTab)
        store.setActiveTab(sourceTab.id)

        let fakeRuntime = FakePaneRuntime(paneId: PaneId(uuid: sourcePane.id))
        coordinator.registerRuntime(fakeRuntime)

        fakeRuntime.emit(
            makeRuntimeEnvelope(
                source: .pane(PaneId(uuid: sourcePane.id)),
                paneKind: .terminal,
                seq: 1,
                commandId: nil,
                correlationId: nil,
                timestamp: ContinuousClock().now,
                epoch: 0,
                event: .terminal(.gotoTab(target: .index(99)))
            )
        )

        await eventually("gotoTab(index>count) clamps to last tab") {
            store.activeTabId == lastTab.id
        }
        #expect(store.activeTabId == lastTab.id)

        fakeRuntime.emit(
            makeRuntimeEnvelope(
                source: .pane(PaneId(uuid: sourcePane.id)),
                paneKind: .terminal,
                seq: 2,
                commandId: nil,
                correlationId: nil,
                timestamp: ContinuousClock().now,
                epoch: 0,
                event: .terminal(.gotoTab(target: .index(0)))
            )
        )

        await eventually("gotoTab(index<1) clamps to first tab") {
            store.activeTabId == sourceTab.id
        }
        #expect(store.activeTabId == sourceTab.id)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("runtime terminal gotoTab(index) handles 1, N-1, N, and N+1 edges")
    func runtimeEventGotoTabIndexBoundaryCoverage() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-events-goto-index-boundaries-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let mockSurfaceManager = MockWorkspaceSurfaceCoordinatorSurfaceManager()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )

        let sourcePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/source-boundary")!)),
            metadata: PaneMetadata(title: "Source")
        )
        let middlePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/middle-boundary")!)),
            metadata: PaneMetadata(title: "Middle")
        )
        let lastPane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/last-boundary")!)),
            metadata: PaneMetadata(title: "Last")
        )
        let sourceTab = Tab(paneId: sourcePane.id)
        let middleTab = Tab(paneId: middlePane.id)
        let lastTab = Tab(paneId: lastPane.id)
        store.appendTab(sourceTab)
        store.appendTab(middleTab)
        store.appendTab(lastTab)
        store.setActiveTab(lastTab.id)

        let fakeRuntime = FakePaneRuntime(paneId: PaneId(uuid: sourcePane.id))
        coordinator.registerRuntime(fakeRuntime)

        fakeRuntime.emit(
            makeRuntimeEnvelope(
                source: .pane(PaneId(uuid: sourcePane.id)),
                paneKind: .terminal,
                seq: 1,
                commandId: nil,
                correlationId: nil,
                timestamp: ContinuousClock().now,
                epoch: 0,
                event: .terminal(.gotoTab(target: .index(1)))
            )
        )

        await eventually("gotoTab(index=1) selects first tab") {
            store.activeTabId == sourceTab.id
        }
        #expect(store.activeTabId == sourceTab.id)

        fakeRuntime.emit(
            makeRuntimeEnvelope(
                source: .pane(PaneId(uuid: sourcePane.id)),
                paneKind: .terminal,
                seq: 2,
                commandId: nil,
                correlationId: nil,
                timestamp: ContinuousClock().now,
                epoch: 0,
                event: .terminal(.gotoTab(target: .index(2)))
            )
        )

        await eventually("gotoTab(index=N-1) selects middle tab") {
            store.activeTabId == middleTab.id
        }
        #expect(store.activeTabId == middleTab.id)

        fakeRuntime.emit(
            makeRuntimeEnvelope(
                source: .pane(PaneId(uuid: sourcePane.id)),
                paneKind: .terminal,
                seq: 3,
                commandId: nil,
                correlationId: nil,
                timestamp: ContinuousClock().now,
                epoch: 0,
                event: .terminal(.gotoTab(target: .index(3)))
            )
        )

        await eventually("gotoTab(index=N) selects last tab") {
            store.activeTabId == lastTab.id
        }
        #expect(store.activeTabId == lastTab.id)

        fakeRuntime.emit(
            makeRuntimeEnvelope(
                source: .pane(PaneId(uuid: sourcePane.id)),
                paneKind: .terminal,
                seq: 4,
                commandId: nil,
                correlationId: nil,
                timestamp: ContinuousClock().now,
                epoch: 0,
                event: .terminal(.gotoTab(target: .index(4)))
            )
        )

        await eventually("gotoTab(index=N+1) clamps to last tab") {
            store.activeTabId == lastTab.id
        }
        #expect(store.activeTabId == lastTab.id)

        try? FileManager.default.removeItem(at: tempDir)
    }
}

@MainActor
private final class MockWorkspaceSurfaceCoordinatorSurfaceManager: WorkspaceSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>

    init() {
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
        .failure(.ghosttyNotInitialized)
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {}

    func undoClose() -> ManagedSurface? {
        nil
    }

    func requeueUndo(_ surfaceId: UUID) {}

    func destroy(_ surfaceId: UUID) {}
}
