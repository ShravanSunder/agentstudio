import CryptoKit
import Foundation

extension BridgePaneProductSchemeProvider {
    func annotationProjectionQueryResponse(
        queryRequest: BridgeProductAnnotationProjectionQueryRequest,
        request: BridgeProductControlRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgeProductControlResponse {
        let descriptor: BridgeProductAnnotationProjectionContentDescriptor
        do {
            descriptor = try await annotationProjectionSource.descriptor(
                for: queryRequest,
                issuing: request,
                productAdmission: productAdmission
            )
        } catch let sourceError as BridgeAnnotationProjectionSourceError {
            return try annotationProjectionError(sourceError, for: request)
        } catch {
            return try annotationProjectionUnavailableError(for: request)
        }
        let result: BridgeProductCallResult =
            switch queryRequest.surface {
            case .file:
                .fileAnnotationsProjectionQuery(.init(descriptor: descriptor))
            case .review:
                .reviewAnnotationsProjectionQuery(.init(descriptor: descriptor))
            }
        return try .callCompleted(correlating: request, result: result)
    }

    func runAnnotationProjectionContentProducer(
        request: BridgeProductAnnotationProjectionContentRequest,
        lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        session: BridgeProductSession
    ) async throws {
        var page: BridgePaneProductWorktreeAnnotationProjectionPage
        do {
            page = try await annotationProjectionSource.claim(request)
        } catch {
            try await enqueueUnavailableContentTerminal(
                for: lease,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
                session: session
            )
            return
        }

        var byteCount = 0
        var hasher = SHA256()
        do {
            while let batch = try page.cursor.nextEncodedBatch() {
                try Task.checkCancellation()
                guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return }
                let batchOffset = byteCount
                let enqueueResult = try await session.enqueueContentFrame(
                    for: lease,
                    productAdmission: productAdmission,
                    foregroundWorkAdmission: foregroundWorkAdmission,
                    build: { sequence in
                        .content(
                            .init(
                                header: try .data(
                                    contentSequence: sequence,
                                    offsetBytes: batchOffset
                                ),
                                payload: batch
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
                guard case .enqueued(let frame) = enqueueResult,
                    await session.waitUntilProducerFrameSequenceObserved(
                        for: lease,
                        sequence: frame.sequence,
                        productAdmission: productAdmission
                    )
                else { return }
                hasher.update(data: batch)
                byteCount += batch.count
            }
            guard byteCount == page.descriptor.maximumBytes else {
                throw BridgeAnnotationProjectionSourceError.descriptorMismatch
            }
        } catch is CancellationError {
            return
        } catch {
            try await enqueueAnnotationProjectionFailureTerminal(
                for: lease,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
                session: session
            )
            return
        }

        let sha256 = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let observedByteCount = byteCount
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
                            observedByteLength: observedByteCount,
                            observedSha256: sha256
                        ),
                        payload: Data()
                    )
                )
            }
        )
    }

    private func enqueueAnnotationProjectionFailureTerminal(
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
                            code: .internal,
                            retryable: true,
                            safeMessage: "Annotation projection is unavailable"
                        ),
                        payload: Data()
                    )
                )
            }
        )
    }

    private func annotationProjectionUnavailableError(
        for request: BridgeProductControlRequest
    ) throws -> BridgeProductControlResponse {
        try .requestError(
            correlating: request,
            code: .internal,
            nextExpectedRequestSequence: request.requestSequence + 1,
            retryAfterMilliseconds: nil,
            retryable: true,
            safeMessage: "Annotation projection is unavailable"
        )
    }

    private func annotationProjectionError(
        _ error: BridgeAnnotationProjectionSourceError,
        for request: BridgeProductControlRequest
    ) throws -> BridgeProductControlResponse {
        switch error {
        case .staleSourceGeneration:
            return try .requestError(
                correlating: request,
                code: .staleSource,
                nextExpectedRequestSequence: request.requestSequence + 1,
                retryAfterMilliseconds: nil,
                retryable: false,
                safeMessage: "Annotation projection source generation is stale"
            )
        case .initialSourceGenerationUnavailable,
            .projectionCaptureUnavailable,
            .revalidatedSourceGenerationUnavailable,
            .sourceRefreshUnavailable,
            .unavailable:
            return try annotationProjectionUnavailableError(for: request)
        case .descriptorMismatch, .invalidCursor:
            return try .requestError(
                correlating: request,
                code: .invalidRequest,
                nextExpectedRequestSequence: request.requestSequence + 1,
                retryAfterMilliseconds: nil,
                retryable: false,
                safeMessage: "Annotation projection request is invalid"
            )
        }
    }
}
