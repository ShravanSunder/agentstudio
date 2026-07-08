import Foundation
import Testing
import WebKit

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct BridgeWorktreeFileSurfaceLiveTransportTests {
        init() {
            installTestAtomRegistryIfNeeded()
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
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await eventCapture.recordResponse()
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            let spec = sourceSpec(
                fixture: fixture,
                clientRequestId: "request-live",
                pathScope: []
            )

            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-live",
                    method: "worktreeFileSurface.openSourceStream",
                    params: spec
                ).jsonString()
            )
            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            let snapshotEnvelope = try await waitForSnapshotFrame(from: eventCapture)
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
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()

            let events = await eventCapture.events()
            #expect(events == ["response", "intake", "intake", "intake", "intake"])
            let intakeFrames = await eventCapture.intakeFrames()
            #expect(intakeFrames.count == 4)
            #expect(snapshotEnvelope.kind == "snapshot")
            #expect(snapshotEnvelope.streamId == response.result.streamId)
            let statusEnvelope = try decodeIntakeEnvelope(
                intakeFrames[1],
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
                intakeFrames[2],
                as: BridgeWorktreeFileInvalidatedFrame.self
            )
            let secondInvalidation = try decodeIntakeEnvelope(
                intakeFrames[3],
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

        @Test("live Worktree/File invalidation carries latest descriptor and serves replacement bytes")
        func liveWorktreeFileInvalidationCarriesLatestDescriptorAndServesReplacementBytes() async throws {
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
            let updatedText = "struct View {}\nlet updated = true\n"
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try updatedText.write(to: fileURL, atomically: true, encoding: .utf8)
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await eventCapture.recordResponse()
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            let spec = sourceSpec(
                fixture: fixture,
                clientRequestId: "request-replacement",
                pathScope: []
            )

            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-replacement",
                    method: "worktreeFileSurface.openSourceStream",
                    params: spec
                ).jsonString()
            )
            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            let snapshot = try await waitForSnapshotFrame(from: eventCapture)
            try await fixture.controller.publishWorktreeFileSurfaceChangeset(
                FileChangeset(
                    worktreeId: fixture.worktreeId,
                    rootPath: fixture.rootURL,
                    paths: ["Sources/App/View.swift"],
                    timestamp: .now,
                    batchSeq: 43
                )
            )
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()

            let intakeFrames = await eventCapture.intakeFrames()
            #expect(snapshot.streamId == response.result.streamId)
            // The watch-event changeset also emits a worktree.treeDelta frame
            // (manifest index reconcile), so select the invalidation frame by
            // shape instead of a fixed index.
            let invalidation = try #require(
                intakeFrames.compactMap { frameJSON in
                    try? decodeIntakeEnvelope(
                        frameJSON,
                        as: BridgeWorktreeFileInvalidatedFrame.self
                    )
                }.first
            )
            let latestDescriptor = try #require(invalidation.payload.invalidation.latestDescriptor)
            #expect(invalidation.streamId == response.result.streamId)
            #expect(invalidation.sequence == 2)
            #expect(latestDescriptor.path == "Sources/App/View.swift")
            #expect(latestDescriptor.virtualizedExtentKind == .exactLineCount)
            #expect(latestDescriptor.lineCount == 3)
            let contentResource = try #require(
                BridgeTransportResourceURL.parse(
                    latestDescriptor.contentDescriptor.descriptor.resourceUrl,
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
                url: latestDescriptor.contentDescriptor.descriptor.resourceUrl,
                handler: schemeHandler
            )
            #expect(String(data: contentBody, encoding: .utf8) == updatedText)
            fixture.controller.teardown()
        }

        @Test("live Worktree/File reset revokes source leases and suppresses stale frames")
        func liveWorktreeFileResetRevokesSourceLeasesAndSuppressesStaleFrames() async throws {
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await eventCapture.recordResponse()
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )

            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-reset",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-reset",
                        pathScope: []
                    )
                ).jsonString()
            )
            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            let snapshot = try await waitForSnapshotFrame(from: eventCapture)
            #expect(snapshot.payload.frameKind == "worktree.snapshot")

            try await fixture.controller.publishWorktreeFileSurfaceReset(reason: .providerRestart)
            try await fixture.controller.publishWorktreeFileSurfaceStatus(
                GitWorkingTreeStatus(
                    summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                    branch: "stale",
                    origin: nil
                )
            )
            // Drain fully before asserting suppression: the stale status must
            // not deliver even once the scheduler has run everything it holds.
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()

            let intakeFrames = await eventCapture.intakeFrames()
            #expect(intakeFrames.count == 2)
            let reset = try decodeIntakeEnvelope(
                intakeFrames[1],
                as: BridgeWorktreeResetFrame.self
            )
            #expect(reset.streamId == response.result.streamId)
            #expect(reset.sequence == 1)
            #expect(reset.payload.frameKind == "worktree.reset")
            #expect(reset.payload.reason == .providerRestart)
            #expect(reset.payload.source == snapshot.payload.source)
            fixture.controller.teardown()
        }
    }
}
