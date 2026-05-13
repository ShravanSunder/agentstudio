import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxPromoter")
struct InboxPromoterTests {
    @Test("settled activity creates one unread claim")
    func settledActivityCreatesOneUnreadClaim() {
        let fixture = Fixture()
        let paneId = UUID()

        fixture.promoter.promoteSettledActivity(
            makeSettledActivity(rowsAdded: 40),
            paneId: paneId,
            context: .init(paneId: paneId)
        )

        #expect(fixture.atom.notifications.count == 1)
        #expect(fixture.atom.notifications[0].kind == .unseenActivity)
        #expect(fixture.atom.notifications[0].claimKey?.sessionId != nil)
        #expect(fixture.atom.globalUnreadCount == 1)
    }

    @Test("repeated unread settled activity refreshes timestamp and sidebar sort")
    func repeatedUnreadSettledActivityRefreshesTimestampAndSidebarSort() {
        var now = Date(timeIntervalSince1970: 1000)
        let fixture = Fixture(now: { now })
        let paneId = UUID()
        let otherPaneId = UUID()

        fixture.promoter.promoteSettledActivity(
            makeSettledActivity(burstWindowId: UUID(), eventCount: 3, rowsAdded: 40),
            paneId: paneId,
            context: .init(paneId: paneId)
        )
        let firstSessionId = fixture.atom.notifications[0].claimKey?.sessionId
        fixture.promoter.promoteExplicit(
            .init(
                kind: .agentRpc,
                title: "Other pane",
                body: nil,
                semantic: .agentRpc,
                paneId: otherPaneId,
                sessionId: nil,
                context: .init(paneId: otherPaneId)
            ))
        now = Date(timeIntervalSince1970: 25_200)
        fixture.promoter.promoteSettledActivity(
            makeSettledActivity(burstWindowId: UUID(), eventCount: 4, rowsAdded: 90),
            paneId: paneId,
            context: .init(paneId: paneId)
        )

        #expect(fixture.atom.notifications.count == 2)
        #expect(fixture.atom.notifications[0].claimKey?.sessionId == firstSessionId)
        #expect(fixture.atom.notifications[0].timestamp == now)
        #expect(fixture.atom.notifications[0].activityContext?.eventCount == 7)
        #expect(fixture.atom.notifications[0].activityContext?.rowsAdded == 90)
        let listModel = InboxNotificationListModel(
            notifications: fixture.atom.notifications,
            grouping: .none,
            sort: .newestFirst,
            searchText: ""
        )
        #expect(listModel.sections.first?.notifications.first?.id == fixture.atom.notifications[0].id)
    }

    @Test("observed pinned repeated activity updates one read history session")
    func observedPinnedRepeatedActivityUpdatesOneReadHistorySession() {
        let paneId = UUID()
        let fixture = Fixture(
            policySnapshot: .init(observedPaneIds: [paneId], pinnedToBottomByPaneId: [paneId: true])
        )

        fixture.promoter.promoteSettledActivity(
            makeSettledActivity(burstWindowId: UUID(), rowsAdded: 60),
            paneId: paneId,
            context: .init(paneId: paneId)
        )
        let firstSessionId = fixture.atom.notifications[0].claimKey?.sessionId
        fixture.promoter.promoteSettledActivity(
            makeSettledActivity(burstWindowId: UUID(), rowsAdded: 90),
            paneId: paneId,
            context: .init(paneId: paneId)
        )

        #expect(fixture.atom.notifications.count == 1)
        #expect(fixture.atom.notifications[0].claimKey?.sessionId == firstSessionId)
        #expect(fixture.atom.notifications[0].isRead == true)
        #expect(fixture.atom.notifications[0].isDismissedFromPaneInbox == true)
        #expect(fixture.atom.notifications[0].activityContext?.rowsAdded == 90)
    }

    @Test("focused explicit activity clears existing unread session")
    func focusedExplicitActivityClearsExistingUnreadSession() {
        let paneId = UUID()
        let fixture = Fixture(
            policySnapshot: .init(attendedPaneId: paneId, observedPaneIds: [paneId])
        )

        fixture.promoter.promoteSettledActivity(
            makeSettledActivity(rowsAdded: 60),
            paneId: paneId,
            context: .init(paneId: paneId)
        )
        let notificationId = fixture.atom.notifications[0].id
        fixture.promoter.promoteExplicit(
            .init(
                kind: .agentRpc,
                title: "Claude needs input",
                body: nil,
                semantic: .agentRpc,
                paneId: paneId,
                sessionId: nil,
                context: .init(paneId: paneId)
            ))

        #expect(fixture.atom.notifications.count == 1)
        #expect(fixture.atom.notifications[0].id == notificationId)
        #expect(fixture.atom.notifications[0].isRead == true)
        #expect(fixture.atom.notifications[0].isDismissedFromPaneInbox == true)
        #expect(fixture.atom.globalUnreadCount == 0)
    }

