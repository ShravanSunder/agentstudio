import Foundation

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
            publication,
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
                let outcome = try await reviewMetadataSource.deliver(
                    package: publication.package,
                    reservation: reservation,
                    productAdmission: productAdmission
                )
                switch outcome {
                case .delivered(let receipt):
                    guard activeStream?.lease == publishingStream.lease,
                        foregroundWorkAdmission.withValidAdmission({ true }) == true,
                        await isReviewPublicationCurrent(
                            publication.publicationId,
                            productAdmission
                        )
                    else { return .deferred }
                    if let maximumFinalSequence = receipt.finalFrames.map(\.sequence).max() {
                        guard
                            await publishingStream.session.waitUntilProducerFrameSequenceObserved(
                                for: publishingStream.lease,
                                sequence: maximumFinalSequence,
                                productAdmission: productAdmission
                            )
                        else {
                            guard activeStream?.lease == publishingStream.lease,
                                foregroundWorkAdmission.withValidAdmission({ true }) == true,
                                await isReviewPublicationCurrent(
                                    publication.publicationId,
                                    productAdmission
                                ),
                                (productAdmission.withValidAdmission { true }) == true
                            else { return .deferred }
                            return .failed
                        }
                    }
                    guard activeStream?.lease == publishingStream.lease,
                        foregroundWorkAdmission.withValidAdmission({ true }) == true,
                        await isReviewPublicationCurrent(
                            publication.publicationId,
                            productAdmission
                        )
                    else { return .deferred }
                    await lifecycleTraceRecorder?.record(
                        .completed(receipt: receipt, traceContext: traceContext)
                    )
                    return receipt.publishedSubscriptions > 0
                        ? .transportAcknowledged
                        : .deferred
                case .deferred:
                    return .deferred
                }
            } catch {
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
            await retireReviewSubscriptionAfterReset(subscriptionId: subscriptionId)
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
