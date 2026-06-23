import Foundation
import Testing

@testable import AgentStudio

@MainActor
struct BridgeWorktreeFileSurfaceTransportTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("open source stream returns native Worktree/File snapshot without Review lineage")
    func openSourceStreamReturnsNativeSnapshotWithoutReviewLineage() async throws {
        let fixture = try makeControllerFixture()
        let paneId = fixture.paneId
        let repoId = fixture.repoId
        let worktreeId = fixture.worktreeId
        let rootURL = fixture.rootURL
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let sourceSpec = BridgeWorktreeFileSurfaceSourceSpec(
            clientRequestId: "request-1",
            repoId: repoId,
            worktreeId: worktreeId,
            rootPathToken: fixture.worktree.stableKey,
            cwdScope: nil,
            pathScope: ["Sources"],
            includeStatuses: true,
            includeFileDescriptors: false,
            includeComments: false,
            includeAgentComms: false,
            freshness: .live
        )
        let controller = fixture.controller
        let capturedResponse = BridgeWorktreeFileSurfaceResponseCapture()
        controller.router.onResponse = { responseJSON in
            await capturedResponse.set(responseJSON)
        }

        await controller.handleIncomingRPC(
            #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
        )
        let request = try BridgeWorktreeFileSurfaceRPCRequest(
            id: "open-1",
            method: "worktreeFileSurface.openSourceStream",
            params: sourceSpec
        ).jsonString()

        await controller.handleIncomingRPC(request)

        let responseJSON = try #require(await capturedResponse.get())
        let responseData = try #require(responseJSON.data(using: .utf8))
        let response = try JSONDecoder().decode(BridgeWorktreeFileSurfaceSuccessResponse.self, from: responseData)
        #expect(response.jsonrpc == "2.0")
        #expect(response.id == "open-1")
        #expect(response.result.frameKind == "worktree.snapshot")
        #expect(response.result.source.repoId == repoId.uuidString)
        #expect(response.result.source.worktreeId == worktreeId.uuidString)
        #expect(response.result.source.subscriptionGeneration == 1)
        #expect(response.result.treeDescriptor.descriptor.protocolId == "worktree-file")
        #expect(response.result.treeDescriptor.descriptor.resourceKind == "worktree.treeWindow")
        #expect(response.result.statusDescriptor?.descriptor.resourceKind == "worktree.status")
        let treeResource = try #require(
            BridgeTransportResourceURL.parse(
                response.result.treeDescriptor.descriptor.resourceUrl,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            )
        )
        #expect(await controller.resourceLeaseRegistry.contains(treeResource, paneId: paneId))
        let schemeHandler = BridgeSchemeHandler(
            paneId: paneId,
            worktreeFileResourceStore: controller.worktreeFileResourceStore,
            resourceLeaseRegistry: controller.resourceLeaseRegistry
        )
        let treeBodyData = try await resourceBody(
            url: response.result.treeDescriptor.descriptor.resourceUrl,
            handler: schemeHandler
        )
        let treeBody = try JSONDecoder().decode(BridgeWorktreeTreeWindowResourceBody.self, from: treeBodyData)
        #expect(treeBody.source == response.result.source)
        #expect(treeBody.treeSizeFacts == response.result.treeSizeFacts)
        let statusURL = try #require(response.result.statusDescriptor?.descriptor.resourceUrl)
        let statusBodyData = try await resourceBody(url: statusURL, handler: schemeHandler)
        let statusBody = try JSONDecoder().decode(BridgeWorktreeStatusResourceBody.self, from: statusBodyData)
        #expect(statusBody.source == response.result.source)
        #expect(response.result.requestSelector?.pathScope == ["Sources"])
        #expect(response.result.treeSizeFacts.extentKind == .exactPathCount)
        #expect(response.result.treeSizeFacts.pathCount == 0)
        #expect(controller.paneState.diff.packageMetadata == nil)
        #expect(controller.paneState.diff.packageSnapshotProtocolFrame == nil)

        controller.teardown()
    }

    @Test("file scoped open source reports one tree row and revokes stale Worktree/File leases")
    func fileScopedOpenSourceReportsOneRowAndRevokesStaleLeases() async throws {
        let fixture = try makeControllerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let fileURL = fixture.rootURL
            .appending(path: "Sources")
            .appending(path: "App")
            .appending(path: "View.swift")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "struct View {}\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let firstResponseCapture = BridgeWorktreeFileSurfaceResponseCapture()
        fixture.controller.router.onResponse = { responseJSON in
            await firstResponseCapture.set(responseJSON)
        }
        await fixture.controller.handleIncomingRPC(
            #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
        )

        let firstSpec = sourceSpec(
            fixture: fixture,
            clientRequestId: "request-file",
            pathScope: ["Sources/App/View.swift"]
        )
        await fixture.controller.handleIncomingRPC(
            try BridgeWorktreeFileSurfaceRPCRequest(
                id: "open-file",
                method: "worktreeFileSurface.openSourceStream",
                params: firstSpec
            ).jsonString()
        )

        let firstResponse = try await decodedResponse(from: firstResponseCapture)
        #expect(firstResponse.result.treeSizeFacts.extentKind == .exactPathCount)
        #expect(firstResponse.result.treeSizeFacts.pathCount == 1)
        let firstTreeResource = try #require(
            BridgeTransportResourceURL.parse(
                firstResponse.result.treeDescriptor.descriptor.resourceUrl,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            )
        )
        #expect(await fixture.controller.resourceLeaseRegistry.contains(firstTreeResource, paneId: fixture.paneId))

        let secondResponseCapture = BridgeWorktreeFileSurfaceResponseCapture()
        fixture.controller.router.onResponse = { responseJSON in
            await secondResponseCapture.set(responseJSON)
        }
        let secondSpec = sourceSpec(
            fixture: fixture,
            clientRequestId: "request-root",
            pathScope: []
        )
        await fixture.controller.handleIncomingRPC(
            try BridgeWorktreeFileSurfaceRPCRequest(
                id: "open-root",
                method: "worktreeFileSurface.openSourceStream",
                params: secondSpec
            ).jsonString()
        )

        _ = try await decodedResponse(from: secondResponseCapture)
        #expect(
            await fixture.controller.resourceLeaseRegistry.contains(
                firstTreeResource,
                paneId: fixture.paneId
            ) == false
        )
        fixture.controller.teardown()
        #expect(
            await fixture.controller.resourceLeaseRegistry.contains(
                firstTreeResource,
                paneId: fixture.paneId
            ) == false
        )
    }

    private func makeControllerFixture() throws -> BridgeWorktreeFileSurfaceControllerFixture {
        let paneId = UUIDv7.generate()
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()
        let fixtureDirectoryName = "agentstudio-worktree-file-transport-\(UUIDv7.generate().uuidString)"
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: fixtureDirectoryName)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let worktree = Worktree(
            id: worktreeId,
            repoId: repoId,
            name: "transport-worktree",
            path: rootURL
        )
        let state = BridgePaneState(
            panelKind: .diffViewer,
            source: .workspace(rootPath: rootURL.path, baseline: .headMinusOne)
        )
        let metadata = PaneMetadata(
            paneId: PaneId(uuid: paneId),
            contentType: .diff,
            launchDirectory: rootURL,
            title: "Worktree",
            facets: PaneContextFacets(
                repoId: repoId,
                worktreeId: worktreeId,
                worktreeName: "transport-worktree",
                cwd: rootURL
            )
        )
        let controller = BridgePaneController(paneId: paneId, state: state, metadata: metadata)
        return BridgeWorktreeFileSurfaceControllerFixture(
            paneId: paneId,
            repoId: repoId,
            worktreeId: worktreeId,
            rootURL: rootURL,
            worktree: worktree,
            controller: controller
        )
    }

    private func sourceSpec(
        fixture: BridgeWorktreeFileSurfaceControllerFixture,
        clientRequestId: String,
        pathScope: [String]
    ) -> BridgeWorktreeFileSurfaceSourceSpec {
        BridgeWorktreeFileSurfaceSourceSpec(
            clientRequestId: clientRequestId,
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            rootPathToken: fixture.worktree.stableKey,
            cwdScope: nil,
            pathScope: pathScope,
            includeStatuses: true,
            includeFileDescriptors: false,
            includeComments: false,
            includeAgentComms: false,
            freshness: .live
        )
    }

    private func decodedResponse(
        from capture: BridgeWorktreeFileSurfaceResponseCapture
    ) async throws -> BridgeWorktreeFileSurfaceSuccessResponse {
        let responseJSON = try #require(await capture.get())
        let responseData = try #require(responseJSON.data(using: .utf8))
        return try JSONDecoder().decode(BridgeWorktreeFileSurfaceSuccessResponse.self, from: responseData)
    }

    private func resourceBody(
        url: String,
        handler: BridgeSchemeHandler
    ) async throws -> Data {
        let request = URLRequest(url: URL(string: url)!)
        var body = Data()
        for try await result in handler.reply(for: request) {
            switch result {
            case .response:
                break
            case .data(let chunk):
                body.append(chunk)
            @unknown default:
                Issue.record("Unexpected URL scheme task result")
            }
        }
        return body
    }
}

private struct BridgeWorktreeFileSurfaceControllerFixture {
    let paneId: UUID
    let repoId: UUID
    let worktreeId: UUID
    let rootURL: URL
    let worktree: Worktree
    let controller: BridgePaneController
}

private struct BridgeWorktreeFileSurfaceRPCRequest<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: String
    let method: String
    let params: Params

    func jsonString() throws -> String {
        let data = try JSONEncoder().encode(self)
        return try #require(String(data: data, encoding: .utf8))
    }
}

private struct BridgeWorktreeFileSurfaceSuccessResponse: Decodable {
    let jsonrpc: String
    let id: String
    let result: BridgeWorktreeSnapshotFrame
}

private actor BridgeWorktreeFileSurfaceResponseCapture {
    private var payload: String?

    func set(_ value: String) {
        payload = value
    }

    func get() -> String? {
        payload
    }
}
