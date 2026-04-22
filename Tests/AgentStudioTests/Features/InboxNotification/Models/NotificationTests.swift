import Foundation
import Testing

@testable import AgentStudio

@Suite("Notification model")
struct NotificationTests {
    @Test("InboxNotification round-trips through JSON")
    func jsonRoundtrip() throws {
        let id = UUID()
        let now = Date()
        let original = InboxNotification(
            id: id,
            timestamp: now,
            kind: .agentDesktopNotification,
            title: "Codex done",
            body: "exit 0 · 4m 12s",
            paneId: UUID(),
            tabId: UUID(),
            repoId: UUID(),
            repoName: "agent-studio",
            worktreeId: UUID(),
            worktreeName: "drawer-improvements",
            branchName: "drawer-improvements",
            isRead: false,
            isDismissedFromDrawer: false
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(InboxNotification.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
        #expect(decoded.kind == original.kind)
        #expect(decoded.repoName == original.repoName)
        #expect(decoded.isRead == original.isRead)
        #expect(decoded.isDismissedFromDrawer == original.isDismissedFromDrawer)
    }

    @Test("InboxNotificationKind enumerates expected cases")
    func kindCases() {
        let _: InboxNotificationKind = .agentDesktopNotification
        let _: InboxNotificationKind = .bellRang
        let _: InboxNotificationKind = .commandFinished
        let _: InboxNotificationKind = .agentRpc
        let _: InboxNotificationKind = .approvalRequested
        let _: InboxNotificationKind = .securityEvent
    }

    @Test("InboxNotificationGrouping enumerates expected cases")
    func groupingCases() {
        let _: InboxNotificationGrouping = .none
        let _: InboxNotificationGrouping = .byRepo
        let _: InboxNotificationGrouping = .byPane
        let _: InboxNotificationGrouping = .byTab
    }

    @Test("InboxNotificationSort enumerates expected cases")
    func sortCases() {
        let _: InboxNotificationSort = .newestFirst
        let _: InboxNotificationSort = .oldestFirst
    }
}
