import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioInboxNotification

@MainActor
extension InboxNotificationRouterObservedPaneTests {
    @Test("entering Zoom clears a bottom-pinned minimized source without focus or layout mutation")
    func enteringZoomClearsBottomPinnedMinimizedSourceWithoutFocusOrLayoutMutation() async throws {
        let fixture = await makeFixture(startRouter: false)
        let attendedPaneId = PaneId.generateUUIDv7()
        let zoomSourcePaneId = PaneId.generateUUIDv7()
        let tabId = addTerminalPane(attendedPaneId, to: fixture)
        addVisiblePaneToActiveTab(zoomSourcePaneId, to: fixture)
        #expect(fixture.tabLayout.minimizePane(zoomSourcePaneId.uuid, inTab: tabId))
        makeWindowKey(fixture.windowLifecycle)
        await consumeFocusGain(attendedPaneId.uuid, from: fixture.tracker)
        fixture.inboxAtom.append(
            makeNotification(kind: .agentDesktopNotification, paneId: zoomSourcePaneId.uuid)
        )
        fixture.terminalPinnedState.setPinnedToBottom(
            true,
            paneId: zoomSourcePaneId.uuid
        )
        await fixture.router.start()
        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [zoomSourcePaneId.uuid]) == 1)

        fixture.tabLayout.arrangementAtom.presentationAtom.enterZoom(
            inTab: tabId,
            sourcePaneId: zoomSourcePaneId.uuid,
            viewerPresentation: .unavailable
        )

        await assertEventuallyMain("entering Zoom should observe and clear the minimized source pane") {
            fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [zoomSourcePaneId.uuid]) == 0
        }
        await stop(fixture)
    }

    @Test("canceling Zoom clears a newly visible bottom-pinned sibling without focus or layout mutation")
    func cancelingZoomClearsNewlyVisibleBottomPinnedSiblingWithoutFocusOrLayoutMutation() async {
        let fixture = await makeFixture(startRouter: false)
        let zoomSourcePaneId = PaneId.generateUUIDv7()
        let visibleSiblingPaneId = PaneId.generateUUIDv7()
        let tabId = addTerminalPane(zoomSourcePaneId, to: fixture)
        addVisiblePaneToActiveTab(visibleSiblingPaneId, to: fixture)
        fixture.tabLayout.arrangementAtom.presentationAtom.enterZoom(
            inTab: tabId,
            sourcePaneId: zoomSourcePaneId.uuid,
            viewerPresentation: .unavailable
        )
        makeWindowKey(fixture.windowLifecycle)
        await consumeFocusGain(visibleSiblingPaneId.uuid, from: fixture.tracker)
        fixture.inboxAtom.append(
            makeNotification(kind: .agentDesktopNotification, paneId: visibleSiblingPaneId.uuid)
        )
        fixture.terminalPinnedState.setPinnedToBottom(
            true,
            paneId: visibleSiblingPaneId.uuid
        )
        await fixture.router.start()
        #expect(fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [visibleSiblingPaneId.uuid]) == 1)

        fixture.tabLayout.arrangementAtom.presentationAtom.cancelZoom(inTab: tabId)

        await assertEventuallyMain("canceling Zoom should observe and clear the newly visible sibling pane") {
            fixture.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [visibleSiblingPaneId.uuid]) == 0
        }
        await stop(fixture)
    }

    private func consumeFocusGain(
        _ expectedPaneId: UUID,
        from tracker: PaneFocusTracker
    ) async {
        var observedPaneId: UUID?
        let consumer = Task { @MainActor in
            var iterator = tracker.focusGainedStream.makeAsyncIterator()
            observedPaneId = await iterator.next()
        }
        await assertEventuallyMain("baseline focus gain should be consumed before router startup") {
            observedPaneId != nil
        }
        consumer.cancel()
        await consumer.value
        #expect(observedPaneId == expectedPaneId)
    }
}
