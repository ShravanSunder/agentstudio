import Foundation

@MainActor
extension BridgePaneController {
    @discardableResult
    func requestViewerSurface(_ surface: BridgeProductSurface) -> Bool {
        guard let productSchemeProvider,
            let productAdmission = productAdmissionGate.acquire()
        else {
            return false
        }
        guard
            productAdmission.withValidAdmission({
                surfaceSelectionAuthority.retainIntent(surface: surface)
                return true
            }) == true
        else {
            return false
        }

        let precedingTransition = surfaceSelectionTransitionTail
        let transition = Task { @MainActor [weak self] in
            if let precedingTransition {
                await precedingTransition.value
            }
            await self?.bindAndPublishRetainedSurfaceSelection(
                productAdmission: productAdmission,
                productSchemeProvider: productSchemeProvider
            )
        }
        surfaceSelectionTransitionTail = transition
        return true
    }

    func bindAndPublishRetainedSurfaceSelection(
        productAdmission: BridgeProductAdmissionContext,
        productSchemeProvider: BridgePaneProductSchemeProvider,
        bootstrap: BridgeProductSessionBootstrap? = nil
    ) async {
        let activeBootstrap: BridgeProductSessionBootstrap
        if let bootstrap {
            activeBootstrap = bootstrap
        } else {
            guard let bootstrap = await productSessionOwner.activeBootstrap() else { return }
            activeBootstrap = bootstrap
        }
        let admittedRequests: [BridgePaneSurfaceSelectionRequest]?
        do {
            admittedRequests = try productAdmission.withValidAdmission {
                guard
                    let request = try surfaceSelectionAuthority.bindRetainedIntent(
                        paneSessionId: activeBootstrap.paneSessionId,
                        workerInstanceId: activeBootstrap.workerInstanceId
                    )
                else { return [] }
                return [request]
            }
        } catch {
            return
        }
        guard let request = admittedRequests?.first else { return }
        await productSchemeProvider.publishPaneSurfaceSelectionRequest(
            request,
            productAdmission: productAdmission
        )
    }
}
