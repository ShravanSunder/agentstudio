import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite("BridgePaneController mode-switch suppression catch-up", .serialized)
    struct BridgeModeSwitchCatchUpTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("suppressed review churn catches up when accepted mode flips back to review")
        func suppressedReviewChurnCatchesUpWhenAcceptedModeFlipsBackToReview() async throws {
            let telemetryRecorder = SuppressionCatchUpTelemetryRecorder()
            let fixture = try makeChurnFixture(telemetryRecorder: telemetryRecorder)
            let controller = fixture.controller
            let repoId = fixture.repoId
            let worktreeId = fixture.worktreeId
            let rootURL = fixture.rootURL
            let capturedFrames = fixture.capturedFrames
            defer { try? FileManager.default.removeItem(at: rootURL) }
            defer { controller.teardown() }
            controller.handleBridgeReady()

            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )
            await controller.activeReviewRefreshTask?.value
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            let outcome = try await controller.handleWorktreeFileSurfaceOpenSourceStream(
                makeWorktreeFileSourceSpec(
                    clientRequestId: "review-catch-up-file-open",
                    repoId: repoId,
                    worktreeId: worktreeId,
                    rootURL: rootURL
                )
            )
            await controller.activeWorktreeFileTreeWindowTask?.value
            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(
                    protocolId: "worktree-file",
                    streamId: outcome.streamId,
                    generation: outcome.generation
                )
            )
            await controller.handleBridgeActiveViewerModeUpdate(
                BridgeActiveViewerModeUpdateMethod.Params(
                    sessionId: "session-review-catch-up",
                    sequence: 1,
                    mode: .file,
                    activeSource: BridgeActiveViewerSource(
                        protocolId: .worktreeFile,
                        streamId: outcome.streamId,
                        generation: outcome.generation
                    )
                )
            )
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()
            await capturedFrames.removeAll()

            await controller.handlePaneFilesystemContextEvent(
                .cwdSubtreeChanged(
                    context: PaneFilesystemContext(
                        paneId: PaneId(uuid: controller.paneId),
                        repoId: repoId,
                        cwd: rootURL,
                        worktreeId: worktreeId
                    ),
                    paths: ["File.swift"],
                    batchSeq: 11
                )
            )
            await controller.activeReviewRefreshTask?.value
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()
            #expect(
                !(await capturedFrames.get()).contains { Self.frameKind(of: $0)?.hasPrefix("review.") == true },
                "Review churn should stay silent while file mode is the accepted active viewer"
            )

            let reviewGeneration = try #require(controller.paneState.diff.packageMetadata?.reviewGeneration.rawValue)
            await controller.handleBridgeActiveViewerModeUpdate(
                BridgeActiveViewerModeUpdateMethod.Params(
                    sessionId: "session-review-catch-up",
                    sequence: 2,
                    mode: .review,
                    activeSource: BridgeActiveViewerSource(
                        protocolId: .review,
                        streamId: controller.reviewProtocolStreamId(),
                        generation: reviewGeneration
                    )
                )
            )
            await controller.activeReviewRefreshTask?.value
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            let frames = await capturedFrames.get()
            #expect(
                frames.contains { Self.frameKind(of: $0) == "review.metadataSnapshot" },
                "Returning to review after suppressed churn must deliver a fresh review snapshot"
            )
            let catchUpSamples = await telemetryRecorder.samples(
                named: "performance.bridge.swift.active_viewer_mode_suppression_catch_up"
            )
            #expect(
                catchUpSamples.contains {
                    $0.stringAttributes["agentstudio.bridge.protocol"] == "review"
                        && $0.stringAttributes["agentstudio.bridge.phase"]
                            == "active_viewer_mode_suppression_catch_up"
                }
            )
        }

        @Test("suppressed worktree-file churn catches up when accepted mode flips back to file")
        func suppressedWorktreeFileChurnCatchesUpWhenAcceptedModeFlipsBackToFile() async throws {
            let telemetryRecorder = SuppressionCatchUpTelemetryRecorder()
            let fixture = try makeChurnFixture(telemetryRecorder: telemetryRecorder)
            let controller = fixture.controller
            let repoId = fixture.repoId
            let worktreeId = fixture.worktreeId
            let rootURL = fixture.rootURL
            let capturedFrames = fixture.capturedFrames
            defer { try? FileManager.default.removeItem(at: rootURL) }
            defer { controller.teardown() }
            controller.handleBridgeReady()

            let outcome = try await controller.handleWorktreeFileSurfaceOpenSourceStream(
                makeWorktreeFileSourceSpec(
                    clientRequestId: "worktree-catch-up-file-open",
                    repoId: repoId,
                    worktreeId: worktreeId,
                    rootURL: rootURL
                )
            )
            await controller.activeWorktreeFileTreeWindowTask?.value
            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(
                    protocolId: "worktree-file",
                    streamId: outcome.streamId,
                    generation: outcome.generation
                )
            )
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )
            await controller.activeReviewRefreshTask?.value
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let reviewGeneration = try #require(controller.paneState.diff.packageMetadata?.reviewGeneration.rawValue)
            await controller.handleBridgeActiveViewerModeUpdate(
                BridgeActiveViewerModeUpdateMethod.Params(
                    sessionId: "session-worktree-catch-up",
                    sequence: 1,
                    mode: .review,
                    activeSource: BridgeActiveViewerSource(
                        protocolId: .review,
                        streamId: controller.reviewProtocolStreamId(),
                        generation: reviewGeneration
                    )
                )
            )
            await capturedFrames.removeAll()

            try "let value = 2\n"
                .write(to: rootURL.appending(path: "File.swift"), atomically: true, encoding: .utf8)
            try await controller.publishWorktreeFileSurfaceChangeset(
                FileChangeset(
                    worktreeId: worktreeId,
                    repoId: repoId,
                    rootPath: rootURL,
                    paths: ["File.swift"],
                    timestamp: .now,
                    batchSeq: 21
                )
            )
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()
            #expect(
                !(await capturedFrames.get()).contains {
                    Self.frameKind(of: $0)?.hasPrefix("worktree.") == true
                },
                "Worktree/File churn should stay silent while review mode is the accepted active viewer"
            )

            await controller.handleBridgeActiveViewerModeUpdate(
                BridgeActiveViewerModeUpdateMethod.Params(
                    sessionId: "session-worktree-catch-up",
                    sequence: 2,
                    mode: .file,
                    activeSource: BridgeActiveViewerSource(
                        protocolId: .worktreeFile,
                        streamId: outcome.streamId,
                        generation: outcome.generation
                    )
                )
            )
            await controller.activeWorktreeFileTreeWindowTask?.value
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            let frames = await capturedFrames.get()
            #expect(
                frames.contains { Self.frameKind(of: $0) == "worktree.snapshot" },
                "Returning to file mode after suppressed churn must deliver fresh worktree metadata"
            )
            let catchUpSamples = await telemetryRecorder.samples(
                named: "performance.bridge.swift.active_viewer_mode_suppression_catch_up"
            )
            #expect(
                catchUpSamples.contains {
                    $0.stringAttributes["agentstudio.bridge.protocol"] == "worktree-file"
                        && $0.stringAttributes["agentstudio.bridge.phase"]
                            == "active_viewer_mode_suppression_catch_up"
                }
            )
        }

        private func makeChurnFixture(
            telemetryRecorder: any BridgePerformanceTraceRecording
        ) throws -> SuppressionCatchUpFixture {
            let capturedFrames = SuppressionCatchUpFrameCapture()
            let repoId = UUIDv7.generate()
            let worktreeId = UUIDv7.generate()
            let rootURL = try makeWorktreeFixtureDirectory()
            try "let value = 1\n"
                .write(to: rootURL.appending(path: "File.swift"), atomically: true, encoding: .utf8)
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(rootPath: rootURL.path, baseline: .headMinusOne)
                ),
                metadata: PaneMetadata(
                    contentType: .diff,
                    launchDirectory: rootURL,
                    title: "Bridge Review",
                    facets: PaneContextFacets(
                        repoId: repoId,
                        worktreeId: worktreeId,
                        worktreeName: "mode-switch-worktree",
                        cwd: rootURL
                    )
                ),
                reviewSourceProvider: makeReviewProvider(),
                telemetryRecorder: telemetryRecorder,
                intakeFrameSink: { _, frameJSON, _ in
                    await capturedFrames.append(frameJSON)
                }
            )
            return SuppressionCatchUpFixture(
                controller: controller,
                rootURL: rootURL,
                repoId: repoId,
                worktreeId: worktreeId,
                capturedFrames: capturedFrames
            )
        }

        private func makeReviewProvider() -> BridgeReviewSourceProviderFake {
            BridgeReviewSourceProviderFake(
                comparison: BridgeEndpointComparison(
                    baseEndpoint: makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef),
                    headEndpoint: makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree),
                    changedFiles: [
                        makeBridgeEndpointChangedFile(
                            fileId: "source",
                            path: "Sources/App/View.swift",
                            sizeBytes: 100
                        )
                    ]
                ),
                contentByHandleId: [:]
            )
        }

        private func makeWorktreeFixtureDirectory() throws -> URL {
            let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "agentstudio-suppression-catch-up-\(UUIDv7.generate().uuidString)")
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            return rootURL
        }

        private func makeWorktreeFileSourceSpec(
            clientRequestId: String,
            repoId: UUID,
            worktreeId: UUID,
            rootURL: URL
        ) -> BridgeWorktreeFileSurfaceSourceSpec {
            BridgeWorktreeFileSurfaceSourceSpec(
                clientRequestId: clientRequestId,
                repoId: repoId,
                worktreeId: worktreeId,
                rootPathToken: Worktree(
                    id: worktreeId,
                    repoId: repoId,
                    name: "mode-switch-worktree",
                    path: rootURL
                ).stableKey,
                cwdScope: nil,
                pathScope: [],
                includeStatuses: true,
                includeComments: false,
                includeAgentComms: false,
                freshness: .live
            )
        }

        private static func frameKind(of frameJSON: String) -> String? {
            guard let data = frameJSON.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let payload = object["payload"] as? [String: Any]
            else {
                return nil
            }
            return payload["frameKind"] as? String
        }
    }
}

private actor SuppressionCatchUpFrameCapture {
    private var frames: [String] = []

    func append(_ frameJSON: String) {
        frames.append(frameJSON)
    }

    func get() -> [String] {
        frames
    }

    func removeAll() {
        frames.removeAll()
    }
}

private actor SuppressionCatchUpTelemetryRecorder: BridgePerformanceTraceRecording {
    private var recordedSamples: [BridgeTelemetrySample] = []

    func record(sample: BridgeTelemetrySample, receivedAtUnixNano _: UInt64) {
        recordedSamples.append(sample)
    }

    func recordDrop(
        reason _: BridgeTelemetryDropReason,
        droppedCount _: Int,
        receivedAtUnixNano _: UInt64
    ) {}

    func drain() async throws {}

    func samples(named sampleName: String) -> [BridgeTelemetrySample] {
        recordedSamples.filter { $0.name == sampleName }
    }
}

@MainActor
private struct SuppressionCatchUpFixture {
    let controller: BridgePaneController
    let rootURL: URL
    let repoId: UUID
    let worktreeId: UUID
    let capturedFrames: SuppressionCatchUpFrameCapture
}
