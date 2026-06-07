import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite("Notification Inbox bridge WebKit integration", .serialized)
    struct InboxNotificationBridgeWebKitIntegrationTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("bridge inbox.post reaches router and atom through runtime events")
        func bridgeInboxPostReachesRouterAndAtom() async {
            let fixture = await InboxNotificationIntegrationHarness.makeFixture()
            let paneUUID = UUIDv7.generate()
            let paneId = PaneId(uuid: paneUUID)
            let bridgeState = BridgePaneState(panelKind: .diffViewer, source: nil)
            let tabId = InboxNotificationIntegrationHarness.addPane(
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
    }
}