    @Test("approval request upgrades unseen activity claim instead of adding sibling row")
    func approvalRequestUpgradesUnseenActivityClaimInsteadOfAddingSiblingRow() throws {
        let fixture = Fixture()
        let paneId = UUID()

        fixture.promoter.promoteSettledActivity(
            makeSettledActivity(rowsAdded: 40),
            paneId: paneId,
            context: .init(paneId: paneId)
        )
        let sessionId = try #require(fixture.atom.notifications[0].claimKey?.sessionId)
        fixture.promoter.promoteExplicit(
            .init(
                kind: .approvalRequested,
                title: "Approval requested",
                body: "Allow command?",
                semantic: .approvalRequested,
                paneId: paneId,
                sessionId: sessionId,
                context: .init(paneId: paneId)
            ))

        #expect(fixture.atom.notifications.count == 1)
        #expect(fixture.atom.notifications[0].kind == .approvalRequested)
        #expect(fixture.atom.notifications[0].title == "Approval requested")
        #expect(fixture.atom.notifications[0].claimKey?.lane == .actionNeeded)
        #expect(fixture.atom.notifications[0].activityContext?.rowsAdded == 40)
    }

    @Test("approval request upgrade preserves denormalized source labels")
    func approvalRequestUpgradePreservesDenormalizedSourceLabels() throws {
        let fixture = Fixture()
        let paneId = UUID()
        let repoId = UUID()
        let worktreeId = UUID()

        fixture.promoter.promoteSettledActivity(
            makeSettledActivity(rowsAdded: 40),
            paneId: paneId,
            context: .init(
                paneId: paneId,
                tabId: UUID(),
                tabDisplayLabel: "Tab askluna",
                repoId: repoId,
                repoName: "askluna",
                worktreeId: worktreeId,
                worktreeName: "askluna",
                branchName: "feature/luna",
                paneDisplayLabel: "Pane Claude Code",
                runtimeDisplayLabel: "Claude Code"
            )
        )
        let sessionId = try #require(fixture.atom.notifications[0].claimKey?.sessionId)
        fixture.promoter.promoteExplicit(
            .init(
                kind: .approvalRequested,
                title: "Approval requested",
                body: nil,
                semantic: .approvalRequested,
                paneId: paneId,
                sessionId: sessionId,
                context: .init(paneId: paneId)
            ))

        #expect(fixture.atom.notifications.count == 1)
        #expect(fixture.atom.notifications[0].repoName == "askluna")
        #expect(fixture.atom.notifications[0].worktreeName == "askluna")
        #expect(fixture.atom.notifications[0].branchName == "feature/luna")
    }

    @Test("settled activity merges into existing approval claim for same pane")
    func settledActivityMergesIntoExistingApprovalClaimForSamePane() {
        let fixture = Fixture()
        let paneId = UUID()
        let sessionId = UUID()

        fixture.promoter.promoteExplicit(
            .init(
                kind: .approvalRequested,
                title: "Approval requested",
                body: nil,
                semantic: .approvalRequested,
                paneId: paneId,
                sessionId: sessionId,
                context: .init(paneId: paneId)
            ))
        fixture.promoter.promoteSettledActivity(
            makeSettledActivity(rowsAdded: 120),
            paneId: paneId,
            context: .init(paneId: paneId)
        )

        #expect(fixture.atom.notifications.count == 1)
        #expect(fixture.atom.notifications[0].kind == .approvalRequested)
        #expect(fixture.atom.notifications[0].claimKey?.lane == .actionNeeded)
        #expect(fixture.atom.notifications[0].claimKey?.sessionId == sessionId)
        #expect(fixture.atom.notifications[0].activityContext?.rowsAdded == 120)
    }

    @Test("safety claim can coexist with approval claim")
    func safetyClaimCanCoexistWithApprovalClaim() {
        let fixture = Fixture()
        let paneId = UUID()

        fixture.promoter.promoteExplicit(
            .init(
                kind: .approvalRequested,
                title: "Approval requested",
                body: nil,
                semantic: .approvalRequested,
                paneId: paneId,
                sessionId: nil,
                context: .init(paneId: paneId)
            ))
        fixture.promoter.promoteExplicit(
            .init(
                kind: .terminalRendererUnhealthy,
                title: "Terminal renderer unhealthy",
                body: nil,
                semantic: .rendererUnhealthy,
                paneId: paneId,
                sessionId: nil,
                context: .init(paneId: paneId)
            ))

        #expect(fixture.atom.notifications.count == 2)
        #expect(Set(fixture.atom.notifications.compactMap(\.claimKey?.lane)) == Set([.actionNeeded, .safety]))
    }

