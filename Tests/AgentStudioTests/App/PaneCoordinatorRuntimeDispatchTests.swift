import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneCoordinatorRuntimeDispatchTests {
    @Test("coordinator injects its runtime registry into Ghostty action routing")
    func coordinatorInjectsGhosttyRuntimeRegistry() {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-registry-injection-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let mockSurfaceManager = MockPaneCoordinatorSurfaceManager()
        let runtimeRegistry = RuntimeRegistry()
        _ = PaneCoordinator(
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
        let mockSurfaceManager = MockPaneCoordinatorSurfaceManager()
        let runtimeRegistry = RuntimeRegistry()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: runtimeRegistry
        )

        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/runtime-dispatch")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
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
        let mockSurfaceManager = MockPaneCoordinatorSurfaceManager()
        let coordinator = PaneCoordinator(
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
        let mockSurfaceManager = MockPaneCoordinatorSurfaceManager()
        let runtimeRegistry = RuntimeRegistry()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: runtimeRegistry
        )

        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/runtime-not-ready")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
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
        let mockSurfaceManager = MockPaneCoordinatorSurfaceManager()
        let runtimeRegistry = RuntimeRegistry()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: runtimeRegistry
        )

        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/runtime-capability")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
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
        let mockSurfaceManager = MockPaneCoordinatorSurfaceManager()
        let runtimeRegistry = RuntimeRegistry()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: runtimeRegistry
        )

        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/runtime-diff")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
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
        let mockSurfaceManager = MockPaneCoordinatorSurfaceManager()
        let runtimeRegistry = RuntimeRegistry()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: runtimeRegistry
        )

        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/runtime-close")!)),
            metadata: PaneMetadata(
                source: .floating(workingDirectory: nil, title: "RuntimeClose"), title: "RuntimeClose")
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
        let mockSurfaceManager = MockPaneCoordinatorSurfaceManager()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )

        let sourcePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/source")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Source"), title: "Source")
        )
        let otherPane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/other")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Other"), title: "Other")
        )
        let sourceTab = Tab(paneId: sourcePane.id)
        let otherTab = Tab(paneId: otherPane.id)
        store.appendTab(sourceTab)
        store.appendTab(otherTab)
        store.setActiveTab(sourceTab.id)

        let fakeRuntime = FakePaneRuntime(paneId: PaneId(uuid: sourcePane.id))
        coordinator.registerRuntime(fakeRuntime)

        fakeRuntime.emit(
            PaneEventEnvelope(
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
        let mockSurfaceManager = MockPaneCoordinatorSurfaceManager()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )

        let sourcePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/source-next")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Source"), title: "Source")
        )
        let nextPane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/next")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Next"), title: "Next")
        )
        let sourceTab = Tab(paneId: sourcePane.id)
        let nextTab = Tab(paneId: nextPane.id)
        store.appendTab(sourceTab)
        store.appendTab(nextTab)
        store.setActiveTab(sourceTab.id)

        let fakeRuntime = FakePaneRuntime(paneId: PaneId(uuid: sourcePane.id))
        coordinator.registerRuntime(fakeRuntime)

        fakeRuntime.emit(
            PaneEventEnvelope(
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
        let mockSurfaceManager = MockPaneCoordinatorSurfaceManager()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )

        let sourcePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/source-metadata")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Source"), title: "Source")
        )
        let sourceTab = Tab(paneId: sourcePane.id)
        store.appendTab(sourceTab)
        store.setActiveTab(sourceTab.id)

        let fakeRuntime = FakePaneRuntime(paneId: PaneId(uuid: sourcePane.id))
        coordinator.registerRuntime(fakeRuntime)

        fakeRuntime.emit(
            PaneEventEnvelope(
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
            PaneEventEnvelope(
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

    @Test("runtime terminal closeTab(rightTabs) closes tabs strictly to the right of source")
    func runtimeEventCloseRightTabs() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-events-close-right-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let mockSurfaceManager = MockPaneCoordinatorSurfaceManager()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )

        let leftPane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/left")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Left"), title: "Left")
        )
        let sourcePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/source-right")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Source"), title: "Source")
        )
        let rightPane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/right")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Right"), title: "Right")
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
            PaneEventEnvelope(
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
        let mockSurfaceManager = MockPaneCoordinatorSurfaceManager()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )

        let sourcePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/source-first")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Source"), title: "Source")
        )
        let rightOnePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/right-one")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "RightOne"), title: "RightOne")
        )
        let rightTwoPane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/right-two")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "RightTwo"), title: "RightTwo")
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
            PaneEventEnvelope(
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
        let mockSurfaceManager = MockPaneCoordinatorSurfaceManager()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )

        let leftPane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/left-last")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Left"), title: "Left")
        )
        let sourcePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/source-last")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Source"), title: "Source")
        )
        let leftTab = Tab(paneId: leftPane.id)
        let sourceTab = Tab(paneId: sourcePane.id)
        store.appendTab(leftTab)
        store.appendTab(sourceTab)
        store.setActiveTab(sourceTab.id)

        let fakeRuntime = FakePaneRuntime(paneId: PaneId(uuid: sourcePane.id))
        coordinator.registerRuntime(fakeRuntime)

        fakeRuntime.emit(
            PaneEventEnvelope(
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
        let mockSurfaceManager = MockPaneCoordinatorSurfaceManager()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )

        let sourcePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/source-index")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Source"), title: "Source")
        )
        let middlePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/middle-index")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Middle"), title: "Middle")
        )
        let lastPane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/last-index")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Last"), title: "Last")
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
            PaneEventEnvelope(
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
            PaneEventEnvelope(
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
        let mockSurfaceManager = MockPaneCoordinatorSurfaceManager()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )

        let sourcePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/source-boundary")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Source"), title: "Source")
        )
        let middlePane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/middle-boundary")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Middle"), title: "Middle")
        )
        let lastPane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/last-boundary")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Last"), title: "Last")
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
            PaneEventEnvelope(
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
            PaneEventEnvelope(
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
            PaneEventEnvelope(
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
            PaneEventEnvelope(
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
private func eventually(
    _ description: String,
    maxAttempts: Int = 200,
    pollIntervalNanoseconds: UInt64 = 5_000_000,
    condition: @escaping @MainActor () -> Bool
) async {
    for _ in 0..<maxAttempts {
        if condition() {
            return
        }
        await Task.yield()
        try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
    #expect(condition(), "\(description) timed out")
}

@MainActor
private final class FakePaneRuntime: PaneRuntime {
    let paneId: PaneId
    var metadata: PaneMetadata
    var lifecycle: PaneRuntimeLifecycle = .ready
    var capabilities: Set<PaneCapability> = [.input]
    private let stream: AsyncStream<PaneEventEnvelope>
    private let continuation: AsyncStream<PaneEventEnvelope>.Continuation

    private(set) var receivedCommands: [RuntimeCommandEnvelope] = []
    private(set) var receivedCommandIds: [UUID] = []

    init(paneId: PaneId) {
        self.paneId = paneId
        self.metadata = PaneMetadata(source: .floating(workingDirectory: nil, title: "Fake"), title: "Fake")
        var streamContinuation: AsyncStream<PaneEventEnvelope>.Continuation?
        self.stream = AsyncStream<PaneEventEnvelope> { continuation in
            streamContinuation = continuation
        }
        self.continuation = streamContinuation!
    }

    func handleCommand(_ envelope: RuntimeCommandEnvelope) async -> ActionResult {
        if let requiredCapability = requiredCapability(for: envelope.command),
            !capabilities.contains(requiredCapability)
        {
            return .failure(
                .unsupportedCommand(
                    command: String(describing: envelope.command),
                    required: requiredCapability
                )
            )
        }

        receivedCommands.append(envelope)
        receivedCommandIds.append(envelope.commandId)
        return .success(commandId: envelope.commandId)
    }

    func subscribe() -> AsyncStream<PaneEventEnvelope> {
        stream
    }

    func emit(_ envelope: PaneEventEnvelope) {
        continuation.yield(envelope)
    }

    func snapshot() -> PaneRuntimeSnapshot {
        PaneRuntimeSnapshot(
            paneId: paneId,
            metadata: metadata,
            lifecycle: lifecycle,
            capabilities: capabilities,
            lastSeq: 0,
            timestamp: Date()
        )
    }

    func eventsSince(seq: UInt64) async -> EventReplayBuffer.ReplayResult {
        EventReplayBuffer.ReplayResult(events: [], nextSeq: seq, gapDetected: false)
    }

    func shutdown(timeout: Duration) async -> [UUID] {
        continuation.finish()
        return []
    }

    private func requiredCapability(for command: RuntimeCommand) -> PaneCapability? {
        switch command {
        case .activate, .deactivate, .prepareForClose, .requestSnapshot:
            return nil
        case .terminal(let terminalCommand):
            switch terminalCommand {
            case .sendInput, .clearScrollback:
                return .input
            case .resize:
                return .resize
            }
        case .browser:
            return .navigation
        case .diff:
            return .diffReview
        case .editor:
            return .editorActions
        case .plugin:
            return nil
        }
    }
}

@MainActor
private final class MockPaneCoordinatorSurfaceManager: PaneCoordinatorSurfaceManaging {
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
