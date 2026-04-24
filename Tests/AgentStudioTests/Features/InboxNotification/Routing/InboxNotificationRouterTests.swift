import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxNotificationRouter routing contract", .serialized)
struct InboxNotificationRouterTests {
    struct Fixture {
        let bus: EventBus<RuntimeEnvelope>
        let inboxAtom: InboxNotificationAtom
        let prefsAtom: InboxNotificationPrefsAtom
        let paneAtom: WorkspacePaneAtom
        let tabLayout: WorkspaceTabLayoutAtom
        let windowLifecycle: WindowLifecycleAtom
        let managementLayer: ManagementLayerAtom
        let attendedPane: AttendedPaneAtom
        let tracker: PaneFocusTracker
        let router: InboxNotificationRouter
    }

    private func makeFixture() async -> Fixture {
        let bus = EventBus<RuntimeEnvelope>()
        let inboxAtom = InboxNotificationAtom()
        let prefsAtom = InboxNotificationPrefsAtom()
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
            prefsAtom: prefsAtom,
            paneAtom: paneAtom,
            tabLayout: tabLayout,
            attendedPane: attendedPane,
            focusTracker: tracker
        )
        await router.start()

        return Fixture(
            bus: bus,
            inboxAtom: inboxAtom,
            prefsAtom: prefsAtom,
            paneAtom: paneAtom,
            tabLayout: tabLayout,
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer,
            attendedPane: attendedPane,
            tracker: tracker,
            router: router
        )
    }

    private func makeWindowKey(_ atom: WindowLifecycleAtom) {
        let id = UUID()
        atom.recordWindowRegistered(id)
        atom.recordWindowBecameKey(id)
    }

    private func addTerminalPane(
        _ paneId: PaneId,
        to fixture: Fixture,
        repoId: UUID? = nil,
        worktreeId: UUID? = nil
    ) -> UUID {
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
        let pane = Pane(
            id: paneId.uuid,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: metadata
        )
        fixture.paneAtom.addPane(pane)

        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: pane.id),
            visiblePaneIds: [pane.id]
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

    private func makePaneEnvelope(
        paneId: PaneId,
        event: PaneRuntimeEvent,
        seq: UInt64 = 1
    ) -> RuntimeEnvelope {
        .pane(
            .test(
                event: event,
                paneId: paneId,
                paneKind: .terminal,
                seq: seq
            )
        )
    }

    private func waitForNotificationCount(
        _ count: Int,
        in fixture: Fixture,
        description: String
    ) async {
        await assertEventuallyMain(description) {
            fixture.inboxAtom.notifications.count == count
        }
    }

    @Test("desktopNotificationRequested posts an inbox notification")
    func desktopNotificationRequested() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.desktopNotificationRequested(title: "Done", body: "exit 0"))
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "desktop notification should be routed"
        )

        #expect(fixture.inboxAtom.notifications.count == 1)
        #expect(fixture.inboxAtom.notifications[0].kind == .agentDesktopNotification)
        #expect(fixture.inboxAtom.notifications[0].title == "Done")
        #expect(fixture.inboxAtom.notifications[0].body == "exit 0")
        #expect(fixture.inboxAtom.notifications[0].paneId == paneId.uuid)
        fixture.router.stop()
        fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("bell is gated by prefs")
    func bellIsGated() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(makePaneEnvelope(paneId: paneId, event: .terminal(.bellRang)))

        fixture.prefsAtom.setBellEnabled(true)
        _ = await fixture.bus.post(makePaneEnvelope(paneId: paneId, event: .terminal(.bellRang), seq: 2))
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "enabled bell should be routed once"
        )
        #expect(fixture.inboxAtom.notifications.count == 1)
        #expect(fixture.inboxAtom.notifications[0].kind == .bellRang)
        fixture.router.stop()
        fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("commandFinished only notifies for unfocused long-running commands")
    func commandFinishedGating() async {
        let fixture = await makeFixture()
        makeWindowKey(fixture.windowLifecycle)

        let focusedPaneId = PaneId()
        _ = addTerminalPane(focusedPaneId, to: fixture)
        await Task.yield()

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: focusedPaneId,
                event: .terminal(.commandFinished(exitCode: 0, duration: 20))
            )
        )

        let unfocusedPaneId = PaneId()
        _ = addTerminalPane(unfocusedPaneId, to: fixture)
        fixture.tabLayout.setActiveTab(fixture.tabLayout.tabs.first?.id)
        await Task.yield()

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: unfocusedPaneId,
                event: .terminal(.commandFinished(exitCode: 0, duration: 3)),
                seq: 2
            )
        )

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: unfocusedPaneId,
                event: .terminal(.commandFinished(exitCode: 1, duration: 15)),
                seq: 3
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "unattended long-running command should be routed once"
        )
        #expect(fixture.inboxAtom.notifications.count == 1)
        #expect(fixture.inboxAtom.notifications[0].kind == .commandFinished)
        #expect(fixture.inboxAtom.notifications[0].paneId == unfocusedPaneId.uuid)
        fixture.router.stop()
        fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("commandFinished uses attended pane instead of active tab for focus gating")
    func commandFinishedUsesAttendedPaneForFocusGating() async {
        let fixture = await makeFixture()

        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)
        #expect(fixture.tabLayout.activeTab?.activePaneId == paneId.uuid)
        #expect(fixture.attendedPane.attendedPaneId == nil)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.commandFinished(exitCode: 0, duration: 20))
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "unattended active pane should route while window is not key"
        )

        #expect(fixture.inboxAtom.notifications.count == 1)
        if fixture.inboxAtom.notifications.count == 1 {
            #expect(fixture.inboxAtom.notifications[0].kind == .commandFinished)
        }
        fixture.router.stop()
        fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("approvalRequested and selected security alerts notify")
    func approvalAndSecurityRouting() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        let repoId = UUID()
        let worktreeId = UUID()
        _ = addTerminalPane(paneId, to: fixture, repoId: repoId, worktreeId: worktreeId)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .artifact(.approvalRequested(request: ApprovalRequest(id: UUID(), summary: "Need approval")))
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .security(.sandboxHealthChanged(healthy: false)),
                seq: 2
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .security(.sandboxHealthChanged(healthy: false)),
                seq: 3
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.progressReportUpdated(nil)),
                seq: 4
            )
        )
        await waitForNotificationCount(
            2,
            in: fixture,
            description: "approval and sandbox health should be routed"
        )

        #expect(fixture.inboxAtom.notifications.count == 2)
        #expect(fixture.inboxAtom.notifications[0].kind == .approvalRequested)
        #expect(fixture.inboxAtom.notifications[1].kind == .securityEvent)
        #expect(fixture.inboxAtom.notifications[1].repoId == repoId)
        #expect(fixture.inboxAtom.notifications[1].worktreeId == worktreeId)
        fixture.router.stop()
        fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("sandbox health unhealthy edge is tracked per pane and reset on stop")
    func sandboxHealthEdgesArePerPaneAndResetOnStop() async {
        let fixture = await makeFixture()
        let firstPaneId = PaneId()
        let secondPaneId = PaneId()
        _ = addTerminalPane(firstPaneId, to: fixture)
        _ = addTerminalPane(secondPaneId, to: fixture)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: firstPaneId,
                event: .security(.sandboxHealthChanged(healthy: false))
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: secondPaneId,
                event: .security(.sandboxHealthChanged(healthy: false)),
                seq: 2
            )
        )
        await waitForNotificationCount(
            2,
            in: fixture,
            description: "each pane should route its own unhealthy edge"
        )

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: secondPaneId,
                event: .security(.sandboxHealthChanged(healthy: false)),
                seq: 3
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: firstPaneId,
                event: .security(.sandboxHealthChanged(healthy: true)),
                seq: 4
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: firstPaneId,
                event: .security(.sandboxHealthChanged(healthy: false)),
                seq: 5
            )
        )
        await waitForNotificationCount(
            3,
            in: fixture,
            description: "healthy transition should arm only that pane's next unhealthy edge"
        )

        fixture.router.stop()
        await fixture.router.start()
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: secondPaneId,
                event: .security(.sandboxHealthChanged(healthy: false)),
                seq: 6
            )
        )
        await waitForNotificationCount(
            4,
            in: fixture,
            description: "router restart should reset sandbox edge state"
        )

        fixture.router.stop()
        fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("progress error notifies on error edge and rearms after non-error progress")
    func progressErrorNotifiesOnErrorEdgeAndRearms() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.progressReportUpdated(ProgressState(kind: .set, percent: 40)))
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.progressReportUpdated(ProgressState(kind: .error, percent: 80))),
                seq: 2
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.progressReportUpdated(ProgressState(kind: .error, percent: 90))),
                seq: 3
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "first progress error edge should notify once"
        )

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.progressReportUpdated(nil)),
                seq: 4
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.progressReportUpdated(ProgressState(kind: .error, percent: nil))),
                seq: 5
            )
        )
        await waitForNotificationCount(
            2,
            in: fixture,
            description: "progress remove should rearm next progress error edge"
        )

        #expect(fixture.inboxAtom.notifications.map(\.kind) == [.terminalProgressError, .terminalProgressError])
        #expect(fixture.inboxAtom.notifications[0].body == "progress 80%")
        fixture.router.stop()
        fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("secure input true notifies once and rearms after false")
    func secureInputTrueNotifiesOnceAndRearmsAfterFalse() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.secureInputChanged(true))
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.secureInputChanged(true)),
                seq: 2
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "first secure input true edge should notify once"
        )

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.secureInputChanged(false)),
                seq: 3
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.secureInputChanged(true)),
                seq: 4
            )
        )
        await waitForNotificationCount(
            2,
            in: fixture,
            description: "secure input false should rearm the next true edge"
        )

        #expect(
            fixture.inboxAtom.notifications.map(\.kind) == [
                .terminalSecureInputRequested,
                .terminalSecureInputRequested,
            ])
        #expect(fixture.inboxAtom.notifications[0].title == "Secure input requested")
        fixture.router.stop()
        fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("renderer unhealthy notifies on unhealthy edge per pane")
    func rendererUnhealthyNotifiesOnUnhealthyEdgePerPane() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.rendererHealthChanged(healthy: false))
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.rendererHealthChanged(healthy: false)),
                seq: 2
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "first renderer unhealthy edge should notify once"
        )

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.rendererHealthChanged(healthy: true)),
                seq: 3
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.rendererHealthChanged(healthy: false)),
                seq: 4
            )
        )
        await waitForNotificationCount(
            2,
            in: fixture,
            description: "healthy renderer transition should rearm next unhealthy edge"
        )

        #expect(
            fixture.inboxAtom.notifications.map(\.kind) == [.terminalRendererUnhealthy, .terminalRendererUnhealthy])
        #expect(fixture.inboxAtom.notifications[0].title == "Terminal renderer unhealthy")
        fixture.router.stop()
        fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("pane closed prunes edge detector state for reused pane identifiers")
    func paneClosedPrunesEdgeDetectorState() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.rendererHealthChanged(healthy: false))
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "first unhealthy edge should notify"
        )

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .lifecycle(.paneClosed),
                seq: 2
            )
        )
        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.rendererHealthChanged(healthy: false)),
                seq: 3
            )
        )

        await waitForNotificationCount(
            2,
            in: fixture,
            description: "closed pane should re-enter with fresh renderer edge state"
        )

        #expect(
            fixture.inboxAtom.notifications.map(\.kind) == [
                .terminalRendererUnhealthy,
                .terminalRendererUnhealthy,
            ])
        fixture.router.stop()
        fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("focus-gained marks pane notifications read and dismissed from drawer")
    func focusGainedClearsUnread() async {
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
                isDismissedFromDrawer: false
            )
        )
        #expect(fixture.inboxAtom.unreadCount(forPaneId: paneId.uuid) == 1)

        await Task.yield()
        makeWindowKey(fixture.windowLifecycle)
        await assertEventuallyMain("focus gain should mark pane notification read") {
            fixture.inboxAtom.unreadCount(forPaneId: paneId.uuid) == 0
                && fixture.inboxAtom.notifications[0].isDismissedFromDrawer
        }

        #expect(fixture.inboxAtom.unreadCount(forPaneId: paneId.uuid) == 0)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromDrawer)
        fixture.router.stop()
        fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("agent notification requests become agentRpc inbox rows")
    func agentNotificationRequested() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .agentNotificationRequested(title: "Claude Code finished", body: "3 files changed")
            )
        )
        await waitForNotificationCount(
            1,
            in: fixture,
            description: "agent notification should be routed"
        )

        #expect(fixture.inboxAtom.notifications.count == 1)
        #expect(fixture.inboxAtom.notifications[0].kind == .agentRpc)
        #expect(fixture.inboxAtom.notifications[0].title == "Claude Code finished")
        #expect(fixture.inboxAtom.notifications[0].body == "3 files changed")
        fixture.router.stop()
        fixture.tracker.stop()
        fixture.attendedPane.stop()
    }
}