    @Test("read claim does not absorb future settled activity")
    func readClaimDoesNotAbsorbFutureSettledActivity() {
        let fixture = Fixture()
        let paneId = UUID()

        fixture.promoter.promoteSettledActivity(
            makeSettledActivity(rowsAdded: 40),
            paneId: paneId,
            context: .init(paneId: paneId)
        )
        let firstId = fixture.atom.notifications[0].id
        let firstSessionId = fixture.atom.notifications[0].claimKey?.sessionId
        #expect(fixture.atom.markRead(id: firstId))
        #expect(fixture.atom.dismissFromPaneInbox(id: firstId))

        fixture.promoter.promoteSettledActivity(
            makeSettledActivity(rowsAdded: 90),
            paneId: paneId,
            context: .init(paneId: paneId)
        )

        #expect(fixture.atom.notifications.count == 2)
        #expect(fixture.atom.notifications[1].claimKey?.sessionId != firstSessionId)
        #expect(fixture.atom.notifications[1].isRead == false)
    }

    @Test("stale observed history session does not absorb future settled activity")
    func staleObservedHistorySessionDoesNotAbsorbFutureSettledActivity() {
        var now = Date(timeIntervalSince1970: 1000)
        let paneId = UUID()
        let fixture = Fixture(
            policySnapshot: .init(observedPaneIds: [paneId], pinnedToBottomByPaneId: [paneId: true]),
            now: { now }
        )

        fixture.promoter.promoteSettledActivity(
            makeSettledActivity(rowsAdded: 40),
            paneId: paneId,
            context: .init(paneId: paneId)
        )
        let firstSessionId = fixture.atom.notifications[0].claimKey?.sessionId
        now = now.addingTimeInterval(301)

        fixture.promoter.promoteSettledActivity(
            makeSettledActivity(rowsAdded: 90),
            paneId: paneId,
            context: .init(paneId: paneId)
        )

        #expect(fixture.atom.notifications.count == 2)
        #expect(fixture.atom.notifications[1].claimKey?.sessionId != firstSessionId)
    }

    @Test("observed pinned small activity is suppressed")
    func observedPinnedSmallActivityIsSuppressed() {
        let paneId = UUID()
        let fixture = Fixture(
            policySnapshot: .init(observedPaneIds: [paneId], pinnedToBottomByPaneId: [paneId: true])
        )

        fixture.promoter.promoteSettledActivity(
            makeSettledActivity(rowsAdded: 10),
            paneId: paneId,
            context: .init(paneId: paneId)
        )

        #expect(fixture.atom.notifications.isEmpty)
    }

    @Test("observed not pinned activity creates unread claim")
    func observedNotPinnedActivityCreatesUnreadClaim() {
        let paneId = UUID()
        let fixture = Fixture(
            policySnapshot: .init(observedPaneIds: [paneId], pinnedToBottomByPaneId: [paneId: false])
        )

        fixture.promoter.promoteSettledActivity(
            makeSettledActivity(rowsAdded: 10),
            paneId: paneId,
            context: .init(paneId: paneId)
        )

        #expect(fixture.atom.notifications.count == 1)
        #expect(fixture.atom.notifications[0].isRead == false)
        #expect(fixture.atom.notifications[0].isDismissedFromPaneInbox == false)
    }

    @Test("observed pinned large activity is retained as read history")
    func observedPinnedLargeActivityIsRetainedAsReadHistory() {
        let paneId = UUID()
        let fixture = Fixture(
            policySnapshot: .init(observedPaneIds: [paneId], pinnedToBottomByPaneId: [paneId: true])
        )

        fixture.promoter.promoteSettledActivity(
            makeSettledActivity(rowsAdded: 60),
            paneId: paneId,
            context: .init(paneId: paneId)
        )

        #expect(fixture.atom.notifications.count == 1)
        #expect(fixture.atom.notifications[0].isRead == true)
        #expect(fixture.atom.notifications[0].isDismissedFromPaneInbox == true)
    }

    private struct Fixture {
        let atom: InboxNotificationAtom
        let promoter: InboxPromoter

        @MainActor
        init(
            policySnapshot: InboxPolicySnapshot = .init(),
            now: @escaping () -> Date = { Date(timeIntervalSince1970: 1000) }
        ) {
            let atom = InboxNotificationAtom()
            self.atom = atom
            self.promoter = InboxPromoter(
                inboxAtom: atom,
                autoClearPolicy: PaneInboxAutoClearPolicy(),
                policySnapshot: { policySnapshot },
                traceRuntime: nil,
                now: now
            )
        }
    }

    private func makeSettledActivity(
        burstWindowId: UUID = UUID(),
        eventCount: Int = 1,
        rowsAdded: Int = 40
    ) -> TerminalSettledActivity {
        TerminalSettledActivity(
            burstWindowId: burstWindowId,
            thresholdRows: 30,
            debounceMilliseconds: 750,
            startedAtMilliseconds: 1000,
            settledAtMilliseconds: 1750,
            eventCount: eventCount,
            rowsAdded: rowsAdded,
            baselineRows: 100,
            latestRows: 100 + rowsAdded,
            isPinnedToBottom: false
        )
    }
}
