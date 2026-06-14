import Foundation
import Testing

@testable import AgentStudio

@MainActor
extension InboxNotificationRouterTests {
    @Test("terminal unseen activity settled fact routes as auto-clearable notification")
    func terminalUnseenActivitySettledRoutesAsAutoClearableNotification() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminalActivity(.unseenActivitySettled(makeSettledActivity()))
            )
        )

        await waitForNotificationCount(
            1,
            in: fixture,
            description: "derived terminal activity should route to inbox"
        )
        #expect(fixture.inboxAtom.notifications[0].kind == .unseenActivity)
        #expect(fixture.inboxAtom.notifications[0].title == "New terminal activity")
        #expect(fixture.inboxAtom.notifications[0].claimKey?.lane == .activity)
        #expect(fixture.inboxAtom.notifications[0].claimKey?.semantic == .unseenActivity)
        #expect(fixture.inboxAtom.notifications[0].claimKey?.sessionId != nil)
        #expect(fixture.inboxAtom.notifications[0].paneId == paneId.uuid)
        #expect(fixture.inboxAtom.notifications[0].isRead == false)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == false)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("focused bottom-pinned pane activity appends no unread PaneInbox notification")
    func focusedBottomPinnedPaneActivityAppendsNoUnreadPaneInboxNotification() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)
        makeWindowKey(fixture.windowLifecycle)
        await waitForAttendedPane(
            paneId.uuid,
            in: fixture,
            description: "focused pane should be attended before derived activity arrives"
        )

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminalActivity(.unseenActivitySettled(makeSettledActivity(isPinnedToBottom: true)))
            )
        )

        await waitForNotificationCount(
            1,
            in: fixture,
            description: "focused derived terminal activity should append read history"
        )
        #expect(fixture.inboxAtom.notifications[0].kind == .unseenActivity)
        #expect(fixture.inboxAtom.notifications[0].isRead == true)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == true)
        #expect(fixture.inboxAtom.globalUnreadCount == 0)
        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [paneId.uuid]) == 0)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("visible sibling scrolled to bottom keeps derived activity unread")
    func visibleSiblingScrolledToBottomKeepsDerivedActivityUnread() async {
        let fixture = await makeFixture()
        let focusedPaneId = PaneId()
        let visibleSiblingPaneId = PaneId()
        let tabId = addTerminalPane(focusedPaneId, to: fixture)
        addVisiblePaneToActiveTab(visibleSiblingPaneId, to: fixture)
        fixture.tabLayout.setActivePane(focusedPaneId.uuid, inTab: tabId)
        makeWindowKey(fixture.windowLifecycle)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: visibleSiblingPaneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 100, bottom: 140, total: 140)))
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: visibleSiblingPaneId,
                event: .terminalActivity(.unseenActivitySettled(makeSettledActivity(isPinnedToBottom: true))),
                seq: 2
            )
        )

        await waitForNotificationCount(
            1,
            in: fixture,
            description: "bottom-pinned visible sibling activity should remain unread until attended"
        )
        #expect(fixture.inboxAtom.notifications[0].isRead == false)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == false)
        #expect(fixture.inboxAtom.globalUnreadCount == 1)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("visible sibling scrolled up keeps derived activity unread")
    func visibleSiblingScrolledUpKeepsDerivedActivityUnread() async {
        let fixture = await makeFixture()
        let focusedPaneId = PaneId()
        let visibleSiblingPaneId = PaneId()
        let tabId = addTerminalPane(focusedPaneId, to: fixture)
        addVisiblePaneToActiveTab(visibleSiblingPaneId, to: fixture)
        fixture.tabLayout.setActivePane(focusedPaneId.uuid, inTab: tabId)
        makeWindowKey(fixture.windowLifecycle)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: visibleSiblingPaneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 40, bottom: 80, total: 140)))
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: visibleSiblingPaneId,
                event: .terminalActivity(.unseenActivitySettled(makeSettledActivity())),
                seq: 2
            )
        )

        await waitForNotificationCount(
            1,
            in: fixture,
            description: "scrolled-up visible sibling activity should remain unread"
        )
        #expect(fixture.inboxAtom.notifications[0].isRead == false)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == false)
        #expect(fixture.inboxAtom.globalUnreadCount == 1)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("repeated unseen activity coalesces into one unread notification")
    func repeatedUnseenActivityCoalescesIntoOneUnreadNotification() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminalActivity(
                    .unseenActivitySettled(makeSettledActivity(burstWindowId: UUID(), rowsAdded: 40)))
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminalActivity(
                    .unseenActivitySettled(makeSettledActivity(burstWindowId: UUID(), rowsAdded: 90))),
                seq: 2
            )
        )

        await assertEventuallyMain("settled unseen activity facts for the same pane should coalesce") {
            fixture.inboxAtom.notifications.count == 1
                && fixture.inboxAtom.notifications[0].activityContext?.eventCount == 2
        }
        #expect(fixture.inboxAtom.notifications[0].kind == .unseenActivity)
        #expect(fixture.inboxAtom.notifications[0].claimKey?.sessionId != nil)
        #expect(fixture.inboxAtom.notifications[0].activityContext?.eventCount == 2)
        #expect(fixture.inboxAtom.notifications[0].activityContext?.rowsAdded == 90)
        #expect(fixture.inboxAtom.globalUnreadCount == 1)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("read dismissed unseen activity row does not absorb a new settled fact")
    func readDismissedUnseenActivityRowDoesNotAbsorbNewSettledFact() async throws {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminalActivity(.unseenActivitySettled(makeSettledActivity(rowsAdded: 40)))
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "first settled unseen activity should route to inbox"
        )
        let firstNotification = try #require(fixture.inboxAtom.notifications.first)
        #expect(fixture.inboxAtom.markRead(id: firstNotification.id) == true)
        #expect(fixture.inboxAtom.dismissFromPaneInbox(id: firstNotification.id) == true)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminalActivity(.unseenActivitySettled(makeSettledActivity(rowsAdded: 90))),
                seq: 2
            )
        )

        await waitForNotificationCount(
            2,
            in: fixture,
            description: "new settled fact after observation should create a fresh unread row"
        )
        #expect(fixture.inboxAtom.notifications[0].isRead == true)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == true)
        #expect(fixture.inboxAtom.notifications[1].isRead == false)
        #expect(fixture.inboxAtom.notifications[1].isDismissedFromPaneInbox == false)
        #expect(fixture.inboxAtom.globalUnreadCount == 1)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    private func addVisiblePaneToActiveTab(
        _ paneId: PaneId,
        to fixture: Fixture
    ) {
        let pane = Pane(
            id: paneId.uuid,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                paneId: paneId,
                contentType: .terminal,
                title: "Terminal"
            )
        )
        fixture.paneAtom.addPane(pane)
        guard let activeTab = fixture.tabLayout.activeTab, let activePaneId = activeTab.activePaneId else {
            Issue.record("Expected active tab and pane before adding visible sibling")
            return
        }
        #expect(
            fixture.tabLayout.insertPane(
                pane.id,
                inTab: activeTab.id,
                at: activePaneId,
                direction: .horizontal,
                position: .after,
                sizingMode: .proportional
            ) == true
        )
    }

    private func makeSettledActivity(
        burstWindowId: UUID = UUID(),
        rowsAdded: Int = 40,
        isPinnedToBottom: Bool = false
    ) -> TerminalSettledActivity {
        TerminalSettledActivity(
            burstWindowId: burstWindowId,
            thresholdRows: 30,
            debounceMilliseconds: 750,
            startedAtMilliseconds: 1000,
            settledAtMilliseconds: 1200,
            eventCount: 1,
            rowsAdded: rowsAdded,
            baselineRows: 100,
            latestRows: 100 + rowsAdded,
            isPinnedToBottom: isPinnedToBottom
        )
    }
}
