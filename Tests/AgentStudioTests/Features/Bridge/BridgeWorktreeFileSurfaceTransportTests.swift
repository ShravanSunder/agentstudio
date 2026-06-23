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
        let paneId = UUIDv7.generate()
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()
        let fixtureDirectoryName = "agentstudio-worktree-file-transport-\(UUIDv7.generate().uuidString)"
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: fixtureDirectoryName)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let worktree = Worktree(
            id: worktreeId,
            repoId: repoId,
            name: "transport-worktree",
            path: rootURL
        )
        let sourceSpec = BridgeWorktreeFileSurfaceSourceSpec(
            clientRequestId: "request-1",
            repoId: repoId,
            worktreeId: worktreeId,
            rootPathToken: worktree.stableKey,
            cwdScope: nil,
            pathScope: ["Sources"],
            includeStatuses: true,
            includeFileDescriptors: false,
            includeComments: false,
            includeAgentComms: false,
            freshness: .live
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
        #expect(response.result.requestSelector?.pathScope == ["Sources"])
        #expect(response.result.treeSizeFacts.extentKind == .exactPathCount)
        #expect(response.result.treeSizeFacts.pathCount == 0)
        #expect(controller.paneState.diff.packageMetadata == nil)
        #expect(controller.paneState.diff.packageSnapshotProtocolFrame == nil)

        controller.teardown()
    }
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
