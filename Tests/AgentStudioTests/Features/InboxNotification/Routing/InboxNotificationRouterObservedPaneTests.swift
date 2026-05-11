import Foundation
import Testing

@testable import AgentStudio

@MainActor
extension InboxNotificationRouterTests {
    @Test("attended pane scrolling back to bottom auto-clears passive pane notifications")
    func attendedPaneScrollingBackToBottomAutoClearsPassivePaneNotifications() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)
        fixture.terminalActivityAtom.consume(
            PaneEnvelope.test(
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 0, bottom: 20, total: 100))),
                paneId: paneId,
                paneKind: .terminal
            )
        )

        fixture.inboxAtom.append(
            InboxNotification(
                id: UUID(),
                timestamp: Date(),
                kind: .bellRang,
                title: "Bell",
                body: nil,
                source: .pane(.init(paneId: paneId.uuid)),
                isRead: false,
                isDismissedFromPaneInbox: false
            )
        )
        makeWindowKey(fixture.windowLifecycle)
        await assertEventuallyMain("pane should be attended") {
            fixture.attendedPane.attendedPaneId == paneId.uuid
        }
        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [paneId.uuid]) == 1)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100)))
            )
        )
        await assertEventuallyMain("scrolling to bottom should clear pane inbox unread state") {
            fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [paneId.uuid]) == 0
        }

        #expect(fixture.inboxAtom.notifications[0].isRead)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("unattended pane at bottom keeps pane inbox notifications unread")
    func unattendedPaneAtBottomKeepsPaneInboxNotificationsUnread() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        fixture.inboxAtom.append(
            InboxNotification(
                id: UUID(),
                timestamp: Date(),
                kind: .bellRang,
                title: "Bell",
                body: nil,
                source: .pane(.init(paneId: paneId.uuid)),
                isRead: false,
                isDismissedFromPaneInbox: false
            )
        )

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100)))
            )
        )
        await Task.yield()

        #expect(fixture.attendedPane.attendedPaneId == nil)
        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [paneId.uuid]) == 1)
        #expect(fixture.inboxAtom.notifications[0].isRead == false)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == false)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("focus gained keeps action-required notifications visible even when source is pinned to bottom")
    func focusGainedKeepsActionRequiredNotificationsVisibleWhenSourceIsPinnedToBottom() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)
        fixture.terminalActivityAtom.consume(
            PaneEnvelope.test(
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100))),
                paneId: paneId,
                paneKind: .terminal
            )
        )

        fixture.inboxAtom.append(
            InboxNotification(
                id: UUID(),
                timestamp: Date(),
                kind: .approvalRequested,
                title: "Approval requested",
                body: nil,
                source: .pane(.init(paneId: paneId.uuid)),
                isRead: false,
                isDismissedFromPaneInbox: false
            )
        )

        await Task.yield()
        makeWindowKey(fixture.windowLifecycle)
        await assertEventuallyMain("focus gain should mark pane attended") {
            fixture.attendedPane.attendedPaneId == paneId.uuid
        }

        #expect(fixture.inboxAtom.unreadCount(forPaneId: paneId.uuid) == 1)
        #expect(fixture.inboxAtom.notifications[0].isRead == false)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == false)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("observed pane appends passive notifications already read and hidden from pane inbox")
    func observedPaneAppendsPassiveNotificationsAlreadyReadAndHiddenFromPaneInbox() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)
        fixture.terminalActivityAtom.consume(
            PaneEnvelope.test(
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100))),
                paneId: paneId,
                paneKind: .terminal
            )
        )

        await Task.yield()
        makeWindowKey(fixture.windowLifecycle)
        await assertEventuallyMain("pane should be attended") {
            fixture.attendedPane.attendedPaneId == paneId.uuid
        }

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.desktopNotificationRequested(title: "Done", body: "exit 0"))
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "observed passive notification should still be logged"
        )

        #expect(fixture.inboxAtom.notifications[0].isRead)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox)
        #expect(fixture.inboxAtom.globalUnreadCount == 0)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("observed pane uses same stream pinned state for immediate passive notifications")
    func observedPaneUsesSameStreamPinnedStateForImmediatePassiveNotifications() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        makeWindowKey(fixture.windowLifecycle)
        await assertEventuallyMain("pane should be attended") {
            fixture.attendedPane.attendedPaneId == paneId.uuid
        }

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100))),
                seq: 1
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.desktopNotificationRequested(title: "Done", body: "exit 0")),
                seq: 2
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "immediate passive notification should still be logged"
        )

        #expect(fixture.inboxAtom.notifications[0].isRead)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox)
        #expect(fixture.inboxAtom.globalUnreadCount == 0)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("observed commandFinished appends read dismissed history row")
    func observedCommandFinishedAppendsReadDismissedHistoryRow() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)
        fixture.terminalActivityAtom.consume(
            PaneEnvelope.test(
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100))),
                paneId: paneId,
                paneKind: .terminal
            )
        )

        await Task.yield()
        makeWindowKey(fixture.windowLifecycle)
        await assertEventuallyMain("pane should be attended") {
            fixture.attendedPane.attendedPaneId == paneId.uuid
        }

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.commandFinished(exitCode: 0, duration: 20_000_000_000))
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "observed command finished should still be logged"
        )

        #expect(fixture.inboxAtom.notifications[0].kind == .commandFinished)
        #expect(fixture.inboxAtom.notifications[0].body == "exit 0 · 20s")
        #expect(fixture.inboxAtom.notifications[0].isRead)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox)
        #expect(fixture.inboxAtom.globalUnreadCount == 0)
        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [paneId.uuid]) == 0)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("observed pane keeps action-required notifications unread")
    func observedPaneKeepsActionRequiredNotificationsUnread() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)
        fixture.terminalActivityAtom.consume(
            PaneEnvelope.test(
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100))),
                paneId: paneId,
                paneKind: .terminal
            )
        )

        await Task.yield()
        makeWindowKey(fixture.windowLifecycle)
        await assertEventuallyMain("pane should be attended") {
            fixture.attendedPane.attendedPaneId == paneId.uuid
        }

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .artifact(.approvalRequested(request: ApprovalRequest(id: UUID(), summary: "Need approval")))
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "observed action-required notification should be logged"
        )

        #expect(fixture.inboxAtom.notifications[0].isRead == false)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == false)
        #expect(fixture.inboxAtom.globalUnreadCount == 1)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("observed secure input still creates unread pane inbox notification")
    func observedSecureInputStillCreatesUnreadPaneInboxNotification() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)
        fixture.terminalActivityAtom.consume(
            PaneEnvelope.test(
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 80, bottom: 100, total: 100))),
                paneId: paneId,
                paneKind: .terminal
            )
        )

        makeWindowKey(fixture.windowLifecycle)
        await assertEventuallyMain("pane should be attended") {
            fixture.attendedPane.attendedPaneId == paneId.uuid
        }

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.secureInputChanged(true))
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "observed secure input should still route as action-required"
        )

        #expect(fixture.inboxAtom.notifications[0].kind == .terminalSecureInputRequested)
        #expect(fixture.inboxAtom.notifications[0].isRead == false)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == false)
        #expect(fixture.inboxAtom.globalUnreadCount == 1)
        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [paneId.uuid]) == 1)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }
}
