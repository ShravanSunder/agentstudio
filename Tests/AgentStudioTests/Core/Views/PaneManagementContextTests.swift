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
        repoCache.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: worktree.id,
                repoId: repo.id,
                branch: "main"
            )
        )
        repoCache.setPullRequestCount(2, for: worktree.id)
        repoCache.setNotificationCount(1, for: worktree.id)

        let context = PaneManagementContext.project(paneId: pane.id, store: store, repoCache: repoCache)

        #expect(context.targetPath?.path == "/tmp/agent-studio/subdir")
        #expect(context.title == worktree.path.lastPathComponent)
        #expect(context.detailLine == "main")
        #expect(context.statusChips?.branchStatus.prCount == 2)
        #expect(context.statusChips?.notificationCount == 1)
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
        #expect(context.detailLine == "detached HEAD")
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
        #expect(context.detailLine == "No filesystem target")
        #expect(context.statusChips == nil)
        #expect(context.showsIdentityBlock == true)
    }

    @Test
    func genericBrowserPane_hidesIdentityBlock_whenNoWorkspaceAssociationExists() {
        let persistor = WorkspacePersistor(
            workspacesDir: FileManager.default.temporaryDirectory.appending(
                path: "pane-management-context-\(UUID().uuidString)")
        )
        persistor.ensureDirectory()
        let store = WorkspaceStore(persistor: persistor)
        let repoCache = WorkspaceRepoCache()

        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://github.com")!)),
            metadata: PaneMetadata(
                contentType: .browser,
                source: .floating(workingDirectory: nil, title: "GitHub"),
                title: "GitHub"
            )
        )

        let context = PaneManagementContext.project(paneId: pane.id, store: store, repoCache: repoCache)

        #expect(context.showsIdentityBlock == false)
    }

    @Test
    func contextualBrowserPane_showsIdentityBlock_whenWorkspaceAssociationExists() {
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
            content: .webview(WebviewState(url: URL(string: "https://github.com/ShravanSunder/agentstudio")!)),
            metadata: PaneMetadata(
                contentType: .browser,
                source: .worktree(worktreeId: worktree.id, repoId: repo.id),
                title: "GitHub",
                facets: PaneContextFacets(
                    repoId: repo.id,
                    repoName: repo.name,
                    worktreeId: worktree.id,
                    worktreeName: worktree.name,
                    cwd: worktree.path
                )
            )
        )

        let context = PaneManagementContext.project(paneId: pane.id, store: store, repoCache: repoCache)

        #expect(context.showsIdentityBlock == true)
    }
}
