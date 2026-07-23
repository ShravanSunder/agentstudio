import Foundation

enum BridgeReviewPackageLoadCommitDisposition: Equatable, Sendable {
    case committed(delivery: BridgeReviewPublicationDeliveryDisposition)
    case rejected
}

@MainActor
extension BridgePaneController {
    func commitReviewPackageLoad(
        _ load: BridgeReviewPackageLoadData,
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

        let reservation: BridgeReviewMetadataPublicationReservation?
        do {
            guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                _ = reviewPublicationCoordinator.rejectReservation(
                    publicationToken,
                    productAdmission: productAdmission
                )
                return .rejected
            }
            reservation = try await productSchemeProvider?.reserveReviewPublication(
                package: load.package,
                publicationId: publicationToken.publicationId,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        } catch {
            _ = reviewPublicationCoordinator.rejectReservation(
                publicationToken,
                productAdmission: productAdmission
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
            return .rejected
        }

        let commitPublication = {
            self.reviewPublicationCoordinator.commit(
                publicationToken,
                productAdmission: productAdmission
            ) { committedPublication in
                self.paneState.diff.setPackageMetadata(committedPublication.package)
                self.paneState.diff.setPackageDelta(committedPublication.delta)
                self.paneState.diff.setStatus(.ready)
            }
        }
        guard let commitResult = foregroundWorkAdmission.withValidAdmission(commitPublication)
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
}
