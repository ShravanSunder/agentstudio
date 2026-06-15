import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct PaneManagementContextTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test
    func targetPath_prefersLiveCwd_thenFallsBackToWorktreeRoot() {
        withTestAtomRegistry { atoms in
            let persistor = WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(
                    path: "pane-management-context-\(UUID().uuidString)")
            )
            persistor.ensureDirectory()
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout,
                persistor: persistor
            )

            let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
            guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
                Issue.record("Expected main worktree")
                return
            }

            let pane = store.createPane(
                launchDirectory: worktree.path,
                title: "Terminal",
                facets: PaneContextFacets(
                    repoId: repo.id,
                    worktreeId: worktree.id,
                    cwd: URL(fileURLWithPath: "/tmp/agent-studio/subdir")
                )
            )
            store.paneAtom.updatePaneNote(pane.id, note: "Watch release logs")
            atoms.repoCache.setWorktreeEnrichment(
                WorktreeEnrichment(
                    worktreeId: worktree.id,
                    repoId: repo.id,
                    branch: "main"
                )
            )
            atoms.repoCache.setPullRequestCount(2, for: worktree.id)

            let context = PaneManagementContext.project(
                paneId: pane.id,
                store: store,
                notificationCountForWorktree: { resolvedWorktreeId in
                    resolvedWorktreeId == worktree.id ? 1 : 0
                }
            )

            #expect(context.targetPath?.path == "/tmp/agent-studio/subdir")
            #expect(context.identityRows.first(where: { $0.id == "repo" })?.text == repo.name)
            #expect(context.identityRows.first(where: { $0.id == "branch" })?.text == "main")
            #expect(context.identityRows.first(where: { $0.id == "cwd" })?.text == "subdir")
            #expect(context.identityRows.last?.id == "note")
            #expect(context.identityRows.last?.icon == .system("long.text.page.and.pencil"))
            #expect(context.identityRows.last?.text == "Watch release logs")
            #expect(context.statusChips?.branchStatus.prCount == 2)
            #expect(context.statusChips?.notificationCount == 1)
        }
    }

    @Test
    func targetPath_fallsBackToWorktreeRoot_whenCwdMissing() {
        withTestAtomRegistry { atoms in
            let persistor = WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(
                    path: "pane-management-context-\(UUID().uuidString)")
            )
            persistor.ensureDirectory()
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout,
                persistor: persistor
            )

            let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
            guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
                Issue.record("Expected main worktree")
                return
            }

            let pane = store.createPane(
                launchDirectory: worktree.path,
                title: "Terminal",
                facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path),
            )

            let context = PaneManagementContext.project(paneId: pane.id, store: store)

            #expect(context.targetPath?.path == worktree.path.path)
            #expect(context.identityRows.first(where: { $0.id == "branch" })?.text == "detached HEAD")
            #expect(context.identityRows.first(where: { $0.id == "cwd" })?.text == worktree.path.lastPathComponent)
        }
    }

    @Test
    func targetPath_isNil_whenNeitherCwdNorWorktreeExists() {
        withTestAtomRegistry { atoms in
            let persistor = WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(
                    path: "pane-management-context-\(UUID().uuidString)")
            )
            persistor.ensureDirectory()
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout,
                persistor: persistor
            )

            let pane = store.createPane(
                title: "Floating"
            )

            let context = PaneManagementContext.project(paneId: pane.id, store: store)

            #expect(context.targetPath == nil)
            #expect(context.identityRows.first(where: { $0.id == "fallback" })?.text == "Floating")
            #expect(context.statusChips == nil)
            #expect(context.showsIdentityBlock == true)
        }
    }

    @Test
    func standaloneCwdUsesAbsolutePathWhenNoWorktreeContextExists() {
        withTestAtomRegistry { atoms in
            let persistor = WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(
                    path: "pane-management-context-\(UUID().uuidString)")
            )
            persistor.ensureDirectory()
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout,
                persistor: persistor
            )

            let cwd = URL(fileURLWithPath: "/Users/dev/project-dev")
            let pane = store.createPane(
                launchDirectory: cwd,
                title: "Floating",
                facets: PaneContextFacets(cwd: cwd)
            )

            let context = PaneManagementContext.project(paneId: pane.id, store: store)

            let cwdRow = context.identityRows.first { $0.id == "cwd" }
            #expect(context.targetPath == cwd)
            #expect(cwdRow?.text == "/Users/dev/project-dev")
            #expect(cwdRow?.toolTip == "/Users/dev/project-dev")
            #expect(context.identityRows.contains { $0.id == "repo" } == false)
            #expect(context.identityRows.contains { $0.id == "worktree" } == false)
        }
    }

    @Test
    func genericBrowserPane_hidesIdentityBlock_whenNoWorkspaceAssociationExists() {
        withTestAtomRegistry { atoms in
            let persistor = WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(
                    path: "pane-management-context-\(UUID().uuidString)")
            )
            persistor.ensureDirectory()
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout,
                persistor: persistor
            )

            let pane = store.createPane(
                content: .webview(WebviewState(url: URL(string: "https://github.com")!)),
                metadata: PaneMetadata(
                    contentType: .browser,
                    title: "GitHub"
                )
            )

            let context = PaneManagementContext.project(paneId: pane.id, store: store)

            #expect(context.showsIdentityBlock == false)
        }
    }

    @Test
    func contextualBrowserPane_showsIdentityBlock_whenWorkspaceAssociationExists() {
        withTestAtomRegistry { atoms in
            let persistor = WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(
                    path: "pane-management-context-\(UUID().uuidString)")
            )
            persistor.ensureDirectory()
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout,
                persistor: persistor
            )

            let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
            guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
                Issue.record("Expected main worktree")
                return
            }

            let pane = store.createPane(
                content: .webview(WebviewState(url: URL(string: "https://github.com/ShravanSunder/agentstudio")!)),
                metadata: PaneMetadata(
                    contentType: .browser,
                    launchDirectory: worktree.path,
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

            let context = PaneManagementContext.project(paneId: pane.id, store: store)

            #expect(context.showsIdentityBlock == true)
        }
    }
}
