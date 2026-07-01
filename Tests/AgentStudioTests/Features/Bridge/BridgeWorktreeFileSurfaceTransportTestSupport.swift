import Foundation
import Testing
import WebKit

@testable import AgentStudio

@MainActor
protocol BridgeWorktreeFileSurfaceTransportTestHelpers {}

extension WebKitSerializedTests.BridgeWorktreeFileSurfaceTransportTests:
    BridgeWorktreeFileSurfaceTransportTestHelpers
{}

extension WebKitSerializedTests.BridgeWorktreeFileSurfaceDescriptorTransportTests:
    BridgeWorktreeFileSurfaceTransportTestHelpers
{}

extension WebKitSerializedTests.BridgeWorktreeFileSurfaceLiveTransportTests:
    BridgeWorktreeFileSurfaceTransportTestHelpers
{}

extension WebKitSerializedTests.BridgeWorktreeFileSurfaceScopeTransportTests:
    BridgeWorktreeFileSurfaceTransportTestHelpers
{}

extension WebKitSerializedTests.BridgeWorktreeFileTreeBoundaryTests:
    BridgeWorktreeFileSurfaceTransportTestHelpers
{}

extension BridgeWorktreeFileSurfaceTransportTestHelpers {
    func makeControllerFixture() throws -> BridgeWorktreeFileSurfaceControllerFixture {
        try makeControllerFixtureWithIntakeSink(intakeFrameSink: nil)
    }

    func makeControllerFixtureWithIntakeSink(
        rootURL providedRootURL: URL? = nil,
        telemetryRecorder: (any BridgePerformanceTraceRecording)? = nil,
        intakeFrameSink: (@MainActor (WebPage, String, String) async throws -> Void)?
    ) throws -> BridgeWorktreeFileSurfaceControllerFixture {
        let paneId = UUIDv7.generate()
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()
        let rootURL: URL
        if let providedRootURL {
            rootURL = providedRootURL
        } else {
            let fixtureDirectoryName = "agentstudio-worktree-file-transport-\(UUIDv7.generate().uuidString)"
            rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: fixtureDirectoryName)
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
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
                    telemetryRecorder: telemetryRecorder,
                    intakeFrameSink: intakeFrameSink
                )
            } else {
                BridgePaneController(
                    paneId: paneId,
                    state: state,
                    metadata: metadata,
                    telemetryRecorder: telemetryRecorder
                )
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

    func sourceSpec(
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
            includeComments: false,
            includeAgentComms: false,
            freshness: .live
        )
    }

    func decodedResponse(
        from capture: BridgeWorktreeFileSurfaceResponseCapture
    ) async throws -> BridgeWorktreeFileSurfaceSuccessResponse {
        let responseJSON = try #require(await capture.get())
        let responseData = try #require(responseJSON.data(using: .utf8))
        return try JSONDecoder().decode(BridgeWorktreeFileSurfaceSuccessResponse.self, from: responseData)
    }

    func resourceBody(
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

    func requestFileDescriptor(
        controller: BridgePaneController,
        requestId: String,
        sourceIdentity: BridgeWorktreeFileSurfaceSourceIdentity,
        row: BridgeWorktreeTreeRowMetadata,
        path: String,
        lane: BridgeDemandLane
    ) async throws {
        await controller.handleIncomingRPC(
            try BridgeWorktreeFileSurfaceRPCRequest(
                id: requestId,
                method: "worktreeFileSurface.requestFileDescriptor",
                params: BridgeWorktreeFileDescriptorRequest(
                    sourceIdentity: sourceIdentity,
                    rowId: row.rowId,
                    path: path,
                    fileId: try #require(row.fileId),
                    lane: lane
                )
            ).jsonString()
        )
    }

    func decodeDescriptorEnvelope(
        _ json: String
    ) throws -> WorktreeFileIntakeEnvelope<BridgeWorktreeFileDescriptorFrame> {
        try decodeIntakeEnvelope(json, as: BridgeWorktreeFileDescriptorFrame.self)
    }

    func decodeIntakeEnvelope<Payload: Decodable>(
        _ json: String,
        as _: Payload.Type
    ) throws -> WorktreeFileIntakeEnvelope<Payload> {
        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(
            WorktreeFileIntakeEnvelope<Payload>.self,
            from: data
        )
    }

    func waitForIntakeFrameCount(
        _ expectedCount: Int,
        from eventCapture: BridgeWorktreeFileSurfaceEventCapture,
        description: String
    ) async {
        await assertEventuallyAsync(description, maxTurns: 200_000) {
            await eventCapture.intakeFrames().count >= expectedCount
        }
    }

    func waitForSnapshotFrame(
        from eventCapture: BridgeWorktreeFileSurfaceEventCapture
    ) async throws -> WorktreeFileIntakeEnvelope<BridgeWorktreeSnapshotFrame> {
        await waitForIntakeFrameCount(
            1,
            from: eventCapture,
            description: "Worktree/File snapshot should stream after intake ready"
        )
        let snapshotJSON = try #require(await eventCapture.intakeFrames().first)
        return try decodeIntakeEnvelope(snapshotJSON, as: BridgeWorktreeSnapshotFrame.self)
    }
}

