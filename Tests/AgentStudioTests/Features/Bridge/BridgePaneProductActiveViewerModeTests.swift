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

        @Test("committed File product mode accepts a worktree File source")
        func committedFileProductModeAcceptsWorktreeFileSource() async throws {
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
            #expect(acceptedSignal.sequenceFloor == 1)
        }

        @Test("committed Review product mode accepts the current stream and generation")
        func committedReviewProductModeAcceptsCurrentStreamAndGeneration() async throws {
            let controller = makeController()
            defer { controller.teardown() }
            let reviewPackage = try productActiveViewerReviewPackageFixture()
            controller.paneState.diff.setPackageMetadata(reviewPackage)
            let activeSource = BridgeActiveViewerSource(
                protocolId: .review,
                streamId: controller.reviewProtocolStreamId(),
                generation: reviewPackage.reviewGeneration.rawValue
            )

            await controller.handleCommittedProductActiveViewerModeUpdate(
                sessionId: "product-review-session",
                sequence: 1,
                mode: .review,
                activeSource: activeSource
            )

            let acceptedSignal = try #require(controller.activeViewerModeSignalState.acceptedSignal)
            #expect(acceptedSignal.mode == .review)
            #expect(acceptedSignal.activeSource == activeSource)
            #expect(acceptedSignal.sequenceFloor == 1)
        }

        @Test("committed Review product mode rejects a stale generation")
        func committedReviewProductModeRejectsStaleGeneration() async throws {
            let controller = makeController()
            defer { controller.teardown() }
            let reviewPackage = try productActiveViewerReviewPackageFixture()
            controller.paneState.diff.setPackageMetadata(reviewPackage)

            await controller.handleCommittedProductActiveViewerModeUpdate(
                sessionId: "product-review-session",
                sequence: 1,
                mode: .review,
                activeSource: BridgeActiveViewerSource(
                    protocolId: .review,
                    streamId: controller.reviewProtocolStreamId(),
                    generation: reviewPackage.reviewGeneration.rawValue + 1
                )
            )

            #expect(controller.activeViewerModeSignalState.lastSequence == 1)
            #expect(controller.activeViewerModeSignalState.acceptedSignal == nil)
        }

        @Test("committed Review product mode rejects a mismatched stream")
        func committedReviewProductModeRejectsMismatchedStream() async throws {
            let controller = makeController()
            defer { controller.teardown() }
            let reviewPackage = try productActiveViewerReviewPackageFixture()
            controller.paneState.diff.setPackageMetadata(reviewPackage)

            await controller.handleCommittedProductActiveViewerModeUpdate(
                sessionId: "product-review-session",
                sequence: 1,
                mode: .review,
                activeSource: BridgeActiveViewerSource(
                    protocolId: .review,
                    streamId: "stale-review-stream",
                    generation: reviewPackage.reviewGeneration.rawValue
                )
            )

            #expect(controller.activeViewerModeSignalState.lastSequence == 1)
            #expect(controller.activeViewerModeSignalState.acceptedSignal == nil)
        }

        @Test("Review package state is installed before product ready publication")
        func reviewPackageStateIsInstalledBeforeProductReadyPublication() async throws {
            // Arrange
            let controllerBox = ProductActiveViewerControllerBox()
            let reviewMetadataRecorder = ProductActiveViewerReviewMetadataRecorder(
                controllerBox: controllerBox
            )
            let productProvider = BridgePaneProductSchemeProvider(
                fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
                reviewMetadataSource: reviewMetadataRecorder,
                reviewContentSource: BridgeUnavailablePaneProductReviewContentSource(),
                markReviewItemViewed: { _ in }
            )
            let paneId = UUIDv7.generate()
            let installation = BridgePaneController.makeInitialProductSessionInstallation(
                paneSessionId: paneId.uuidString,
                provider: productProvider
            )
            let owner = BridgePaneController.makeProductSessionOwner(
                paneSessionId: paneId.uuidString,
                provider: productProvider,
                activeInstallation: installation
            )
            let controller = BridgePaneController(
                paneId: paneId,
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .commit(sha: "product-ready-ordering")
                ),
                productSessionDependencies: BridgePaneProductSessionDependencies(
                    installation: installation,
                    owner: owner,
                    productProvider: productProvider
                )
            )
            controllerBox.controller = controller
            defer { controller.teardown() }

            let harness = try await BridgeProductSessionLifecycleHarness.opened()
            let metadataRequest = try bridgeProductMetadataStreamRequest(
                metadataStreamId: "metadata-product-ready-ordering",
                resumeFromStreamSequence: nil
            )
            let registration = await harness.session.registerMetadataProducer(
                request: metadataRequest
            ) { lease in
                await productProvider.runMetadataProducer(
                    request: metadataRequest,
                    lease: lease,
                    session: harness.session
                )
            }
            let metadataLease = try bridgeProductAcceptedLease(registration)
            #expect(
                await consumeNextBridgeProductProducerFrame(
                    for: metadataLease,
                    from: harness.session
                )?.sequence == 0
            )
            let reviewOpenRequest = try bridgeProductLifecycleControlRequest(
                bridgeProductLifecycleReviewSubscriptionOpenObject(requestSequence: 2, epoch: 1)
            )
            var metadataStreamIsReady = false
            for _ in 0..<1000 {
                if case .subscriptionOpenAccepted = await productProvider.response(for: reviewOpenRequest) {
                    metadataStreamIsReady = true
                    break
                }
                await Task.yield()
            }
            #expect(metadataStreamIsReady)

            let reviewPackage = try productActiveViewerReviewPackageFixture()
            let reviewDelta = BridgeReviewDelta(
                packageId: reviewPackage.packageId,
                reviewGeneration: reviewPackage.reviewGeneration,
                revision: reviewPackage.revision + 1,
                operations: BridgeReviewDelta.Operations()
            )

            // Act
            await controller.commitReviewPackageLoad(
                BridgeReviewPackageLoadData(package: reviewPackage, delta: reviewDelta),
                traceContext: nil
            )
            let observations = await reviewMetadataRecorder.observations

            // Assert
            let observation = try #require(observations.last)
            #expect(observations.count == 1)
            #expect(observation.availability == .ready(reviewPackage))
            #expect(observation.packageMetadata == reviewPackage)
            #expect(observation.packageDelta == reviewDelta)
            #expect(observation.status == .ready)
            try await closeBridgeProductSessionProducer(metadataLease, in: harness.session)
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

        @Test("new product session accepts a lower sequence")
        func newProductSessionAcceptsLowerSequence() async throws {
            let controller = makeController()
            defer { controller.teardown() }
            await controller.handleCommittedProductActiveViewerModeUpdate(
                sessionId: "first-product-session",
                sequence: 9,
                mode: .file,
                activeSource: BridgeActiveViewerSource(
                    protocolId: .worktreeFile,
                    streamId: "first-file-stream",
                    generation: 1
                )
            )
            let replacementSource = BridgeActiveViewerSource(
                protocolId: .worktreeFile,
                streamId: "replacement-file-stream",
                generation: 2
            )

            await controller.handleCommittedProductActiveViewerModeUpdate(
                sessionId: "replacement-product-session",
                sequence: 1,
                mode: .file,
                activeSource: replacementSource
            )

            #expect(controller.activeViewerModeSignalState.sessionId == "replacement-product-session")
            #expect(controller.activeViewerModeSignalState.lastSequence == 1)
            #expect(controller.activeViewerModeSignalState.acceptedSignal?.activeSource == replacementSource)
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

    }
}

