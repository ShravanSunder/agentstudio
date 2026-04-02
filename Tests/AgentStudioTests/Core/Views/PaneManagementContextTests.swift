import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct PaneManagementContextTests {
    @Test
    func targetPath_prefersLiveCwd_thenFallsBackToWorktreeRoot() {
        let persistor = WorkspacePersistor(
            workspacesDir: FileManager.default.temporaryDirectory.appending(
                path: "pane-management-context-\(UUID().uuidString)")
        )
        persistor.ensureDirectory()
        let store = WorkspaceStore(persistor: persistor)
        let repoCache = WorkspaceRepoCache()

        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
        guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
            Issue.record("Expected main worktree")
            return
        }

        let pane = store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            title: "Terminal",
            facets: PaneContextFacets(cwd: URL(fileURLWithPath: "/tmp/agent-studio/subdir"))
        )

        let context = PaneManagementContext.project(paneId: pane.id, store: store, repoCache: repoCache)

        #expect(context.targetPath?.path == "/tmp/agent-studio/subdir")
    }

    @Test
    func targetPath_fallsBackToWorktreeRoot_whenCwdMissing() {
        let persistor = WorkspacePersistor(
            workspacesDir: FileManager.default.temporaryDirectory.appending(
                path: "pane-management-context-\(UUID().uuidString)")
        )
        persistor.ensureDirectory()
        let store = WorkspaceStore(persistor: persistor)
        let repoCache = WorkspaceRepoCache()

        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
        guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
            Issue.record("Expected main worktree")
            return
        }

        let pane = store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            title: "Terminal"
        )

        let context = PaneManagementContext.project(paneId: pane.id, store: store, repoCache: repoCache)

        #expect(context.targetPath?.path == worktree.path.path)
    }

    @Test
    func targetPath_isNil_whenNeitherCwdNorWorktreeExists() {
        let persistor = WorkspacePersistor(
            workspacesDir: FileManager.default.temporaryDirectory.appending(
                path: "pane-management-context-\(UUID().uuidString)")
        )
        persistor.ensureDirectory()
        let store = WorkspaceStore(persistor: persistor)
        let repoCache = WorkspaceRepoCache()

        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: "Floating"),
            title: "Floating"
        )

        let context = PaneManagementContext.project(paneId: pane.id, store: store, repoCache: repoCache)

        #expect(context.targetPath == nil)
        #expect(context.subtitle == "No filesystem target")
    }
}
