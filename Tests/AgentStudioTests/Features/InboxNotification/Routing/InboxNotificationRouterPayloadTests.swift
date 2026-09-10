import AgentStudioCore
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioInboxNotification

@MainActor
@Suite("InboxNotificationRouter payload contract", .serialized)
struct InboxNotificationRouterPayloadTests {
    struct Fixture {
        let bus: EventBus<RuntimeEnvelope>
        let inboxAtom: InboxNotificationAtom
        let paneAtom: WorkspacePaneAtom
        let tabLayout: WorkspaceTabLayoutAtom
        let router: InboxNotificationRouter
        let tracker: PaneFocusTracker
        let attendedPane: AttendedPaneDerived
    }

    func makeFixture() async -> Fixture {
        let bus = EventBus<RuntimeEnvelope>()
        let inboxAtom = InboxNotificationAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayout = WorkspaceTabLayoutAtom()
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let attendedPane = AttendedPaneDerived(
            tabLayout: tabLayout,
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer
        )
        let tracker = PaneFocusTracker(attendedPane: attendedPane)
        let router = InboxNotificationRouter(
            bus: bus,
            inboxAtom: inboxAtom,
            prefsAtom: InboxNotificationPrefsAtom(),
            paneAtom: paneAtom,
            tabLayout: tabLayout,
            attendedPane: attendedPane,
            focusTracker: tracker,
            terminalIsPinnedToBottom: { _ in false },
            terminalPinnedStateSnapshot: { [:] }
        )
        await router.start()
        return Fixture(
            bus: bus,
            inboxAtom: inboxAtom,
            paneAtom: paneAtom,
            tabLayout: tabLayout,
            router: router,
            tracker: tracker,
            attendedPane: attendedPane
        )
    }

    @Test("command finished duration uses Ghostty nanoseconds")
    func commandFinishedDurationUsesGhosttyNanoseconds() async throws {
        let fixture = await makeFixture()
        let paneId = PaneId.generateUUIDv7()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: paneId,
                event: .terminal(.commandFinished(exitCode: 0, duration: 18_000_000_000))
            )
        )

        try #require(
            await waitForNotificationState { fixture.inboxAtom.notifications.count == 1 },
            "nanosecond duration should notify"
        )
        #expect(fixture.inboxAtom.notifications[0].title == "Command finished")
        #expect(fixture.inboxAtom.notifications[0].body == "exit 0 · 18s")
        await stop(fixture)
    }

    @Test("command finished title branches on exit code")
    func commandFinishedTitleBranchesOnExitCode() async throws {
        let fixture = await makeFixture()
        let paneId = PaneId.generateUUIDv7()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: paneId,
                event: .terminal(.commandFinished(exitCode: 1, duration: 18_000_000_000))
            )
        )

        try #require(
            await waitForNotificationState { fixture.inboxAtom.notifications.count == 1 },
            "failed command should notify"
        )
        #expect(fixture.inboxAtom.notifications[0].title == "Command failed")
        #expect(fixture.inboxAtom.notifications[0].body == "exit 1 · 18s")
        await stop(fixture)
    }

    @Test("command finished duration renders minute boundary")
    func commandFinishedDurationRendersMinuteBoundary() async throws {
        let fixture = await makeFixture()
        let paneId = PaneId.generateUUIDv7()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: paneId,
                event: .terminal(.commandFinished(exitCode: 0, duration: 60_000_000_000))
            )
        )

        try #require(
            await waitForNotificationState { fixture.inboxAtom.notifications.count == 1 },
            "minute boundary should notify"
        )
        #expect(fixture.inboxAtom.notifications[0].body == "exit 0 · 1m 0s")
        await stop(fixture)
    }

    @Test("command finished ignores implausible duration payloads")
    func commandFinishedIgnoresImplausibleDurationPayloads() async throws {
        let fixture = await makeFixture()
        let paneId = PaneId.generateUUIDv7()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: paneId,
                event: .terminal(.commandFinished(exitCode: 0, duration: UInt64.max))
            )
        )
        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: paneId,
                event: .agentNotificationRequested(title: "Sentinel", body: nil),
                seq: 2
            )
        )

        try #require(
            await waitForNotificationState {
                fixture.inboxAtom.notifications.map(\.title) == ["Sentinel"]
            },
            "sentinel event should prove the router drained prior events"
        )
        #expect(fixture.inboxAtom.notifications.map(\.title) == ["Sentinel"])
        await stop(fixture)
    }

    @Test("blank desktop notification title promotes body preview")
    func blankDesktopNotificationTitlePromotesBodyPreview() async throws {
        let fixture = await makeFixture()
        let paneId = PaneId.generateUUIDv7()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: paneId,
                event: .terminal(
                    .desktopNotificationRequested(
                        title: "   ",
                        body: "Agent output changed while you were away"
                    )
                )
            )
        )

        try #require(
            await waitForNotificationState { fixture.inboxAtom.notifications.count == 1 },
            "blank title should still create a readable notification"
        )
        #expect(fixture.inboxAtom.notifications[0].title == "Agent output changed while you were away")
        #expect(fixture.inboxAtom.notifications[0].body == nil)
        await stop(fixture)
    }

    private func addTerminalPane(
        _ paneId: PaneId,
        to fixture: Fixture
    ) -> UUID {
        let metadata = PaneMetadata(
            paneId: paneId,
            contentType: .terminal,
            title: "Terminal"
        )
        let pane = Pane(
            id: paneId.uuid,
            content: .terminal(
                TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())
            ),
            metadata: metadata
        )
        fixture.paneAtom.addPane(pane)

        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: pane.id)
        )
        let tab = Tab(
            name: "Tab",
            allPaneIds: [pane.id],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )
        fixture.tabLayout.appendTab(tab)
        return tab.id
    }

    private func runtimeEnvelope(
        paneId: PaneId,
        event: PaneRuntimeEvent,
        seq: UInt64 = 1
    ) -> RuntimeEnvelope {
        .pane(.test(event: event, paneId: paneId, paneKind: .terminal, seq: seq))
    }

    private func waitForNotificationState(
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return condition()
    }

    private func stop(_ fixture: Fixture) async {
        await fixture.router.stop()
        await fixture.tracker.stop()
    }
}
