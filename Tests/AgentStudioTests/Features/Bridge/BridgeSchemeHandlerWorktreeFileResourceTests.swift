import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct BridgeSchemeHandlerWorktreeFileResourceTests {
    @Test
    func worktreeFileTreeWindowResourceEmitsLeasedBody() async throws {
        let resourceURL =
            "agentstudio://resource/worktree-file/worktree.treeWindow/tree-window-1?generation=3&cursor=cursor-3"
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                resourceURL,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            ))
        let paneId = UUID()
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let resourceStore = BridgeWorktreeFileResourceStore()
        let body = Data(#"{"rows":[],"treeSizeFacts":{"extentKind":"exactPathCount","pathCount":0}}"#.utf8)
        await resourceStore.register(
            resource,
            body: BridgeWorktreeFileResourceBody(
                data: body,
                mimeType: "application/json"
            )
        )
        await resourceLeaseRegistry.register(
            resource,
            paneId: paneId,
            descriptorId: resource.opaqueId,
            maxBytes: 1024,
            expectedRevocationRevision: 0
        )
        let handler = BridgeSchemeHandler(
            paneId: paneId,
            worktreeFileResourceStore: resourceStore,
            resourceLeaseRegistry: resourceLeaseRegistry
        )
        let request = URLRequest(url: URL(string: resourceURL)!)

        var response: URLResponse?
        var receivedBody = Data()
        var eventOrder: [String] = []
        for try await result in handler.reply(for: request) {
            switch result {
            case .response(let emittedResponse):
                response = emittedResponse
                eventOrder.append("response")
            case .data(let chunk):
                receivedBody.append(chunk)
                eventOrder.append("data")
            @unknown default:
                Issue.record("Unexpected URL scheme task result")
            }
        }

        #expect(eventOrder == ["response", "data"])
        #expect(response?.mimeType == "application/json")
        #expect(response?.expectedContentLength == Int64(body.count))
        #expect(receivedBody == body)
    }

    @Test
    func revokedWorktreeFileResourceFailsWithoutLeakingCapabilityURL() async throws {
        let resourceURL =
            "agentstudio://resource/worktree-file/worktree.status/status-1?generation=3&cursor=cursor-3"
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                resourceURL,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            ))
        let paneId = UUID()
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let resourceStore = BridgeWorktreeFileResourceStore()
        await resourceStore.register(
            resource,
            body: BridgeWorktreeFileResourceBody(
                data: Data(#"{"branchName":"main"}"#.utf8),
                mimeType: "application/json"
            )
        )
        await resourceLeaseRegistry.register(
            resource,
            paneId: paneId,
            descriptorId: resource.opaqueId,
            maxBytes: 1024,
            expectedRevocationRevision: 0
        )
        resourceLeaseRegistry.revokeSynchronously(
            paneId: paneId,
            protocolId: "worktree-file",
            resourceKind: "worktree.status"
        )
        let handler = BridgeSchemeHandler(
            paneId: paneId,
            worktreeFileResourceStore: resourceStore,
            resourceLeaseRegistry: resourceLeaseRegistry
        )
        let request = URLRequest(url: URL(string: resourceURL)!)

        do {
            for try await _ in handler.reply(for: request) {}
            Issue.record("Expected revoked Worktree/File resource request to fail before bytes")
        } catch BridgeSchemeError.invalidRoute(let route) {
            #expect(route != resourceURL)
            #expect(route.contains("status-1") == false)
            #expect(route.contains("cursor-3") == false)
            #expect(route.contains("agentstudio://resource") == false)
        } catch {
            Issue.record("Expected invalidRoute, got \(error)")
        }
    }
}
