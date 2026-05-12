import Foundation
import Testing

@testable import AgentStudio

@MainActor
extension InboxNotificationRouterTests {
    @Test("desktopNotificationRequested records pane ordinal without duplicating runtime label")
    func desktopNotificationRequestedRecordsPaneOrdinalWithoutDuplicatingRuntimeLabel() async {
        let fixture = await makeFixture()
        let firstPaneId = PaneId()
        let secondPaneId = PaneId()
        addTerminalPaneWithoutTab(firstPaneId, to: fixture)
        addTerminalPaneWithoutTab(secondPaneId, to: fixture)
        fixture.tabLayout.appendTab(makeTab(paneIds: [firstPaneId.uuid, secondPaneId.uuid]))

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: secondPaneId,
                event: .terminal(.desktopNotificationRequested(title: "Done", body: "exit 0"))
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "desktop notification should include routed pane placement"
        )

        let notification = fixture.inboxAtom.notifications[0]
        let display = InboxNotificationSourceDisplay(notification: notification)
        #expect(notification.tabDisplayLabel == "Tab 1")
        #expect(notification.paneDisplayLabel == nil)
        #expect(notification.paneOrdinal == 2)
        #expect(display.placementLine == "Tab 1 · Pane 2 · Terminal")
        #expect(display.placementLine?.contains("Terminal · Terminal") == false)
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    func addTerminalPaneWithoutTab(
        _ paneId: PaneId,
        to fixture: Fixture,
        repoId: UUID? = nil,
        worktreeId: UUID? = nil
    ) {
        let facets = PaneContextFacets(
            repoId: repoId,
            repoName: repoId.map { "Repo-\($0.uuidString.prefix(4))" },
            worktreeId: worktreeId,
            worktreeName: worktreeId.map { "Worktree-\($0.uuidString.prefix(4))" }
        )
        let metadata = PaneMetadata(
            paneId: paneId,
            contentType: .terminal,
            source: .floating(launchDirectory: nil, title: nil),
            title: "Terminal",
            facets: facets,
            checkoutRef: "main"
        )
        fixture.paneAtom.addPane(
            Pane(
                id: paneId.uuid,
                content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
                metadata: metadata
            )
        )
    }
}
