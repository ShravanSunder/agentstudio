import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    /// A Bridge pane hosts BOTH viewer modes in one webview and the browser
    /// toggles between them (no reload). Native must bootstrap the protocol a
    /// pane switches INTO regardless of the pane's fixed `panelKind`:
    /// switching to review must yield a review snapshot; switching to file
    /// must yield a worktree-file snapshot plus a tree window.
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

private actor ModeSwitchFrameCapture {
    private var frames: [String] = []

    func append(_ frameJSON: String) {
        frames.append(frameJSON)
    }

    func get() -> [String] {
        frames
    }
}
