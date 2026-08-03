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
            let retainedCommandId = productAdmission.withValidAdmission({
                surfaceSelectionAuthority.retainIntent(surface: surface)
            })
        else {
            return false
        }

        _ = enqueueRetainedSurfaceSelectionTransition(
            commandId: retainedCommandId,
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
            let retainedCommandId = productAdmission.withValidAdmission({
                surfaceSelectionAuthority.retainReviewTarget(source: source, target: target)
            })
        else {
            throw CancellationError()
        }
        let transition = enqueueRetainedSurfaceSelectionTransition(
            commandId: retainedCommandId,
            productAdmission: productAdmission,
            productSchemeProvider: productSchemeProvider
        )
        guard await transition.value else {
            throw CancellationError()
        }
    }

    private func enqueueRetainedSurfaceSelectionTransition(
        commandId: String,
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
                commandId: commandId,
                productAdmission: productAdmission,
                productSchemeProvider: productSchemeProvider
            )
        }
        surfaceSelectionTransitionTail = transition
        return transition
    }

    func bindAndPublishRetainedSurfaceSelection(
        commandId: String,
        productAdmission: BridgeProductAdmissionContext,
        productSchemeProvider: BridgePaneProductSchemeProvider,
        bootstrap: BridgeProductSessionBootstrap? = nil
    ) async -> Bool {
        await bindAndPublishSurfaceSelection(
            binding: .retainedCommand(commandId),
            productAdmission: productAdmission,
            productSchemeProvider: productSchemeProvider,
            bootstrap: bootstrap,
            streamAbsenceDisposition: .reject
        )
    }

    func rebindAndPublishRetainedSurfaceSelection(
        productAdmission: BridgeProductAdmissionContext,
        productSchemeProvider: BridgePaneProductSchemeProvider,
        bootstrap: BridgeProductSessionBootstrap? = nil
    ) async -> Bool {
        await bindAndPublishSurfaceSelection(
            binding: .currentRetainedIntent,
            productAdmission: productAdmission,
            productSchemeProvider: productSchemeProvider,
            bootstrap: bootstrap,
            streamAbsenceDisposition: .retainForReplay
        )
    }

    private func bindAndPublishSurfaceSelection(
        binding: BridgePaneSurfaceSelectionBinding,
        productAdmission: BridgeProductAdmissionContext,
        productSchemeProvider: BridgePaneProductSchemeProvider,
        bootstrap: BridgeProductSessionBootstrap?,
        streamAbsenceDisposition: BridgePaneSurfaceSelectionStreamAbsenceDisposition
    ) async -> Bool {
        let activeBootstrap: BridgeProductSessionBootstrap
        if let bootstrap {
            activeBootstrap = bootstrap
        } else {
            guard let bootstrap = await productSessionOwner.activeBootstrap() else {
                if case .retainedCommand(let commandId) = binding {
                    _ = productAdmission.withValidAdmission {
                        surfaceSelectionAuthority.invalidateFailedExactIntent(
                            commandId: commandId
                        )
                    }
                }
                return false
            }
            activeBootstrap = bootstrap
        }
        let admittedRequests: [BridgePaneSurfaceSelectionRequest]?
        do {
            admittedRequests = try productAdmission.withValidAdmission {
                let request: BridgePaneSurfaceSelectionRequest?
                switch binding {
                case .retainedCommand(let commandId):
                    request = try surfaceSelectionAuthority.bindRetainedIntent(
                        commandId: commandId,
                        paneSessionId: activeBootstrap.paneSessionId,
                        workerInstanceId: activeBootstrap.workerInstanceId
                    )
                case .currentRetainedIntent:
                    request = try surfaceSelectionAuthority.rebindRetainedIntent(
                        paneSessionId: activeBootstrap.paneSessionId,
                        workerInstanceId: activeBootstrap.workerInstanceId
                    )
                }
                guard let request else { return [] }
                return [request]
            }
        } catch {
            return false
        }
        guard let request = admittedRequests?.first else { return false }
        let wasPublished = await productSchemeProvider.publishPaneSurfaceSelectionRequest(
            request,
            productAdmission: productAdmission,
            streamAbsenceDisposition: streamAbsenceDisposition
        )
        if !wasPublished, streamAbsenceDisposition == .reject {
            _ = productAdmission.withValidAdmission {
                surfaceSelectionAuthority.invalidateFailedExactIntent(
                    commandId: request.requestId
                )
            }
        }
        return wasPublished
    }
}

private enum BridgePaneSurfaceSelectionBinding {
    case retainedCommand(String)
    case currentRetainedIntent
}
