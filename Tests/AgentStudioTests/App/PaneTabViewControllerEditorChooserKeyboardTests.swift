import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerEditorChooserKeyboardTests {
    private final class LaunchRecorder {
        var openedEditors: [(id: EditorTargetId, path: URL)] = []
    }

    private struct Harness {
        let store: WorkspaceStore
        let controller: PaneTabViewController
        let tempDir: URL
        let launchRecorder: LaunchRecorder
    }

    init() {
        installTestAtomRegistryIfNeeded()
    }

    private func makeHarness(installedEditorTargets: [ExternalEditorTarget]) -> Harness {
        atom(\.uiState).clear()

        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-editor-chooser-keyboard-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let runtimeRegistry = RuntimeRegistry()
        let surfaceManager = MockEditorChooserKeyboardSurfaceManager(
            createSurfaceResult: .failure(.ghosttyNotInitialized)
        )
        let appLifecycleStore = AppLifecycleAtom()
        let windowLifecycleStore = WindowLifecycleAtom()
        let applicationLifecycleMonitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appLifecycleStore,
            windowLifecycleStore: windowLifecycleStore
        )
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: surfaceManager,
            runtimeRegistry: runtimeRegistry,
            windowLifecycleStore: windowLifecycleStore
        )
        let executor = ActionExecutor(coordinator: coordinator, store: store)
        let launchRecorder = LaunchRecorder()
        let controller = PaneTabViewController(
            store: store,
            repoCache: RepoCacheAtom(),
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            executor: executor,
            tabBarAdapter: TabBarAdapter(store: store, repoCache: RepoCacheAtom()),
            viewRegistry: viewRegistry,
            installedEditorTargetsProvider: { installedEditorTargets },
            openEditorHandler: { editorId, path, _ in
                launchRecorder.openedEditors.append((id: editorId, path: path))
                return true
            },
            openFinderHandler: { _ in true }
        )

        return Harness(
            store: store,
            controller: controller,
            tempDir: tempDir,
            launchRecorder: launchRecorder
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

    @Test("editor chooser digit launches selected editor and closes chooser")
    func handleEditorChooserKeyEvent_digitLaunchesSelectedEditorAndClosesChooser() {
        let harness = makeHarness(installedEditorTargets: [.cursor, .vscode, .xcode])
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
        atom(\.uiState).setOpenEditorPane(parentPane.id)

        guard let event = makeKeyEvent(characters: "2", charactersIgnoringModifiers: "2", keyCode: 19) else {
            Issue.record("Expected synthetic key event")
            return
        }

        let result = harness.controller.handleEditorChooserKeyEvent(event)

        #expect(result == nil)
        #expect(harness.launchRecorder.openedEditors.count == 1)
        #expect(harness.launchRecorder.openedEditors.first?.id == ExternalEditorTarget.vscode.id)
        #expect(
            harness.launchRecorder.openedEditors.first?.path.standardizedFileURL
                == worktree.path.standardizedFileURL
        )
        #expect(atom(\.uiState).editorChooserState.openForPaneId == nil)
    }

    @Test("editor chooser consumes out-of-range digits while remaining open")
    func handleEditorChooserKeyEvent_outOfRangeDigit_consumesAndKeepsChooserOpen() {
        let harness = makeHarness(installedEditorTargets: [.cursor, .vscode])
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
        atom(\.uiState).setOpenEditorPane(parentPane.id)

        guard let event = makeKeyEvent(characters: "9", charactersIgnoringModifiers: "9", keyCode: 25) else {
            Issue.record("Expected synthetic key event")
            return
        }

        let result = harness.controller.handleEditorChooserKeyEvent(event)

        #expect(result == nil)
        #expect(harness.launchRecorder.openedEditors.isEmpty)
        #expect(atom(\.uiState).editorChooserState.openForPaneId == parentPane.id)
        #expect(worktree.path.path.isEmpty == false)
    }

    @Test("editor chooser ignores digits when the chooser is closed")
    func handleEditorChooserKeyEvent_whenClosed_passesEventThrough() {
        let harness = makeHarness(installedEditorTargets: [.cursor, .vscode])
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        guard let event = makeKeyEvent(characters: "1", charactersIgnoringModifiers: "1", keyCode: 18) else {
            Issue.record("Expected synthetic key event")
            return
        }

        let result = harness.controller.handleEditorChooserKeyEvent(event)

        #expect(result === event)
        #expect(harness.launchRecorder.openedEditors.isEmpty)
        #expect(atom(\.uiState).editorChooserState.openForPaneId == nil)
    }
}

private final class MockEditorChooserKeyboardSurfaceManager: PaneCoordinatorSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>
    private let createSurfaceResult: Result<ManagedSurface, SurfaceError>

    init(createSurfaceResult: Result<ManagedSurface, SurfaceError>) {
        self.createSurfaceResult = createSurfaceResult
        self.cwdStream = AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { continuation in
            continuation.finish()
        }
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { cwdStream }

    func syncFocus(activeSurfaceId _: UUID?) {}

    func createSurface(
        config _: Ghostty.SurfaceConfiguration,
        metadata _: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        createSurfaceResult
    }

    @discardableResult
    func attach(_: UUID, to _: UUID) -> Ghostty.SurfaceView? {
        nil
    }

    func detach(_: UUID, reason _: SurfaceDetachReason) {}

    func undoClose() -> ManagedSurface? { nil }

    func requeueUndo(_: UUID) {}

    func destroy(_: UUID) {}
}
