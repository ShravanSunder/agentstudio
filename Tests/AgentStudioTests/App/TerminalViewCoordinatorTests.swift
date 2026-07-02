import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceSurfaceCoordinatorViewFactoryTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    private struct WorkspaceSurfaceCoordinatorHarness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let runtime: SessionRuntime
        let coordinator: WorkspaceSurfaceCoordinator
        let tempDir: URL
    }

    private func makeHarness() -> WorkspaceSurfaceCoordinatorHarness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-coordinator-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore(persistor: persistor)
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            windowLifecycleStore: WindowLifecycleAtom()
        )
        return WorkspaceSurfaceCoordinatorHarness(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            coordinator: coordinator,
            tempDir: tempDir
        )
    }

    @Test("createViewForContent registers a host whose mounted content is a webview mount")
    func createViewForContent_registersHostedWebviewView() {
        let harness = makeHarness()
        let viewRegistry = harness.viewRegistry
        let coordinator = harness.coordinator
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pane = Pane(
            id: UUIDv7.generate(),
            content: .webview(WebviewState(url: URL(string: "https://example.com")!)),
            metadata: PaneMetadata()
        )

        let maybeView = coordinator.createViewForContent(pane: pane)
        let registered = viewRegistry.view(for: pane.id)

        #expect(maybeView is WebviewPaneMountView)
        #expect(!(maybeView is PaneHostView))
        #expect(registered != nil)
        #expect(registered?.mountedContentViewForTesting is WebviewPaneMountView)
        #expect(viewRegistry.allWebviewViews.count == 1)
        #expect(viewRegistry.allWebviewViews[pane.id] === maybeView as? WebviewPaneMountView)
    }

    @Test("createViewForContent registers a host whose mounted content is a code viewer mount")
    func createViewForContent_registersHostedCodeViewerView() {
        let harness = makeHarness()
        let viewRegistry = harness.viewRegistry
        let coordinator = harness.coordinator
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pane = Pane(
            id: UUIDv7.generate(),
            content: .codeViewer(
                CodeViewerState(filePath: URL(fileURLWithPath: "/tmp/example.swift"), scrollToLine: 42)
            ),
            metadata: PaneMetadata()
        )

        let maybeView = coordinator.createViewForContent(pane: pane)
        let registered = viewRegistry.view(for: pane.id)

        #expect(maybeView is CodeViewerPaneMountView)
        #expect(!(maybeView is PaneHostView))
        #expect(registered != nil)
        #expect(registered?.mountedContentViewForTesting is CodeViewerPaneMountView)
        #expect(viewRegistry.registeredPaneIds == Set([pane.id]))
    }

    @Test("createViewForContent builds bridge mounted content under a host and teardown clears bridge readiness")
    func createViewForContent_bridgeView_tearsDownCleanly() {
        let harness = makeHarness()
        let viewRegistry = harness.viewRegistry
        let coordinator = harness.coordinator
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pane = Pane(
            id: UUIDv7.generate(),
            content: .bridgePanel(BridgePaneState(panelKind: .diffViewer, source: .commit(sha: "abc123"))),
            metadata: PaneMetadata()
        )

        let maybeView = coordinator.createViewForContent(pane: pane)
        guard let bridgeView = maybeView as? BridgePaneMountView else {
            Issue.record("Expected a BridgePaneMountView")
            return
        }
        let registered = viewRegistry.view(for: pane.id)
        #expect(registered != nil)
        #expect(registered?.mountedContentViewForTesting === bridgeView)
        let bridgeController = bridgeView.controller
        #expect(bridgeController.isBridgeReady == false)

        bridgeController.handleBridgeReady()
        #expect(bridgeController.isBridgeReady == true)

        coordinator.teardownView(for: pane.id)

        #expect(bridgeController.isBridgeReady == false)
        #expect(viewRegistry.view(for: pane.id) == nil)
        #expect(viewRegistry.registeredPaneIds == Set<UUID>())
    }

    @Test("createViewForContent derives Bridge workspace identity from source root before bootstrap")
    func createViewForContent_bridgeWorkspaceSourceDerivesMissingWorktreeFacets() {
        let harness = makeHarness()
        let store = harness.store
        let coordinator = harness.coordinator
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let repo = store.addRepo(at: tempDir.appending(path: "repo"))
        guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
            Issue.record("Expected main worktree")
            return
        }
        let pane = Pane(
            id: UUIDv7.generate(),
            content: .bridgePanel(
                BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(
                        rootPath: worktree.path.path,
                        baseline: .localDefaultBranch(branchName: "main")
                    )
                )
            ),
            metadata: PaneMetadata(
                contentType: .diff,
                launchDirectory: worktree.path,
                title: "Bridge Review"
            )
        )

        let maybeView = coordinator.createViewForContent(pane: pane)
        guard let bridgeView = maybeView as? BridgePaneMountView else {
            Issue.record("Expected a BridgePaneMountView")
            return
        }

        #expect(bridgeView.controller.runtime.metadata.repoId == repo.id)
        #expect(bridgeView.controller.runtime.metadata.worktreeId == worktree.id)
        #expect(bridgeView.controller.runtime.metadata.cwd == worktree.path)
    }

    @Test("createViewForContent repairs restored FileView identity from pane working directory")
    func createViewForContent_restoredFileViewerDerivesWorktreeFacetsFromCWD() {
        let harness = makeHarness()
        let store = harness.store
        let coordinator = harness.coordinator
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let repo = store.addRepo(at: tempDir.appending(path: "repo"))
        guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
            Issue.record("Expected main worktree")
            return
        }
        let pane = Pane(
            id: UUIDv7.generate(),
            content: .bridgePanel(
                BridgePaneState(
                    panelKind: .fileViewer,
                    source: nil
                )
            ),
            metadata: PaneMetadata(
                contentType: .diff,
                launchDirectory: worktree.path,
                title: "Files",
                facets: PaneContextFacets(cwd: worktree.path)
            )
        )

        let maybeView = coordinator.createViewForContent(pane: pane)
        guard let bridgeView = maybeView as? BridgePaneMountView else {
            Issue.record("Expected a BridgePaneMountView")
            return
        }
        let script = bridgeView.controller.bootstrapScriptSourceForTesting

        #expect(bridgeView.controller.runtime.metadata.repoId == repo.id)
        #expect(bridgeView.controller.runtime.metadata.worktreeId == worktree.id)
        #expect(bridgeView.controller.runtime.metadata.cwd == worktree.path)
        #expect(script.contains("const APP_PROTOCOL = \"worktree-file\""))
        #expect(script.contains("data-bridge-app-protocol"))
        #expect(script.contains(repo.id.uuidString))
        #expect(script.contains(worktree.id.uuidString))
        #expect(!script.contains("const WORKTREE_FILE_SOURCE_SPEC = null;"))
    }

    @Test("review bootstrap keeps Review route while exposing Worktree/File source spec")
    func reviewBootstrapWithWorktreeMetadataKeepsReviewRouteAndExposesFileSourceSpec() {
        let repoId = UUID()
        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/agentstudio-review-root")
        let metadata = PaneMetadata(
            contentType: .diff,
            launchDirectory: rootPath,
            title: "Bridge Review",
            facets: PaneContextFacets(
                repoId: repoId,
                repoName: "repo",
                worktreeId: worktreeId,
                worktreeName: "repo",
                cwd: rootPath
            )
        )

        let artifacts = BridgePaneController.makeBootstrapArtifacts(
            paneId: UUIDv7.generate(),
            metadata: metadata,
            state: BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(rootPath: rootPath.path, baseline: .localDefaultBranch(branchName: "main"))
            ),
            telemetryScopeGate: BridgeTelemetryScopeGate(enabledScopes: []),
            bridgeWorld: .page
        )

        #expect(artifacts.script.source.contains("const APP_PROTOCOL = \"review\""))
        #expect(artifacts.script.source.contains("data-bridge-app-protocol"))
        #expect(artifacts.script.source.contains("data-bridge-worktree-file-source-spec"))
        #expect(artifacts.script.source.contains(repoId.uuidString))
        #expect(artifacts.script.source.contains(worktreeId.uuidString))
        #expect(!artifacts.script.source.contains("const WORKTREE_FILE_SOURCE_SPEC = null;"))
    }

    @Test("file viewer bootstrap selects Worktree/File route from workspace metadata")
    func fileViewerBootstrapWithWorktreeMetadataSelectsWorktreeFileRoute() throws {
        let repoId = UUID()
        let worktreeId = UUID()
        let paneId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/agentstudio-file-view-root")
        let metadata = PaneMetadata(
            contentType: .diff,
            launchDirectory: rootPath,
            title: "Files",
            facets: PaneContextFacets(
                repoId: repoId,
                repoName: "repo",
                worktreeId: worktreeId,
                worktreeName: "repo",
                cwd: rootPath
            )
        )
        let state = BridgePaneState(
            panelKind: .fileViewer,
            source: .workspace(rootPath: rootPath.path, baseline: .localDefaultBranch(branchName: "main"))
        )

        let sourceSpec = try #require(
            BridgePaneController.makeWorktreeFileBootstrapSourceSpec(
                paneId: paneId,
                metadata: metadata,
                source: state.source
            )
        )
        let artifacts = BridgePaneController.makeBootstrapArtifacts(
            paneId: paneId,
            metadata: metadata,
            state: state,
            telemetryScopeGate: BridgeTelemetryScopeGate(enabledScopes: []),
            bridgeWorld: .page
        )

        #expect(sourceSpec.clientRequestId == "bootstrap:\(paneId.uuidString)")
        #expect(sourceSpec.repoId == repoId)
        #expect(sourceSpec.worktreeId == worktreeId)
        #expect(sourceSpec.rootPathToken == StableKey.fromPath(rootPath))
        #expect(sourceSpec.includeStatuses)
        #expect(sourceSpec.freshness == .live)
        #expect(artifacts.script.source.contains("const APP_PROTOCOL = \"worktree-file\""))
        #expect(artifacts.script.source.contains("data-bridge-app-protocol"))
        #expect(artifacts.script.source.contains("data-bridge-worktree-file-source-spec"))
        #expect(artifacts.script.source.contains(repoId.uuidString))
        #expect(artifacts.script.source.contains(worktreeId.uuidString))
        #expect(!artifacts.script.source.contains("const WORKTREE_FILE_SOURCE_SPEC = null;"))
    }

    @Test("createViewForContent registers runtime for bridge, webview, and code viewer panes")
    func createViewForContent_registersNonTerminalRuntimes() {
        let harness = makeHarness()
        let coordinator = harness.coordinator
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let webviewPane = Pane(
            id: UUIDv7.generate(),
            content: .webview(WebviewState(url: URL(string: "https://example.com/runtime-web")!)),
            metadata: PaneMetadata()
        )
        let bridgePane = Pane(
            id: UUIDv7.generate(),
            content: .bridgePanel(BridgePaneState(panelKind: .diffViewer, source: .commit(sha: "def456"))),
            metadata: PaneMetadata()
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "code-view-runtime-\(UUID().uuidString).swift")
        try? "struct Runtime {}\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let codeViewerPane = Pane(
            id: UUIDv7.generate(),
            content: .codeViewer(CodeViewerState(filePath: fileURL, scrollToLine: 1)),
            metadata: PaneMetadata(
                contentType: .codeViewer,
                launchDirectory: fileURL.deletingLastPathComponent(),
                title: "Code"
            )
        )

        _ = coordinator.createViewForContent(pane: webviewPane)
        _ = coordinator.createViewForContent(pane: bridgePane)
        _ = coordinator.createViewForContent(pane: codeViewerPane)

        #expect(coordinator.runtimeForPane(PaneId(uuid: webviewPane.id)) is WebviewRuntime)
        #expect(coordinator.runtimeForPane(PaneId(uuid: bridgePane.id)) is BridgeRuntime)
        #expect(coordinator.runtimeForPane(PaneId(uuid: codeViewerPane.id)) is SwiftPaneRuntime)
    }

    @Test("createViewForContent returns nil for unsupported pane content")
    func createViewForContent_unsupportedContentReturnsNil() {
        let harness = makeHarness()
        let viewRegistry = harness.viewRegistry
        let coordinator = harness.coordinator
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pane = Pane(
            id: UUIDv7.generate(),
            content: .unsupported(UnsupportedContent(type: "legacy", version: 1, rawState: nil)),
            metadata: PaneMetadata()
        )

        let maybeView = coordinator.createViewForContent(pane: pane)

        #expect(maybeView == nil)
        #expect(viewRegistry.view(for: pane.id) == nil)
        #expect(viewRegistry.registeredPaneIds.isEmpty)
    }

    @Test("floating zmx restore uses drawer session IDs for drawer panes")
    func floatingZmxRestoreSessionId_drawerPane_usesDrawerSessionId() {
        let parentPaneId = UUIDv7.generate()
        let drawerPaneId = UUIDv7.generate()
        let pane = Pane(
            id: drawerPaneId,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                launchDirectory: URL(fileURLWithPath: "/Users/test"),
                title: "Drawer"
            ),
            kind: .drawerChild(parentPaneId: parentPaneId)
        )

        let sessionId = WorkspaceSurfaceCoordinator.floatingZmxRestoreSessionId(
            for: pane,
            launchDirectory: URL(fileURLWithPath: "/Users/test")
        )

        #expect(sessionId == ZmxBackend.drawerSessionId(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId))
    }

    @Test("floating zmx restore uses floating session IDs for top-level floating panes")
    func floatingZmxRestoreSessionId_topLevelFloatingPane_usesFloatingSessionId() {
        let paneId = UUIDv7.generate()
        let launchDirectory = URL(fileURLWithPath: "/Users/test/project")
        let pane = Pane(
            id: paneId,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                launchDirectory: launchDirectory,
                title: "Floating"
            )
        )

        let sessionId = WorkspaceSurfaceCoordinator.floatingZmxRestoreSessionId(
            for: pane,
            launchDirectory: launchDirectory
        )

        #expect(sessionId == ZmxBackend.floatingSessionId(launchDirectory: launchDirectory, paneId: paneId))
    }
}
