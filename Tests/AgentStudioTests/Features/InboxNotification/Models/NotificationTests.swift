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
            source: .pane(
                .init(
                    paneId: UUID(),
                    tabId: UUID(),
                    repoId: UUID(),
                    repoName: "agent-studio",
                    worktreeId: UUID(),
                    worktreeName: "drawer-improvements",
                    branchName: "drawer-improvements",
                    paneDisplayLabel: "Claude",
                    runtimeDisplayLabel: "Terminal"
                )
            ),
            isRead: false,
            isDismissedFromPaneInbox: false
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
        #expect(decoded.source == original.source)
        #expect(decoded.isRead == original.isRead)
        #expect(decoded.isDismissedFromPaneInbox == original.isDismissedFromPaneInbox)
    }

    @Test("legacy pane source JSON defaults new display context fields")
    func legacyPaneSourceJSONDefaultsNewDisplayContextFields() throws {
        let payload = """
            {
              "id": "00000000-0000-7000-8000-000000000001",
              "timestamp": "2026-05-07T00:00:00Z",
              "kind": "agentDesktopNotification",
              "title": "Claude Code",
              "body": "waiting",
              "source": {
                "pane": {
                  "_0": {
                    "paneId": "00000000-0000-7000-8000-000000000002",
                    "tabId": null,
                    "repo": null,
                    "worktree": null,
                    "branchName": null
                  }
                }
              },
              "isRead": false,
              "isDismissedFromPaneInbox": false
            }
            """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(InboxNotification.self, from: Data(payload.utf8))

        #expect(decoded.title == "Claude Code")
        #expect(decoded.paneContext?.paneRole == .main)
        #expect(decoded.tabDisplayLabel == nil)
        #expect(decoded.paneDisplayLabel == nil)
        #expect(decoded.runtimeDisplayLabel == nil)
    }

    @Test("InboxNotificationKind enumerates expected cases")
    func kindCases() {
        let _: InboxNotificationKind = .agentDesktopNotification
        let _: InboxNotificationKind = .bellRang
        let _: InboxNotificationKind = .commandFinished
        let _: InboxNotificationKind = .terminalSecureInputRequested
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
