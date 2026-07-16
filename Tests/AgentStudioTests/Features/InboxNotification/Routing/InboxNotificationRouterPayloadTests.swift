import Foundation
import Testing

@testable import AgentStudio

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
        let attendedPane: AttendedPaneAtom
    }

    func makeFixture() async -> Fixture {
        let bus = EventBus<RuntimeEnvelope>()
        let inboxAtom = InboxNotificationAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayout = WorkspaceTabLayoutAtom()
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let attendedPane = AttendedPaneAtom(
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
            focusTracker: tracker
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
    func commandFinishedDurationUsesGhosttyNanoseconds() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: paneId,
                event: .terminal(.commandFinished(exitCode: 0, duration: 18_000_000_000))
            )
        )

        await assertEventuallyMain("nanosecond duration should notify") {
            fixture.inboxAtom.notifications.count == 1
        }
        #expect(fixture.inboxAtom.notifications[0].title == "Command finished")
        #expect(fixture.inboxAtom.notifications[0].body == "exit 0 · 18s")
        await stop(fixture)
    }

    @Test("command finished title branches on exit code")
    func commandFinishedTitleBranchesOnExitCode() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: paneId,
                event: .terminal(.commandFinished(exitCode: 1, duration: 18_000_000_000))
            )
        )

        await assertEventuallyMain("failed command should notify") {
            fixture.inboxAtom.notifications.count == 1
        }
        #expect(fixture.inboxAtom.notifications[0].title == "Command failed")
        #expect(fixture.inboxAtom.notifications[0].body == "exit 1 · 18s")
        await stop(fixture)
    }

    @Test("command finished duration renders minute boundary")
    func commandFinishedDurationRendersMinuteBoundary() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            runtimeEnvelope(
                paneId: paneId,
                event: .terminal(.commandFinished(exitCode: 0, duration: 60_000_000_000))
            )
        )

        await assertEventuallyMain("minute boundary should notify") {
            fixture.inboxAtom.notifications.count == 1
        }
        #expect(fixture.inboxAtom.notifications[0].body == "exit 0 · 1m 0s")
        await stop(fixture)
    }

    @Test("command finished ignores implausible duration payloads")
    func commandFinishedIgnoresImplausibleDurationPayloads() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
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

        await assertEventuallyMain("sentinel event should prove the router drained prior events") {
            fixture.inboxAtom.notifications.count >= 1
        }
        #expect(fixture.inboxAtom.notifications.map(\.title) == ["Sentinel"])
        await stop(fixture)
    }

    @Test("blank desktop notification title promotes body preview")
    func blankDesktopNotificationTitlePromotesBodyPreview() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
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

        await assertEventuallyMain("blank title should still create a readable notification") {
            fixture.inboxAtom.notifications.count == 1
        }
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
            panes: [pane.id],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: pane.id
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

    private func stop(_ fixture: Fixture) async {
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
    }
}
