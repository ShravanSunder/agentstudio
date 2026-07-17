import CryptoKit
import Foundation

actor BridgePaneProductSchemeProvider: BridgeProductSchemeProvider {
    private struct BufferedContentBody: Sendable {
        let data: Data
        let endOfSource: Bool
        let sha256: String
    }

    private struct FileContentStreamDigest: Sendable {
        let byteCount: Int
        let sha256: String
    }

    private let applyActiveViewerModeUpdate:
        @MainActor @Sendable (BridgeProductCallRequest, BridgeProductAdmissionContext) async -> Void
    private let contentDemandAdmission: BridgeContentDemandAdmission
    private let fileContentReaderFactory: BridgePaneProductFileContentReaderFactory
    private let fileMetadataSource: any BridgePaneProductFileMetadataProducing
    private let handleReviewIntakeReady:
        @MainActor @Sendable (BridgeProductReviewIntakeReadyRequest, BridgeProductAdmissionContext) async -> Void
    private let markReviewItemViewed: @MainActor @Sendable (String, BridgeProductAdmissionContext) -> Void
    private let metadataCoordinator: BridgePaneProductMetadataCoordinator
    private let recordReviewPublicationApplication: @MainActor @Sendable (UUID, BridgeProductAdmissionContext) -> Bool
    private let refreshWorkAdmissionSource: BridgePaneRefreshWorkAdmissionSource
    private let reviewContentSource: any BridgePaneProductReviewContentProducing

    init(
        fileMetadataSource: any BridgePaneProductFileMetadataProducing,
        reviewMetadataSource: any BridgePaneProductReviewMetadataProducing,
        reviewContentSource: any BridgePaneProductReviewContentProducing,
        reviewPublicationReplay:
            @escaping @MainActor @Sendable (BridgeProductAdmissionContext) ->
            BridgeReviewCommittedPublication? = { _ in nil },
        isReviewPublicationCurrent:
            @escaping @MainActor @Sendable (UUID, BridgeProductAdmissionContext) -> Bool = { _, _ in true },
        recordReviewPublicationApplication:
            @escaping @MainActor @Sendable (UUID, BridgeProductAdmissionContext) -> Bool = { _, _ in false },
        markReviewItemViewed: @escaping @MainActor @Sendable (String, BridgeProductAdmissionContext) -> Void,
        handleReviewIntakeReady:
            @escaping @MainActor @Sendable (
                BridgeProductReviewIntakeReadyRequest,
                BridgeProductAdmissionContext
            ) async -> Void = { _, _ in },
        applyActiveViewerModeUpdate:
            @escaping @MainActor @Sendable (
                BridgeProductCallRequest,
                BridgeProductAdmissionContext
            ) async -> Void = { _, _ in },
        initialPanePresentation: BridgePaneProductPresentationSnapshot? = nil,
        refreshWorkAdmissionSource: BridgePaneRefreshWorkAdmissionSource,
        lifecycleTraceRecorder: (any BridgeProductMetadataLifecycleTraceRecording)? = nil,
        contentDemandAdmission: BridgeContentDemandAdmission = BridgeContentDemandAdmission(),
        fileContentReaderFactory: @escaping BridgePaneProductFileContentReaderFactory =
            BridgePaneProductFileContentSource.openReadSession
    ) {
        self.contentDemandAdmission = contentDemandAdmission
        self.fileContentReaderFactory = fileContentReaderFactory
        self.fileMetadataSource = fileMetadataSource
        self.handleReviewIntakeReady = handleReviewIntakeReady
        self.metadataCoordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: fileMetadataSource,
            reviewMetadataSource: reviewMetadataSource,
            reviewContentSource: reviewContentSource,
            reviewPublicationReplay: reviewPublicationReplay,
            isReviewPublicationCurrent: isReviewPublicationCurrent,
            initialPanePresentation: initialPanePresentation,
            refreshWorkAdmissionSource: refreshWorkAdmissionSource,
            lifecycleTraceRecorder: lifecycleTraceRecorder
        )
        self.markReviewItemViewed = markReviewItemViewed
        self.recordReviewPublicationApplication = recordReviewPublicationApplication
        self.refreshWorkAdmissionSource = refreshWorkAdmissionSource
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
                case .reviewPublicationApplied:
                    return try .callCompleted(
                        correlating: request,
                        result: .reviewPublicationApplied
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
        for request: BridgeProductControlRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async {
        if case .productCall(let committedProductCall) = effect,
            case .productCall(let callRequest) = request,
            committedProductCall == callRequest.call
        {
            guard (productAdmission.withValidAdmission { true }) == true else { return }
            switch committedProductCall {
            case .fileSourceCurrent:
                break
            case .fileActiveViewerModeUpdate, .reviewActiveViewerModeUpdate:
                await applyActiveViewerModeUpdate(committedProductCall, productAdmission)
            case .reviewMarkFileViewed(let markRequest):
                await markReviewItemViewed(markRequest.itemId, productAdmission)
            case .reviewIntakeReady(let intakeRequest):
                await handleReviewIntakeReady(intakeRequest, productAdmission)
            case .reviewPublicationApplied(let appliedRequest):
                _ = await recordReviewPublicationApplication(
                    appliedRequest.publicationId,
                    productAdmission
                )
            }
            return
        }
        await metadataCoordinator.apply(
            effect,
            productAdmission: productAdmission
        )
    }

    func reserveReviewPublication(
        package: BridgeReviewPackage,
        publicationId: UUID,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async throws -> BridgeReviewMetadataPublicationReservation {
        try await metadataCoordinator.reserveReviewPublication(
            package: package,
            publicationId: publicationId,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission
        )
    }

    func deliverReviewPublication(
        _ publication: BridgeReviewCommittedPublication,
        reservation: BridgeReviewMetadataPublicationReservation,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        traceContext: BridgeTraceContext? = nil
    ) async -> BridgeReviewPublicationDeliveryDisposition {
        await metadataCoordinator.deliverReviewPublication(
            publication,
            reservation: reservation,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
            traceContext: traceContext
        )
    }

    func suspendForegroundWork() async {
        await metadataCoordinator.suspendForegroundWork()
    }

    func resumeForegroundWork() async {
        await metadataCoordinator.resumeForegroundWork()
    }

    func publishPanePresentation(
        _ snapshot: BridgePaneProductPresentationSnapshot
    ) async {
        await metadataCoordinator.publishPanePresentation(snapshot)
    }

    func runMetadataProducer(
        request: BridgeProductMetadataStreamRequest,
        lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        session: BridgeProductSession
    ) async {
        do {
            await metadataCoordinator.install(
                request: request,
                lease: lease,
                productAdmission: productAdmission,
                session: session
            )
            _ = try await session.enqueueRequiredProducerOpeningFrame(
                for: lease,
                productAdmission: productAdmission,
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
            await metadataCoordinator.replayPanePresentation()
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
        productAdmission: BridgeProductAdmissionContext,
        session: BridgeProductSession
    ) async {
        guard let foregroundWorkAdmission = refreshWorkAdmissionSource.acquire() else { return }
        guard
            let invalidationHandlerId = foregroundWorkAdmission.registerInvalidationHandler({
                Task { [weak self] in
                    await self?.retireActivityInvalidatedProducer(
                        lease: lease,
                        session: session
                    )
                }
            })
        else {
            await retireActivityInvalidatedProducer(lease: lease, session: session)
            return
        }
        defer {
            foregroundWorkAdmission.removeInvalidationHandler(invalidationHandlerId)
        }
        let interest = await metadataCoordinator.contentDemandInterest(
            for: request,
            productAdmission: productAdmission
        )
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return }
        do {
            try await contentDemandAdmission.withAdmission(for: interest) {
                try await self.runAdmittedContentProducer(
                    request: request,
                    lease: lease,
                    productAdmission: productAdmission,
                    foregroundWorkAdmission: foregroundWorkAdmission,
                    session: session
                )
            }
        } catch {
            return
        }
    }

    private func retireActivityInvalidatedProducer(
        lease: BridgeProductProducerLease,
        session: BridgeProductSession
    ) async {
        let retirement = await session.beginProducerRetirement(
            lease,
            acknowledgeLifecycle: acknowledgeLifecycle,
            stopRequest: nil,
            abandonOutstandingDelivery: true
        )
        _ = await retirement.wait()
    }

    private func runAdmittedContentProducer(
        request: BridgeProductContentRequest,
        lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        session: BridgeProductSession
    ) async throws {
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return }
        let openingResult = try await session.enqueueRequiredContentOpeningFrame(
            for: lease,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
            build: { _ in
                .content(
                    .init(
                        header: .accepted(for: request.admission),
                        payload: Data()
                    )
                )
            }
        )
        guard
            foregroundWorkAdmission.withValidAdmission({ true }) == true,
            await waitForExactWorkerObservation(
                openingResult,
                lease: lease,
                productAdmission: productAdmission,
                session: session
            )
        else { return }
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return }
        switch request {
        case .fileContent(let fileRequest):
            await runFileContentProducer(
                request: fileRequest,
                lease: lease,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
                session: session
            )
        case .reviewContent(let reviewRequest):
            guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return }
            guard
                let body = try? await reviewContentSource.contentBody(
                    for: reviewRequest,
                    productAdmission: productAdmission
                )
            else {
                guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return }
                try await enqueueUnavailableContentTerminal(
                    for: lease,
                    productAdmission: productAdmission,
                    foregroundWorkAdmission: foregroundWorkAdmission,
                    session: session
                )
                return
            }
            guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return }
            try await runBufferedContentProducer(
                BufferedContentBody(
                    data: body.data,
                    endOfSource: body.isFinalRange,
                    sha256: body.sha256
                ),
                lease: lease,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
                session: session
            )
        }
    }

    private func runBufferedContentProducer(
        _ body: BufferedContentBody,
        lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        session: BridgeProductSession
    ) async throws {
        var offsetBytes = 0
        while offsetBytes < body.data.count {
            try Task.checkCancellation()
            guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return }
            let endOffset = min(
                offsetBytes + BridgeProductWireContract.maximumContentDataPayloadBytes,
                body.data.count
            )
            let chunkOffsetBytes = offsetBytes
            let payload = body.data.subdata(in: offsetBytes..<endOffset)
            let result = try await session.enqueueContentFrame(
                for: lease,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
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
            guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return }
            offsetBytes = endOffset
        }
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return }
        _ = try await session.enqueueTerminalContentFrame(
            for: lease,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
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

    private func runFileContentProducer(
        request: BridgeProductFileContentRequest,
        lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        session: BridgeProductSession
    ) async {
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return }
        guard
            let readPlan = await metadataCoordinator.contentReadPlan(
                for: request,
                productAdmission: productAdmission
            ),
            foregroundWorkAdmission.withValidAdmission({ true }) == true,
            readPlan.descriptor == request.descriptor
        else {
            guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return }
            try? await enqueueUnavailableContentTerminal(
                for: lease,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
                session: session
            )
            return
        }
        let reader: any BridgePaneProductFileContentReading
        do {
            guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return }
            reader = try await fileContentReaderFactory(readPlan)
            guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                await reader.close()
                return
            }
        } catch {
            guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return }
            try? await enqueueStaleSourceReset(
                for: lease,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
                session: session
            )
            return
        }

        do {
            let digest = try await streamFileContentChunks(
                reader: reader,
                descriptor: request.descriptor,
                lease: lease,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
                session: session
            )
            await reader.close()
            guard let digest,
                foregroundWorkAdmission.withValidAdmission({ true }) == true
            else { return }
            guard digest.byteCount == request.descriptor.declaredByteLength,
                digest.sha256 == request.descriptor.expectedSha256
            else {
                guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return }
                try await enqueueStaleSourceReset(
                    for: lease,
                    productAdmission: productAdmission,
                    foregroundWorkAdmission: foregroundWorkAdmission,
                    session: session
                )
                return
            }
            _ = try await session.enqueueTerminalContentFrame(
                for: lease,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
                build: { sequence in
                    .content(
                        .init(
                            header: try .end(
                                contentSequence: sequence,
                                endOfSource: true,
                                observedByteLength: digest.byteCount,
                                observedSha256: digest.sha256
                            ),
                            payload: Data()
                        )
                    )
                }
            )
        } catch is CancellationError {
            await reader.close()
        } catch {
            await reader.close()
            guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return }
            try? await enqueueStaleSourceReset(
                for: lease,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
                session: session
            )
        }
    }

    private func streamFileContentChunks(
        reader: any BridgePaneProductFileContentReading,
        descriptor: BridgeProductFileContentDescriptor,
        lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        session: BridgeProductSession
    ) async throws -> FileContentStreamDigest? {
        var byteCount = 0
        var hasher = SHA256()
        while foregroundWorkAdmission.withValidAdmission({ true }) == true {
            guard
                let chunk = try await reader.nextChunk(
                    maximumByteCount: BridgeProductWireContract.maximumContentDataPayloadBytes
                )
            else { break }
            try Task.checkCancellation()
            guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                await reader.close()
                return nil
            }
            let (nextByteCount, overflowed) = byteCount.addingReportingOverflow(chunk.count)
            guard !overflowed,
                nextByteCount <= descriptor.declaredByteLength
            else {
                try await enqueueStaleSourceReset(
                    for: lease,
                    productAdmission: productAdmission,
                    foregroundWorkAdmission: foregroundWorkAdmission,
                    session: session
                )
                return nil
            }
            let chunkOffsetBytes = byteCount
            hasher.update(data: chunk)
            let result = try await session.enqueueContentFrame(
                for: lease,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
                build: { sequence in
                    .content(
                        .init(
                            header: try .data(
                                contentSequence: sequence,
                                offsetBytes: chunkOffsetBytes
                            ),
                            payload: chunk
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
            guard
                foregroundWorkAdmission.withValidAdmission({ true }) == true,
                await waitForExactWorkerObservation(
                    result,
                    lease: lease,
                    productAdmission: productAdmission,
                    session: session
                )
            else {
                return nil
            }
            byteCount = nextByteCount
        }
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return nil }
        let sha256 = hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
        return FileContentStreamDigest(byteCount: byteCount, sha256: sha256)
    }

    private func waitForExactWorkerObservation(
        _ result: BridgeProductProducerEnqueueResult,
        lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        session: BridgeProductSession
    ) async -> Bool {
        guard case .enqueued(let frame) = result else { return false }
        return await session.waitUntilProducerFrameSequenceObserved(
            for: lease,
            sequence: frame.sequence,
            productAdmission: productAdmission
        )
    }

    private func enqueueUnavailableContentTerminal(
        for lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        session: BridgeProductSession
    ) async throws {
        _ = try await session.enqueueTerminalContentFrame(
            for: lease,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
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
    }

    private func enqueueStaleSourceReset(
        for lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        session: BridgeProductSession
    ) async throws {
        _ = try await session.enqueueTerminalContentFrame(
            for: lease,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
            build: { sequence in
                .content(
                    .init(
                        header: try .reset(
                            contentSequence: sequence,
                            reason: .staleSource
                        ),
                        payload: Data()
                    )
                )
            }
        )
    }

    func publishFileStatus(
        _ status: GitWorkingTreeStatus,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async -> BridgePaneProductFileRefreshPublicationDisposition {
        await metadataCoordinator.publish(
            status: status,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission
        )
    }

    func publishFileChangeset(
        _ changeset: FileChangeset,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async -> BridgePaneProductFileRefreshPublicationDisposition {
        await metadataCoordinator.publish(
            changeset: changeset,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission
        )
    }

    func acknowledgeLifecycle(
        _ acknowledgement: BridgeProductProducerLifecycleAcknowledgement
    ) async -> Bool {
        _ = acknowledgement
        return true
    }

    func closeAndDrain() async {
        await metadataCoordinator.closeAndDrain()
        await contentDemandAdmission.closeAndDrain()
    }

    private func waitForProducerCancellation() async {
        let stream = AsyncStream<Void> { _ in }
        for await _ in stream {}
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
