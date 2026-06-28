import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct BridgeSchemeHandlerReviewResourceTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test
    func reviewPackageResourceEmitsLeasedBodyInChunks() async throws {
        let resourceURL =
            "agentstudio://resource/review/review-package/package-1?generation=3&revision=7"
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                resourceURL,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            ))
        let paneId = UUID()
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let resourceStore = BridgeReviewResourceStore()
        let body = Data(String(repeating: "package-body-", count: 7000).utf8)
        await resourceStore.register(
            resource,
            body: BridgeReviewResourceBody(
                data: body,
                mimeType: "application/json"
            )
        )
        await resourceLeaseRegistry.register(
            resource,
            paneId: paneId,
            descriptorId: resource.opaqueId,
            maxBytes: body.count,
            expectedRevocationRevision: 0
        )
        let handler = BridgeSchemeHandler(
            paneId: paneId,
            reviewResourceStore: resourceStore,
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

        #expect(eventOrder == ["response", "data", "data"])
        #expect(response?.mimeType == "application/json")
        #expect(response?.expectedContentLength == Int64(body.count))
        #expect(receivedBody == body)
    }

    @Test
    func reviewPackageHeadDoesNotMaterializeLazyBody() async throws {
        let resourceURL =
            "agentstudio://resource/review/review-package/package-lazy?generation=3&revision=7"
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                resourceURL,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            ))
        let paneId = UUID()
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let resourceStore = BridgeReviewResourceStore()
        let bodyProbe = BridgeReviewLazyBodyProbe(
            data: Data(#"{"packageId":"package-lazy","items":[]}"#.utf8)
        )
        await resourceStore.register(
            resource,
            mimeType: "application/json"
        ) {
            bodyProbe.load()
        }
        await resourceLeaseRegistry.register(
            resource,
            paneId: paneId,
            descriptorId: resource.opaqueId,
            maxBytes: 1024,
            expectedRevocationRevision: 0
        )
        let handler = BridgeSchemeHandler(
            paneId: paneId,
            reviewResourceStore: resourceStore,
            resourceLeaseRegistry: resourceLeaseRegistry
        )
        var request = URLRequest(url: URL(string: resourceURL)!)
        request.httpMethod = "HEAD"

        var eventOrder: [String] = []
        for try await result in handler.reply(for: request) {
            switch result {
            case .response(let emittedResponse):
                eventOrder.append("response")
                #expect(emittedResponse.mimeType == "application/json")
            case .data:
                eventOrder.append("data")
            @unknown default:
                Issue.record("Unexpected URL scheme task result")
            }
        }

        #expect(eventOrder == ["response"])
        #expect(bodyProbe.loadCount == 0)
    }

    @Test
    func reviewDeltaGetMaterializesLazyBodyAfterLeaseValidation() async throws {
        let resourceURL =
            "agentstudio://resource/review/review-delta/delta-lazy?generation=3&revision=8"
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                resourceURL,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            ))
        let paneId = UUID()
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let resourceStore = BridgeReviewResourceStore()
        let body = Data(#"{"addItems":[],"updateItems":[]}"#.utf8)
        let bodyProbe = BridgeReviewLazyBodyProbe(data: body)
        await resourceStore.register(
            resource,
            mimeType: "application/json"
        ) {
            bodyProbe.load()
        }
        #expect(bodyProbe.loadCount == 0)
        await resourceLeaseRegistry.register(
            resource,
            paneId: paneId,
            descriptorId: resource.opaqueId,
            maxBytes: 1024,
            expectedRevocationRevision: 0
        )
        let handler = BridgeSchemeHandler(
            paneId: paneId,
            reviewResourceStore: resourceStore,
            resourceLeaseRegistry: resourceLeaseRegistry
        )
        let request = URLRequest(url: URL(string: resourceURL)!)

        var receivedBody = Data()
        for try await result in handler.reply(for: request) {
            switch result {
            case .response:
                break
            case .data(let chunk):
                receivedBody.append(chunk)
            @unknown default:
                Issue.record("Unexpected URL scheme task result")
            }
        }

        #expect(bodyProbe.loadCount == 1)
        #expect(receivedBody == body)
    }

    @Test
    func reviewPackageReplacePrunesSupersededPackageBodies() async throws {
        let oldResourceURL =
            "agentstudio://resource/review/review-package/package-old?generation=3&revision=7"
        let newResourceURL =
            "agentstudio://resource/review/review-package/package-new?generation=3&revision=8"
        let oldResource = try #require(
            BridgeTransportResourceURL.parse(
                oldResourceURL,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            ))
        let newResource = try #require(
            BridgeTransportResourceURL.parse(
                newResourceURL,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            ))
        let resourceStore = BridgeReviewResourceStore()

        await resourceStore.replace(
            oldResource,
            body: BridgeReviewResourceBody(
                data: Data(#"{"revision":7}"#.utf8),
                mimeType: "application/json"
            )
        )
        #expect(await resourceStore.metadata(oldResource) != nil)

        await resourceStore.replace(
            newResource,
            body: BridgeReviewResourceBody(
                data: Data(#"{"revision":8}"#.utf8),
                mimeType: "application/json"
            )
        )

        #expect(await resourceStore.metadata(oldResource) == nil)
        #expect(await resourceStore.metadata(newResource) != nil)
        let loadedNewBody = BridgeReviewChunkCollector()
        let emitted = try await resourceStore.emitChunks(
            newResource,
            chunkByteCount: 1024
        ) { chunk in
            loadedNewBody.append(chunk)
            return true
        }
        #expect(emitted == true)
        #expect(loadedNewBody.data == Data(#"{"revision":8}"#.utf8))
    }

    @Test
    func revokedReviewDeltaResourceFailsWithoutLeakingCapabilityURL() async throws {
        let resourceURL =
            "agentstudio://resource/review/review-delta/delta-1?generation=3&revision=8"
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                resourceURL,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            ))
        let paneId = UUID()
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let resourceStore = BridgeReviewResourceStore()
        await resourceStore.register(
            resource,
            body: BridgeReviewResourceBody(
                data: Data(#"{"addItems":[],"updateItems":[]}"#.utf8),
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
            protocolId: "review",
            resourceKind: "review-delta"
        )
        let handler = BridgeSchemeHandler(
            paneId: paneId,
            reviewResourceStore: resourceStore,
            resourceLeaseRegistry: resourceLeaseRegistry
        )
        let request = URLRequest(url: URL(string: resourceURL)!)

        do {
            for try await _ in handler.reply(for: request) {}
            Issue.record("Expected revoked Review resource request to fail before bytes")
        } catch BridgeSchemeError.invalidRoute(let route) {
            #expect(route != resourceURL)
            #expect(route.contains("delta-1") == false)
            #expect(route.contains("revision=8") == false)
            #expect(route.contains("agentstudio://resource") == false)
        } catch {
            Issue.record("Expected invalidRoute, got \(error)")
        }
    }

    @Test
    func reviewResourceStopsBeforeEmittingChunkPastLeaseBudget() async throws {
        let resourceURL =
            "agentstudio://resource/review/review-package/package-too-large?generation=3&revision=7"
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                resourceURL,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            ))
        let paneId = UUID()
        let resourceLeaseRegistry = BridgeTransportResourceLeaseRegistry()
        let resourceStore = BridgeReviewResourceStore()
        await resourceStore.register(
            resource,
            body: BridgeReviewResourceBody(
                data: Data(String(repeating: "x", count: 32_000).utf8),
                mimeType: "application/json"
            )
        )
        await resourceLeaseRegistry.register(
            resource,
            paneId: paneId,
            descriptorId: resource.opaqueId,
            maxBytes: 8000,
            expectedRevocationRevision: 0
        )
        let handler = BridgeSchemeHandler(
            paneId: paneId,
            reviewResourceStore: resourceStore,
            resourceLeaseRegistry: resourceLeaseRegistry
        )
        let request = URLRequest(url: URL(string: resourceURL)!)

        var receivedBody = Data()
        do {
            for try await result in handler.reply(for: request) {
                switch result {
                case .response:
                    break
                case .data(let chunk):
                    receivedBody.append(chunk)
                @unknown default:
                    Issue.record("Unexpected URL scheme task result")
                }
            }
            Issue.record("Expected over-budget Review resource request to fail")
        } catch BridgeSchemeError.invalidRoute(let route) {
            #expect(receivedBody.count <= 8000)
            #expect(route != resourceURL)
            #expect(route.contains("package-too-large") == false)
            #expect(route.contains("agentstudio://resource") == false)
        } catch {
            Issue.record("Expected invalidRoute, got \(error)")
        }
    }

    @Test
    @MainActor
    func runtimeReviewPackageHeadUsesDescriptorByteCountWithoutBodyBytes() async throws {
        let package = try makeRuntimeReviewResourcePackage()
        let packageBodyFacts = try await BridgeReviewJSONResourceEmitter.packageBodyFacts(package)
        let snapshotFrame = try BridgeReviewProtocolFrameBuilder.snapshot(
            request: BridgeReviewProtocolSnapshotBuildRequest(
                paneId: "pane-runtime",
                sourceIdentity: package.query.queryId,
                streamId: "review:pane-runtime",
                sequence: package.revision,
                package: package,
                packageBodyFacts: packageBodyFacts,
                changesetCluster: nil
            )
        )
        let controller = BridgePaneController(
            paneId: UUIDv7.generate(),
            state: BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(rootPath: "Sources", baseline: .headMinusOne)
            )
        )
        defer { controller.teardown() }
        try await controller.activateReviewProtocolBodyResources(
            frames: BridgeReviewPackageLoadFrames(
                package: package,
                delta: nil,
                snapshotFrame: snapshotFrame,
                deltaFrame: nil,
                packageBodyFacts: packageBodyFacts,
                deltaBodyFacts: nil
            ),
            expectedPackageResourceRevocationRevision: controller.reviewResourceRevocationRevision(
                resourceKind: "review-package"),
            expectedDeltaResourceRevocationRevision: controller.reviewResourceRevocationRevision(
                resourceKind: "review-delta")
        )
        let handler = BridgeSchemeHandler(
            paneId: controller.paneId,
            reviewResourceStore: controller.reviewResourceStore,
            resourceLeaseRegistry: controller.resourceLeaseRegistry
        )
        var request = URLRequest(
            url: URL(string: snapshotFrame.package.rootDescriptor.descriptor.resourceUrl)!)
        request.httpMethod = "HEAD"

        var eventOrder: [String] = []
        for try await result in handler.reply(for: request) {
            switch result {
            case .response(let emittedResponse):
                eventOrder.append("response")
                #expect(emittedResponse.mimeType == "application/json")
                #expect(emittedResponse.expectedContentLength == Int64(packageBodyFacts.byteCount))
            case .data:
                eventOrder.append("data")
            @unknown default:
                Issue.record("Unexpected URL scheme task result")
            }
        }

        #expect(eventOrder == ["response"])
    }
}

