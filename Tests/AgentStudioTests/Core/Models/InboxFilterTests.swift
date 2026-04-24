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
        let matchingNotification = notification(repoId: repoId, worktreeId: worktreeId)
        let otherNotification = notification(repoId: UUID(), worktreeId: UUID())

        #expect(InboxFilter.worktree(id: worktreeId).matches(matchingNotification))
        #expect(!InboxFilter.worktree(id: worktreeId).matches(otherNotification))
        #expect(InboxFilter.repo(id: repoId).matches(matchingNotification))
        #expect(!InboxFilter.repo(id: repoId).matches(otherNotification))
    }

    private func notification(repoId: UUID, worktreeId: UUID) -> InboxNotification {
        InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .agentRpc,
            title: "Done",
            body: nil,
            source: .pane(.init(paneId: UUID(), repoId: repoId, worktreeId: worktreeId)),
            isRead: false,
            isDismissedFromDrawer: false
        )
    }
}
