import Foundation
import Testing

@testable import AgentStudio

@MainActor
extension InboxNotificationRouterTests {
    @Test("commandFinished notifies for drawer child while owning parent pane is attended")
    func commandFinishedNotifiesForDrawerChildOfAttendedParentPane() async throws {
        let fixture = await makeFixture()

        let parentPaneId = PaneId()
        _ = addTerminalPane(parentPaneId, to: fixture)
        let drawerPane = try #require(
            fixture.paneAtom.addDrawerPane(to: parentPaneId.uuid, parentFallbackCWD: nil)
        )
        makeWindowKey(fixture.windowLifecycle)
        await Task.yield()
        #expect(fixture.attendedPane.attendedPaneId == parentPaneId.uuid)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: PaneId(uuid: drawerPane.id),
                event: .terminal(.commandFinished(exitCode: 0, duration: 20_000_000_000))
            )
        )

        await waitForNotificationCount(
            1,
            in: fixture,
            description: "hidden drawer child command finish should route to parent pane inbox"
        )
        #expect(fixture.inboxAtom.notifications[0].kind == .commandFinished)
        #expect(fixture.inboxAtom.notifications[0].paneId == drawerPane.id)
        #expect(fixture.inboxAtom.notifications[0].isRead == false)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == false)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("desktop notification from drawer child remains visible in parent pane inbox scope")
    func drawerChildDesktopNotificationRemainsVisibleInParentPaneInboxScope() async throws {
        let fixture = await makeFixture()

        let parentPaneId = PaneId()
        _ = addTerminalPane(parentPaneId, to: fixture)
        let drawerPane = try #require(
            fixture.paneAtom.addDrawerPane(to: parentPaneId.uuid, parentFallbackCWD: nil)
        )

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: PaneId(uuid: drawerPane.id),
                event: .terminal(.desktopNotificationRequested(title: "Gemini", body: "waiting for input"))
            )
        )

        await waitForNotificationCount(
            1,
            in: fixture,
            description: "drawer child desktop notification should be routed"
        )

        let scope = PaneInboxScopeResolver.resolve(
            anchorPaneId: parentPaneId.uuid,
            pane: { fixture.paneAtom.pane($0) }
        )
        let visiblePaneInboxNotifications = PaneInboxNotificationPopover.relevantNotifications(
            paneIds: scope.paneIds,
            notifications: fixture.inboxAtom.notifications
        )

        #expect(scope.parentPaneId == parentPaneId.uuid)
        #expect(scope.paneIds == [parentPaneId.uuid, drawerPane.id])
        #expect(visiblePaneInboxNotifications.map(\.paneId) == [drawerPane.id])
        #expect(visiblePaneInboxNotifications.map(\.title) == ["Gemini"])
        #expect(visiblePaneInboxNotifications.first?.isRead == false)
        #expect(visiblePaneInboxNotifications.first?.isDismissedFromPaneInbox == false)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("focus-gained on parent pane keeps drawer-child pane inbox notifications visible")
    func focusGainedOnParentPaneDoesNotDismissDrawerChildPaneInboxNotifications() async throws {
        let fixture = await makeFixture()
        let parentPaneId = PaneId()
        _ = addTerminalPane(parentPaneId, to: fixture)
        let drawerPane = try #require(
            fixture.paneAtom.addDrawerPane(to: parentPaneId.uuid, parentFallbackCWD: nil)
        )

        fixture.inboxAtom.append(
            InboxNotification(
                id: UUID(),
                timestamp: Date(),
                kind: .commandFinished,
                title: "Done",
                body: nil,
                source: .pane(.init(paneId: drawerPane.id)),
                isRead: false,
                isDismissedFromPaneInbox: false
            )
        )

        await Task.yield()
        makeWindowKey(fixture.windowLifecycle)
        await assertEventuallyMain("focus gain should mark parent as attended") {
            fixture.attendedPane.attendedPaneId == parentPaneId.uuid
        }

        #expect(fixture.inboxAtom.notifications[0].paneId == drawerPane.id)
        #expect(fixture.inboxAtom.notifications[0].isRead == false)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromPaneInbox == false)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }
}
