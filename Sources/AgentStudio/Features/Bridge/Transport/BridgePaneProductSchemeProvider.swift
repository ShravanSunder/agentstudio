import Foundation

actor BridgePaneProductSchemeProvider: BridgeProductSchemeProvider {
    private struct ContentBody: Sendable {
        let data: Data
        let endOfSource: Bool
        let sha256: String
    }

    private let applyActiveViewerModeUpdate: @MainActor @Sendable (BridgeProductCallRequest) async -> Void
    private let contentDemandAdmission: BridgeContentDemandAdmission
    private let fileMetadataSource: any BridgePaneProductFileMetadataProducing
    private let handleReviewIntakeReady: @MainActor @Sendable (BridgeProductReviewIntakeReadyRequest) async -> Void
    private let markReviewItemViewed: @MainActor @Sendable (String) -> Void
    private let metadataCoordinator: BridgePaneProductMetadataCoordinator
    private let reviewContentSource: any BridgePaneProductReviewContentProducing

    init(
        fileMetadataSource: any BridgePaneProductFileMetadataProducing,
        reviewMetadataSource: any BridgePaneProductReviewMetadataProducing,
        reviewContentSource: any BridgePaneProductReviewContentProducing,
        markReviewItemViewed: @escaping @MainActor @Sendable (String) -> Void,
        handleReviewIntakeReady: @escaping @MainActor @Sendable (BridgeProductReviewIntakeReadyRequest) async -> Void =
            { _ in },
        applyActiveViewerModeUpdate: @escaping @MainActor @Sendable (BridgeProductCallRequest) async -> Void = { _ in },
        lifecycleTraceRecorder: (any BridgeProductMetadataLifecycleTraceRecording)? = nil,
        contentDemandAdmission: BridgeContentDemandAdmission = BridgeContentDemandAdmission()
    ) {
        self.contentDemandAdmission = contentDemandAdmission
        self.fileMetadataSource = fileMetadataSource
        self.handleReviewIntakeReady = handleReviewIntakeReady
        self.metadataCoordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: fileMetadataSource,
            reviewMetadataSource: reviewMetadataSource,
            reviewContentSource: reviewContentSource,
            lifecycleTraceRecorder: lifecycleTraceRecorder
        )
        self.markReviewItemViewed = markReviewItemViewed
        self.reviewContentSource = reviewContentSource
        self.applyActiveViewerModeUpdate = applyActiveViewerModeUpdate
    }

    func response(
        for request: BridgeProductControlRequest
    ) async -> BridgeProductControlResponse {
        do {
            switch request {
            case .workerSessionOpen:
                return try .workerSessionAccepted(correlating: request)
            case .productCall(let callRequest):
                switch callRequest.call {
                case .fileSourceCurrent:
                    return try .callCompleted(
                        correlating: request,
                        result: .fileSourceCurrent(await fileMetadataSource.currentSource())
                    )
                case .fileActiveViewerModeUpdate:
                    return try .callCompleted(
                        correlating: request,
                        result: .fileActiveViewerModeUpdate
                    )
                case .reviewActiveViewerModeUpdate:
                    return try .callCompleted(
                        correlating: request,
                        result: .reviewActiveViewerModeUpdate
                    )
                case .reviewMarkFileViewed:
                    return try .callCompleted(
                        correlating: request,
                        result: .reviewMarkFileViewed
                    )
                case .reviewIntakeReady:
                    return try .callCompleted(
                        correlating: request,
                        result: .reviewIntakeReady
                    )
                }
            case .subscriptionOpen(let openRequest):
                guard await metadataCoordinator.hasActiveStream else {
                    return try metadataStreamRequiredError(for: request)
                }
                let emptyInterestState = BridgeProductSubscriptionState.emptyInterestState(
                    for: openRequest.subscription.subscriptionKind
                )
                return try .subscriptionOpenAccepted(
                    correlating: request,
                    interestSha256: emptyInterestState.sha256Hex()
                )
            case .subscriptionUpdateBatch(let updateRequest):
                guard await metadataCoordinator.hasActiveStream else {
                    return try metadataStreamRequiredError(for: request)
                }
                let disposition: BridgeProductSubscriptionUpdateBatchDisposition =
                    updateRequest.batchIndex + 1 == updateRequest.batchCount
                    ? .committed
                    : .staged
                return try .subscriptionUpdateBatchAccepted(
                    correlating: request,
                    disposition: disposition
                )
            case .subscriptionCancel:
                guard await metadataCoordinator.hasActiveStream else {
                    return try metadataStreamRequiredError(for: request)
                }
                return try .subscriptionCancelAccepted(correlating: request)
            case .workerSessionResync(let resyncRequest):
                guard await metadataCoordinator.hasActiveStream else {
                    return try metadataStreamRequiredError(for: request)
                }
                return try .resyncAccepted(
                    correlating: request,
                    metadataStreamSequenceBarrier: resyncRequest.lastAcceptedStreamSequence,
                    nextExpectedRequestSequence: request.requestSequence + 1,
                    reconciliation: []
                )
            }
        } catch {
            preconditionFailure("Bridge product provider could not build a correlated response")
        }
    }

    func applyCommittedControlEffect(
        _ effect: BridgeProductSessionCompletionEffect,
        for request: BridgeProductControlRequest
    ) async {
        if case .productCall(let committedProductCall) = effect,
            case .productCall(let callRequest) = request,
            committedProductCall == callRequest.call
        {
            switch committedProductCall {
            case .fileSourceCurrent:
                break
            case .fileActiveViewerModeUpdate, .reviewActiveViewerModeUpdate:
                await applyActiveViewerModeUpdate(committedProductCall)
            case .reviewMarkFileViewed(let markRequest):
                await markReviewItemViewed(markRequest.itemId)
            case .reviewIntakeReady(let intakeRequest):
                await handleReviewIntakeReady(intakeRequest)
            }
            return
        }
        await metadataCoordinator.apply(effect)
    }

    func publish(
        availability: BridgePaneProductReviewMetadataAvailability,
        traceContext: BridgeTraceContext? = nil
    ) async {
        await metadataCoordinator.publish(
            availability: availability,
            traceContext: traceContext
        )
    }

    func runMetadataProducer(
        request: BridgeProductMetadataStreamRequest,
        lease: BridgeProductProducerLease,
        session: BridgeProductSession
    ) async {
        do {
            _ = try await session.enqueueRequiredProducerOpeningFrame(
                for: lease,
                build: { _ in
                    try .metadata(
                        .metadataStreamAccepted(
                            for: request,
                            resumeDisposition: request.resumeFromStreamSequence == nil
                                ? .snapshotRequired
                                : .resumed
                        )
                    )
                }
            )
            await metadataCoordinator.install(
                request: request,
                lease: lease,
                session: session
            )
            await waitForProducerCancellation()
            await metadataCoordinator.uninstall(lease: lease)
        } catch {
            await metadataCoordinator.uninstall(lease: lease)
            return
        }
    }

    func runContentProducer(
        request: BridgeProductContentRequest,
        lease: BridgeProductProducerLease,
        session: BridgeProductSession
    ) async {
        let interest = await metadataCoordinator.contentDemandInterest(for: request)
        do {
            try await contentDemandAdmission.withAdmission(for: interest) {
                try await self.runAdmittedContentProducer(
                    request: request,
                    lease: lease,
                    session: session
                )
            }
        } catch {
            return
        }
    }

    private func runAdmittedContentProducer(
        request: BridgeProductContentRequest,
        lease: BridgeProductProducerLease,
        session: BridgeProductSession
    ) async throws {
        _ = try await session.enqueueRequiredProducerOpeningFrame(
            for: lease,
            build: { _ in
                .content(
                    .init(
                        header: .accepted(for: request.admission),
                        payload: Data()
                    )
                )
            }
        )
        guard let body = await contentBody(for: request) else {
            _ = try await session.enqueueTerminalProducerFrame(
                for: lease,
                build: { sequence in
                    .content(
                        .init(
                            header: try .error(
                                contentSequence: sequence,
                                code: .unsupportedContent,
                                retryable: false,
                                safeMessage: "Content descriptor is not active"
                            ),
                            payload: Data()
                        )
                    )
                }
            )
            return
        }
        var offsetBytes = 0
        while offsetBytes < body.data.count {
            try Task.checkCancellation()
            let endOffset = min(
                offsetBytes + BridgeProductWireContract.maximumContentDataPayloadBytes,
                body.data.count
            )
            let chunkOffsetBytes = offsetBytes
            let payload = body.data.subdata(in: offsetBytes..<endOffset)
            let result = try await session.enqueueProducerFrame(
                for: lease,
                build: { sequence in
                    .content(
                        .init(
                            header: try .data(
                                contentSequence: sequence,
                                offsetBytes: chunkOffsetBytes
                            ),
                            payload: payload
                        )
                    )
                },
                overflowReset: { sequence in
                    .content(
                        .init(
                            header: try .reset(
                                contentSequence: sequence,
                                reason: .producerOverflow
                            ),
                            payload: Data()
                        )
                    )
                }
            )
            guard case .enqueued = result else { return }
            offsetBytes = endOffset
        }
        _ = try await session.enqueueTerminalProducerFrame(
            for: lease,
            build: { sequence in
                .content(
                    .init(
                        header: try .end(
                            contentSequence: sequence,
                            endOfSource: body.endOfSource,
                            observedByteLength: body.data.count,
                            observedSha256: body.sha256
                        ),
                        payload: Data()
                    )
                )
            }
        )
    }

    func publishFileStatus(_ status: GitWorkingTreeStatus) async {
        await metadataCoordinator.publish(status: status)
    }

    func publishFileChangeset(_ changeset: FileChangeset) async {
        await metadataCoordinator.publish(changeset: changeset)
    }

    func acknowledgeLifecycle(
        _ acknowledgement: BridgeProductProducerLifecycleAcknowledgement
    ) async -> Bool {
        _ = acknowledgement
        return true
    }

    private func waitForProducerCancellation() async {
        let stream = AsyncStream<Void> { _ in }
        for await _ in stream {}
    }

    private func contentBody(for request: BridgeProductContentRequest) async -> ContentBody? {
        switch request {
        case .fileContent(let fileRequest):
            guard let body = await metadataCoordinator.contentBody(for: fileRequest) else {
                return nil
            }
            return ContentBody(
                data: body.data,
                endOfSource: body.endOfSource,
                sha256: body.sha256
            )
        case .reviewContent(let reviewRequest):
            guard let body = try? await reviewContentSource.contentBody(for: reviewRequest) else {
                return nil
            }
            return ContentBody(
                data: body.data,
                endOfSource: body.isFinalRange,
                sha256: body.sha256
            )
        }
    }

    private func metadataStreamRequiredError(
        for request: BridgeProductControlRequest
    ) throws -> BridgeProductControlResponse {
        try .requestError(
            correlating: request,
            code: .resyncRequired,
            nextExpectedRequestSequence: request.requestSequence + 1,
            retryAfterMilliseconds: nil,
            retryable: true,
            safeMessage: "Metadata stream is not installed"
        )
    }

}
