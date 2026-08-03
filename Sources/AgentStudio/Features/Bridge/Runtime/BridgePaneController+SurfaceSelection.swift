import Foundation

enum BridgePaneSurfaceSelectionAwaitError: Error, Equatable, Sendable {
    case admissionClosed
    case callerCancelled
    case controllerTeardown
    case sessionInvalidated
    case sourceInvalidated
    case superseded
    case workerReplaced
}

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
            let retention = productAdmission.withValidAdmission({
                surfaceSelectionAuthority.retainIntent(surface: surface)
            })
        else {
            return false
        }
        terminateSurfaceSelectionWaiter(
            commandId: retention.supersededCommandId,
            error: .superseded
        )

        enqueueRetainedSurfaceSelectionTransition(
            productAdmission: productAdmission,
            productSchemeProvider: productSchemeProvider
        )
        return true
    }

    func requestReviewTargetAndWaitForSurfaceReceipt(
        source: BridgeProductNavigationReviewSource,
        target: BridgeProductNavigationReviewTarget
    ) async throws {
        guard let productSchemeProvider,
            let productAdmission = productAdmissionGate.acquire(),
            let retention = productAdmission.withValidAdmission({
                surfaceSelectionAuthority.retainReviewTarget(source: source, target: target)
            })
        else {
            throw BridgePaneSurfaceSelectionAwaitError.admissionClosed
        }
        terminateSurfaceSelectionWaiter(
            commandId: retention.supersededCommandId,
            error: .superseded
        )

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                surfaceSelectionReceiptWaiters[retention.commandId] = continuation
                if Task.isCancelled {
                    terminateSurfaceSelectionWaiter(
                        commandId: retention.commandId,
                        error: .callerCancelled
                    )
                    return
                }
                enqueueRetainedSurfaceSelectionTransition(
                    productAdmission: productAdmission,
                    productSchemeProvider: productSchemeProvider
                )
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.terminateSurfaceSelectionWaiter(
                    commandId: retention.commandId,
                    error: .callerCancelled
                )
            }
        }
    }

    func resolveSurfaceSelectionWaiter(commandId: String) {
        surfaceSelectionReceiptWaiters.removeValue(forKey: commandId)?.resume()
    }

    func terminateSurfaceSelectionWaiter(
        commandId: String?,
        error: BridgePaneSurfaceSelectionAwaitError
    ) {
        guard let commandId else { return }
        surfaceSelectionReceiptWaiters.removeValue(forKey: commandId)?.resume(throwing: error)
    }

    func terminateAllSurfaceSelectionWaiters(error: BridgePaneSurfaceSelectionAwaitError) {
        let continuations = Array(surfaceSelectionReceiptWaiters.values)
        surfaceSelectionReceiptWaiters.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }

    private func enqueueRetainedSurfaceSelectionTransition(
        productAdmission: BridgeProductAdmissionContext,
        productSchemeProvider: BridgePaneProductSchemeProvider
    ) {

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
