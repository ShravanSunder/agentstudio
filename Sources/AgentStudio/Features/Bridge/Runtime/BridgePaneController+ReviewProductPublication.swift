import Foundation

enum BridgeReviewPackageLoadCommitDisposition: Equatable, Sendable {
    case committed
    case rejected
}

@MainActor
extension BridgePaneController {
    func commitReviewPackageLoad(
        _ load: BridgeReviewPackageLoadData,
        productAdmission: BridgeProductAdmissionContext,
        traceContext: BridgeTraceContext?
    ) async -> BridgeReviewPackageLoadCommitDisposition {
        guard
            let publicationToken = reviewPublicationCoordinator.stage(
                load.preparedPublication,
                productAdmission: productAdmission
            )
        else {
            return .rejected
        }

        let reservation: BridgeReviewMetadataPublicationReservation?
        do {
            reservation = try await productSchemeProvider?.reserveReviewPublication(
                package: load.package,
                publicationId: publicationToken.publicationId,
                productAdmission: productAdmission
            )
        } catch {
            _ = reviewPublicationCoordinator.rejectReservation(
                publicationToken,
                productAdmission: productAdmission
            )
            return .rejected
        }

        let commitResult = reviewPublicationCoordinator.commit(
            publicationToken,
            productAdmission: productAdmission
        ) { committedPublication in
            paneState.diff.setPackageMetadata(committedPublication.package)
            paneState.diff.setPackageDelta(committedPublication.delta)
            paneState.diff.setStatus(.ready)
        }
        guard case .committed(let committedPublication) = commitResult else {
            return .rejected
        }

        // Native B is already committed. A closed admission may suppress this
        // rebuildable index update, but cannot turn the commit into rejection.
        _ = await reviewChangeIndex.recordCommittedLoad(
            load.changeIndexLoad,
            productAdmission: productAdmission
        )

        guard
            reviewPublicationCoordinator.isCurrentPublication(
                publicationId: committedPublication.publicationId,
                productAdmission: productAdmission
            )
        else {
            return .committed
        }

        let deliveryDisposition: BridgeReviewPublicationDeliveryDisposition
        if let reservation, let productSchemeProvider {
            deliveryDisposition = await productSchemeProvider.deliverReviewPublication(
                committedPublication,
                reservation: reservation,
                productAdmission: productAdmission,
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
        return .committed
    }
}
