import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioRepoExplorer
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Repo Explorer command presentation batch", .serialized)
struct RepoExplorerCommandPresentationBatchTests {
    @Test("batch resolves targeted requests once and live dispatch can reject a stale enabled result")
    func batchIsAdvisoryAndLiveDispatchRevalidates() async throws {
        let handler = MockCommandHandler()
        handler.targetedCanExecuteResult = true
        let worktreeId = UUIDv7.generate()
        let requests = RepoExplorerWorktreeCommandPresentation.requests(
            worktreeId: worktreeId,
            repoId: UUIDv7.generate(),
            isFavorite: false,
            showsFavoriteControl: true
        )

        try await withIsolatedCommandDispatcher(
            configure: {
                AppCommandDispatcher.shared.handler = handler
                AppCommandDispatcher.shared.appCommandRouter = nil
            },
            body: {
                let snapshot = AppCommandDispatcher.shared.repoExplorerCommandPresentationSnapshot(
                    requests: requests,
                    generation: 4
                )
                let openRequest = requests.first { request in
                    request.command == .openWorktree && request.surface == .inlineControl
                }!
                #expect(snapshot.generation == 4)
                #expect(snapshot.results[openRequest] == true)

                handler.targetedCanExecuteResult = false
                AppCommandDispatcher.shared.dispatch(
                    .openWorktree,
                    target: worktreeId,
                    targetType: .worktree
                )

                #expect(handler.executedCommands.isEmpty)
            }
        )
    }

    @Test("capability generation follows structural owners while title-only mutation stays quiet")
    func capabilityGenerationTracksStructuralChangesButNotTitles() async throws {
        installTestAtomRegistryIfNeeded()
        atom(\.managementLayer).deactivate()
        defer { atom(\.managementLayer).deactivate() }

        let store = WorkspaceStore()
        let visibleWorktrees = SidebarVisibleWorktreesRuntimeAtom()
        let prefs = RepoExplorerSidebarPrefsAtom()
        let pane = store.createPane()
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        visibleWorktrees.setVisibleWorktreeIds([])

        let batch = RepoExplorerCommandPresentationBatch(
            store: store,
            repoExplorerPrefs: prefs,
            visibleWorktrees: visibleWorktrees,
            dispatcher: .shared
        )
        batch.start()
        defer { batch.stop() }

        await eventually("initial command presentation generation") {
            batch.snapshot.generation > 0
        }
        let initialGeneration = batch.snapshot.generation

        store.paneAtom.updatePaneTitle(pane.id, title: "quiet title")
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(batch.snapshot.generation == initialGeneration)

        atom(\.managementLayer).toggle()
        await eventually("management capability generation") {
            batch.snapshot.generation > initialGeneration
        }
        let managementGeneration = batch.snapshot.generation

        store.panePresentationAtom.enterZoom(
            inTab: tab.id,
            sourcePaneId: pane.id,
            viewerPresentation: .unavailable
        )
        await eventually("zoom capability generation") {
            batch.snapshot.generation > managementGeneration
        }
        let zoomGeneration = batch.snapshot.generation

        let secondPane = store.createPane()
        store.appendTab(Tab(paneId: secondPane.id))
        await eventually("tab capability generation") {
            batch.snapshot.generation > zoomGeneration
        }
        let tabGeneration = batch.snapshot.generation

        _ = store.addRepo(
            at: FileManager.default.temporaryDirectory.appending(
                path: "repo-command-batch-\(UUIDv7.generate().uuidString)"
            )
        )
        await eventually("topology capability generation") {
            batch.snapshot.generation > tabGeneration
        }
    }

    @Test("drawer expansion and collapse advance capability generation")
    func drawerVisibilityAdvancesCapabilityGeneration() async {
        installTestAtomRegistryIfNeeded()

        let store = WorkspaceStore()
        let pane = store.createPane()
        store.appendTab(Tab(paneId: pane.id))
        let batch = RepoExplorerCommandPresentationBatch(
            store: store,
            repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
            visibleWorktrees: SidebarVisibleWorktreesRuntimeAtom(),
            dispatcher: .shared
        )
        batch.start()
        defer { batch.stop() }

        await eventually("initial drawer capability generation") {
            batch.snapshot.generation > 0
        }
        let collapsedGeneration = batch.snapshot.generation
        #expect(store.paneAtom.isDrawerExpanded(for: pane.id) == false)

        store.toggleDrawer(for: pane.id)
        await eventually("drawer expansion capability generation") {
            batch.snapshot.generation > collapsedGeneration
        }
        let expandedGeneration = batch.snapshot.generation
        #expect(store.paneAtom.isDrawerExpanded(for: pane.id) == true)

        store.toggleDrawer(for: pane.id)
        await eventually("drawer collapse capability generation") {
            batch.snapshot.generation > expandedGeneration
        }
        #expect(store.paneAtom.isDrawerExpanded(for: pane.id) == false)
    }
}
