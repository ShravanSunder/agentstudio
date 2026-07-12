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

            #expect(controller.handleBridgeReady())
            await controller.dispatchIncomingSchemeCommand(
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

        @Test("bridge inbox.post bounds title and body before inbox persistence")
        func bridgeInboxPostBoundsTitleAndBodyBeforeInboxPersistence() async throws {
            let fixture = await InboxNotificationIntegrationHarness.makeFixture()
            let paneUUID = UUIDv7.generate()
            let paneId = PaneId(uuid: paneUUID)
            let bridgeState = BridgePaneState(panelKind: .diffViewer, source: nil)
            _ = InboxNotificationIntegrationHarness.addPane(
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
            let longTitle = String(repeating: "T", count: AppPolicies.InboxNotification.maxTitleCharacters + 10)
            let longBody = String(repeating: "B", count: AppPolicies.InboxNotification.maxBodyCharacters + 10)
            let payloadData = try JSONEncoder().encode(
                RPCFixtureRequest(
                    method: "inbox.post",
                    params: InboxPostFixtureParams(
                        title: "  \(longTitle)  ",
                        body: "\n\(longBody)\n"
                    )
                )
            )
            let payload = try #require(String(bytes: payloadData, encoding: .utf8))

            #expect(controller.handleBridgeReady())
            await controller.dispatchIncomingSchemeCommand(payload)

            await assertEventuallyMain("bounded bridge inbox.post should reach the inbox atom") {
                fixture.inboxAtom.notifications.count == 1
            }

            let notification = fixture.inboxAtom.notifications[0]
            #expect(notification.title.count == AppPolicies.InboxNotification.maxTitleCharacters)
            #expect(notification.body?.count == AppPolicies.InboxNotification.maxBodyCharacters)
            #expect(notification.title.allSatisfy { $0 == "T" })
            #expect(notification.body?.allSatisfy { $0 == "B" } == true)

            controller.teardown()
            forwardingTask.cancel()
            await forwardingTask.value
            await fixture.shutdown()
        }

        private struct RPCFixtureRequest<TParams: Encodable>: Encodable {
            let jsonrpc = "2.0"
            let method: String
            let params: TParams
        }

        private struct InboxPostFixtureParams: Encodable {
            let title: String
            let body: String?
        }
    }
}