func writeRootScopedDescriptorFixtureFiles(rootURL: URL) throws {
    let sourceURL = rootURL.appending(path: "Sources/App/View.swift")
    let readmeURL = rootURL.appending(path: "README.md")
    let scratchProbeURL =
        rootURL
        .appending(path: "BridgeWeb")
        .appending(path: "BridgeWeb")
        .appending(path: "tmp")
        .appending(path: "bridge-viewer-worktree-dev-server")
        .appending(path: "2026-06-29-review-probe")
        .appending(path: "review-probe.json")
    let buildArtifactURL =
        rootURL
        .appending(path: ".build-agent-1")
        .appending(path: "debug")
        .appending(path: "generated.txt")
    let gitInternalURL = rootURL.appending(path: ".git/index")

    try FileManager.default.createDirectory(
        at: sourceURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: scratchProbeURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: buildArtifactURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: gitInternalURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try "struct View {}\nlet line = 2\n".write(to: sourceURL, atomically: true, encoding: .utf8)
    try "# Fixture\n".write(to: readmeURL, atomically: true, encoding: .utf8)
    try #"{"probe":true}"#.write(to: scratchProbeURL, atomically: true, encoding: .utf8)
    try "generated build artifact\n".write(to: buildArtifactURL, atomically: true, encoding: .utf8)
    try "git metadata".write(to: gitInternalURL, atomically: true, encoding: .utf8)
}

struct BridgeWorktreeFileSurfaceControllerFixture {
    let paneId: UUID
    let repoId: UUID
    let worktreeId: UUID
    let rootURL: URL
    let worktree: Worktree
    let controller: BridgePaneController
}

struct BridgeWorktreeFileSurfaceRPCRequest<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: String
    let method: String
    let params: Params

    func jsonString() throws -> String {
        let data = try JSONEncoder().encode(self)
        return try #require(String(data: data, encoding: .utf8))
    }
}

struct BridgeWorktreeFileSurfaceSuccessResponse: Decodable {
    let jsonrpc: String
    let id: String
    let result: BridgeWorktreeFileSurfaceOpenSourceOutcome
}

struct BridgeWorktreeFileSurfaceIntakeFrameEnvelope: Decodable {
    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let payload: BridgeWorktreeFileDescriptorFrame
}

struct WorktreeFileIntakeEnvelope<Payload: Decodable>: Decodable {
    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let payload: Payload
}

actor BridgeWorktreeFileSurfaceResponseCapture {
    private var payload: String?

    func set(_ value: String) {
        payload = value
    }

    func get() -> String? {
        payload
    }
}

actor BridgeWorktreeFileSurfaceEventCapture {
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
