import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCommandBar
@testable import AgentStudioCore

@MainActor
@Suite("Command bar repository availability", .serialized)
struct CommandBarRepositoryAvailabilityTests {
    @Test("a captured repository level cannot retain launch actions after collection")
    func staleRepositoryLevelHasNoActions() throws {
        try withTestCoreAtoms { _ in
            let store = WorkspaceStore()
            let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/commandbar-collected"))
            store.mutationCoordinator.removeRepo(repo.id)

            let projected = CommandBarDataSource.availableRepository(repo, store: store)
            let level = CommandBarDataSource.buildRepoLevel(
                repo: repo, store: store,
                presenceByWorktreeId: [:], dispatcher: FakeAppCommandDispatcher())

            #expect(projected == nil)
            #expect(level.items.isEmpty)
        }
    }

    @Test("cached and uncached repository rows hide unavailable families")
    func repositoryRowsFollowAvailability() throws {
        try withTestCoreAtoms { _ in
            let store = WorkspaceStore()
            let dispatcher = FakeAppCommandDispatcher()
            let cache = CommandBarRepoScopeItemCache()
            let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/commandbar-availability"))
            #expect(
                CommandBarDataSource.repoScopeItems(store: store, dispatcher: dispatcher, itemCache: cache).count == 1)
            #expect(store.mutationCoordinator.recordRepositoryAbsence(repo.id, at: time))

            #expect(CommandBarDataSource.repoScopeItems(store: store, dispatcher: dispatcher).isEmpty)
            #expect(CommandBarDataSource.repoScopeItems(store: store, dispatcher: dispatcher, itemCache: cache).isEmpty)
            #expect(CommandBarDataSource.everythingWorktreeItems(store: store).isEmpty)
            #expect(CommandBarDataSource.quickOpenItems(store: store, dispatcher: dispatcher).isEmpty)
        }
    }

    @Test("hidden main checkout cannot be the default when a linked checkout is available")
    func hiddenMainUsesAvailableLinkedCheckout() throws {
        try withTestCoreAtoms { _ in
            let store = WorkspaceStore()
            let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/commandbar-hidden-main"))
            let main = try #require(repo.worktrees.first)
            let linked = Worktree(
                id: UUIDv7.generate(), repoId: repo.id, name: "linked",
                path: URL(fileURLWithPath: "/tmp/commandbar-linked"))
            _ = store.mutationCoordinator.reconcileDiscoveredWorktrees(repo.id, worktrees: [main, linked])
            #expect(store.mutationCoordinator.recordWorktreeAbsence(main.id, at: time))

            let items = CommandBarDataSource.everythingWorktreeItems(store: store)
            #expect(items.map(\.id) == ["repo-wt-\(linked.id.uuidString)"])
            let quick = CommandBarDataSource.quickOpenItems(store: store, dispatcher: FakeAppCommandDispatcher())
            let row = try #require(quick.first)
            #expect(row.accessibilityLabel.contains(linked.path.path))
            #expect(!quick.contains { $0.id == "repo-wt-\(main.id.uuidString)" })
        }
    }

    private var time: RepositoryRetentionTime {
        .init(utc: Date(timeIntervalSince1970: 1_700_000_000), bootID: "fixture", uptimeNanoseconds: 1)
    }
}
