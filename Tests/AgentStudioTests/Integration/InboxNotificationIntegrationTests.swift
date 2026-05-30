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
        let topologyAtom: WorkspaceRepositoryTopologyAtom
        let paneAtom: WorkspacePaneAtom
        let tabLayout: WorkspaceTabLayoutAtom
        let windowLifecycle: WindowLifecycleAtom
        let managementLayer: ManagementLayerAtom
        let attendedPane: AttendedPaneAtom
        let tracker: PaneFocusTracker
        let router: InboxNotificationRouter

        func shutdown() async {
            await router.stop()
            await tracker.stop()
            attendedPane.stop()
        }
    }

    private func makeFixture() async -> Fixture {
        let bus = EventBus<RuntimeEnvelope>()
        let inboxAtom = InboxNotificationAtom()
        let prefsAtom = InboxNotificationPrefsAtom()
        let topologyAtom = WorkspaceRepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom(repositoryTopologyAtom: topologyAtom)
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
            topologyAtom: topologyAtom,
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
        if let repoId, let worktreeId {
            let repoName = repoName ?? "Repo"
            let worktreeName = worktreeName ?? "Worktree"
            let repoPath = URL(filePath: "/tmp/\(repoName)")
            let worktree = Worktree(
                id: worktreeId,
                repoId: repoId,
                name: worktreeName,
                path: repoPath.appending(path: worktreeName)
            )
            let repo = Repo(
                id: repoId,
                name: repoName,
                repoPath: repoPath,
                worktrees: [worktree]
            )
            let repos = fixture.topologyAtom.repos.filter { $0.id != repoId } + [repo]
            fixture.topologyAtom.hydrate(runtimeRepos: repos, watchedPaths: [], unavailableRepoIds: [])
        }

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
            layout: Layout(paneId: paneId.uuid)
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

        await fixture.shutdown()
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
        await fixture.shutdown()
    }

    @Test("approval and security receive-side events land in list and drawer surfaces")
    func approvalAndSecurityReceiveSideEventsReachInboxSurfaces() async {
        let fixture = await makeFixture()
        let paneId = PaneId()
        let repoId = UUID()
        let worktreeId = UUID()
        _ = addPane(
            paneId,
            to: fixture,
            repoId: repoId,
            repoName: "agent-studio",
            worktreeId: worktreeId,
            worktreeName: "security-worktree"
        )

        let routedEvents: [PaneRuntimeEvent] = [
            .artifact(.approvalRequested(request: ApprovalRequest(id: UUID(), summary: "Allow tool?"))),
            .security(.networkEgressBlocked(destination: "api.example.test", rule: "deny-net")),
            .security(.filesystemAccessDenied(path: "/tmp/secret", operation: "read")),
            .security(.secretAccessed(secretId: "OPENAI_API_KEY", consumerId: "agent")),
            .security(.processSpawnBlocked(command: "curl", rule: "no-shell")),
            .security(.sandboxHealthChanged(healthy: false)),
        ]
        for (index, event) in routedEvents.enumerated() {
            _ = await fixture.bus.post(
                RuntimeEnvelopeHarness.paneEnvelope(
                    event: event,
                    paneId: paneId,
                    seq: UInt64(index + 1)
                )
            )
        }
        _ = await fixture.bus.post(
            RuntimeEnvelopeHarness.paneEnvelope(
                event: .security(.sandboxStarted(backend: .local, policy: "default")),
                paneId: paneId,
                seq: 100
            )
        )
        _ = await fixture.bus.post(
            RuntimeEnvelopeHarness.paneEnvelope(
                event: .security(.sandboxStopped(reason: "done")),
                paneId: paneId,
                seq: 101
            )
        )

        await assertEventuallyMain("approval and security receive-side events should route") {
            fixture.inboxAtom.notifications.count == routedEvents.count
        }

        let notifications = fixture.inboxAtom.notifications
        #expect(
            notifications.map(\.kind) == [
                .approvalRequested,
                .securityEvent,
                .securityEvent,
                .securityEvent,
                .securityEvent,
                .securityEvent,
            ])
        #expect(notifications.map(\.paneId).allSatisfy { $0 == paneId.uuid })
        #expect(notifications.map(\.repoId).allSatisfy { $0 == repoId })
        #expect(notifications.map(\.worktreeId).allSatisfy { $0 == worktreeId })
        #expect(
            notifications.map(\.title) == [
                "Approval requested",
                "Network egress blocked",
                "Filesystem access denied",
                "Secret accessed",
                "Process spawn blocked",
                "Sandbox unhealthy",
            ])

        let listModel = InboxNotificationListModel(
            notifications: notifications,
            grouping: .byPane,
            sort: .newestFirst,
            searchText: "security-worktree"
        )
        #expect(listModel.sections.count == 1)
        #expect(listModel.sections[0].notifications.count == routedEvents.count)

        let paneNotifications = PaneInboxNotificationPopover.relevantNotifications(
            paneIds: [paneId.uuid],
            notifications: notifications
        )
        #expect(paneNotifications.count == routedEvents.count)

        await fixture.shutdown()
    }
}
