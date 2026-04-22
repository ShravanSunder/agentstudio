import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxNotificationRouter routing contract")
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

    private func makeFixture() -> Fixture {
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
            focusTracker: tracker
        )

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

    private func waitForRouterDelivery() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }

    @Test("desktopNotificationRequested posts an inbox notification")
    func desktopNotificationRequested() async {
        let fixture = makeFixture()
        await waitForBusSubscriberCount(fixture.bus, atLeast: 1)
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: paneId,
                event: .terminal(.desktopNotificationRequested(title: "Done", body: "exit 0"))
            )
        )
        await waitForRouterDelivery()

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
        let fixture = makeFixture()
        await waitForBusSubscriberCount(fixture.bus, atLeast: 1)
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        _ = await fixture.bus.post(makePaneEnvelope(paneId: paneId, event: .terminal(.bellRang)))
        await waitForRouterDelivery()
        #expect(fixture.inboxAtom.notifications.isEmpty)

        fixture.prefsAtom.setBellEnabled(true)
        _ = await fixture.bus.post(makePaneEnvelope(paneId: paneId, event: .terminal(.bellRang), seq: 2))
        await waitForRouterDelivery()
        #expect(fixture.inboxAtom.notifications.count == 1)
        #expect(fixture.inboxAtom.notifications[0].kind == .bellRang)
        fixture.router.stop()
        fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("commandFinished only notifies for unfocused long-running commands")
    func commandFinishedGating() async {
        let fixture = makeFixture()
        await waitForBusSubscriberCount(fixture.bus, atLeast: 1)
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
        await waitForRouterDelivery()
        #expect(fixture.inboxAtom.notifications.isEmpty)

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
        await waitForRouterDelivery()
        #expect(fixture.inboxAtom.notifications.isEmpty)

        _ = await fixture.bus.post(
            makePaneEnvelope(
                paneId: unfocusedPaneId,
                event: .terminal(.commandFinished(exitCode: 1, duration: 15)),
                seq: 3
            )
        )
        await waitForRouterDelivery()
        #expect(fixture.inboxAtom.notifications.count == 1)
        #expect(fixture.inboxAtom.notifications[0].kind == .commandFinished)
        #expect(fixture.inboxAtom.notifications[0].paneId == unfocusedPaneId.uuid)
        fixture.router.stop()
        fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("approvalRequested and selected security alerts notify")
    func approvalAndSecurityRouting() async {
        let fixture = makeFixture()
        await waitForBusSubscriberCount(fixture.bus, atLeast: 1)
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
        await waitForRouterDelivery()

        #expect(fixture.inboxAtom.notifications.count == 2)
        #expect(fixture.inboxAtom.notifications[0].kind == .approvalRequested)
        #expect(fixture.inboxAtom.notifications[1].kind == .securityEvent)
        #expect(fixture.inboxAtom.notifications[1].repoId == repoId)
        #expect(fixture.inboxAtom.notifications[1].worktreeId == worktreeId)
        fixture.router.stop()
        fixture.tracker.stop()
        fixture.attendedPane.stop()
    }

    @Test("focus-gained marks pane notifications read and dismissed from drawer")
    func focusGainedClearsUnread() async {
        let fixture = makeFixture()
        await waitForBusSubscriberCount(fixture.bus, atLeast: 1)
        let paneId = PaneId()
        _ = addTerminalPane(paneId, to: fixture)

        fixture.inboxAtom.append(
            InboxNotification(
                id: UUID(),
                timestamp: Date(),
                kind: .bellRang,
                title: "Bell",
                body: nil,
                paneId: paneId.uuid,
                tabId: nil,
                repoId: nil,
                repoName: nil,
                worktreeId: nil,
                worktreeName: nil,
                branchName: nil,
                isRead: false,
                isDismissedFromDrawer: false
            )
        )
        #expect(fixture.inboxAtom.unreadCount(forPaneId: paneId.uuid) == 1)

        await Task.yield()
        makeWindowKey(fixture.windowLifecycle)
        await waitForRouterDelivery()

        #expect(fixture.inboxAtom.unreadCount(forPaneId: paneId.uuid) == 0)
        #expect(fixture.inboxAtom.notifications[0].isDismissedFromDrawer)
        fixture.router.stop()
        fixture.tracker.stop()
        fixture.attendedPane.stop()
    }
}
