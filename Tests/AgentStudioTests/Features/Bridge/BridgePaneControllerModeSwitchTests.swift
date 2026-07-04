import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    /// Native must bootstrap whichever Bridge protocol the shared webview switches into.
    @MainActor
    @Suite(.serialized)
    struct BridgePaneControllerModeSwitchTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("file viewer pane bootstraps a review package so a switch to review has content")
        func fileViewerPaneEmitsReviewSnapshotForReviewModeSwitch() async throws {
            let capturedFrames = ModeSwitchFrameCapture()
            let repoId = UUIDv7.generate()
            let worktreeId = UUIDv7.generate()
            let provider = makeReviewProvider()
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(
                    panelKind: .fileViewer,
                    source: .workspace(rootPath: "/tmp/worktree", baseline: .unstaged)
                ),
                metadata: PaneMetadata(
                    contentType: .diff,
                    title: "Files",
                    facets: PaneContextFacets(repoId: repoId, worktreeId: worktreeId)
                ),
                reviewSourceProvider: provider,
                intakeFrameSink: { _, frameJSON, _ in
                    await capturedFrames.append(frameJSON)
                }
            )
            defer { controller.teardown() }
            controller.handleBridgeReady()

            let result = await controller.loadInitialReviewPackageIfPossible(correlationId: nil)

            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            guard case .success = result else {
                Issue.record("File-viewer pane must load its review package for a review-mode switch")
                return
            }
            #expect(controller.paneState.diff.status == .ready)
            #expect(controller.paneState.diff.packageMetadata?.query.worktreeId == worktreeId)
            let frames = await capturedFrames.get()
            #expect(
                frames.contains { Self.frameKind(of: $0) == "review.metadataSnapshot" },
                "A switch to review must deliver a review snapshot frame"
            )
        }

        @Test("review intake-ready announce alone bootstraps the review package and delivers a snapshot")
        func reviewIntakeReadyAnnounceBootstrapsReviewPackage() async throws {
            let capturedFrames = ModeSwitchFrameCapture()
            let repoId = UUIDv7.generate()
            let worktreeId = UUIDv7.generate()
            let provider = makeReviewProvider()
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(
                    panelKind: .fileViewer,
                    source: .workspace(rootPath: "/tmp/worktree", baseline: .unstaged)
                ),
                metadata: PaneMetadata(
                    contentType: .diff,
                    title: "Files",
                    facets: PaneContextFacets(repoId: repoId, worktreeId: worktreeId)
                ),
                reviewSourceProvider: provider,
                intakeFrameSink: { _, frameJSON, _ in
                    await capturedFrames.append(frameJSON)
                }
            )
            defer { controller.teardown() }
            controller.handleBridgeReady()

            // The switched-in review surface re-runs only its intake-ready
            // announce (no explicit load call); native must bootstrap the
            // package from that announce, exactly like a fresh mount.
            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )
            await controller.activeReviewRefreshTask?.value
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            #expect(controller.paneState.diff.packageMetadata?.query.worktreeId == worktreeId)
            let frames = await capturedFrames.get()
            #expect(
                frames.contains { Self.frameKind(of: $0) == "review.metadataSnapshot" },
                "A review intake-ready announce must bootstrap and deliver a review snapshot"
            )
        }

        @Test("review intake-ready announce on a loaded pane re-delivers a fresh snapshot generation")
        func reviewIntakeReadyAnnounceOnLoadedPaneRedeliversFreshGeneration() async throws {
            let capturedFrames = ModeSwitchFrameCapture()
            let provider = makeReviewProvider()
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(
                    panelKind: .fileViewer,
                    source: .workspace(rootPath: "/tmp/worktree", baseline: .unstaged)
                ),
                metadata: PaneMetadata(
                    contentType: .diff,
                    title: "Files",
                    facets: PaneContextFacets(repoId: UUIDv7.generate(), worktreeId: UUIDv7.generate())
                ),
                reviewSourceProvider: provider,
                intakeFrameSink: { _, frameJSON, _ in
                    await capturedFrames.append(frameJSON)
                }
            )
            defer { controller.teardown() }
            controller.handleBridgeReady()

            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )
            await controller.activeReviewRefreshTask?.value
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let framesAfterFirstLoad = await capturedFrames.get()
            let firstSnapshotCount =
                framesAfterFirstLoad
                .filter { Self.frameKind(of: $0) == "review.metadataSnapshot" }.count
            #expect(firstSnapshotCount == 1)

            // A browser whose review surface lost the snapshot (dropped while
            // the surface was inactive, sequence gap, fresh receiver) heals by
            // re-announcing. Native must re-deliver as a HIGHER generation:
            // only a higher-generation reset can re-key a browser receiver
            // stuck in resetRequired.
            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )
            await controller.activeReviewRefreshTask?.value
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            let frames = await capturedFrames.get()
            let resetGenerations = frames.compactMap { Self.frameGeneration(of: $0, kind: "review.reset") }
            let snapshotGenerations = frames.compactMap {
                Self.frameGeneration(of: $0, kind: "review.metadataSnapshot")
            }
            #expect(
                resetGenerations.count == 2 && Set(resetGenerations).count == 2,
                "A re-announce on a loaded pane must re-key the browser with a new reset generation"
            )
            #expect(
                snapshotGenerations.count == 2 && Set(snapshotGenerations).count == 2,
                "A re-announce on a loaded pane must re-deliver the snapshot under the new generation"
            )
        }

        @Test("concurrent review intake-ready announces coalesce into one package load")
        func concurrentReviewIntakeReadyAnnouncesCoalesceIntoOnePackageLoad() async throws {
            let capturedFrames = ModeSwitchFrameCapture()
            let comparisonGate = BridgeComparisonGate()
            let provider = BridgeReviewSourceProviderFake(
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
                contentByHandleId: [:],
                comparisonGate: comparisonGate
            )
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(
                    panelKind: .fileViewer,
                    source: .workspace(rootPath: "/tmp/worktree", baseline: .unstaged)
                ),
                metadata: PaneMetadata(
                    contentType: .diff,
                    title: "Files",
                    facets: PaneContextFacets(repoId: UUIDv7.generate(), worktreeId: UUIDv7.generate())
                ),
                reviewSourceProvider: provider,
                intakeFrameSink: { _, frameJSON, _ in
                    await capturedFrames.append(frameJSON)
                }
            )
            defer { controller.teardown() }
            controller.handleBridgeReady()

            // A mode toggle re-announces intake-ready while the first
            // announce's package load is still in flight (held at the
            // comparison gate). The races must coalesce into ONE load: extra
            // generations orphan the browser's adopted stream and its
            // snapshots die as stream_mismatch.
            async let firstAnnounce: Void = controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )
            async let secondAnnounce: Void = controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )
            await comparisonGate.waitForStartedComparisonCount(1)
            await comparisonGate.releaseAll()
            _ = await (firstAnnounce, secondAnnounce)
            await controller.activeReviewRefreshTask?.value
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            let comparisonCount = await provider.recordedComparisonRequestsCount()
            #expect(
                comparisonCount == 1,
                "Racing intake-ready announces must not start a second package load"
            )
            let resetFrameCount = (await capturedFrames.get())
                .filter { Self.frameKind(of: $0) == "review.reset" }
                .count
            #expect(
                resetFrameCount == 1,
                "One package load must produce exactly one review reset generation"
            )
        }

        @Test("review pane opens the worktree-file surface so a switch to file has content")
        func reviewPaneEmitsWorktreeFileSnapshotForFileModeSwitch() async throws {
            let capturedFrames = ModeSwitchFrameCapture()
            let repoId = UUIDv7.generate()
            let worktreeId = UUIDv7.generate()
            let rootURL = try makeWorktreeFixtureDirectory()
            defer { try? FileManager.default.removeItem(at: rootURL) }
            // A separate `worktree.treeWindow` continuation frame only emits
            // past the startup snapshot window, so seed enough files to force
            // one (mirrors the cold-open path that publishes multiple windows).
            for index in 0..<260 {
                try "let value\(index) = \(index)\n".write(
                    to: rootURL.appending(path: String(format: "File-%03d.swift", index)),
                    atomically: true,
                    encoding: .utf8
                )
            }
            let provider = makeReviewProvider()
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
                reviewSourceProvider: provider,
                intakeFrameSink: { _, frameJSON, _ in
                    await capturedFrames.append(frameJSON)
                }
            )
            defer { controller.teardown() }
            controller.handleBridgeReady()

            _ = await controller.loadInitialReviewPackageIfPossible(correlationId: nil)
            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )

            let outcome = try await controller.handleWorktreeFileSurfaceOpenSourceStream(
                BridgeWorktreeFileSurfaceSourceSpec(
                    clientRequestId: "mode-switch-open",
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

            let frames = await capturedFrames.get()
            #expect(
                frames.contains { Self.frameKind(of: $0) == "review.metadataSnapshot" },
                "The review package loaded at creation must still deliver its snapshot"
            )
            #expect(
                frames.contains { Self.frameKind(of: $0) == "worktree.snapshot" },
                "A switch to file must deliver a worktree-file snapshot frame"
            )
            #expect(
                frames.contains { Self.frameKind(of: $0) == "worktree.treeWindow" },
                "A switch to file must deliver at least one tree window batch"
            )
        }

        @Test("file clicks keep working after review load and refresh churn on the same pane")
        func fileDescriptorRequestSurvivesReviewChurnOnSamePane() async throws {
            let fixture = try makeChurnFixture()
            let controller = fixture.controller
            let repoId = fixture.repoId
            let worktreeId = fixture.worktreeId
            let rootURL = fixture.rootURL
            let capturedFrames = fixture.capturedFrames
            defer { try? FileManager.default.removeItem(at: rootURL) }
            defer { controller.teardown() }
            controller.handleBridgeReady()

            // Switch to file: open the surface and land the snapshot.
            let outcome = try await controller.handleWorktreeFileSurfaceOpenSourceStream(
                BridgeWorktreeFileSurfaceSourceSpec(
                    clientRequestId: "churn-open",
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
            let fileRow = try #require(
                Self.firstFileRow(in: await capturedFrames.get()),
                "The worktree-file snapshot must publish at least one file row"
            )

            // Churn the OTHER protocol: load review and drive a refresh through
            // the shared metadata scheduler while the file surface stays open.
            _ = await controller.loadInitialReviewPackageIfPossible(correlationId: nil)
            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )
            await controller.handlePaneFilesystemContextEvent(
                .cwdSubtreeChanged(
                    context: PaneFilesystemContext(
                        paneId: PaneId(uuid: controller.paneId),
                        repoId: repoId,
                        cwd: rootURL,
                        worktreeId: worktreeId
                    ),
                    paths: ["File.swift"],
                    batchSeq: 7
                )
            )
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            // The file "click": a descriptor request must still resolve to a
            // descriptor frame — the file surface is not wedged by review churn.
            let source = try #require(controller.activeWorktreeFileSurfaceSource?.source)
            _ = try await controller.handleWorktreeFileDescriptorRequest(
                BridgeWorktreeFileDescriptorRequest(
                    sourceIdentity: source,
                    rowId: fileRow.rowId,
                    path: fileRow.path,
                    fileId: fileRow.fileId,
                    lane: .foreground
                )
            )
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            #expect(
                (await capturedFrames.get()).contains {
                    Self.frameKind(of: $0) == "worktree.fileDescriptor"
                },
                "A file click must still deliver a descriptor frame after review churn"
            )
        }

        @Test("explicit review intake clears stale file gate and delivers review snapshot")
        func explicitReviewIntakeClearsStaleFileGateAndDeliversReviewSnapshot() async throws {
            let fixture = try makeChurnFixture()
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
                    clientRequestId: "active-file-open",
                    repoId: repoId,
                    worktreeId: worktreeId,
                    rootURL: rootURL
                )
            )
            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(
                    protocolId: "worktree-file",
                    streamId: outcome.streamId,
                    generation: outcome.generation
                )
            )
            await controller.activeWorktreeFileTreeWindowTask?.value
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            await controller.handleIncomingRPC(
                Self.activeViewerModeUpdateJSON(
                    sessionId: "session-active-file",
                    sequence: 1,
                    mode: "file",
                    protocolId: "worktree-file",
                    streamId: outcome.streamId,
                    generation: outcome.generation
                )
            )

            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )
            await controller.activeReviewRefreshTask?.value
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            let frames = await capturedFrames.get()
            #expect(
                frames.contains { Self.frameKind(of: $0) == "review.metadataSnapshot" },
                "An explicit review intake announce must not lose to stale accepted file mode"
            )
            #expect(
                controller.nextReviewProtocolSequence > 0,
                "Explicit review delivery must consume review sequence after clearing stale file mode"
            )
        }

        @Test("valid active-review signal suppresses inactive worktree production")
        func validActiveReviewSignalSuppressesWorktreeProduction() async throws {
            let fixture = try makeChurnFixture()
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
            let reviewGeneration = try #require(controller.paneState.diff.packageMetadata?.reviewGeneration.rawValue)
            await controller.handleIncomingRPC(
                Self.activeViewerModeUpdateJSON(
                    sessionId: "session-active-review",
                    sequence: 1,
                    mode: "review",
                    protocolId: "review",
                    streamId: controller.reviewProtocolStreamId(),
                    generation: reviewGeneration
                )
            )

            _ = try await controller.handleWorktreeFileSurfaceOpenSourceStream(
                makeWorktreeFileSourceSpec(
                    clientRequestId: "inactive-file-open",
                    repoId: repoId,
                    worktreeId: worktreeId,
                    rootURL: rootURL
                )
            )
            await controller.activeWorktreeFileTreeWindowTask?.value
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            let frames = await capturedFrames.get()
            #expect(
                !frames.contains { Self.frameKind(of: $0) == "worktree.snapshot" },
                "A valid active-review signal must suppress inactive worktree initial production"
            )
            #expect(
                !frames.contains { Self.frameKind(of: $0) == "worktree.treeWindow" },
                "A valid active-review signal must suppress inactive worktree tree-window production"
            )
        }

        @Test("explicit worktree-file open clears stale review gate and publishes file frames")
        func explicitWorktreeFileOpenClearsStaleReviewGateAndPublishesFileFrames() async throws {
            let fixture = try makeChurnFixture()
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
            let reviewGeneration = try #require(controller.paneState.diff.packageMetadata?.reviewGeneration.rawValue)
            await controller.handleIncomingRPC(
                Self.activeViewerModeUpdateJSON(
                    sessionId: "session-stale-review-before-file-open",
                    sequence: 1,
                    mode: "review",
                    protocolId: "review",
                    streamId: controller.reviewProtocolStreamId(),
                    generation: reviewGeneration
                )
            )

            let outcome = try await controller.handleWorktreeFileSurfaceOpenSourceStream(
                makeWorktreeFileSourceSpec(
                    clientRequestId: "explicit-file-open-clears-review-gate",
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

            let frames = await capturedFrames.get()
            #expect(
                frames.contains { Self.frameKind(of: $0) == "worktree.snapshot" },
                "An explicit Worktree/File open must not lose to a stale accepted review mode"
            )
        }

        @Test("stale active-viewer sequence clears accepted state so file production fails open")
        func staleActiveViewerSequenceClearsAcceptedStateSoFileProductionFailsOpen() async throws {
            let fixture = try makeChurnFixture()
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
                    clientRequestId: "stale-sequence-open",
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
            await controller.handleIncomingRPC(
                Self.activeViewerModeUpdateJSON(
                    sessionId: "session-stale-sequence",
                    sequence: 2,
                    mode: "review",
                    protocolId: "review",
                    streamId: controller.reviewProtocolStreamId(),
                    generation: reviewGeneration
                )
            )
            await controller.handleIncomingRPC(
                Self.activeViewerModeUpdateJSON(
                    sessionId: "session-stale-sequence",
                    sequence: 1,
                    mode: "file",
                    protocolId: "worktree-file",
                    streamId: outcome.streamId,
                    generation: outcome.generation
                )
            )

            try await controller.publishWorktreeFileSurfaceStatus(
                GitWorkingTreeStatus(
                    summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                    branch: "main",
                    originResolution: .awaitingResolution
                )
            )
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            #expect(
                (await capturedFrames.get()).contains { Self.frameKind(of: $0) == "worktree.statusPatch" },
                "A stale rejected mode signal must clear accepted state so later file publish gates fail open"
            )
        }

        @Test("explicit file descriptor request clears stale review gate and delivers descriptor frame")
        func explicitFileDescriptorRequestClearsStaleReviewGateAndDeliversDescriptorFrame() async throws {
            let fixture = try makeChurnFixture()
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
                    clientRequestId: "descriptor-gate-open",
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
            let fileRow = try #require(
                Self.firstFileRow(in: await capturedFrames.get()),
                "The worktree-file snapshot must publish at least one file row"
            )

            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )
            await controller.activeReviewRefreshTask?.value
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let reviewGeneration = try #require(controller.paneState.diff.packageMetadata?.reviewGeneration.rawValue)
            await controller.handleIncomingRPC(
                Self.activeViewerModeUpdateJSON(
                    sessionId: "session-descriptor-stale-review",
                    sequence: 1,
                    mode: "review",
                    protocolId: "review",
                    streamId: controller.reviewProtocolStreamId(),
                    generation: reviewGeneration
                )
            )

            let source = try #require(controller.activeWorktreeFileSurfaceSource?.source)
            _ = try await controller.handleWorktreeFileDescriptorRequest(
                BridgeWorktreeFileDescriptorRequest(
                    sourceIdentity: source,
                    rowId: fileRow.rowId,
                    path: fileRow.path,
                    fileId: fileRow.fileId,
                    lane: .foreground
                )
            )
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            #expect(
                (await capturedFrames.get()).contains {
                    Self.frameKind(of: $0) == "worktree.fileDescriptor"
                },
                "A user-driven descriptor request must clear stale review mode evidence and deliver"
            )
        }

        @Test("stale active-viewer generation signal fails open")
        func staleActiveViewerGenerationSignalFailsOpen() async throws {
            let fixture = try makeChurnFixture()
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
                    clientRequestId: "stale-file-open",
                    repoId: repoId,
                    worktreeId: worktreeId,
                    rootURL: rootURL
                )
            )
            await controller.handleIncomingRPC(
                Self.activeViewerModeUpdateJSON(
                    sessionId: "session-stale-file",
                    sequence: 1,
                    mode: "file",
                    protocolId: "worktree-file",
                    streamId: outcome.streamId,
                    generation: outcome.generation + 1
                )
            )

            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )
            await controller.activeReviewRefreshTask?.value
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            #expect(
                (await capturedFrames.get()).contains { Self.frameKind(of: $0) == "review.metadataSnapshot" },
                "A stale active-source generation must be ignored so review delivery fails open"
            )
        }

        @Test("missing active-viewer source fails open")
        func missingActiveViewerSourceFailsOpen() async throws {
            let capturedFrames = ModeSwitchFrameCapture()
            let provider = makeReviewProvider()
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(
                    panelKind: .fileViewer,
                    source: .workspace(rootPath: "/tmp/worktree", baseline: .unstaged)
                ),
                metadata: PaneMetadata(
                    contentType: .diff,
                    title: "Files",
                    facets: PaneContextFacets(repoId: UUIDv7.generate(), worktreeId: UUIDv7.generate())
                ),
                reviewSourceProvider: provider,
                intakeFrameSink: { _, frameJSON, _ in
                    await capturedFrames.append(frameJSON)
                }
            )
            defer { controller.teardown() }
            controller.handleBridgeReady()

            await controller.handleIncomingRPC(
                Self.activeViewerModeUpdateJSON(
                    sessionId: "session-null-source",
                    sequence: 1,
                    mode: "file",
                    protocolId: nil,
                    streamId: nil,
                    generation: nil
                )
            )
            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )
            await controller.activeReviewRefreshTask?.value
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            #expect(
                (await capturedFrames.get()).contains { Self.frameKind(of: $0) == "review.metadataSnapshot" },
                "A null activeSource observation is not a valid gate and must fail open"
            )
        }
    }
}

