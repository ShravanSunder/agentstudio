import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class BridgeSchemeHandlerContentAuthorityTests {
    @Test
    func test_protocolScopedContentRouteRejectsOversizedContentBeforeEmittingBytes() async throws {
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("hello bridge"),
            sizeBytes: 4
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                handle.handleId: makeContentResult(handle: handle, data: "hello bridge")
            ]
        )
        let contentStore = BridgeContentStore(provider: provider)
        await contentStore.activate(handles: [handle], reviewGeneration: 7)
        let handler = await makeLeasedBridgeSchemeHandler(contentStore: contentStore, handle: handle)
        let request = URLRequest(url: URL(string: handle.resourceUrl)!)
        var emittedEventCount = 0

        do {
            for try await _ in handler.reply(for: request) {
                emittedEventCount += 1
            }
            Issue.record("Expected oversized leased content to fail")
        } catch BridgeProviderFailure.oversizedContent(let handleId, let sizeBytes) {
            #expect(handleId == handle.handleId)
            #expect(sizeBytes == 12)
        } catch {
            Issue.record("Expected oversizedContent, got \(error)")
        }
        #expect(emittedEventCount == 0)
    }

    @Test
    func test_protocolScopedContentRouteHeadRejectsOversizedContentBeforeEmittingResponse() async throws {
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("hello bridge"),
            sizeBytes: 4
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                handle.handleId: makeContentResult(handle: handle, data: "hello bridge")
            ]
        )
        let contentStore = BridgeContentStore(provider: provider)
        await contentStore.activate(handles: [handle], reviewGeneration: 7)
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let paneId = UUID()
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                handle.resourceUrl,
                allowedResourceKindsByProtocol: ["review": Set(["content"])]
            ))
        await resourceLeaseRegistry.register(
            resource,
            paneId: paneId,
            maxBytes: 3,
            expectedRevocationRevision: 0
        )
        let handler = BridgeSchemeHandler(
            paneId: paneId,
            contentStore: contentStore,
            resourceLeaseRegistry: resourceLeaseRegistry
        )
        var request = URLRequest(url: URL(string: handle.resourceUrl)!)
        request.httpMethod = "HEAD"
        var emittedEventCount = 0

        do {
            for try await _ in handler.reply(for: request) {
                emittedEventCount += 1
            }
            Issue.record("Expected oversized leased content to fail")
        } catch BridgeSchemeError.invalidRoute(let route) {
            #expect(route == handle.resourceUrl)
        } catch {
            Issue.record("Expected invalidRoute, got \(error)")
        }
        #expect(emittedEventCount == 0)
    }

    @Test
    func test_transportResourceLeaseRejectsDescriptorThatDoesNotMatchResourceAuthority() async throws {
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                "agentstudio://resource/review/content/handle-abc?generation=7",
                allowedResourceKindsByProtocol: ["review": Set(["content"])]
            ))
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let paneId = UUID()

        let registered = await resourceLeaseRegistry.register(
            resource, paneId: paneId, descriptorId: "different-descriptor", expectedRevocationRevision: 0)

        #expect(registered == false)
        #expect(await resourceLeaseRegistry.contains(resource, paneId: paneId) == false)
    }

    @Test
    func test_protocolScopedContentRouteDropsRevokedLeaseBeforeEmittingBytes() async throws {
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("slow")
        )
        let gate = BridgeContentLoadGate()
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                handle.handleId: makeContentResult(handle: handle, data: "slow")
            ],
            contentLoadGate: gate
        )
        let contentStore = BridgeContentStore(provider: provider)
        await contentStore.activate(handles: [handle], reviewGeneration: 7)
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let paneId = UUID()
        let resourceURL = "agentstudio://resource/review/content/\(handle.handleId)?generation=7&revision=1"
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                resourceURL,
                allowedResourceKindsByProtocol: ["review": Set(["content"])]
            ))
        await resourceLeaseRegistry.register(resource, paneId: paneId, expectedRevocationRevision: 0)
        let handler = BridgeSchemeHandler(
            paneId: paneId,
            contentStore: contentStore,
            resourceLeaseRegistry: resourceLeaseRegistry
        )
        let request = URLRequest(url: URL(string: resourceURL)!)
        let eventRecorder = BridgeSchemeHandlerContentAuthorityEventRecorder()
        let stream = handler.reply(for: request)

        let consumerTask = Task {
            do {
                for try await result in stream {
                    switch result {
                    case .response:
                        await eventRecorder.recordEvent()
                    case .data:
                        await eventRecorder.recordEvent()
                    @unknown default:
                        await eventRecorder.recordEvent()
                    }
                }
            } catch {
                await eventRecorder.recordError()
            }
        }
        await gate.waitForStartedLoadCount(1)
        await resourceLeaseRegistry.revoke(resource)
        await gate.releaseAll()
        await provider.waitForFinishedContentLoadCount(1)
        _ = await consumerTask.result

        #expect(await eventRecorder.recordedEventCount() == 0)
        #expect(await eventRecorder.recordedErrorCount() == 1)
    }

    @Test
    func test_protocolScopedContentRouteDropsReplacedLeaseBeforeEmittingBytes() async throws {
        let oldHandle = makeBridgeContentHandle(
            itemId: "old-item",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("old")
        )
        let newHandle = makeBridgeContentHandle(
            itemId: "new-item",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("new")
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                oldHandle.handleId: makeContentResult(handle: oldHandle, data: "old"),
                newHandle.handleId: makeContentResult(handle: newHandle, data: "new"),
            ]
        )
        let contentStore = BridgeContentStore(provider: provider)
        await contentStore.activate(handles: [oldHandle, newHandle], reviewGeneration: 7)
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let paneId = UUID()
        let oldResource = try #require(
            BridgeTransportResourceURL.parse(
                oldHandle.resourceUrl,
                allowedResourceKindsByProtocol: ["review": Set(["content"])]
            ))
        let newResource = try #require(
            BridgeTransportResourceURL.parse(
                newHandle.resourceUrl,
                allowedResourceKindsByProtocol: ["review": Set(["content"])]
            ))
        await resourceLeaseRegistry.register(oldResource, paneId: paneId, expectedRevocationRevision: 0)
        let emissionGate = BridgeContentLoadGate()
        let handler = BridgeSchemeHandler(
            paneId: paneId,
            contentStore: contentStore,
            resourceLeaseRegistry: resourceLeaseRegistry,
            beforeContentEmission: {
                await emissionGate.waitUntilReleased()
            }
        )
        let request = URLRequest(url: URL(string: oldHandle.resourceUrl)!)
        let eventRecorder = BridgeSchemeHandlerContentAuthorityEventRecorder()
        let stream = handler.reply(for: request)

        let consumerTask = Task {
            do {
                for try await result in stream {
                    switch result {
                    case .response:
                        await eventRecorder.recordEvent()
                    case .data:
                        await eventRecorder.recordEvent()
                    @unknown default:
                        await eventRecorder.recordEvent()
                    }
                }
            } catch {
                await eventRecorder.recordError()
            }
        }
        await emissionGate.waitForStartedLoadCount(1)
        await resourceLeaseRegistry.replace(
            paneId: paneId,
            protocolId: "review",
            resourceKind: "content",
            leases: [
                BridgeTransportResourceLease(
                    paneId: paneId,
                    descriptorId: newResource.opaqueId,
                    resource: newResource,
                    maxBytes: newHandle.sizeBytes
                )
            ],
            expectedRevocationRevision: 0
        )
        await emissionGate.releaseAll()
        _ = await consumerTask.result

        #expect(await eventRecorder.recordedEventCount() == 0)
        #expect(await eventRecorder.recordedErrorCount() == 1)
    }

    private func makeLeasedBridgeSchemeHandler(
        contentStore: BridgeContentStore,
        handle: BridgeContentHandle
    ) async -> BridgeSchemeHandler {
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let paneId = UUID()
        if let resource = BridgeTransportResourceURL.parse(
            handle.resourceUrl,
            allowedResourceKindsByProtocol: ["review": Set(["content"])]
        ) {
            await resourceLeaseRegistry.register(
                resource,
                paneId: paneId,
                descriptorId: resource.opaqueId,
                maxBytes: handle.sizeBytes,
                expectedRevocationRevision: 0
            )
        }
        return BridgeSchemeHandler(
            paneId: paneId,
            contentStore: contentStore,
            resourceLeaseRegistry: resourceLeaseRegistry
        )
    }
}

private actor BridgeSchemeHandlerContentAuthorityEventRecorder {
    private var eventCount = 0
    private var errorCount = 0

    func recordEvent() {
        eventCount += 1
    }

    func recordError() {
        errorCount += 1
    }

    func recordedEventCount() -> Int {
        eventCount
    }

    func recordedErrorCount() -> Int {
        errorCount
    }
}
