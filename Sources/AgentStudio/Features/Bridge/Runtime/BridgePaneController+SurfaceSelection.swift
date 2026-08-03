import Foundation

@MainActor
extension BridgePaneController {
    package var retainedViewerSurface: BridgeProductSurface? {
        surfaceSelectionAuthority.diagnosticSnapshot.desiredSurface
    }

    @discardableResult
    package func requestViewerSurface(_ surface: BridgeProductSurface) -> Bool {
        guard let productSchemeProvider,
            let productAdmission = productAdmissionGate.acquire()
        else {
            return false
        }
        guard
            productAdmission.withValidAdmission({
                surfaceSelectionAuthority.retainIntent(surface: surface)
                return true
            })
                == true
        else {
            return false
        }

        _ = enqueueRetainedSurfaceSelectionTransition(
            productAdmission: productAdmission,
            productSchemeProvider: productSchemeProvider
        )
        return true
    }

    func requestReviewTargetAndPublish(
        source: BridgeProductNavigationReviewSource,
        target: BridgeProductNavigationReviewTarget
    ) async throws {
        guard let productSchemeProvider,
            let productAdmission = productAdmissionGate.acquire(),
            productAdmission.withValidAdmission({
                surfaceSelectionAuthority.retainReviewTarget(source: source, target: target)
                return true
            })
                == true
        else {
            throw CancellationError()
        }
        let transition = enqueueRetainedSurfaceSelectionTransition(
            productAdmission: productAdmission,
            productSchemeProvider: productSchemeProvider
        )
        guard await transition.value else {
            throw CancellationError()
        }
    }

    private func enqueueRetainedSurfaceSelectionTransition(
        productAdmission: BridgeProductAdmissionContext,
        productSchemeProvider: BridgePaneProductSchemeProvider
    ) -> Task<Bool, Never> {

        let precedingTransition = surfaceSelectionTransitionTail
        let transition = Task { @MainActor [weak self] in
            if let precedingTransition {
                _ = await precedingTransition.value
            }
            guard let self else { return false }
            return await self.bindAndPublishRetainedSurfaceSelection(
                productAdmission: productAdmission,
                productSchemeProvider: productSchemeProvider
            )
        }
        surfaceSelectionTransitionTail = transition
        return transition
    }

    func bindAndPublishRetainedSurfaceSelection(
        productAdmission: BridgeProductAdmissionContext,
        productSchemeProvider: BridgePaneProductSchemeProvider,
        bootstrap: BridgeProductSessionBootstrap? = nil
    ) async -> Bool {
        let activeBootstrap: BridgeProductSessionBootstrap
        if let bootstrap {
            activeBootstrap = bootstrap
        } else {
            guard let bootstrap = await productSessionOwner.activeBootstrap() else { return false }
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
            return false
        }
        guard let request = admittedRequests?.first else { return false }
        return await productSchemeProvider.publishPaneSurfaceSelectionRequest(
            request,
            productAdmission: productAdmission
        )
    }
}
