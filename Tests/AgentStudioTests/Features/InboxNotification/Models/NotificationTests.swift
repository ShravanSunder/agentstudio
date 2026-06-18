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
                    branchName: "drawer-improvements"
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

    @Test("InboxNotification persists claim identity and split activity ids")
    func persistsClaimIdentityAndSplitActivityIds() throws {
        let paneId = UUID()
        let sessionId = UUID()
        let burstWindowId = UUID()
        let original = InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 10),
            kind: .unseenActivity,
            title: "New terminal activity",
            body: "Output appeared while you were away",
            source: .pane(.init(paneId: paneId)),
            activityContext: .init(
                burstWindowId: burstWindowId,
                activitySessionId: sessionId,
                eventCount: 2,
                rowsAdded: 90,
                thresholdRows: 30,
                latestRows: 190
            ),
            claimKey: .init(
                paneId: paneId,
                lane: .activity,
                semantic: .unseenActivity,
                sessionId: sessionId
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

        #expect(decoded.claimKey == original.claimKey)
        #expect(decoded.activityContext?.burstWindowId == burstWindowId)
        #expect(decoded.activityContext?.activitySessionId == sessionId)
        #expect(decoded.activityContext?.eventCount == 2)
    }

    @Test("activity context coalesces event counts from both windows")
    func activityContextCoalescesEventCountsFromBothWindows() {
        let existing = InboxNotification.ActivityContext(
            burstWindowId: UUID(),
            activitySessionId: UUID(),
            eventCount: 3,
            rowsAdded: 40,
            thresholdRows: 30,
            latestRows: 140
        )
        let incoming = InboxNotification.ActivityContext(
            burstWindowId: UUID(),
            activitySessionId: existing.activitySessionId,
            eventCount: 4,
            rowsAdded: 90,
            thresholdRows: 30,
            latestRows: 230
        )

        let coalesced = existing.coalesced(with: incoming)

        #expect(coalesced.eventCount == 7)
        #expect(coalesced.rowsAdded == 90)
        #expect(coalesced.latestRows == 230)
    }

    @Test("InboxNotificationKind enumerates expected cases")
    func kindCases() {
        let _: InboxNotificationKind = .agentDesktopNotification
        let _: InboxNotificationKind = .bellRang
        let _: InboxNotificationKind = .commandFinished
        let _: InboxNotificationKind = .terminalSecureInputRequested
        let _: InboxNotificationKind = .agentRpc
        let _: InboxNotificationKind = .agentSettledActivity
        let _: InboxNotificationKind = .approvalRequested
        let _: InboxNotificationKind = .securityEvent
    }

    @Test("InboxNotificationGrouping enumerates expected cases")
    func groupingCases() {
        #expect(InboxNotificationGrouping.allCases == [.byTab, .byRepo, .byPane, .none])
        let _: InboxNotificationGrouping = .byRepo
        let _: InboxNotificationGrouping = .byPane
        let _: InboxNotificationGrouping = .byTab
        let _: InboxNotificationGrouping = .none
    }

    @Test("InboxNotificationSort enumerates expected cases")
    func sortCases() {
        let _: InboxNotificationSort = .newestFirst
        let _: InboxNotificationSort = .oldestFirst
    }
}