extension WebKitSerializedTests.BridgePaneControllerModeSwitchTests {
    private static func firstFileRow(
        in frames: [String]
    ) -> (rowId: String, path: String, fileId: String)? {
        for frameJSON in frames {
            guard let data = frameJSON.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let payload = object["payload"] as? [String: Any],
                payload["frameKind"] as? String == "worktree.snapshot",
                let rows = payload["treeRows"] as? [[String: Any]]
            else {
                continue
            }
            for row in rows where row["isDirectory"] as? Bool == false {
                if let rowId = row["rowId"] as? String,
                    let path = row["path"] as? String,
                    let fileId = row["fileId"] as? String
                {
                    return (rowId: rowId, path: path, fileId: fileId)
                }
            }
        }
        return nil
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
            .appending(path: "agentstudio-mode-switch-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    /// Shared setup for coexistence/churn tests; callers own cleanup.
    private func makeChurnFixture() throws -> ModeSwitchChurnFixture {
        let capturedFrames = ModeSwitchFrameCapture()
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
            intakeFrameSink: { _, frameJSON, _ in
                await capturedFrames.append(frameJSON)
            }
        )
        return ModeSwitchChurnFixture(
            controller: controller,
            rootURL: rootURL,
            repoId: repoId,
            worktreeId: worktreeId,
            capturedFrames: capturedFrames
        )
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

    private static func activeViewerModeUpdateJSON(
        sessionId: String,
        sequence: Int,
        mode: String,
        protocolId: String?,
        streamId: String?,
        generation: Int?
    ) -> String {
        let activeSourceJSON: String
        if let protocolId, let streamId, let generation {
            activeSourceJSON = """
                {
                  "protocol": "\(protocolId)",
                  "streamId": "\(streamId)",
                  "generation": \(generation)
                }
                """
        } else {
            activeSourceJSON = "null"
        }
        return """
            {
              "jsonrpc": "2.0",
              "method": "bridge.activeViewerMode.update",
              "params": {
                "sessionId": "\(sessionId)",
                "sequence": \(sequence),
                "mode": "\(mode)",
                "activeSource": \(activeSourceJSON)
              }
            }
            """
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

    private static func frameGeneration(of frameJSON: String, kind: String) -> Int? {
        guard let data = frameJSON.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let payload = object["payload"] as? [String: Any],
            payload["frameKind"] as? String == kind
        else {
            return nil
        }
        return payload["generation"] as? Int
    }
}

private actor ModeSwitchFrameCapture {
    private var frames: [String] = []

    func append(_ frameJSON: String) {
        frames.append(frameJSON)
    }

    func get() -> [String] {
        frames
    }
}

@MainActor
private struct ModeSwitchChurnFixture {
    let controller: BridgePaneController
    let rootURL: URL
    let repoId: UUID
    let worktreeId: UUID
    let capturedFrames: ModeSwitchFrameCapture
}
