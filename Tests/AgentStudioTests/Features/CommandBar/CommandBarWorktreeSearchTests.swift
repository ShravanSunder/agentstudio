import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCommandBar

@MainActor
@Suite(.serialized)
struct CommandBarWorktreeSearchTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("meaningful root searches show worktrees by name, folder, and branch")
    func meaningfulRootSearchesFindWorktrees() async throws {
        let store = WorkspaceStore()
        let repository = store.addRepo(at: URL(filePath: "/tmp/search-repository"))
        let worktree = Worktree(
            repoId: repository.id,
            name: "oauth-work",
            path: URL(filePath: "/tmp/checkout-folder")
        )
        store.reconcileDiscoveredWorktrees(repository.id, worktrees: repository.worktrees + [worktree])
        let repoCache = RepoCacheAtom()
        repoCache.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktree.id, repoId: repository.id, branch: "feature/token-refresh")
        )
        let worktreeID = "repo-wt-\(worktree.id.uuidString)"
        let repositoryID = "repo-\(repository.id.uuidString)"
        let dispatcher = FakeAppCommandDispatcher()

        for scope in [CommandBarScope.everything, .repos] {
            let emptyItems = CommandBarDataSource.items(
                scope: scope, store: store, repoCache: repoCache, dispatcher: dispatcher)
            #expect(!emptyItems.contains { $0.id == worktreeID && $0.group == "Worktrees" })

            let items = CommandBarDataSource.items(
                scope: scope, rootQueryState: .meaningful,
                store: store, repoCache: repoCache, dispatcher: dispatcher)
            let worktreeRow = try #require(items.first { $0.id == worktreeID })
            #expect(worktreeRow.title == "oauth-work")
            #expect(worktreeRow.subtitle == repository.name)
            #expect(worktreeRow.hasChildren)
            #expect(worktreeRow.group == "Worktrees")
            #expect(worktreeRow.keywords.contains("feature/token-refresh"))
            for query in ["oauth-work", "checkout-folder", "token-refresh"] {
                let matchingIds = await searchCommandBarItemIds(items, query: query)
                #expect(matchingIds.contains(worktreeID))
            }
            let matchingIds = await searchCommandBarItemIds(items, query: "oauth-work")
            #expect(!matchingIds.contains(repositoryID))
            if case .worktreeAction(let presence) = worktreeRow.action {
                #expect(presence.worktreeId == worktree.id)
            } else {
                Issue.record("Search result must open the worktree actions menu")
            }
        }
    }
}
