import Foundation
import WebKit
import os.log

private let bridgeProductBootstrapFailureLogger = Logger(
    subsystem: "com.agentstudio",
    category: "BridgeProductBootstrap"
)

/// Why native answered a product-session bootstrap request without a bootstrap. The web
/// page treats every reason as retryable within its own bounded re-request budget.
package enum BridgeProductSessionBootstrapFailureReason: String, Sendable {
    case activationFailed = "activation_failed"
    case candidatePreparationFailed = "candidate_preparation_failed"
    case deliveryFailed = "delivery_failed"
    case noActiveSession = "no_active_session"
    case retirementFailed = "retirement_failed"
}

package typealias BridgeProductSessionBootstrapFailureSink =
    @MainActor (
        _ page: WebPage,
        _ requestId: String,
        _ reason: BridgeProductSessionBootstrapFailureReason,
        _ contentWorld: WKContentWorld
    ) async throws -> Void

@MainActor
extension BridgePaneController {
    /// Replaces the active product session for a page that already received one. Returns
    /// nil after answering the request with a typed failure, or when the pane is closing.
    func activateReplacementProductSessionInstallation(
        requestId: String,
        reason: BridgeReadyMessageHandler.ProductSessionBootstrapReason,
        productAdmission: BridgeProductAdmissionContext,
        predecessor: BridgeProductInstallationFenceSnapshot?
    ) async -> BridgeProductSessionInstallation? {
        surfaceSelectionAuthority.invalidateCurrentBinding()
        do {
            let candidate = try await productSessionOwner.prepareCandidate(
                productAdmission: productAdmission
            )
            guard
                await productSessionOwner.activatePreparedCandidate(
                    candidate,
                    productAdmission: productAdmission,
                    replacing: predecessor
                ) == .activated
            else {
                setProductBootstrapConnectionErrorIfAdmitted(productAdmission)
                await answerProductSessionBootstrapFailure(
                    requestId: requestId,
                    reason: .activationFailed,
                    productAdmission: productAdmission
                )
                return nil
            }
            return candidate
        } catch BridgePaneProductSessionOwnerError.ownerDisposed {
            return nil
        } catch {
            bridgeProductBootstrapFailureLogger.error("Bridge product session replacement failed: \(error)")
            setProductBootstrapConnectionErrorIfAdmitted(productAdmission)
            await answerProductSessionBootstrapFailure(
                requestId: requestId,
                reason: .candidatePreparationFailed,
                productAdmission: productAdmission
            )
            return nil
        }
    }

    /// Every admitted bootstrap request gets an answer, so the page never waits on a
    /// request native abandoned. Delivery of the answer is best effort: when the page
    /// itself is unreachable there is no one left to wait.
    func answerProductSessionBootstrapFailure(
        requestId: String,
        reason: BridgeProductSessionBootstrapFailureReason,
        productAdmission: BridgeProductAdmissionContext
    ) async {
        guard (productAdmission.withValidAdmission { true }) == true else { return }
        bridgeProductBootstrapFailureLogger.error(
            "Answering product session bootstrap requestId=\(requestId, privacy: .public) with failure reason=\(reason.rawValue, privacy: .public)"
        )
        do {
            try await productSessionBootstrapFailureSink(page, requestId, reason, bridgeWorld)
        } catch {
            bridgeProductBootstrapFailureLogger.error(
                "Product session bootstrap failure reply could not be delivered requestId=\(requestId, privacy: .public)"
            )
        }
    }

    static func dispatchProductSessionBootstrapFailure(
        page: WebPage,
        requestId: String,
        reason: BridgeProductSessionBootstrapFailureReason,
        contentWorld: WKContentWorld
    ) async throws {
        try await page.callJavaScript(
            """
            document.dispatchEvent(new CustomEvent('__bridge_product_session_bootstrap', {
                detail: {
                    requestId: requestId,
                    failure: { reason: reason }
                }
            }));
            """,
            arguments: [
                "requestId": requestId,
                "reason": reason.rawValue,
            ],
            contentWorld: contentWorld
        )
    }
}
