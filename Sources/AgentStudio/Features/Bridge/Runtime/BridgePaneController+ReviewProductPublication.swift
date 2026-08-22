import Foundation

enum BridgeReviewPackageLoadCommitDisposition: Equatable, Sendable {
    case committed(delivery: BridgeReviewPublicationDeliveryDisposition)
    case rejected
}

private enum BridgeReviewMetadataReservationResult {
    case accepted(BridgeReviewMetadataPublicationReservation?)
    case rejected
}

@MainActor
extension BridgePaneController {
    func commitReviewPackageLoad(
        _ load: BridgeReviewPackageLoadData,
        expectedReviewGeneration: BridgeReviewGeneration,
        expectedReviewAuthorityGeneration: UInt64? = nil,
        operationCorrelationID: String? = nil,
        productAdmission: BridgeProductAdmissionContext,
        traceContext: BridgeTraceContext?,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async -> BridgeReviewPackageLoadCommitDisposition {
        let operationStageAttempt = 0
        if let operationCorrelationID {
            await productSchemeProvider?.recordOperationLifecycle(
                operationCorrelationID: operationCorrelationID,
                result: .started,
                stage: .refreshCommitStarted,
                stageAttempt: operationStageAttempt,
                surface: .review
            )
        }
        guard
            foregroundWorkAdmission.withValidAdmission({ true }) == true,
            let publicationToken = reviewPublicationCoordinator.stage(
                load.preparedPublication,
                operationCorrelationID: operationCorrelationID,
                productAdmission: productAdmission
            )
        else {
            await recordReviewCommitTerminal(
                operationCorrelationID: operationCorrelationID,
                result: .stale,
                stageAttempt: operationStageAttempt
            )
            return .rejected
        }

        guard
            case .accepted(let reservation) = await reserveReviewPublication(
                load: load,
                publicationToken: publicationToken,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        else {
            await recordReviewCommitTerminal(
                operationCorrelationID: operationCorrelationID,
                result: .failure,
                stageAttempt: operationStageAttempt
            )
            return .rejected
        }

        guard
            foregroundWorkAdmission.withValidAdmission({ true }) == true
        else {
            _ = reviewPublicationCoordinator.rejectReservation(
                publicationToken,
                productAdmission: productAdmission
            )
            await recordReviewCommitTerminal(
                operationCorrelationID: operationCorrelationID,
                result: .stale,
                stageAttempt: operationStageAttempt
            )
            return .rejected
        }

        let commitResult = commitStagedReviewPublication(
            publicationToken,
            expectedReviewGeneration: expectedReviewGeneration,
            expectedReviewAuthorityGeneration: expectedReviewAuthorityGeneration,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission
        )
        guard let commitResult
        else {
            _ = reviewPublicationCoordinator.rejectReservation(
                publicationToken,
                productAdmission: productAdmission
            )
            await recordReviewCommitTerminal(
                operationCorrelationID: operationCorrelationID,
                result: .stale,
                stageAttempt: operationStageAttempt
            )
            return .rejected
        }
        guard case .committed(let committedPublication) = commitResult else {
            let result: BridgeOperationLifecycleTraceEvent.Result =
                commitResult == .closed ? .cancelled : .stale
            await recordReviewCommitTerminal(
                operationCorrelationID: operationCorrelationID,
                result: result,
                stageAttempt: operationStageAttempt
            )
            return .rejected
        }
        _ = scheduleProductPresentationPublication(traceContext: traceContext)
        await recordReviewCommitTerminal(
            operationCorrelationID: operationCorrelationID,
            result: .success,
            stageAttempt: operationStageAttempt
        )
        return await completeCommittedReviewPublication(
            load: load,
            publication: committedPublication,
            reservation: reservation,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
            traceContext: traceContext
        )
    }

    private func commitStagedReviewPublication(
        _ publicationToken: BridgeReviewPublicationToken,
        expectedReviewGeneration: BridgeReviewGeneration,
        expectedReviewAuthorityGeneration: UInt64?,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) -> BridgeReviewPublicationCommitResult? {
        foregroundWorkAdmission.withValidAdmission {
            let currentAuthorityGeneration =
                refreshAdmissionCoordinator.currentAuthorityGeneration(for: .review)
            guard expectedReviewGeneration == nextReviewGeneration,
                (expectedReviewAuthorityGeneration ?? currentAuthorityGeneration)
                    == currentAuthorityGeneration
            else { return nil }
            return reviewPublicationCoordinator.commit(
                publicationToken,
                productAdmission: productAdmission,
                captureCommittedPresentation: captureCommittedReviewComparisonPresentation,
                presentCommitted: { committedPublication in
                    paneState.diff.setPackageMetadata(committedPublication.package)
                    paneState.diff.setPackageDelta(committedPublication.delta)
                    paneState.diff.setStatus(.ready)
                }
            )
        }.flatMap { $0 }
    }

    private func completeCommittedReviewPublication(
        load: BridgeReviewPackageLoadData,
        publication: BridgeReviewCommittedPublication,
        reservation: BridgeReviewMetadataPublicationReservation?,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        traceContext: BridgeTraceContext?
    ) async -> BridgeReviewPackageLoadCommitDisposition {
        invalidateRetainedReviewTargetIfSourceChanged(to: publication.package)

        // Native B is already committed. A closed admission may suppress this
        // rebuildable index update, but cannot turn the commit into rejection.
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
            return .committed(delivery: .deferred)
        }
        _ = await reviewChangeIndex.recordCommittedLoad(
            load.changeIndexLoad,
            productAdmission: productAdmission
        )

        guard foregroundWorkAdmission.withValidAdmission({ true }) == true,
            reviewPublicationCoordinator.isCurrentPublication(
                publicationId: publication.publicationId,
                productAdmission: productAdmission
            )
        else {
            return .committed(delivery: .deferred)
        }

        let deliveryDisposition: BridgeReviewPublicationDeliveryDisposition
        if let reservation, let productSchemeProvider {
            deliveryDisposition = await productSchemeProvider.deliverReviewPublication(
                publication,
                reservation: reservation,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
                traceContext: traceContext
            )
        } else {
            deliveryDisposition = .deferred
        }
        _ = reviewPublicationCoordinator.recordTransportDeliveryDisposition(
            deliveryDisposition,
            publicationId: publication.publicationId,
            productAdmission: productAdmission
        )
        return .committed(delivery: deliveryDisposition)
    }

    private func recordReviewCommitTerminal(
        operationCorrelationID: String?,
        result: BridgeOperationLifecycleTraceEvent.Result,
        stageAttempt: Int
    ) async {
        guard let operationCorrelationID else { return }
        await productSchemeProvider?.recordOperationLifecycle(
            operationCorrelationID: operationCorrelationID,
            result: result,
            stage: .refreshCommitTerminal,
            stageAttempt: stageAttempt,
            surface: .review
        )
    }

    private func reserveReviewPublication(
        load: BridgeReviewPackageLoadData,
        publicationToken: BridgeReviewPublicationToken,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async -> BridgeReviewMetadataReservationResult {
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
            _ = reviewPublicationCoordinator.rejectReservation(
                publicationToken,
                productAdmission: productAdmission
            )
            return .rejected
        }
        do {
            return .accepted(
                try await productSchemeProvider?.reserveReviewPublication(
                    package: load.package,
                    publicationId: publicationToken.publicationId,
                    productAdmission: productAdmission,
                    foregroundWorkAdmission: foregroundWorkAdmission
                )
            )
        } catch {
            _ = reviewPublicationCoordinator.rejectReservation(
                publicationToken,
                productAdmission: productAdmission
            )
            return .rejected
        }
    }

    private func captureCommittedReviewComparisonPresentation(
        _ package: BridgeReviewPackage
    ) -> BridgePaneProductPresentationSnapshot {
        if case .workspace(_, let baseline) = bridgePaneState.source,
            baseline?.contributionTarget != nil
        {
            refreshAdmissionCoordinator.recordCommittedReviewComparisonSnapshot(
                reviewGeneration: package.reviewGeneration.rawValue,
                displayedSnapshotIdentity: BridgePaneReviewDisplayedSnapshotIdentity(
                    packageId: package.packageId,
                    reviewGeneration: package.reviewGeneration.rawValue,
                    revision: package.revision
                )
            )
        }
        return refreshAdmissionCoordinator.productPresentationSnapshot
    }

    private func invalidateRetainedReviewTargetIfSourceChanged(
        to committedPackage: BridgeReviewPackage
    ) {
        surfaceSelectionAuthority.invalidateRetainedReviewTarget(
            ifSourceDoesNotMatch: BridgeProductNavigationReviewSource(
                generation: committedPackage.reviewGeneration.rawValue,
                metadataSourceId: committedPackage.query.queryId,
                packageId: committedPackage.packageId
            )
        )
    }
}
