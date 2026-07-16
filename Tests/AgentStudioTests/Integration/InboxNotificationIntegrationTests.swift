import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Notification Inbox integration", .serialized)
struct InboxNotificationIntegrationTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("pane bus emission reaches atom and list model with source context")
    func paneBusEmissionReachesAtomAndListModel() async {
        let fixture = await InboxNotificationIntegrationHarness.makeFixture()
        let paneId = PaneId.generateUUIDv7()
        let repoId = UUID()
        let worktreeId = UUID()
        let tabId = InboxNotificationIntegrationHarness.addPane(
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

    @Test("approval and security receive-side events land in list and drawer surfaces")
    func approvalAndSecurityReceiveSideEventsReachInboxSurfaces() async {
        let fixture = await InboxNotificationIntegrationHarness.makeFixture()
        let paneId = PaneId.generateUUIDv7()
        let repoId = UUID()
        let worktreeId = UUID()
        _ = InboxNotificationIntegrationHarness.addPane(
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
