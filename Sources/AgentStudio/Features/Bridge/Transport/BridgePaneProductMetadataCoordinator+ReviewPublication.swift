import Foundation

private struct BridgeReviewPublicationAttemptContext {
    let publication: BridgeReviewCommittedPublication
    let reservation: BridgeReviewMetadataPublicationReservation
    let publishingStream: BridgePaneProductMetadataCoordinator.ActiveStream
    let productAdmission: BridgeProductAdmissionContext
    let foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    let traceContext: BridgeTraceContext?
    let attempt: Int
}

extension BridgePaneProductMetadataCoordinator {
    func reserveReviewPublication(
        package: BridgeReviewPackage,
        publicationId: UUID,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async throws -> BridgeReviewMetadataPublicationReservation {
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
            throw CancellationError()
        }
        return try await reviewMetadataSource.reserve(
            package: package,
            publicationId: publicationId,
            productAdmission: productAdmission
        )
    }

    func replayCommittedReviewPublicationIfPresent(
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        traceContext: BridgeTraceContext?
    ) async {
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true,
            let publication = await reviewPublicationReplay(productAdmission),
            foregroundWorkAdmission.withValidAdmission({ true }) == true,
            let reservation = try? await reviewMetadataSource.reserve(
                package: publication.package,
                publicationId: publication.publicationId,
                productAdmission: productAdmission
            )
        else { return }
        _ = await deliverReviewPublication(
            publication.retainedReplay,
            reservation: reservation,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
            traceContext: traceContext
        )
    }

    func deliverReviewPublication(
        _ publication: BridgeReviewCommittedPublication,
        reservation: BridgeReviewMetadataPublicationReservation,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        traceContext: BridgeTraceContext? = nil
    ) async -> BridgeReviewPublicationDeliveryDisposition {
        guard let publishingStream = activeStream,
            publishingStream.productAdmission.matches(productAdmission),
            reservation.publicationId == publication.publicationId,
            foregroundWorkAdmission.withValidAdmission({ true }) == true,
            (productAdmission.withValidAdmission { true }) == true
        else { return .deferred }
        let retainedSubscriptionCount = reviewSubscriptionIds.count
        await lifecycleTraceRecorder?.record(
            .started(
                retainedSubscriptions: retainedSubscriptionCount,
                traceContext: traceContext
            )
        )
        for attempt in 0...1 {
            guard activeStream?.lease == publishingStream.lease,
                foregroundWorkAdmission.withValidAdmission({ true }) == true,
                await isReviewPublicationCurrent(
                    publication.publicationId,
                    productAdmission
                ),
                (productAdmission.withValidAdmission { true }) == true
            else { return .deferred }
            do {
                return try await deliverReviewPublicationAttempt(
                    .init(
                        publication: publication,
                        reservation: reservation,
                        publishingStream: publishingStream,
                        productAdmission: productAdmission,
                        foregroundWorkAdmission: foregroundWorkAdmission,
                        traceContext: traceContext,
                        attempt: attempt
                    )
                )
            } catch {
                if let operationCorrelationID = publication.operationCorrelationID {
                    await recordOperationLifecycle(
                        operationCorrelationID: operationCorrelationID,
                        result: error is CancellationError ? .cancelled : .failure,
                        stage: .metadataEnqueueTerminal,
                        stageAttempt: attempt,
                        surface: .review
                    )
                }
                guard activeStream?.lease == publishingStream.lease,
                    foregroundWorkAdmission.withValidAdmission({ true }) == true,
                    await isReviewPublicationCurrent(
                        publication.publicationId,
                        productAdmission
                    )
                else { return .deferred }
                await recordReviewPublicationFailure(
                    Self.reviewPublicationFailure(for: error),
                    retainedSubscriptions: retainedSubscriptionCount,
                    traceContext: traceContext
                )
                guard attempt == 0,
                    Self.isRetryableReviewDeliveryFailure(error),
                    activeStream?.lease == publishingStream.lease,
                    foregroundWorkAdmission.withValidAdmission({ true }) == true,
                    await isReviewPublicationCurrent(
                        publication.publicationId,
                        productAdmission
                    ),
                    (productAdmission.withValidAdmission { true }) == true
                else { return .failed }
            }
        }
        return .failed
    }

