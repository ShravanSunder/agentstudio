import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("Repository worktree reparenting")
struct RepositoryWorktreeReparentingTests {
    @Test("an explicit same-location owner transition preserves checkout identity and metadata")
    func sameLocationOwnerTransitionPreservesCheckout() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let originalID = UUIDv7.generate()
        let currentID = UUIDv7.generate()
        let checkoutID = UUIDv7.generate()
        let path = URL(fileURLWithPath: "/tmp/reparented-location")
        let checkout = WorkspaceCoreRepository.WorktreeRecord(
            id: checkoutID, repoId: originalID, name: "checkout", path: path,
            isMainWorktree: false, note: "retained checkout note"
        )
        var original = WorkspaceCoreRepository.RepoRecord(
            id: originalID, name: "original", repoPath: URL(fileURLWithPath: "/tmp/original-family"),
            createdAt: Date(timeIntervalSince1970: 100), isPinned: true, note: "original family note",
            worktrees: [checkout]
        )
        var current = WorkspaceCoreRepository.RepoRecord(
            id: currentID, name: "current", repoPath: URL(fileURLWithPath: "/tmp/current-family"),
            createdAt: Date(timeIntervalSince1970: 200), worktrees: []
        )
        try repository.replaceRepositoryTopology(
            .init(
                watchedPaths: [], repos: [original, current], unavailableRepoIds: [currentID]
            ))
        original.worktrees = []
        current.worktrees = [
            .init(
                id: checkoutID, repoId: currentID, name: checkout.name, path: checkout.path,
                stableKey: checkout.stableKey, isMainWorktree: false, note: checkout.note
            )
        ]
        let changed = WorkspaceCoreRepository.RepositoryTopologyRecord(
            watchedPaths: [], repos: [original, current], unavailableRepoIds: [originalID]
        )

        let transition = RepositoryWorktreeReparenting(
            worktreeID: checkoutID, expectedRepositoryID: originalID, repositoryID: currentID
        )
        try repository.replaceRepositoryTopology(changed, reparenting: [transition])
        // A duplicate receipt is idempotent after its expected transition already committed.
        try repository.replaceRepositoryTopology(changed, reparenting: [transition])

        let loaded = try repository.fetchRepositoryTopology()
        #expect(loaded.repos == changed.repos)
        #expect(loaded.repos.flatMap(\.worktrees).map(\.id) == [checkoutID])
        #expect(loaded.repos.first?.note == "original family note")
        #expect(loaded.repos.first?.isPinned == true)
    }
}
