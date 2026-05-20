import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("SidebarSurfaceHost", .serialized)
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
                source: .pane(
                    .init(
                        paneId: UUID(),
                        worktreeId: worktreeId,
                        worktreeName: "main"
                    )
                ),
                isRead: false,
                isDismissedFromPaneInbox: false
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

    @Test("worktree notification action sets sidebar state before dispatching inbox command")
    func worktreeNotificationActionSetsDraftBeforeDispatch() async throws {
        let router = MockAppCommandRouter()
        router.appCommands = [.showInboxNotifications]
        let worktree = Worktree(
            id: UUID(),
            repoId: UUID(),
            name: "main",
            path: URL(fileURLWithPath: "/tmp/repo")
        )
        let sidebarState = InboxSidebarStateAtom()

        try await withIsolatedCommandDispatcher(
            configure: {
                CommandDispatcher.shared.appCommandRouter = router
                CommandDispatcher.shared.handler = nil
            },
            body: {
                SidebarSurfaceHost.showNotifications(
                    for: worktree,
                    inboxSidebarState: sidebarState,
                    dispatcher: .shared
                )

                #expect(sidebarState.peekPendingFilter() == .worktree(id: worktree.id))
                #expect(router.handledCommands == [.showInboxNotifications])
            }
        )
    }
}