private struct ProductActiveViewerReviewPublicationObservation: Equatable, Sendable {
    let availability: BridgePaneProductReviewMetadataAvailability
    let packageMetadata: BridgeReviewPackage?
    let packageDelta: BridgeReviewDelta?
    let status: DiffStatus
}

@MainActor
private final class ProductActiveViewerControllerBox {
    weak var controller: BridgePaneController?

    func observation(
        availability: BridgePaneProductReviewMetadataAvailability
    ) -> ProductActiveViewerReviewPublicationObservation? {
        guard let controller else { return nil }
        return ProductActiveViewerReviewPublicationObservation(
            availability: availability,
            packageMetadata: controller.paneState.diff.packageMetadata,
            packageDelta: controller.paneState.diff.packageDelta,
            status: controller.paneState.diff.status
        )
    }
}

private enum ProductActiveViewerReviewMetadataRecorderError: Error {
    case controllerUnavailable
}

private actor ProductActiveViewerReviewMetadataRecorder:
    BridgePaneProductReviewMetadataProducing
{
    private let controllerBox: ProductActiveViewerControllerBox
    private(set) var observations: [ProductActiveViewerReviewPublicationObservation] = []

    init(controllerBox: ProductActiveViewerControllerBox) {
        self.controllerBox = controllerBox
    }

    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        emit _: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {}

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        emit _: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {}

    func publish(
        availability: BridgePaneProductReviewMetadataAvailability
    ) async throws -> BridgePaneProductReviewMetadataPublicationOutcome {
        guard let observation = await controllerBox.observation(availability: availability) else {
            throw ProductActiveViewerReviewMetadataRecorderError.controllerUnavailable
        }
        observations.append(observation)
        return .loading(retained: 0)
    }

    func cancel(subscriptionId _: String) {}
}

private func productActiveViewerReviewPackageFixture() throws -> BridgeReviewPackage {
    let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
    let fixtureURL = projectRoot.appending(
        path: "Tests/BridgeContractFixtures/valid/bridge-review-package.json"
    )
    return try JSONDecoder().decode(
        BridgeReviewPackage.self,
        from: Data(contentsOf: fixtureURL)
    )
}
