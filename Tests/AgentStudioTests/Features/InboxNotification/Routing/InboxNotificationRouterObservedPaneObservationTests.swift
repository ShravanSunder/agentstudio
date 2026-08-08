import AgentStudioCore
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioInboxNotification

@MainActor
private final class DrawerViewReadRecorder {
    private(set) var readCount = 0

    func record() {
        readCount += 1
    }
}

extension InboxNotificationRouterObservedPaneTests {
    @Test("current-surface observation ignores pane titles and refreshes for membership")
    func currentSurfaceObservationIsTitleInsensitive() async throws {
        let drawerViewReadRecorder = DrawerViewReadRecorder()
        let fixture = await makeFixture(
            startRouter: false,
            onDrawerViewRead: { _ in
                drawerViewReadRecorder.record()
            }
        )
        let parentPaneId = PaneId.generateUUIDv7()
        let tabId = addTerminalPane(parentPaneId, to: fixture)
        let drawerPane = try #require(
            fixture.paneAtom.addDrawerPane(
                to: parentPaneId.uuid,
                parentFallbackCWD: nil,
                zmxSessionID: .generateUUIDv7()
            )
        )
        let drawerId = try #require(
            fixture.paneAtom.graphAtom.paneStructuralFacts(parentPaneId.uuid)?.ownedDrawerID
        )
        fixture.tabLayout.arrangementAtom.addDrawerPaneView(
            drawerId: drawerId,
            parentPaneId: parentPaneId.uuid,
            drawerPaneId: drawerPane.id,
            inTab: tabId
        )
        makeWindowKey(fixture.windowLifecycle)
        await fixture.router.start()
        for _ in 0..<20 {
            await Task.yield()
        }
        let baselineReadCount = drawerViewReadRecorder.readCount

        fixture.paneAtom.updatePaneTitle(parentPaneId.uuid, title: "Updated title")
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(drawerViewReadRecorder.readCount == baselineReadCount)

        addVisiblePaneToActiveTab(.generateUUIDv7(), to: fixture)
        await assertEventuallyMain("pane membership should refresh current-surface observation") {
            drawerViewReadRecorder.readCount > baselineReadCount
        }
        await stop(fixture)
    }
}
