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
        await resourceLeaseRegistry.register(
            oldResource,
            paneId: paneId,
            expectedRevocationRevision: 0
        )
        await resourceLeaseRegistry.register(
            otherPaneResource,
            paneId: otherPaneId,
            expectedRevocationRevision: 0
        )

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
            ],
            expectedRevocationRevision: 0
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
        await resourceLeaseRegistry.register(
            oldResource,
            paneId: paneId,
            expectedRevocationRevision: 0
        )
        await resourceLeaseRegistry.register(
            newResource,
            paneId: paneId,
            expectedRevocationRevision: 0
        )

        await resourceLeaseRegistry.reset(paneId: paneId, protocolId: "review", resourceKind: "content", generation: 7)

        #expect(await resourceLeaseRegistry.contains(oldResource, paneId: paneId) == false)
        #expect(await resourceLeaseRegistry.contains(newResource, paneId: paneId) == true)
        #expect(
            resourceLeaseRegistry.isRevokedSynchronously(
                paneId: paneId,
                protocolId: "review",
                resourceKind: "content"
            ) == false)
        #expect(
            resourceLeaseRegistry.revocationRevision(
                paneId: paneId,
                protocolId: "review",
                resourceKind: "content"
            ) == 1)
    }

    @Test
    func test_transportResourceLeaseRegisterRejectsStaleRevocationRevision() async throws {
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                "agentstudio://resource/review/content/handle-old?generation=7",
                allowedResourceKindsByProtocol: ["review": Set(["content"])]
            ))
        let paneId = UUID()
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let initialRevision = resourceLeaseRegistry.revocationRevision(
            paneId: paneId,
            protocolId: "review",
            resourceKind: "content"
        )

        await resourceLeaseRegistry.reset(paneId: paneId, protocolId: "review", resourceKind: "content")
        let staleRegistered = await resourceLeaseRegistry.register(
            resource,
            paneId: paneId,
            expectedRevocationRevision: initialRevision
        )
        let currentRegistered = await resourceLeaseRegistry.register(
            resource,
            paneId: paneId,
            expectedRevocationRevision: resourceLeaseRegistry.revocationRevision(
                paneId: paneId,
                protocolId: "review",
                resourceKind: "content"
            )
        )

        #expect(staleRegistered == false)
        #expect(currentRegistered == true)
        #expect(await resourceLeaseRegistry.contains(resource, paneId: paneId) == true)
    }

    @Test
    func test_transportResourceLeaseRegisterRejectsStaleRevisionAfterTargetedRevoke() async throws {
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                "agentstudio://resource/review/content/handle-old?generation=7",
                allowedResourceKindsByProtocol: ["review": Set(["content"])]
            ))
        let paneId = UUID()
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let initialRevision = resourceLeaseRegistry.revocationRevision(
            paneId: paneId,
            protocolId: "review",
            resourceKind: "content"
        )
        await resourceLeaseRegistry.register(
            resource,
            paneId: paneId,
            expectedRevocationRevision: initialRevision
        )

        await resourceLeaseRegistry.revoke(resource)
        let staleRegistered = await resourceLeaseRegistry.register(
            resource,
            paneId: paneId,
            expectedRevocationRevision: initialRevision
        )
        let currentRegistered = await resourceLeaseRegistry.register(
            resource,
            paneId: paneId,
            expectedRevocationRevision: resourceLeaseRegistry.revocationRevision(
                paneId: paneId,
                protocolId: "review",
                resourceKind: "content"
            )
        )

        #expect(staleRegistered == false)
        #expect(currentRegistered == true)
        #expect(await resourceLeaseRegistry.contains(resource, paneId: paneId) == true)
    }

    @Test
    func test_transportResourceLeaseReplaceRejectsStaleRevocationRevision() async throws {
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                "agentstudio://resource/review/content/handle-new?generation=7",
                allowedResourceKindsByProtocol: ["review": Set(["content"])]
            ))
        let paneId = UUID()
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let initialRevision = resourceLeaseRegistry.revocationRevision(
            paneId: paneId,
            protocolId: "review",
            resourceKind: "content"
        )

        await resourceLeaseRegistry.reset(paneId: paneId, protocolId: "review", resourceKind: "content")
        let staleReplaced = await resourceLeaseRegistry.replace(
            paneId: paneId,
            protocolId: "review",
            resourceKind: "content",
            leases: [
                BridgeTransportResourceLease(
                    paneId: paneId,
                    descriptorId: resource.opaqueId,
                    resource: resource
                )
            ],
            expectedRevocationRevision: initialRevision
        )

        #expect(staleReplaced == false)
        #expect(await resourceLeaseRegistry.contains(resource, paneId: paneId) == false)
    }
}
