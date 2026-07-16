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
            productAdmission.withValidAdmission({
                paneState.diff.setPackageMetadata(load.package)
                paneState.diff.setPackageDelta(load.delta)
                paneState.diff.setStatus(.ready)
                return true
            }) == true
        else {
            return .rejected
        }
        await productSchemeProvider?.publish(
            availability: .ready(load.package),
            productAdmission: productAdmission,
            traceContext: traceContext
        )
        return productAdmission.withValidAdmission {
            BridgeReviewPackageLoadCommitDisposition.committed
        } ?? .rejected
    }
}
