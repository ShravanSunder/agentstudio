import Foundation
import Testing
import WebKit

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

    @Test("file scoped open source queues descriptor frame after response and serves content")
    func fileScopedOpenSourceQueuesDescriptorAfterResponseAndServesContent() async throws {
        let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
        let fixture = try makeControllerFixtureWithIntakeSink(
            intakeFrameSink: { _, frameJSON, _ in
                await eventCapture.recordIntake(frameJSON)
            }
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let fileURL = fixture.rootURL
            .appending(path: "Sources")
            .appending(path: "App")
            .appending(path: "View.swift")
        let fileText = "struct View {}\nlet value = 1"
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileText.write(to: fileURL, atomically: true, encoding: .utf8)
        let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
        fixture.controller.router.onResponse = { responseJSON in
            await eventCapture.recordResponse()
            await responseCapture.set(responseJSON)
        }
        await fixture.controller.handleIncomingRPC(
            #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
        )
        let spec = sourceSpec(
            fixture: fixture,
            clientRequestId: "request-file-descriptor",
            pathScope: ["Sources/App/View.swift"],
            includeFileDescriptors: true
        )

        await fixture.controller.handleIncomingRPC(
            try BridgeWorktreeFileSurfaceRPCRequest(
                id: "open-file-descriptor",
                method: "worktreeFileSurface.openSourceStream",
                params: spec
            ).jsonString()
        )

        let response = try await decodedResponse(from: responseCapture)
        let events = await eventCapture.events()
        #expect(events == ["response", "intake"])
        let intakeFrameJSON = try #require(await eventCapture.intakeFrames().first)
        let intakeFrameData = try #require(intakeFrameJSON.data(using: .utf8))
        let intakeFrame = try JSONDecoder().decode(
            BridgeWorktreeFileSurfaceIntakeFrameEnvelope.self,
            from: intakeFrameData
        )
        #expect(intakeFrame.kind == "delta")
        #expect(intakeFrame.streamId == response.result.streamId)
        #expect(intakeFrame.generation == response.result.generation)
        #expect(intakeFrame.sequence == 1)
        #expect(intakeFrame.payload.frameKind == "worktree.fileDescriptor")
        #expect(intakeFrame.payload.descriptor.path == "Sources/App/View.swift")
        #expect(intakeFrame.payload.descriptor.virtualizedExtentKind == .exactLineCount)
        #expect(intakeFrame.payload.descriptor.lineCount == 2)
        #expect(intakeFrame.payload.descriptor.contentDescriptor.descriptor.resourceKind == "worktree.fileContent")
        let contentResource = try #require(
            BridgeTransportResourceURL.parse(
                intakeFrame.payload.descriptor.contentDescriptor.descriptor.resourceUrl,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            )
        )
        #expect(await fixture.controller.resourceLeaseRegistry.contains(contentResource, paneId: fixture.paneId))
        let schemeHandler = BridgeSchemeHandler(
            paneId: fixture.paneId,
            worktreeFileResourceStore: fixture.controller.worktreeFileResourceStore,
            resourceLeaseRegistry: fixture.controller.resourceLeaseRegistry
        )
        let contentBody = try await resourceBody(
            url: intakeFrame.payload.descriptor.contentDescriptor.descriptor.resourceUrl,
            handler: schemeHandler
        )
        #expect(String(data: contentBody, encoding: .utf8) == fileText)
        fixture.controller.teardown()
    }

    @Test("active Worktree/File source emits live status and invalidation frames in sequence")
    func activeWorktreeFileSourceEmitsLiveStatusAndInvalidationsInSequence() async throws {
        let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
        let fixture = try makeControllerFixtureWithIntakeSink(
            intakeFrameSink: { _, frameJSON, _ in
                await eventCapture.recordIntake(frameJSON)
            }
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
        fixture.controller.router.onResponse = { responseJSON in
            await eventCapture.recordResponse()
            await responseCapture.set(responseJSON)
        }
        await fixture.controller.handleIncomingRPC(
            #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
        )
        let spec = sourceSpec(
            fixture: fixture,
            clientRequestId: "request-live",
            pathScope: [],
            includeFileDescriptors: false
        )

        await fixture.controller.handleIncomingRPC(
            try BridgeWorktreeFileSurfaceRPCRequest(
                id: "open-live",
                method: "worktreeFileSurface.openSourceStream",
                params: spec
            ).jsonString()
        )
        let response = try await decodedResponse(from: responseCapture)
        let status = GitWorkingTreeStatus(
            summary: GitWorkingTreeSummary(
                changed: 2,
                staged: 1,
                untracked: 3,
                aheadCount: 5,
                behindCount: 8
            ),
            branch: "ticket-03",
            origin: "git@example.com:repo/project.git"
        )
        try await fixture.controller.publishWorktreeFileSurfaceStatus(status)
        try await fixture.controller.publishWorktreeFileSurfaceChangeset(
            FileChangeset(
                worktreeId: fixture.worktreeId,
                rootPath: fixture.rootURL,
                paths: ["Sources/App/View.swift", ".git/index", "README.md"],
                containsGitInternalChanges: true,
                timestamp: .now,
                batchSeq: 42
            )
        )

        let events = await eventCapture.events()
        #expect(events == ["response", "intake", "intake", "intake"])
        let intakeFrames = await eventCapture.intakeFrames()
        #expect(intakeFrames.count == 3)
        let statusEnvelope = try decodeIntakeEnvelope(
            intakeFrames[0],
            as: BridgeWorktreeStatusPatchFrame.self
        )
        #expect(statusEnvelope.streamId == response.result.streamId)
        #expect(statusEnvelope.generation == response.result.generation)
        #expect(statusEnvelope.sequence == 1)
        #expect(statusEnvelope.payload.frameKind == "worktree.statusPatch")
        #expect(statusEnvelope.payload.patch.branchName == "ticket-03")
        #expect(statusEnvelope.payload.patch.staged == 1)
        #expect(statusEnvelope.payload.patch.unstaged == 2)
        #expect(statusEnvelope.payload.patch.untracked == 3)
        let firstInvalidation = try decodeIntakeEnvelope(
            intakeFrames[1],
            as: BridgeWorktreeFileInvalidatedFrame.self
        )
        let secondInvalidation = try decodeIntakeEnvelope(
            intakeFrames[2],
            as: BridgeWorktreeFileInvalidatedFrame.self
        )
        #expect(firstInvalidation.sequence == 2)
        #expect(secondInvalidation.sequence == 3)
        #expect(firstInvalidation.payload.invalidation.path == "Sources/App/View.swift")
        #expect(secondInvalidation.payload.invalidation.path == "README.md")
        #expect(firstInvalidation.payload.invalidation.reason == .contentChanged)
        #expect(secondInvalidation.payload.invalidation.reason == .contentChanged)
        fixture.controller.teardown()
    }

    private func makeControllerFixture() throws -> BridgeWorktreeFileSurfaceControllerFixture {
        try makeControllerFixtureWithIntakeSink(intakeFrameSink: nil)
    }

    private func makeControllerFixtureWithIntakeSink(
        intakeFrameSink: (@MainActor (WebPage, String, String) async throws -> Void)?
    ) throws -> BridgeWorktreeFileSurfaceControllerFixture {
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
        let controller =
            if let intakeFrameSink {
                BridgePaneController(
                    paneId: paneId,
                    state: state,
                    metadata: metadata,
                    intakeFrameSink: intakeFrameSink
                )
            } else {
                BridgePaneController(paneId: paneId, state: state, metadata: metadata)
            }
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
        pathScope: [String],
        includeFileDescriptors: Bool = false
    ) -> BridgeWorktreeFileSurfaceSourceSpec {
        BridgeWorktreeFileSurfaceSourceSpec(
            clientRequestId: clientRequestId,
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            rootPathToken: fixture.worktree.stableKey,
            cwdScope: nil,
            pathScope: pathScope,
            includeStatuses: true,
            includeFileDescriptors: includeFileDescriptors,
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

    private func decodeIntakeEnvelope<Payload: Decodable>(
        _ json: String,
        as _: Payload.Type
    ) throws -> WorktreeFileIntakeEnvelope<Payload> {
        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(
            WorktreeFileIntakeEnvelope<Payload>.self,
            from: data
        )
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

private struct BridgeWorktreeFileSurfaceIntakeFrameEnvelope: Decodable {
    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let payload: BridgeWorktreeFileDescriptorFrame
}

private struct WorktreeFileIntakeEnvelope<Payload: Decodable>: Decodable {
    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let payload: Payload
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

private actor BridgeWorktreeFileSurfaceEventCapture {
    private var recordedEvents: [String] = []
    private var recordedIntakeFrames: [String] = []

    func recordResponse() {
        recordedEvents.append("response")
    }

    func recordIntake(_ frameJSON: String) {
        recordedEvents.append("intake")
        recordedIntakeFrames.append(frameJSON)
    }

    func events() -> [String] {
        recordedEvents
    }

    func intakeFrames() -> [String] {
        recordedIntakeFrames
    }
}
