import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge pane surface-selection publication")
struct BridgePaneSurfaceSelectionPublicationTests {
    @Test("an exact command without a current metadata stream is rejected and cannot replay later")
    func commandWithoutCurrentMetadataStreamIsRejectedAndCannotReplay() async throws {
        // Arrange
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let coordinator = makeSurfaceSelectionCoordinator(
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        let request = makeSurfaceSelectionRequest(commandId: "selection-no-stream")

        // Act
        let wasPublished = await coordinator.publishPaneSurfaceSelectionRequest(
            request,
            productAdmission: harness.productAdmission.context,
            streamAbsenceDisposition: .reject
        )
        let lease = try await harness.admitMetadataFrames(through: 0)
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
        await coordinator.replayPaneSurfaceSelectionRequest()

        // Assert
        #expect(!wasPublished)
        #expect((await harness.session.producerSnapshot()).queuedFrameCount == 0)
        await coordinator.uninstall(lease: lease)
        try await harness.closeProducer(lease)
    }

    @Test("an exact command succeeds only after enqueue into the current metadata stream")
    func commandSucceedsAfterCurrentMetadataStreamEnqueue() async throws {
        // Arrange
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            productAdmission: harness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        let coordinator = makeSurfaceSelectionCoordinator(
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
        let request = makeSurfaceSelectionRequest(commandId: "selection-current-stream")

        // Act
        let wasPublished = await coordinator.publishPaneSurfaceSelectionRequest(
            request,
            productAdmission: harness.productAdmission.context,
            streamAbsenceDisposition: .reject
        )
        let frame = try await pullMetadataFrame(from: pump)

        // Assert
        #expect(wasPublished)
        guard case .paneSurfaceSelectionRequested(let publishedRequest) = frame else {
            Issue.record("Expected a pane surface-selection frame")
            return
        }
        #expect(publishedRequest.navigationCommand.commandId == request.requestId)
        await coordinator.uninstall(lease: lease)
        #expect(await pump.cancel())
    }

    @Test("surface selection overflow emits a retryable resync terminal")
    func surfaceSelectionOverflowEmitsRetryableResyncTerminal() async throws {
        let queueLimits = try BridgeProductProducerQueueLimits(
            maximumQueuedFrameCount: 3,
            maximumQueuedByteCount: BridgeProductWireContract.maximumQueuedStreamBytes,
            maximumEncodedFrameByteCount:
                BridgeProductProducerQueueLimits.maximumProductEncodedFrameByteCount,
            terminalFrameReserve: BridgeProductWireContract.terminalFrameReserve
        )
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let harness = try await BridgeProductSessionLifecycleHarness.opened(
            producerQueueLimits: queueLimits
        )
        let lease = try await harness.admitMetadataFrames(through: 0)
        let coordinator = makeSurfaceSelectionCoordinator(
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
        await coordinator.publishPanePresentation(
            overflowPanePresentation(presentationRevision: 30)
        )
        await coordinator.publishPanePresentation(
            overflowPanePresentation(presentationRevision: 31)
        )

        let wasPublished = await coordinator.publishPaneSurfaceSelectionRequest(
            makeSurfaceSelectionRequest(commandId: "selection-overflow"),
            productAdmission: harness.productAdmission.context,
            streamAbsenceDisposition: .reject
        )

        #expect(!wasPublished)
        let terminal = try #require(
            await consumeNextBridgeProductProducerFrame(
                for: lease,
                from: harness.session,
                productAdmission: harness.productAdmission.context
            )
        )
        let decoder = try BridgeProductMetadataFrameDecoder()
        let decodedFrames = try decoder.append(terminal.data)
        guard case .metadataStreamError(let error) = try #require(decodedFrames.first) else {
            Issue.record("Expected pane surface-selection overflow to emit metadata.streamError")
            return
        }
        #expect(error.code == .resyncRequired)
        #expect(error.retryable)
        await coordinator.uninstall(lease: lease)
    }

    @Test("an enqueue rejection fails the exact command instead of retaining it for replay")
    func enqueueRejectionFailsCommandWithoutReplay() async throws {
        // Arrange
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let leaseOwner = try await BridgeProductSessionLifecycleHarness.opened()
        let activeSession = try await BridgeProductSessionLifecycleHarness.opened()
        let foreignLease = try await leaseOwner.admitMetadataFrames(through: 0)
        let coordinator = makeSurfaceSelectionCoordinator(
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: foreignLease,
            productAdmission: activeSession.productAdmission.context,
            session: activeSession.session
        )

        // Act
        let wasPublished = await coordinator.publishPaneSurfaceSelectionRequest(
            makeSurfaceSelectionRequest(commandId: "selection-rejected"),
            productAdmission: activeSession.productAdmission.context,
            streamAbsenceDisposition: .reject
        )
        await coordinator.replayPaneSurfaceSelectionRequest()

        // Assert
        #expect(!wasPublished)
        #expect((await activeSession.session.producerSnapshot()).queuedFrameCount == 0)
        await coordinator.uninstall(lease: foreignLease)
        try await leaseOwner.closeProducer(foreignLease)
    }

    @Test("an encoding failure rejects the exact command instead of retaining it for replay")
    func encodingFailureRejectsCommandWithoutReplay() async throws {
        // Arrange
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let coordinator = makeSurfaceSelectionCoordinator(
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
        let invalidRequest = makeSurfaceSelectionRequest(
            commandId: String(repeating: "x", count: 4097)
        )

        // Act
        let wasPublished = await coordinator.publishPaneSurfaceSelectionRequest(
            invalidRequest,
            productAdmission: harness.productAdmission.context,
            streamAbsenceDisposition: .reject
        )
        await coordinator.replayPaneSurfaceSelectionRequest()

        // Assert
        #expect(!wasPublished)
        #expect((await harness.session.producerSnapshot()).queuedFrameCount == 0)
        await coordinator.uninstall(lease: lease)
        try await harness.closeProducer(lease)
    }
}

private func makeSurfaceSelectionCoordinator(
    refreshWorkAdmissionSource: BridgePaneRefreshWorkAdmissionSource
) -> BridgePaneProductMetadataCoordinator {
    BridgePaneProductMetadataCoordinator(
        fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
        reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
        refreshWorkAdmissionSource: refreshWorkAdmissionSource
    )
}

private func overflowPanePresentation(
    presentationRevision: Int
) -> BridgePaneProductPresentationSnapshot {
    BridgePaneProductPresentationSnapshot(
        nativeActivity: .foreground,
        presentationRevision: presentationRevision,
        refreshingLanes: [.review],
        reviewComparison: nil
    )
}

private func makeSurfaceSelectionRequest(commandId: String) -> BridgePaneSurfaceSelectionRequest {
    BridgePaneSurfaceSelectionRequest(
        navigationCommand: .activateReviewTarget(
            commandId: commandId,
            bindingRevision: 1,
            source: BridgeProductNavigationReviewSource(
                generation: 1,
                metadataSourceId: "review-query-1",
                packageId: "review-package-1"
            ),
            target: BridgeProductNavigationReviewTarget(reviewItemId: "review-item-1")
        ),
        paneSessionId: "pane-session-1",
        workerInstanceId: "worker-instance-1"
    )
}
