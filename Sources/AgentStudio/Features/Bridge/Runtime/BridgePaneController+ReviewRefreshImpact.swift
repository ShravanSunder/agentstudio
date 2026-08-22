import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

@MainActor
extension BridgePaneController {
    func commitClassifiedReviewPackageRefresh(
        _ load: BridgeReviewPackageLoadData,
        refreshGeneration: BridgeReviewGeneration,
        reservation: BridgePaneRefreshCatchUpReservation,
        productAdmission: BridgeProductAdmissionContext,
        packageTraceContext: BridgeTraceContext?,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async -> BridgePaneRefreshCatchUpOutcome {
        let contentRegisterStart = ContinuousClock.now
        await recordReviewContentRegisterTelemetry(
            traceContext: packageTraceContext,
            contentRegisterStart: contentRegisterStart
        )
        let disposition = await commitReviewPackageLoad(
            load,
            expectedReviewGeneration: refreshGeneration,
            expectedReviewAuthorityGeneration: reservation.authorityGeneration,
            operationCorrelationID: reservation.operationCorrelationID,
            productAdmission: productAdmission,
            traceContext: packageTraceContext,
            foregroundWorkAdmission: foregroundWorkAdmission
        )
        guard case .committed = disposition else {
            return failCurrentReviewComparisonRefresh(
                refreshGeneration,
                failureKind: "publicationRejected",
                reservation: reservation,
                foregroundWorkAdmission: foregroundWorkAdmission,
                productAdmission: productAdmission
            )
        }
        return .succeeded
    }

    func classifyReviewPackageRefresh(
        _ load: BridgeReviewPackageLoadData,
        currentPublication: BridgeReviewCommittedPublication,
        refreshGeneration: BridgeReviewGeneration,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        productAdmission: BridgeProductAdmissionContext,
        reservation: BridgePaneRefreshCatchUpReservation
    ) async throws -> BridgeReviewPackageLoadData? {
        let displayedPublication = reviewPublicationCoordinator.acknowledgedDisplayedPublication(
            productAdmission: productAdmission
        )
        let expectedDisplayedPublicationId = displayedPublication?.publicationId
        let impact: BridgeReviewRefreshImpact
        if let displayedPublication,
            let impactProvider = reviewSourceProvider as? any BridgeReviewRefreshImpactSourceProvider
        {
            impact = try await impactProvider.measureRefreshImpact(
                displayedPackage: displayedPublication.package,
                candidatePackage: load.package,
                candidateGeneration: refreshGeneration
            )
        } else {
            impact = .unknown(
                displayedPackage: displayedPublication?.package,
                candidatePackage: load.package
            )
        }
        guard !Task.isCancelled,
            foregroundWorkAdmission.withValidAdmission({ true }) == true,
            productAdmission.withValidAdmission({ true }) == true,
            refreshAdmissionCoordinator.isRefreshPassCurrent(reservation),
            refreshGeneration == nextReviewGeneration,
            reviewPublicationCoordinator.isCurrentPublication(
                publicationId: currentPublication.publicationId,
                productAdmission: productAdmission
            ),
            reviewPublicationCoordinator.acknowledgedDisplayedPublication(
                productAdmission: productAdmission
            )?.publicationId == expectedDisplayedPublicationId
        else { return nil }
        return load.classified(with: impact)
    }
}
