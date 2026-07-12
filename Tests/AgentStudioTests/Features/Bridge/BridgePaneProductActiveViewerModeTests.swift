import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite("Bridge pane product active-viewer mode", .serialized)
    struct BridgePaneProductActiveViewerModeTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("committed File product mode suppresses Review production")
        func committedFileProductModeSuppressesReviewProduction() async throws {
            let controller = makeController()
            defer { controller.teardown() }
            let activeSource = BridgeActiveViewerSource(
                protocolId: .worktreeFile,
                streamId: "product-file-stream",
                generation: 41
            )

            await controller.handleCommittedProductActiveViewerModeUpdate(
                sessionId: "product-session",
                sequence: 1,
                mode: .file,
                activeSource: activeSource
            )

            let acceptedSignal = try #require(controller.activeViewerModeSignalState.acceptedSignal)
            #expect(acceptedSignal.mode == .file)
            #expect(acceptedSignal.activeSource == activeSource)
            #expect(controller.shouldSuppressReviewProtocolProduction(generation: 999))
        }

        @Test("committed File to Review switch catches up suppressed Review metadata")
        func committedFileToReviewSwitchCatchesUpSuppressedReviewMetadata() async throws {
            // Arrange
            let frameCapture = ProductActiveViewerReviewFrameCapture()
            let controller = makeReviewController(frameCapture: frameCapture)
            defer { controller.teardown() }
            #expect(controller.handleBridgeReady())
            guard case .success = await controller.loadInitialReviewPackageIfPossible(correlationId: nil) else {
                Issue.record("Expected the Review package fixture to load")
                return
            }
            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )
            await controller.activeReviewRefreshTask?.value
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let package = try #require(controller.paneState.diff.packageMetadata)
            await frameCapture.removeAll()
            await controller.handleCommittedProductActiveViewerModeUpdate(
                sessionId: "product-mode-switch-session",
                sequence: 1,
                mode: .file,
                activeSource: BridgeActiveViewerSource(
                    protocolId: .worktreeFile,
                    streamId: "product-file-stream",
                    generation: 1
                )
            )

            // Act
            await controller.commitReviewPackageLoad(
                BridgeReviewPackageLoadData(package: package, delta: nil),
                traceContext: nil
            )
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let framesWhileFileIsActive = await frameCapture.frames
            let suppressedDrop = controller.reviewProtocolSuppressedDrop
            await controller.handleCommittedProductActiveViewerModeUpdate(
                sessionId: "product-mode-switch-session",
                sequence: 2,
                mode: .review,
                activeSource: BridgeActiveViewerSource(
                    protocolId: .review,
                    streamId: controller.reviewProtocolStreamId(),
                    generation: package.reviewGeneration.rawValue
                )
            )
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            // Assert
            #expect(framesWhileFileIsActive.isEmpty)
            #expect(suppressedDrop != nil)
            #expect(controller.reviewProtocolSuppressedDrop == nil)
            #expect(
                (await frameCapture.frames).contains {
                    ProductActiveViewerReviewFrameCapture.frameKind(of: $0)
                        == "review.metadataSnapshot"
                }
            )
        }

        @Test("replayed committed File hint cannot replace the accepted sequence")
        func replayedCommittedFileHintIsIgnored() async throws {
            let controller = makeController()
            defer { controller.teardown() }
            let acceptedSource = BridgeActiveViewerSource(
                protocolId: .worktreeFile,
                streamId: "accepted-file-stream",
                generation: 7
            )
            await controller.handleCommittedProductActiveViewerModeUpdate(
                sessionId: "product-session",
                sequence: 2,
                mode: .file,
                activeSource: acceptedSource
            )

            await controller.handleCommittedProductActiveViewerModeUpdate(
                sessionId: "product-session",
                sequence: 2,
                mode: .file,
                activeSource: BridgeActiveViewerSource(
                    protocolId: .worktreeFile,
                    streamId: "replayed-file-stream",
                    generation: 8
                )
            )

            #expect(controller.activeViewerModeSignalState.lastSequence == 2)
            #expect(controller.activeViewerModeSignalState.acceptedSignal?.activeSource == acceptedSource)
        }

        @Test("mismatched product File source fails open")
        func mismatchedProductFileSourceFailsOpen() async {
            let controller = makeController()
            defer { controller.teardown() }

            await controller.handleCommittedProductActiveViewerModeUpdate(
                sessionId: "product-session",
                sequence: 1,
                mode: .file,
                activeSource: BridgeActiveViewerSource(
                    protocolId: .review,
                    streamId: "review-stream",
                    generation: 1
                )
            )

            #expect(controller.activeViewerModeSignalState.acceptedSignal == nil)
            #expect(!controller.shouldSuppressReviewProtocolProduction(generation: 1))
        }

        private func makeController() -> BridgePaneController {
            BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(
                    panelKind: .fileViewer,
                    source: .workspace(rootPath: "/tmp/product-file-viewer", baseline: .unstaged)
                )
            )
        }

        private func makeReviewController(
            frameCapture: ProductActiveViewerReviewFrameCapture
        ) -> BridgePaneController {
            BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(
                    panelKind: .fileViewer,
                    source: .workspace(rootPath: "/tmp/product-file-viewer", baseline: .unstaged)
                ),
                metadata: PaneMetadata(
                    contentType: .diff,
                    title: "Files",
                    facets: PaneContextFacets(
                        repoId: UUIDv7.generate(),
                        worktreeId: UUIDv7.generate()
                    )
                ),
                reviewSourceProvider: BridgeReviewSourceProviderFake(
                    comparison: BridgeEndpointComparison(
                        baseEndpoint: makeBridgeEndpoint(
                            endpointId: "baseline-headMinusOne",
                            kind: .gitRef
                        ),
                        headEndpoint: makeBridgeEndpoint(
                            endpointId: "working-tree",
                            kind: .workingTree
                        ),
                        changedFiles: [
                            makeBridgeEndpointChangedFile(
                                fileId: "source",
                                path: "Sources/App/View.swift",
                                sizeBytes: 100
                            )
                        ]
                    ),
                    contentByHandleId: [:]
                ),
                intakeFrameSink: { _, frameJSON, _ in
                    await frameCapture.append(frameJSON)
                }
            )
        }
    }
}

private actor ProductActiveViewerReviewFrameCapture {
    private(set) var frames: [String] = []

    func append(_ frameJSON: String) {
        frames.append(frameJSON)
    }

    func removeAll() {
        frames.removeAll(keepingCapacity: false)
    }

    nonisolated static func frameKind(of frameJSON: String) -> String? {
        guard let data = frameJSON.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let payload = object["payload"] as? [String: Any]
        else {
            return nil
        }
        return payload["frameKind"] as? String
    }
}
