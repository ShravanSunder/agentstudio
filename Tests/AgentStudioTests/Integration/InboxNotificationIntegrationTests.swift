import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Notification Inbox integration", .serialized)
struct InboxNotificationIntegrationTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @MainActor
    private struct Fixture {
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

        func shutdown() {
            router.stop()
            tracker.stop()
            attendedPane.stop()
        }
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

    @discardableResult
    private func addPane(
        _ paneId: PaneId,
        to fixture: Fixture,
        content: PaneContent = .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
        contentType: PaneContentType = .terminal,
        repoId: UUID? = nil,
        repoName: String? = nil,
        worktreeId: UUID? = nil,
        worktreeName: String? = nil
    ) -> UUID {
        let metadata = PaneMetadata(
            paneId: paneId,
            contentType: contentType,
            source: .floating(launchDirectory: nil, title: nil),
            title: "Integration Pane",
            facets: PaneContextFacets(
                repoId: repoId,
                repoName: repoName,
                worktreeId: worktreeId,
                worktreeName: worktreeName
            ),
            checkoutRef: "main"
        )
        fixture.paneAtom.addPane(
            Pane(
                id: paneId.uuid,
                content: content,
                metadata: metadata
            )
        )

        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneId.uuid),
            visiblePaneIds: [paneId.uuid]
        )
        let tab = Tab(
            name: "Tab",
            panes: [paneId.uuid],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: paneId.uuid
        )
        fixture.tabLayout.appendTab(tab)
        return tab.id
    }

    @Test("pane bus emission reaches atom and list model with source context")
    func paneBusEmissionReachesAtomAndListModel() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        let repoId = UUID()
        let worktreeId = UUID()
        let tabId = addPane(
            paneId,
            to: fixture,
            repoId: repoId,
            repoName: "agent-studio",
            worktreeId: worktreeId,
            worktreeName: "notification-system"
        )

        _ = await fixture.bus.post(
            RuntimeEnvelopeHarness.paneEnvelope(
                event: .terminal(.desktopNotificationRequested(title: "Codex done", body: "exit 0")),
                paneId: paneId
            )
        )

        await assertEventuallyMain("desktop notification should be routed into the inbox atom") {
            fixture.inboxAtom.notifications.count == 1
        }

        let notification = fixture.inboxAtom.notifications[0]
        #expect(notification.kind == .agentDesktopNotification)
        #expect(notification.paneId == paneId.uuid)
        #expect(notification.tabId == tabId)
        #expect(notification.repoId == repoId)
        #expect(notification.repoName == "agent-studio")
        #expect(notification.worktreeId == worktreeId)
        #expect(notification.worktreeName == "notification-system")

        let listModel = InboxNotificationListModel(
            notifications: fixture.inboxAtom.notifications,
            grouping: .byRepo,
            sort: .newestFirst,
            searchText: "codex"
        )
        #expect(listModel.sections.map(\.label) == ["agent-studio"])
        #expect(listModel.sections.flatMap(\.notifications).map(\.id) == [notification.id])

        fixture.shutdown()
    }

    @Test("bridge inbox.post reaches router and atom through runtime events")
    func bridgeInboxPostReachesRouterAndAtom() async {
        let fixture = await makeFixture()
        let paneUUID = UUIDv7.generate()
        let paneId = PaneId(uuid: paneUUID)
        let bridgeState = BridgePaneState(panelKind: .diffViewer, source: nil)
        let tabId = addPane(
            paneId,
            to: fixture,
            content: .bridgePanel(bridgeState),
            contentType: .diff,
            repoName: "agent-studio",
            worktreeName: "bridge-worktree"
        )
        let controller = BridgePaneController(
            paneId: paneUUID,
            state: bridgeState
        )

        let forwardingTask = Task { @MainActor in
            for await envelope in controller.runtime.subscribe() {
                _ = await fixture.bus.post(envelope)
            }
        }

        await controller.handleIncomingRPC(
            #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
        )
        await controller.handleIncomingRPC(
            #"{"jsonrpc":"2.0","method":"inbox.post","params":{"title":"Claude Code finished","body":"3 files changed"}}"#
        )

        await assertEventuallyMain("bridge inbox.post should reach the inbox atom") {
            fixture.inboxAtom.notifications.count == 1
        }

        let notification = fixture.inboxAtom.notifications[0]
        #expect(notification.kind == .agentRpc)
        #expect(notification.title == "Claude Code finished")
        #expect(notification.body == "3 files changed")
        #expect(notification.paneId == paneUUID)
        #expect(notification.tabId == tabId)

        controller.teardown()
        forwardingTask.cancel()
        await forwardingTask.value
        fixture.shutdown()
    }
}
