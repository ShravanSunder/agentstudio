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
        productAdmission: BridgeProductAdmissionContext,
        traceContext: BridgeTraceContext?,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async -> BridgeReviewPackageLoadCommitDisposition {
        guard
            foregroundWorkAdmission.withValidAdmission({ true }) == true,
            let publicationToken = reviewPublicationCoordinator.stage(
                load.preparedPublication,
                productAdmission: productAdmission
            )
        else {
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
            return .rejected
        }

        guard
            foregroundWorkAdmission.withValidAdmission({ true }) == true
        else {
            _ = reviewPublicationCoordinator.rejectReservation(
                publicationToken,
                productAdmission: productAdmission
            )
            return .rejected
        }

        let commitResult = foregroundWorkAdmission.withValidAdmission {
            () -> BridgeReviewPublicationCommitResult? in
            let currentReviewAuthorityGeneration =
                self.refreshAdmissionCoordinator.currentAuthorityGeneration(for: .review)
            guard expectedReviewGeneration == self.nextReviewGeneration,
                (expectedReviewAuthorityGeneration ?? currentReviewAuthorityGeneration)
                    == currentReviewAuthorityGeneration
            else { return nil }
            return self.reviewPublicationCoordinator.commit(
                publicationToken,
                productAdmission: productAdmission,
                captureCommittedPresentation: captureCommittedReviewComparisonPresentation,
                presentCommitted: { committedPublication in
                    self.paneState.diff.setPackageMetadata(committedPublication.package)
                    self.paneState.diff.setPackageDelta(committedPublication.delta)
                    self.paneState.diff.setStatus(.ready)
                }
            )
        }.flatMap { $0 }
        guard let commitResult
        else {
            _ = reviewPublicationCoordinator.rejectReservation(
                publicationToken,
                productAdmission: productAdmission
            )
            return .rejected
        }
        guard case .committed(let committedPublication) = commitResult else {
            return .rejected
        }
        invalidateRetainedReviewTargetIfSourceChanged(to: committedPublication.package)

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
                publicationId: committedPublication.publicationId,
                productAdmission: productAdmission
            )
        else {
            return .committed(delivery: .deferred)
        }

        let deliveryDisposition: BridgeReviewPublicationDeliveryDisposition
        if let reservation, let productSchemeProvider {
            deliveryDisposition = await productSchemeProvider.deliverReviewPublication(
                committedPublication,
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
            publicationId: committedPublication.publicationId,
            productAdmission: productAdmission
        )
        return .committed(delivery: deliveryDisposition)
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
