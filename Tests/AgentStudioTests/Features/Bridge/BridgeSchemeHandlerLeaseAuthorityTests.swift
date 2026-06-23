import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class BridgeSchemeHandlerLeaseAuthorityTests {
    @Test
    func test_transportResourceLeaseReplaceSwapsPaneContentLeasesAtomically() async throws {
        let oldResource = try #require(
            BridgeTransportResourceURL.parse(
                "agentstudio://resource/review/content/handle-old?generation=7",
                allowedResourceKindsByProtocol: ["review": Set(["content"])]
            ))
        let newResource = try #require(
            BridgeTransportResourceURL.parse(
                "agentstudio://resource/review/content/handle-new?generation=8",
                allowedResourceKindsByProtocol: ["review": Set(["content"])]
            ))
        let otherPaneResource = try #require(
            BridgeTransportResourceURL.parse(
                "agentstudio://resource/review/content/handle-other?generation=7",
                allowedResourceKindsByProtocol: ["review": Set(["content"])]
            ))
        let paneId = UUID()
        let otherPaneId = UUID()
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        await resourceLeaseRegistry.register(oldResource, paneId: paneId)
        await resourceLeaseRegistry.register(otherPaneResource, paneId: otherPaneId)

        let replaced = await resourceLeaseRegistry.replace(
            paneId: paneId,
            protocolId: "review",
            resourceKind: "content",
            leases: [
                BridgeTransportResourceLease(
                    paneId: paneId,
                    descriptorId: newResource.opaqueId,
                    resource: newResource
                )
            ]
        )

        #expect(replaced == true)
        #expect(await resourceLeaseRegistry.contains(oldResource, paneId: paneId) == false)
        #expect(await resourceLeaseRegistry.contains(newResource, paneId: paneId) == true)
        #expect(await resourceLeaseRegistry.contains(otherPaneResource, paneId: otherPaneId) == true)
    }

    @Test
    func test_transportResourceLeaseFilteredResetPreservesSurvivingLeases() async throws {
        let oldResource = try #require(
            BridgeTransportResourceURL.parse(
                "agentstudio://resource/review/content/handle-old?generation=7",
                allowedResourceKindsByProtocol: ["review": Set(["content"])]
            ))
        let newResource = try #require(
            BridgeTransportResourceURL.parse(
                "agentstudio://resource/review/content/handle-new?generation=8",
                allowedResourceKindsByProtocol: ["review": Set(["content"])]
            ))
        let paneId = UUID()
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        await resourceLeaseRegistry.register(oldResource, paneId: paneId)
        await resourceLeaseRegistry.register(newResource, paneId: paneId)

        await resourceLeaseRegistry.reset(paneId: paneId, protocolId: "review", resourceKind: "content", generation: 7)

        #expect(await resourceLeaseRegistry.contains(oldResource, paneId: paneId) == false)
        #expect(await resourceLeaseRegistry.contains(newResource, paneId: paneId) == true)
        #expect(
            resourceLeaseRegistry.isRevokedSynchronously(
                paneId: paneId,
                protocolId: "review",
                resourceKind: "content"
            ) == false)
    }
}
