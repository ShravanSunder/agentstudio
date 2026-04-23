import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("SidebarSurfaceHost")
struct SidebarSurfaceHostTests {
    @Test("repos surface maps to repo explorer child")
    func childKindRepos() {
        let uiState = UIStateAtom()
        #expect(SidebarSurfaceHost.currentChildKind(uiState: uiState) == .repoExplorer)
    }

    @Test("inbox surface maps to inbox child")
    func childKindInbox() {
        let uiState = UIStateAtom()
        uiState.setSidebarSurface(.inbox)

        #expect(SidebarSurfaceHost.currentChildKind(uiState: uiState) == .inbox)
    }

    @Test("worktree unread count is resolved from inbox atom")
    func worktreeUnreadCountResolvedFromInboxAtom() {
        let worktreeId = UUID()
        let inboxAtom = InboxNotificationAtom()
        inboxAtom.append(
            InboxNotification(
                id: UUID(),
                timestamp: Date(timeIntervalSince1970: 100),
                kind: .agentRpc,
                title: "Build finished",
                body: nil,
                paneId: nil,
                tabId: nil,
                repoId: nil,
                repoName: nil,
                worktreeId: worktreeId,
                worktreeName: nil,
                branchName: nil,
                isRead: false,
                isDismissedFromDrawer: false
            )
        )

        let worktree = Worktree(
            id: worktreeId,
            repoId: UUID(),
            name: "main",
            path: URL(fileURLWithPath: "/tmp/repo")
        )

        #expect(SidebarSurfaceHost.unreadCount(for: worktree, inboxAtom: inboxAtom) == 1)
    }
}
