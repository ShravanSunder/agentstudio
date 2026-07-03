import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    /// End-to-end review package load through the PRODUCTION provider factory
    /// against a real git repository — the layer every fake-backed Bridge
    /// review test skips. Mirrors the shape a workspace pane gets from
    /// `openBridgeReview`: `.workspace` source with the
    /// `.localDefaultBranch("main")` default baseline over a single-commit
    /// repo with working-tree changes (the review-to-file-view smoke's exact
    /// fixture shape, which produced a native review error frame in the live
    /// app on 2026-07-03).
    @MainActor
    @Suite(.serialized)
    struct BridgePaneControllerRealGitReviewLoadTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("a real single-commit repo with working-tree changes loads a review package end-to-end")
        func realGitSingleCommitRepoLoadsReviewPackage() async throws {
            let capturedFrames = RealGitReviewFrameCapture()
            let repoURL = try FilesystemTestGitRepo.create(named: "bridge-review-controller-load")
            defer { FilesystemTestGitRepo.destroy(repoURL) }
            try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repoURL)
            let provider = BridgeReviewSourceProviderFactory.gitProvider(repositoryPath: repoURL)
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(
                        rootPath: repoURL.path,
                        baseline: .localDefaultBranch(branchName: "main")
                    )
                ),
                metadata: PaneMetadata(
                    contentType: .diff,
                    launchDirectory: repoURL,
                    title: "Bridge Review",
                    facets: PaneContextFacets(
                        repoId: UUIDv7.generate(),
                        worktreeId: UUIDv7.generate(),
                        worktreeName: "real-git-review",
                        cwd: repoURL
                    )
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
            await controller.activeReviewRefreshTask?.value
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            guard let result else {
                Issue.record("Real-git review load was skipped by the bootstrap guard")
                return
            }
            if case .failure(let error) = result {
                Issue.record("Real-git review load failed: \(String(describing: error))")
                return
            }
            #expect(controller.paneState.diff.status == .ready)
            let frames = await capturedFrames.get()
            #expect(
                frames.contains { frameKind(of: $0) == "review.metadataSnapshot" },
                "A real-git review load must deliver a metadata snapshot frame"
            )
            #expect(
                !frames.contains { frameKind(of: $0) == "review.error" },
                "A real-git review load must not push a review error frame"
            )
        }

        private func frameKind(of frameJSON: String) -> String? {
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

private actor RealGitReviewFrameCapture {
    private var frames: [String] = []

    func append(_ frameJSON: String) {
        frames.append(frameJSON)
    }

    func get() -> [String] {
        frames
    }
}