private func makeRuntimeReviewResourcePackage() throws -> BridgeReviewPackage {
    let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
    let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .workingTree)
    let comparison = BridgeEndpointComparison(
        baseEndpoint: baseEndpoint,
        headEndpoint: headEndpoint,
        changedFiles: [
            makeBridgeEndpointChangedFile(
                fileId: "source",
                path: "Sources/App/View.swift",
                sizeBytes: 100)
        ]
    )
    return try BridgeReviewPackageBuilder.build(
        request: BridgeReviewPackageBuildRequest(
            packageId: "package-runtime",
            query: makeBridgeReviewQuery(
                baseEndpointId: baseEndpoint.endpointId,
                headEndpointId: headEndpoint.endpointId),
            comparison: comparison,
            checkpointIds: [],
            reviewGeneration: 3,
            generatedAtUnixMilliseconds: 4
        )
    )
}

private final class BridgeReviewLazyBodyProbe: @unchecked Sendable {
    private let data: Data
    private let lock = NSLock()
    private var count = 0

    init(data: Data) {
        self.data = data
    }

    var loadCount: Int {
        lock.withLock { count }
    }

    func load() -> Data {
        lock.withLock {
            count += 1
        }
        return data
    }
}

private final class BridgeReviewChunkCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks = Data()

    var data: Data {
        lock.withLock { chunks }
    }

    func append(_ chunk: Data) {
        lock.withLock {
            chunks.append(chunk)
        }
    }
}
