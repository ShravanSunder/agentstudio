import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("SidebarSurfaceHost", .serialized)
struct SidebarSurfaceHostTests {
    @Test("repos surface maps to repo explorer child")
    func childKindRepos() {
        let uiState = WorkspaceSidebarState()
        #expect(SidebarSurfaceHost.currentChildKind(uiState: uiState) == .repoExplorer)
    }

    @Test("inbox surface maps to inbox child")
    func childKindInbox() {
        let uiState = WorkspaceSidebarState()
        uiState.setSidebarSurface(.inbox)

        #expect(SidebarSurfaceHost.currentChildKind(uiState: uiState) == .inbox)
    }

    @Test("worktree roll-up alert count excludes activity notifications")
    func worktreeRollUpAlertCountExcludesActivityNotifications() {
        let worktreeId = UUID()
        let actionPaneId = UUID()
        let activityPaneId = UUID()
        let inboxAtom = InboxNotificationAtom()
        inboxAtom.append(
            InboxNotification(
                id: UUID(),
                timestamp: Date(timeIntervalSince1970: 100),
                kind: .approvalRequested,
                title: "Approval requested",
                body: nil,
                source: .pane(
                    .init(
                        paneId: actionPaneId,
                        worktreeId: worktreeId,
                        worktreeName: "main"
                    )
                ),
                claimKey: .init(
                    paneId: actionPaneId,
                    lane: .actionNeeded,
                    semantic: .approvalRequested,
                    sessionId: nil
                ),
                isRead: false,
                isDismissedFromPaneInbox: false
            )
        )
        inboxAtom.append(
            InboxNotification(
                id: UUID(),
                timestamp: Date(timeIntervalSince1970: 101),
                kind: .unseenActivity,
                title: "Activity",
                body: nil,
                source: .pane(
                    .init(
                        paneId: activityPaneId,
                        worktreeId: worktreeId,
                        worktreeName: "main"
                    )
                ),
                claimKey: .init(
                    paneId: activityPaneId,
                    lane: .activity,
                    semantic: .unseenActivity,
                    sessionId: nil
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

        #expect(SidebarSurfaceHost.rollUpAlertCount(for: worktree, inboxAtom: inboxAtom) == 1)
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
        let sidebarState = InboxSidebarState()

        try await withIsolatedCommandDispatcher(
            configure: {
                AppCommandDispatcher.shared.appCommandRouter = router
                AppCommandDispatcher.shared.handler = nil
            },
            body: {
                SidebarSurfaceHost.showNotifications(
                    for: worktree,
                    inboxSidebarState: sidebarState,
                    dispatcher: .shared
                )

                #expect(sidebarState.peekPendingFilter() == .worktree(id: worktree.id))
                #expect(
                    sidebarState.peekPendingDisplayOverride()
                        == .init(contentMode: .rollUpAlerts, rowStateFilter: .unreadOnly)
                )
                #expect(router.handledCommands == [.showInboxNotifications])
            }
        )
    }
}
