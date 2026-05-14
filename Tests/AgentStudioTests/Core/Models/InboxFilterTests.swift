import Foundation
import Testing

@testable import AgentStudio

@Suite("InboxFilter")
struct InboxFilterTests {
    @Test("codable preserves filter variant and id")
    func codablePreservesFilterVariantAndId() throws {
        let worktreeId = UUID()
        let encoded = try JSONEncoder().encode(InboxFilter.worktree(id: worktreeId))
        let decoded = try JSONDecoder().decode(InboxFilter.self, from: encoded)

        #expect(decoded == .worktree(id: worktreeId))
    }

    @Test("matches worktree and repo notifications exhaustively")
    func matchesWorktreeAndRepoNotifications() {
        let repoId = UUID()
        let worktreeId = UUID()

        #expect(InboxFilter.worktree(id: worktreeId).matches(worktreeId: worktreeId, repoId: repoId))
        #expect(!InboxFilter.worktree(id: worktreeId).matches(worktreeId: UUID(), repoId: repoId))
        #expect(InboxFilter.repo(id: repoId).matches(worktreeId: worktreeId, repoId: repoId))
        #expect(!InboxFilter.repo(id: repoId).matches(worktreeId: worktreeId, repoId: UUID()))
        #expect(!InboxFilter.worktree(id: worktreeId).matches(worktreeId: nil, repoId: repoId))
        #expect(!InboxFilter.repo(id: repoId).matches(worktreeId: worktreeId, repoId: nil))
    }
}
