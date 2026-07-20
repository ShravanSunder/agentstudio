import Foundation

@testable import AgentStudio

private struct BridgeProductWebKitLiveReviewState {
    let dom: BridgeProductWebKitCarrierDOMSnapshot
    let initialGeneration: Int
    let itemCount: Int
    let successorGeneration: Int
}

private struct BridgeProductWebKitLiveFileState {
    let activated: Bool
    let dom: BridgeProductWebKitCarrierDOMSnapshot
    let pathSelected: Bool
}

@MainActor
extension WebKitSerializedTests.BridgeProductRealGitFileAndReviewWebKitTests {
    func collectLiveProof(
        controller: BridgePaneController,
        sourceOracle: LiveSourceOracle,
        traceRecorder: BridgeProductWebKitCarrierTraceRecorder
    ) async throws -> BridgeProductWebKitCarrierRunResult<LiveProof> {
        try await BridgeProductWebKitCarrierTestSupport
            .withHostedController(controller) { hostedController in
                hostedController.loadApp()
                await waitForLiveShell(hostedController, traceRecorder: traceRecorder)
                let reviewState = try await collectLiveReviewState(
                    hostedController,
                    sourceOracle: sourceOracle,
                    traceRecorder: traceRecorder
                )
                let fileState = await collectLiveFileState(
                    hostedController,
                    sourceOracle: sourceOracle
                )
                return LiveProof(
                    fileDOMAfterFileSwitch: fileState.dom,
                    fileModeActivated: fileState.activated,
                    filePathSelected: fileState.pathSelected,
                    initialReviewGeneration: reviewState.initialGeneration,
                    native: await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(hostedController),
                    reviewDOMBeforeFileSwitch: reviewState.dom,
                    reviewMetadataItemCount: reviewState.itemCount,
                    sourceOracle: sourceOracle,
                    successorReviewGeneration: reviewState.successorGeneration,
                    trace: await traceRecorder.scrubbedTrace()
                )
            }
    }

    private func waitForLiveShell(
        _ controller: BridgePaneController,
        traceRecorder: BridgeProductWebKitCarrierTraceRecorder
    ) async {
        _ = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(15)) {
            let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page)
            let native = await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(controller)
            return dom?.hasAppRoot == true && native.lifecycle == "active"
        }
        _ = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(15)) {
            let trace = await traceRecorder.scrubbedTrace()
            return trace.hasCanonicalEagerSubscriptions && trace.hasFileMetadataWindow
        }
    }

    private func collectLiveReviewState(
        _ controller: BridgePaneController,
        sourceOracle: LiveSourceOracle,
        traceRecorder: BridgeProductWebKitCarrierTraceRecorder
    ) async throws -> BridgeProductWebKitLiveReviewState {
        _ = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(15)) {
            guard let package = try? controller.ipcReviewPackageSnapshot() else { return false }
            return package.status == "ready"
                && package.reviewGeneration != nil
                && package.items.count >= 128
        }
        let initialPackage = try controller.ipcReviewPackageSnapshot()
        guard initialPackage.status == "ready",
            initialPackage.items.count >= 128,
            let initialGeneration = initialPackage.reviewGeneration
        else {
            throw LiveProofError.initialReviewPublicationMissing
        }
        let refresh = try await controller.refreshReviewForIPC(correlationId: nil)
        guard refresh.refreshed,
            let successorGeneration = refresh.reviewGeneration,
            successorGeneration > initialGeneration
        else {
            throw LiveProofError.successorReviewPublicationMissing
        }
        _ = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(15)) {
            guard
                let metadata = await reviewMetadataDOMSnapshot(controller),
                metadata.itemCount >= 128,
                metadata.reviewGeneration == successorGeneration
            else {
                return false
            }
            return await traceRecorder.scrubbedTrace().hasReviewMetadataPublication
        }
        _ = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(15)) {
            let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page)
            guard let dom, let renderedItemId = dom.reviewRenderedItemId else { return false }
            return dom.hasReviewShell
                && dom.hasReviewCodeViewPanel
                && dom.reviewSelectedContentState == "ready"
                && dom.correlations.contains { correlation in
                    correlation.semanticItemId == renderedItemId
                        && correlation.sourceGeneration == successorGeneration
                        && correlation.readableText.contains(sourceOracle.canaryText)
                }
        }
        return BridgeProductWebKitLiveReviewState(
            dom: await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page)
                ?? .unavailable,
            initialGeneration: initialGeneration,
            itemCount: await reviewMetadataDOMSnapshot(controller)?.itemCount ?? 0,
            successorGeneration: successorGeneration
        )
    }

    private func collectLiveFileState(
        _ controller: BridgePaneController,
        sourceOracle: LiveSourceOracle
    ) async -> BridgeProductWebKitLiveFileState {
        let activated = await BridgeProductWebKitCarrierTestSupport.activateFileMode(
            controller.page
        )
        let pathSelected: Bool
        if activated {
            pathSelected = await BridgeProductWebKitCarrierTestSupport.waitUntil(
                timeout: .seconds(15)
            ) {
                await BridgeProductWebKitCarrierTestSupport.selectFilePath(
                    controller.page,
                    path: sourceOracle.path
                )
            }
        } else {
            pathSelected = false
        }
        _ = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(15)) {
            let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page)
            return dom?.fileReadableText.contains(sourceOracle.canaryText) == true
        }
        return BridgeProductWebKitLiveFileState(
            activated: activated,
            dom: await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page)
                ?? .unavailable,
            pathSelected: pathSelected
        )
    }
}
