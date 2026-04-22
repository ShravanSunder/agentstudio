import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Bridge inbox.post RPC handler")
struct InboxPostHandlerTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    private func makeController() -> BridgePaneController {
        BridgePaneController(
            paneId: UUIDv7.generate(),
            state: BridgePaneState(panelKind: .diffViewer, source: nil)
        )
    }

    @Test("valid inbox.post emits an agent notification event for the bound pane")
    func validInboxPost() async throws {
        let controller = makeController()
        defer { controller.teardown() }
        var iterator = controller.runtime.subscribe().makeAsyncIterator()

        await controller.handleIncomingRPC(
            #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
        )

        let payload = try loadFixture("valid/rpc-command-inbox-post.json")
        await controller.handleIncomingRPC(payload)

        let envelope = try #require(await iterator.next())
        guard case .pane(let paneEnvelope) = envelope else {
            Issue.record("expected pane envelope")
            return
        }

        #expect(paneEnvelope.paneId.uuid == controller.paneId)
        guard case .agentNotificationRequested(let title, let body) = paneEnvelope.event else {
            Issue.record("expected agentNotificationRequested event")
            return
        }
        #expect(title == "Claude Code finished")
        #expect(body == "3 files changed, 142 lines")
    }

    @Test("caller-supplied paneId is ignored")
    func spoofedPaneIdIsIgnored() async throws {
        let controller = makeController()
        defer { controller.teardown() }
        var iterator = controller.runtime.subscribe().makeAsyncIterator()

        await controller.handleIncomingRPC(
            #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
        )

        let payload =
            #"{"jsonrpc":"2.0","method":"inbox.post","params":{"title":"Fake","body":"Fake","paneId":"019DB51A-E1C5-75D1-9539-8F80D7F615F8"}}"#
        await controller.handleIncomingRPC(payload)

        let envelope = try #require(await iterator.next())
        guard case .pane(let paneEnvelope) = envelope else {
            Issue.record("expected pane envelope")
            return
        }
        #expect(paneEnvelope.paneId.uuid == controller.paneId)
    }

    private func loadFixture(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let fixtureURL = root.appendingPathComponent("Tests/BridgeContractFixtures/\(name)")
        return try String(contentsOf: fixtureURL, encoding: .utf8)
    }
}
