import Foundation

@MainActor
extension BridgePaneController {
    func commitReviewPackageLoad(
        _ load: BridgeReviewPackageLoadData,
        traceContext: BridgeTraceContext?
    ) async {
        paneState.diff.setPackageMetadata(load.package)
        paneState.diff.setPackageDelta(load.delta)
        paneState.diff.setStatus(.ready)
        await productSchemeProvider?.publish(
            availability: .ready(load.package),
            traceContext: traceContext
        )
    }
}
