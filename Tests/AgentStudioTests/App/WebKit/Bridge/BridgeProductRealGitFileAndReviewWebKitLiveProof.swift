import Foundation

@testable import AgentStudio
@testable import AgentStudioBridge

private struct BridgeProductWebKitLiveReviewState {
    let dom: BridgeProductWebKitCarrierDOMSnapshot
    let expectedSelectedContentHashes: String
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
                _ = try await waitForLiveShell(hostedController, traceRecorder: traceRecorder)
                let reviewState = try await collectLiveReviewState(
                    hostedController,
                    sourceOracle: sourceOracle,
                    traceRecorder: traceRecorder
                )
                let fileState = try await collectLiveFileState(
                    hostedController,
                    sourceOracle: sourceOracle
                )
                guard let installation = await hostedController.productSessionOwner.activeInstallation,
                    await installation.session.waitUntilControlReplayIdle()
                else { throw LiveProofError.appDidNotMount }
                let nativeCompletionSnapshot = await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(
                    hostedController)
                return LiveProof(
                    fileDOMAfterFileSwitch: fileState.dom,
                    fileModeActivated: fileState.activated,
                    filePathSelected: fileState.pathSelected,
                    initialReviewGeneration: reviewState.initialGeneration,
                    native: nativeCompletionSnapshot,
                    reviewDOMBeforeFileSwitch: reviewState.dom,
                    reviewMetadataItemCount: reviewState.itemCount,
                    reviewSelectedContentHashes: reviewState.expectedSelectedContentHashes,
                    sourceOracle: sourceOracle,
                    successorReviewGeneration: reviewState.successorGeneration,
                    trace: await traceRecorder.scrubbedTrace()
                )
            }
    }

    private func waitForLiveShell(
        _ controller: BridgePaneController,
        traceRecorder: BridgeProductWebKitCarrierTraceRecorder
    ) async throws -> BridgeProductWebKitCarrierTrace {
        await WebPageEventWaits.waitForNavigationToFinish(controller.page)
        try await WebPageEventWaits.waitForDocumentSelector(
            controller.page,
            "[data-testid=\"bridge-app-root\"]"
        )
        guard let installation = await controller.productSessionOwner.activeInstallation,
            await installation.session.waitUntilActive(),
            let trace = await traceRecorder.waitForTrace(.fileBootstrap)
        else { throw LiveProofError.appDidNotMount }
        return trace
    }

    private func collectLiveReviewState(
        _ controller: BridgePaneController,
        sourceOracle: LiveSourceOracle,
        traceRecorder: BridgeProductWebKitCarrierTraceRecorder
    ) async throws -> BridgeProductWebKitLiveReviewState {
        let observedGeneration: Int = await BridgePaneControllerEventWaits.waitForValue {
            guard let package = try? controller.ipcReviewPackageSnapshot(),
                package.status == "ready",
                package.items.count >= 128
            else { return nil }
            return package.reviewGeneration
        }
        let initialPackage = try controller.ipcReviewPackageSnapshot()
        guard initialPackage.status == "ready",
            initialPackage.items.count >= 128,
            let initialGeneration = initialPackage.reviewGeneration,
            initialGeneration == observedGeneration
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
        guard
            let successorPackage = controller.paneState.diff.packageMetadata,
            let selectedDescriptor = successorPackage.itemsById.values.first(where: {
                ($0.headPath ?? $0.basePath) == sourceOracle.path
            })
        else {
            throw LiveProofError.successorReviewPublicationMissing
        }
        let expectedSelectedContentHashes = selectedDescriptor.contentRoles.allHandles
            .map { "\($0.role.rawValue):\($0.contentHash)" }
            .joined(separator: ",")
        let metadataValue = try await WebPageEventWaits.waitForDocumentValue(
            controller.page,
            reader: """
                const shell = document.querySelector('[data-testid="review-viewer-shell"]');
                const itemCount = Number(shell?.getAttribute('data-review-metadata-item-count') ?? '0');
                const generation = Number(shell?.getAttribute('data-review-metadata-generation') ?? '0');
                return itemCount >= minimumItems && generation === expectedGeneration ? itemCount : null;
                """,
            arguments: ["minimumItems": 128, "expectedGeneration": successorGeneration]
        )
        guard let metadataItemCount = metadataValue as? Int,
            let reviewTrace = await traceRecorder.waitForTrace(.reviewPublication),
            reviewTrace.hasReviewMetadataPublication
        else { throw LiveProofError.successorReviewPublicationMissing }
        let displayedPath = try await WebPageEventWaits.waitForDocumentValue(
            controller.page,
            reader: """
                const shell = document.querySelector('[data-testid="review-viewer-shell"]');
                const panel = document.querySelector('[data-testid="bridge-code-view-panel"]');
                const hashes = (panel?.getAttribute('data-selected-content-cache-keys') ?? '')
                  .split(',').filter(Boolean)
                  .map(entry => `${entry.split(':')[0] ?? ''}:${entry.split(':').pop() ?? ''}`)
                  .join(',');
                const path = shell?.getAttribute('data-selected-display-path');
                return shell?.getAttribute('data-selected-content-state') === 'ready'
                  && Number(panel?.getAttribute('data-selected-content-line-count') ?? '0') > 0
                  && Boolean(panel?.getAttribute('data-review-rendered-item-id') ?? panel?.getAttribute('data-selected-item-id'))
                  && path === expectedPath && hashes === expectedHashes ? path : null;
                """,
            arguments: [
                "expectedPath": sourceOracle.path,
                "expectedHashes": expectedSelectedContentHashes,
            ]
        )
        guard displayedPath as? String == sourceOracle.path else {
            throw LiveProofError.successorReviewPublicationMissing
        }
        return BridgeProductWebKitLiveReviewState(
            dom: await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page)
                ?? .unavailable,
            expectedSelectedContentHashes: expectedSelectedContentHashes,
            initialGeneration: initialGeneration,
            itemCount: metadataItemCount,
            successorGeneration: successorGeneration
        )
    }

    private func collectLiveFileState(
        _ controller: BridgePaneController,
        sourceOracle: LiveSourceOracle
    ) async throws -> BridgeProductWebKitLiveFileState {
        let activated = await BridgeProductWebKitCarrierTestSupport.activateFileMode(
            controller.page
        )
        guard activated else {
            return BridgeProductWebKitLiveFileState(
                activated: false,
                dom: await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page)
                    ?? .unavailable,
                pathSelected: false
            )
        }
        _ = try await WebPageEventWaits.waitForOpenShadowRootValue(
            controller.page,
            reader: """
                const selector = `button[data-type="item"][data-item-type="file"][data-item-path="${CSS.escape(path)}"]`;
                return findInOpenShadowRoots(document, selector) === null ? null : path;
                """,
            arguments: ["path": sourceOracle.path]
        )
        let pathSelected = await BridgeProductWebKitCarrierTestSupport.selectFilePath(
            controller.page,
            path: sourceOracle.path
        )
        if pathSelected {
            _ = try await WebPageEventWaits.waitForOpenShadowRootValue(
                controller.page,
                reader: """
                    const fileHost = document.querySelector('[data-testid="bridge-viewer-mode-host-file"]');
                    return fileHost !== null && readOpenShadowRootText(fileHost).includes(canaryText)
                      ? canaryText : null;
                    """,
                arguments: ["canaryText": sourceOracle.canaryText]
            )
        }
        return BridgeProductWebKitLiveFileState(
            activated: activated,
            dom: await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page)
                ?? .unavailable,
            pathSelected: pathSelected
        )
    }
}