    private func deliverReviewPublicationAttempt(
        _ context: BridgeReviewPublicationAttemptContext
    ) async throws -> BridgeReviewPublicationDeliveryDisposition {
        await recordReviewMetadataEnqueue(
            publication: context.publication,
            result: .started,
            stage: .metadataEnqueueStarted,
            stageAttempt: context.attempt
        )
        let outcome = try await reviewMetadataSource.deliver(
            publication: context.publication,
            reservation: context.reservation,
            productAdmission: context.productAdmission
        )
        await recordReviewMetadataEnqueue(
            publication: context.publication,
            result: .success,
            stage: .metadataEnqueueTerminal,
            stageAttempt: context.attempt
        )
        guard case .delivered(let receipt) = outcome else { return .deferred }
        guard activeStream?.lease == context.publishingStream.lease,
            context.foregroundWorkAdmission.withValidAdmission({ true }) == true,
            await isReviewPublicationCurrent(
                context.publication.publicationId,
                context.productAdmission
            )
        else { return .deferred }
        await recordReviewMetadataEnqueue(
            publication: context.publication,
            result: .started,
            stage: .metadataDeliveryStarted,
            stageAttempt: context.attempt
        )
        if let failureDisposition = await reviewMetadataReceiptFailureDisposition(
            receipt,
            publication: context.publication,
            publishingStream: context.publishingStream,
            productAdmission: context.productAdmission,
            foregroundWorkAdmission: context.foregroundWorkAdmission,
            stageAttempt: context.attempt
        ) {
            return failureDisposition
        }
        await recordReviewMetadataDeliveryTerminal(
            publication: context.publication,
            result: .success,
            stageAttempt: context.attempt
        )
        await lifecycleTraceRecorder?.record(
            .completed(receipt: receipt, traceContext: context.traceContext)
        )
        return receipt.publishedSubscriptions > 0 ? .transportAcknowledged : .deferred
    }

    private func reviewMetadataReceiptFailureDisposition(
        _ receipt: BridgeReviewMetadataPublicationReceipt,
        publication: BridgeReviewCommittedPublication,
        publishingStream: ActiveStream,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        stageAttempt: Int
    ) async -> BridgeReviewPublicationDeliveryDisposition? {
        if let maximumFinalSequence = receipt.finalFrames.map(\.sequence).max(),
            !(await publishingStream.session.waitUntilProducerFrameSequenceObserved(
                for: publishingStream.lease,
                sequence: maximumFinalSequence,
                productAdmission: productAdmission
            ))
        {
            let publicationRemainsCurrent = await isReviewPublicationCurrent(
                publication.publicationId,
                productAdmission
            )
            let remainsCurrent =
                activeStream?.lease == publishingStream.lease
                && foregroundWorkAdmission.withValidAdmission({ true }) == true
                && publicationRemainsCurrent
                && (productAdmission.withValidAdmission { true }) == true
            await recordReviewMetadataDeliveryTerminal(
                publication: publication,
                result: remainsCurrent ? .failure : .stale,
                stageAttempt: stageAttempt
            )
            return remainsCurrent ? .failed : .deferred
        }
        guard activeStream?.lease == publishingStream.lease,
            foregroundWorkAdmission.withValidAdmission({ true }) == true,
            await isReviewPublicationCurrent(publication.publicationId, productAdmission)
        else {
            await recordReviewMetadataDeliveryTerminal(
                publication: publication,
                result: .stale,
                stageAttempt: stageAttempt
            )
            return .deferred
        }
        return nil
    }

    private func recordReviewMetadataEnqueue(
        publication: BridgeReviewCommittedPublication,
        result: BridgeOperationLifecycleTraceEvent.Result,
        stage: BridgeOperationLifecycleTraceEvent.Stage,
        stageAttempt: Int
    ) async {
        guard let operationCorrelationID = publication.operationCorrelationID else { return }
        await recordOperationLifecycle(
            operationCorrelationID: operationCorrelationID,
            result: result,
            stage: stage,
            stageAttempt: stageAttempt,
            surface: .review
        )
    }

    private func recordReviewMetadataDeliveryTerminal(
        publication: BridgeReviewCommittedPublication,
        result: BridgeOperationLifecycleTraceEvent.Result,
        stageAttempt: Int
    ) async {
        guard let operationCorrelationID = publication.operationCorrelationID else { return }
        await recordOperationLifecycle(
            operationCorrelationID: operationCorrelationID,
            result: result,
            stage: .metadataDeliveryTerminal,
            stageAttempt: stageAttempt,
            surface: .review
        )
    }

    func resetCurrentReviewSubscriptionsForUnavailableSource(
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async {
        guard let resettingStream = activeStream,
            resettingStream.productAdmission.matches(productAdmission),
            foregroundWorkAdmission.withValidAdmission({ true }) == true,
            (productAdmission.withValidAdmission { true }) == true
        else { return }

        for subscriptionId in reviewSubscriptionIds {
            guard activeStream?.lease == resettingStream.lease,
                foregroundWorkAdmission.withValidAdmission({ true }) == true,
                (productAdmission.withValidAdmission { true }) == true
            else { return }
            let resetResult = try? await resettingStream.session.enqueueSubscriptionReset(
                subscriptionId: subscriptionId,
                reason: .staleSource,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
            guard case .enqueued = resetResult else { continue }
            await retireSubscriptionAfterReset(subscriptionId: subscriptionId)
        }
    }

    private func recordReviewPublicationFailure(
        _ failure: BridgeProductReviewMetadataPublicationFailure,
        retainedSubscriptions: Int,
        traceContext: BridgeTraceContext?
    ) async {
        await lifecycleTraceRecorder?.record(
            .failed(
                failure: failure,
                retainedSubscriptions: retainedSubscriptions,
                traceContext: traceContext
            )
        )
    }
}
