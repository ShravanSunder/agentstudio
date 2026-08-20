import AgentStudioCore
import AgentStudioGit
import Foundation

extension BridgePaneProductSchemeProvider {
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

    func resetCurrentReviewSubscriptionsForUnavailableSource(
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async {
        await metadataCoordinator.resetCurrentReviewSubscriptionsForUnavailableSource(
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
            case .fileAnnotationsCommand, .reviewAnnotationsCommand:
                break
            case .fileAnnotationsOutputInspect, .reviewAnnotationsOutputInspect,
                .fileAnnotationsOutputCandidatesQuery, .reviewAnnotationsOutputCandidatesQuery,
                .fileAnnotationsProjectionQuery, .reviewAnnotationsProjectionQuery:
                break
            case .fileSourceCurrent:
                break
            case .fileRefreshRetry:
                await applyFileRefreshRetry(productAdmission)
            case .fileActiveViewerModeUpdate, .reviewActiveViewerModeUpdate:
                await applyActiveViewerModeUpdate(
                    committedProductCall,
                    request.correlation,
                    productAdmission
                )
            case .reviewComparisonUpdate(let updateRequest):
                await applyReviewComparisonUpdate(updateRequest, productAdmission)
            case .reviewComparisonTargetsQuery:
                break
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

    func replayCommittedReviewPublicationIfPresent(
        productAdmission: BridgeProductAdmissionContext,
        traceContext: BridgeTraceContext? = nil
    ) async {
        guard let foregroundWorkAdmission = refreshWorkAdmissionSource.acquire() else { return }
        await metadataCoordinator.replayCommittedReviewPublicationIfPresent(
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
            traceContext: traceContext
        )
    }

    func runContentProducer(
        request: BridgeProductContentRequest,
        lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        session: BridgeProductSession
    ) async {
        let comparisonTargetReservation = claimComparisonTargetReservation(for: request)
        let contentWorkAdmission: BridgePaneRefreshWorkAdmission?
        switch request {
        case .annotationOutput, .annotationProjection:
            contentWorkAdmission = refreshWorkAdmissionSource.acquire()
        case .fileContent:
            contentWorkAdmission = refreshWorkAdmissionSource.acquire()
        case .reviewContent:
            contentWorkAdmission = refreshWorkAdmissionSource.acquireReviewContentContinuation()
        case .reviewComparisonTargets:
            contentWorkAdmission = refreshWorkAdmissionSource.acquire()
        }
        await runContentProducer(
            request: request,
            lease: lease,
            productAdmission: productAdmission,
            session: session,
            contentWorkAdmission: contentWorkAdmission,
            comparisonTargetReservation: comparisonTargetReservation
        )
    }

    nonisolated func makeContentProducerOperation(
        request: BridgeProductContentRequest,
        productAdmission: BridgeProductAdmissionContext,
        session: BridgeProductSession
    ) -> BridgeProductProducerRegistry.ProducerOperation {
        switch request {
        case .annotationOutput, .annotationProjection:
            return { lease in
                await self.runContentProducer(
                    request: request,
                    lease: lease,
                    productAdmission: productAdmission,
                    session: session
                )
            }
        case .fileContent:
            return { lease in
                await self.runContentProducer(
                    request: request,
                    lease: lease,
                    productAdmission: productAdmission,
                    session: session
                )
            }
        case .reviewContent:
            let contentWorkAdmission =
                refreshWorkAdmissionSource.acquireReviewContentContinuation()
            return { lease in
                await self.runContentProducer(
                    request: request,
                    lease: lease,
                    productAdmission: productAdmission,
                    session: session,
                    contentWorkAdmission: contentWorkAdmission
                )
            }
        case .reviewComparisonTargets:
            return { lease in
                await self.runContentProducer(
                    request: request,
                    lease: lease,
                    productAdmission: productAdmission,
                    session: session
                )
            }
        }
    }
}
