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

    @Test("title and body are trimmed and capped before emission")
    func postPayloadIsTrimmedAndCapped() async throws {
        let controller = makeController()
        defer { controller.teardown() }
        var iterator = controller.runtime.subscribe().makeAsyncIterator()

        await controller.handleIncomingRPC(
            #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
        )

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
        await controller.handleIncomingRPC(payload)

        let envelope = try #require(await iterator.next())
        guard case .pane(let paneEnvelope) = envelope,
            case .agentNotificationRequested(let title, let body) = paneEnvelope.event
        else {
            Issue.record("expected agentNotificationRequested event")
            return
        }

        #expect(title.count == AppPolicies.InboxNotification.maxTitleCharacters)
        #expect(body?.count == AppPolicies.InboxNotification.maxBodyCharacters)
        #expect(title.allSatisfy { $0 == "T" })
        #expect(body?.allSatisfy { $0 == "B" } == true)
    }

    @Test("blank title is rejected")
    func blankTitleIsRejected() async {
        let controller = makeController()
        defer { controller.teardown() }
        var errorCode: Int?
        controller.router.onError = { code, _, _ in errorCode = code }

        await controller.handleIncomingRPC(
            #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
        )

        await controller.handleIncomingRPC(
            #"{"jsonrpc":"2.0","method":"inbox.post","params":{"title":"   ","body":"ignored"},"id":1}"#
        )

        #expect(errorCode == -32_602)
    }

    @Test("inbox.post is rate limited per controller")
    func postRateLimitRejectsBursts() async {
        let controller = makeController()
        defer { controller.teardown() }
        var errorCode: Int?
        controller.router.onError = { code, _, _ in errorCode = code }

        await controller.handleIncomingRPC(
            #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
        )

        for index in 0..<AppPolicies.InboxNotification.maxRPCPostsPerWindow {
            await controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"inbox.post","params":{"title":"Notice \#(index)"}}"#
            )
        }
        await controller.handleIncomingRPC(
            #"{"jsonrpc":"2.0","method":"inbox.post","params":{"title":"Overflow"},"id":1}"#
        )

        #expect(errorCode == -32_602)
    }

    private func loadFixture(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let fixtureURL = root.appendingPathComponent("Tests/BridgeContractFixtures/\(name)")
        return try String(contentsOf: fixtureURL, encoding: .utf8)
    }

    private struct RPCFixtureRequest<Params: Encodable>: Encodable {
        let jsonrpc = "2.0"
        let method: String
        let params: Params
    }

    private struct InboxPostFixtureParams: Encodable {
        let title: String
        let body: String?
    }
}
