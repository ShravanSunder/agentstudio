import AgentStudioProgrammaticControl
import Foundation
import Testing
import WebKit

@testable import AgentStudio
@testable import AgentStudioBridge

private struct BridgeProductWebKitLiveReviewState {
    let dom: BridgeProductWebKitCarrierDOMSnapshot
    let expectedSelectedContentHashes: String
    let initialGeneration: Int
    let itemCount: Int
    let successorGeneration: Int
}

struct BridgeProductWebKitLiveFileState: CustomStringConvertible, Sendable {
    let activated: Bool
    let displayPath: String
    let displaySourceId: String?
    let initialDisplayItemCount: Int
    let initialTreeRowCount: Int
    let filteredDisplayItemCount: Int
    let filteredTreeRowCount: Int
    let queryText: String
    let queryStatus: String
    let revealItemId: String?
    let revealPath: String?
    let selectedPath: String?
    let openFilePath: String?
    let openFileState: String?

    var description: String {
        "active=\(activated),path=\(displayPath),source=\(displaySourceId ?? "none"),rows=\(initialTreeRowCount)->\(filteredTreeRowCount),items=\(initialDisplayItemCount)->\(filteredDisplayItemCount),query=\(queryStatus):\(queryText),reveal=\(revealPath ?? "none")/\(revealItemId ?? "none"),selected=\(selectedPath ?? "none"),open=\(openFilePath ?? "none")/\(openFileState ?? "idle")"
    }
}

private struct BridgeProductWebKitLiveFileLogicalSnapshot: Decodable {
    let displayItemCount: Int
    let displaySourceId: String?
    let treeRowCount: Int
    let selectedPath: String?
    let openFilePath: String?
    let openFileState: String?
}

private struct BridgeProductWebKitLiveFileQueryState {
    let initialSnapshot: BridgeProductWebKitLiveFileLogicalSnapshot
    let filteredSnapshot: BridgeProductWebKitLiveFileLogicalSnapshot
    let queryText: String
    let queryStatus: String
}

private struct BridgeProductWebKitLiveFileRevealState {
    let itemId: String?
    let path: String?
    let openState: BridgeProductWebKitLiveFileLogicalSnapshot
}

@MainActor
extension WebKitSerializedTests.BridgeProductRealGitFileAndReviewWebKitTests {
    func assertProof(
        _ run: BridgeProductWebKitCarrierRunResult<LiveProof>
    ) {
        assertProductSessionPublication(run)
        assertReviewPresentation(run)
        assertLogicalFileSelection(run)
    }

    private func assertProductSessionPublication(
        _ run: BridgeProductWebKitCarrierRunResult<LiveProof>
    ) {
        let fileDOM = run.value.fileDOMAfterFileSwitch
        let reviewDOM = run.value.reviewDOMBeforeFileSwitch
        #expect(
            reviewDOM.hasAppRoot && fileDOM.hasAppRoot,
            "W0 product seam: the current bundled BridgeWeb app did not mount"
        )
        #expect(
            run.value.native.lifecycle == "active",
            "W0 product seam: the bundled worker did not open the production product session; native=\(run.value.native)"
        )
        #expect(
            run.value.trace.hasCanonicalEagerSubscriptions,
            "W0 product seam: the worker did not open canonical eager File+Review subscriptions; trace=\(run.value.trace)"
        )
        #expect(
            run.value.trace.hasFileMetadataWindow,
            "W0 product seam: production agentstudio-git File metadata did not reach the worker stream; trace=\(run.value.trace)"
        )
        #expect(
            run.value.trace.hasReviewMetadataPublication,
            "W0 product seam: production agentstudio-git Review metadata did not reach the worker stream; trace=\(run.value.trace)"
        )
        #expect(
            run.value.reviewMetadataItemCount >= 128,
            "W0 product seam: the worker did not publish the complete heavy Review metadata set; itemCount=\(run.value.reviewMetadataItemCount), trace=\(run.value.trace)"
        )
        #expect(
            run.value.successorReviewGeneration > run.value.initialReviewGeneration,
            "W0 product seam: the production refresh did not replace the initial Review publication; initialGeneration=\(run.value.initialReviewGeneration), successorGeneration=\(run.value.successorReviewGeneration)"
        )
        #expect(
            run.value.native.nextControlRequestSequence > 1,
            "W0 product seam: worker-initiated product command POSTs were not acknowledged; native=\(run.value.native)"
        )
        #expect(
            run.value.native.nextMetadataStreamSequence > 1,
            "W0 product seam: streamed metadata frames and bodyless observations did not advance; native=\(run.value.native)"
        )
        #expect(
            run.value.native.inFlightControlRequestSequence == nil,
            "W0 product seam: a product command remained in flight; native=\(run.value.native)"
        )
        #expect(
            reviewDOM.hasReviewModeHost && fileDOM.hasFileModeHost,
            "W0 product seam: the canonical File+Review viewer hosts were not both constructed; reviewDOM=\(reviewDOM), fileDOM=\(fileDOM)"
        )
        #expect(
            reviewDOM.hasReviewShell,
            "W0 construction seam: Review metadata crossed the worker but no product Review shell mounted; reviewDOM=\(reviewDOM), trace=\(run.value.trace)"
        )
    }

    private func assertReviewPresentation(
        _ run: BridgeProductWebKitCarrierRunResult<LiveProof>
    ) {
        let reviewDOM = run.value.reviewDOMBeforeFileSwitch
        #expect(
            reviewDOM.hasReviewCodeViewPanel
                && reviewDOM.reviewSelectedContentState == "ready"
                && reviewDOM.reviewSelectedContentLineCount > 0
                && reviewDOM.reviewSelectedContentHashes == run.value.reviewSelectedContentHashes,
            "W0 content-observation seam: Swift emitted successor Review content, but the worker did not acknowledge and drain it into a ready CodeView; reviewDOM=\(reviewDOM), native=\(run.value.native), host=\(run.hostSnapshot)"
        )
        #expect(
            reviewDOM.reviewSelectedDisplayPath == run.value.sourceOracle.path,
            "G0 PACKAGED SELECTED IDENTITY MISSING: selected Review path did not match the live-git oracle; selected=\(reviewDOM.reviewSelectedDisplayPath ?? "missing"), expected=\(run.value.sourceOracle.path)"
        )
        #expect(
            reviewDOM.reviewRenderedItemId?.isEmpty == false,
            "G0 PACKAGED SEMANTIC ITEM MISSING: rendered Review item did not retain its canonical semantic identity"
        )
    }

    private func assertLogicalFileSelection(
        _ run: BridgeProductWebKitCarrierRunResult<LiveProof>
    ) {
        #expect(
            run.value.fileModeActivated,
            "G0 PACKAGED FILE MODE MISSING: the real bundled File control was not available"
        )
        #expect(
            run.value.fileIPCRevealSelected,
            "G0 PACKAGED FILE SELECTION MISSING: File IPC reveal did not select the live-git source"
        )
        #expect(
            run.value.fileState.displaySourceId?.isEmpty == false
                && run.value.fileState.initialDisplayItemCount > 1
                && run.value.fileState.initialTreeRowCount > 1
                && run.value.fileState.filteredDisplayItemCount > 0
                && run.value.fileState.filteredTreeRowCount == 1,
            "G0 FILE INDEX/QUERY MISSING: logical collection index did not narrow to the tracked source; state=\(run.value.fileState)"
        )
        #expect(
            run.value.fileState.queryStatus == "accepted"
                && run.value.fileState.queryText == run.value.sourceOracle.path,
            "G0 FILE QUERY MISSING: the page did not accept the expected query; state=\(run.value.fileState)"
        )
        #expect(
            run.value.fileState.revealItemId?.isEmpty == false
                && run.value.fileState.revealPath == run.value.fileState.displayPath,
            "G0 FILE IPC REVEAL MISSING: reveal did not resolve the member's display key; state=\(run.value.fileState)"
        )
        #expect(
            run.value.fileState.selectedPath == run.value.fileState.displayPath
                && run.value.fileState.openFilePath == run.value.fileState.displayPath
                && run.value.fileState.openFileState == "ready",
            "G0 FILE OPEN-READY MISSING: logical selection or content-open state did not settle; state=\(run.value.fileState)"
        )
        #expect(
            run.teardownSnapshot.hasZeroResidue,
            "W0 teardown seam: production product session retained transport residue; snapshot=\(run.teardownSnapshot)"
        )
    }

    func collectLiveProof(
        controller: BridgePaneController,
        sourceOracle: LiveSourceOracle,
        traceRecorder: BridgeProductWebKitCarrierTraceRecorder
    ) async throws -> BridgeProductWebKitCarrierRunResult<LiveProof> {
        try await BridgeProductWebKitCarrierTestSupport
            .withHostedController(controller) { hostedController, hostWindow in
                recordRealGitLiveProofStage(
                    "host-snapshot=\(BridgeProductWebKitCarrierTestSupport.hostSnapshot(window: hostWindow))"
                )
                recordRealGitLiveProofStage("load-app")
                hostedController.loadApp()
                recordRealGitLiveProofStage("await-live-shell")
                await waitForLiveShell(hostedController, traceRecorder: traceRecorder)
                recordRealGitLiveProofStage("live-shell-ready")
                recordRealGitLiveProofStage("await-review-state")
                let reviewState = try await collectLiveReviewState(
                    hostedController,
                    sourceOracle: sourceOracle,
                    traceRecorder: traceRecorder
                )
                recordRealGitLiveProofStage("review-state-ready")
                recordRealGitLiveProofStage("await-file-state")
                let fileState = try await collectLiveFileState(
                    hostedController,
                    sourceOracle: sourceOracle
                )
                recordRealGitLiveProofStage("file-state-ready")
                let fileDOM =
                    await BridgeProductWebKitCarrierTestSupport.domSnapshot(
                        hostedController.page
                    ) ?? .unavailable
                var nativeCompletionSnapshot = await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(
                    hostedController)
                recordRealGitLiveProofStage("await-final-control-receipt")
                _ = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(15)) {
                    nativeCompletionSnapshot = await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(
                        hostedController)
                    return nativeCompletionSnapshot.inFlightControlRequestSequence == nil
                }
                recordRealGitLiveProofStage("final-control-receipt-ready")
                return LiveProof(
                    fileDOMAfterFileSwitch: fileDOM,
                    fileModeActivated: fileState.activated,
                    fileIPCRevealSelected: fileState.selectedPath == fileState.displayPath,
                    fileState: fileState,
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
    ) async {
        recordRealGitLiveProofStage("await-app-root-and-native-active")
        _ = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(15)) {
            let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page)
            let native = await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(controller)
            return dom?.hasAppRoot == true && native.lifecycle == "active"
        }
        recordRealGitLiveProofStage("app-root-and-native-active-observed")
        recordRealGitLiveProofStage("await-eager-subscriptions-and-file-window")
        _ = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(15)) {
            let trace = await traceRecorder.scrubbedTrace()
            return trace.hasCanonicalEagerSubscriptions && trace.hasFileMetadataWindow
        }
        recordRealGitLiveProofStage("eager-subscriptions-and-file-window-observed")
    }

    private func collectLiveReviewState(
        _ controller: BridgePaneController,
        sourceOracle: LiveSourceOracle,
        traceRecorder: BridgeProductWebKitCarrierTraceRecorder
    ) async throws -> BridgeProductWebKitLiveReviewState {
        recordRealGitLiveProofStage("await-initial-review-package")
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
        recordRealGitLiveProofStage("initial-review-package-ready")
        recordRealGitLiveProofStage("request-review-refresh")
        let refresh = try await controller.refreshReviewForIPC(correlationId: nil)
        recordRealGitLiveProofStage("review-refresh-replied")
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
        recordRealGitLiveProofStage("await-successor-review-metadata")
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
        recordRealGitLiveProofStage("successor-review-metadata-observed")
        recordRealGitLiveProofStage("await-rendered-review-content-state")
        _ = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(15)) {
            let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page)
            guard let dom else { return false }
            return dom.hasReviewShell
                && dom.hasReviewCodeViewPanel
                && dom.reviewSelectedContentState == "ready"
                && dom.reviewSelectedContentLineCount > 0
                && dom.reviewSelectedDisplayPath == sourceOracle.path
                && dom.reviewRenderedItemId?.isEmpty == false
                && dom.reviewSelectedContentHashes == expectedSelectedContentHashes
        }
        recordRealGitLiveProofStage("rendered-review-content-state-observed")
        return BridgeProductWebKitLiveReviewState(
            dom: await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page)
                ?? .unavailable,
            expectedSelectedContentHashes: expectedSelectedContentHashes,
            initialGeneration: initialGeneration,
            itemCount: await reviewMetadataDOMSnapshot(controller)?.itemCount ?? 0,
            successorGeneration: successorGeneration
        )
    }

    private func collectLiveFileState(
        _ controller: BridgePaneController,
        sourceOracle: LiveSourceOracle
    ) async throws -> BridgeProductWebKitLiveFileState {
        recordRealGitLiveProofStage("activate-file-mode")
        let activated = await BridgeProductWebKitCarrierTestSupport.activateFileMode(
            controller.page
        )
        recordRealGitLiveProofStage("file-mode-activation-replied")
        recordRealGitLiveProofStage("await-active-file-viewer-host")
        try await BridgeProductWebKitCarrierTestSupport.waitForActiveFileViewerHost(
            controller.page
        )
        recordRealGitLiveProofStage("active-file-viewer-host-ready")
        // Files lists the worktree's rows under its collection group key.
        guard activated,
            let worktreeId = controller.filesBinding?.members.first?.id,
            let fileDisplayPath = await controller.fileCollectionDisplayPath(
                worktreeId: worktreeId,
                relativePath: sourceOracle.path
            )
        else {
            throw WebKitLiveProofError.fileIndexMissing
        }

        recordRealGitLiveProofStage("capture-initial-logical-file-index")
        let initialFileIndexSnapshot = try await controller.page.callJavaScript(
            """
            const fileShell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
            return JSON.stringify({
                  documentVisibilityState: document.visibilityState,
                  fileModeHostPresent:
                    document.querySelector('[data-testid="bridge-viewer-mode-host-file"]') !== null,
                  fileModeHostActive:
                    document.querySelector('[data-testid="bridge-viewer-mode-host-file"]')
                      ?.getAttribute('data-bridge-viewer-mode-active') === 'true',
                  fileShellPresent: fileShell !== null,
              fileViewerActive: fileShell?.getAttribute('data-file-viewer-active') === 'true',
              displaySourceId: fileShell?.getAttribute('data-file-display-source-id') ?? null,
              displayItemCount: Number(fileShell?.getAttribute('data-file-display-item-count') ?? '0'),
              treeRowCount: Number(fileShell?.getAttribute('data-file-display-tree-row-count') ?? '0')
            });
            """,
            contentWorld: .page
        )
        recordRealGitLiveProofStage(
            "initial-logical-file-index-snapshot=\(initialFileIndexSnapshot as? String ?? "unavailable")"
        )
        recordRealGitLiveProofStage("await-initial-logical-file-index")
        let initialState = try await waitForLiveFileIndex(controller.page)
        recordRealGitLiveProofStage("initial-logical-file-index-ready")
        let queryState = try await searchLiveFileByIPC(
            controller,
            relativePath: sourceOracle.path,
            initialState: initialState
        )
        let revealState = try await revealLiveFileByIPC(
            controller,
            relativePath: sourceOracle.path,
            displayPath: fileDisplayPath
        )

        return BridgeProductWebKitLiveFileState(
            activated: activated,
            displayPath: fileDisplayPath,
            displaySourceId: revealState.openState.displaySourceId,
            initialDisplayItemCount: queryState.initialSnapshot.displayItemCount,
            initialTreeRowCount: queryState.initialSnapshot.treeRowCount,
            filteredDisplayItemCount: queryState.filteredSnapshot.displayItemCount,
            filteredTreeRowCount: queryState.filteredSnapshot.treeRowCount,
            queryText: queryState.queryText,
            queryStatus: queryState.queryStatus,
            revealItemId: revealState.itemId,
            revealPath: revealState.path,
            selectedPath: revealState.openState.selectedPath,
            openFilePath: revealState.openState.openFilePath,
            openFileState: revealState.openState.openFileState
        )
    }

    private func searchLiveFileByIPC(
        _ controller: BridgePaneController,
        relativePath: String,
        initialState: BridgeProductWebKitLiveFileLogicalSnapshot
    ) async throws -> BridgeProductWebKitLiveFileQueryState {
        recordRealGitLiveProofStage("issue-file-search")
        let searchResult = try await controller.applyPageControlForIPC(
            .fileTreeSearch(searchText: relativePath),
            correlationId: nil
        )
        guard searchResult.status == "accepted",
            searchResult.method
                == IPCBridgePageControlCommand.fileTreeSearch(searchText: relativePath).method,
            searchResult.treeSearchText == relativePath
        else {
            throw WebKitLiveProofError.fileSearchWasNotAccepted
        }

        recordRealGitLiveProofStage("file-search-control-replied")
        recordRealGitLiveProofStage("await-filtered-logical-file-index")
        let filteredState = try await waitForLiveFileQuery(
            controller.page,
            expectedTreeRowCount: 1
        )
        guard filteredState.treeRowCount < initialState.treeRowCount else {
            throw WebKitLiveProofError.fileQueryDidNotReplaceTheIndex
        }

        return BridgeProductWebKitLiveFileQueryState(
            initialSnapshot: initialState,
            filteredSnapshot: filteredState,
            queryText: searchResult.treeSearchText,
            queryStatus: searchResult.status
        )
    }

    private func revealLiveFileByIPC(
        _ controller: BridgePaneController,
        relativePath: String,
        displayPath: String
    ) async throws -> BridgeProductWebKitLiveFileRevealState {
        recordRealGitLiveProofStage("filtered-logical-file-index-ready")
        recordRealGitLiveProofStage("issue-file-reveal")
        let revealResult = try await controller.applyPageControlForIPC(
            .fileTreeRevealPath(path: relativePath),
            correlationId: nil
        )
        guard revealResult.status == "accepted",
            revealResult.method
                == IPCBridgePageControlCommand.fileTreeRevealPath(path: relativePath).method,
            revealResult.path == displayPath,
            revealResult.itemId?.isEmpty == false
        else {
            throw WebKitLiveProofError.fileRevealWasNotAccepted
        }

        recordRealGitLiveProofStage("file-reveal-control-replied")
        recordRealGitLiveProofStage("await-file-open-ready")
        let openState = try await waitForLiveFileOpenState(
            controller.page,
            expectedDisplayPath: displayPath
        )
        guard openState.selectedPath == displayPath,
            openState.openFilePath == displayPath,
            openState.openFileState == "ready"
        else {
            throw WebKitLiveProofError.fileOpenDidNotReachReady
        }
        recordRealGitLiveProofStage("file-open-ready")

        return BridgeProductWebKitLiveFileRevealState(
            itemId: revealResult.itemId,
            path: revealResult.path,
            openState: openState
        )
    }

    private func waitForLiveFileIndex(
        _ page: WebPage
    ) async throws -> BridgeProductWebKitLiveFileLogicalSnapshot {
        let encodedState = try await WebPageEventWaits.waitForDocumentValue(
            page,
            reader: """
                const fileShell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
                if (fileShell === null) return null;
                const displaySourceId = fileShell.getAttribute('data-file-display-source-id');
                const displayItemCount = Number(fileShell.getAttribute('data-file-display-item-count') ?? '0');
                const treeRowCount = Number(fileShell.getAttribute('data-file-display-tree-row-count') ?? '0');
                if (fileShell.getAttribute('data-file-viewer-active') !== 'true' ||
                    displaySourceId === null || displayItemCount < 2 || treeRowCount < 2) return null;
                return JSON.stringify({ displayItemCount, displaySourceId, treeRowCount });
                """,
            arguments: [:]
        )
        return try decodeLiveFileLogicalSnapshot(encodedState)
    }

    private func waitForLiveFileQuery(
        _ page: WebPage,
        expectedTreeRowCount: Int
    ) async throws -> BridgeProductWebKitLiveFileLogicalSnapshot {
        let encodedState = try await WebPageEventWaits.waitForDocumentValue(
            page,
            reader: """
                const fileShell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
                if (fileShell === null) return null;
                const displaySourceId = fileShell.getAttribute('data-file-display-source-id');
                const displayItemCount = Number(fileShell.getAttribute('data-file-display-item-count') ?? '0');
                const treeRowCount = Number(fileShell.getAttribute('data-file-display-tree-row-count') ?? '0');
                if (fileShell.getAttribute('data-file-viewer-active') !== 'true' ||
                    displaySourceId === null || displayItemCount === 0 ||
                    treeRowCount !== expectedTreeRowCount) return null;
                return JSON.stringify({ displayItemCount, displaySourceId, treeRowCount });
                """,
            arguments: ["expectedTreeRowCount": expectedTreeRowCount]
        )
        return try decodeLiveFileLogicalSnapshot(encodedState)
    }

    private func waitForLiveFileOpenState(
        _ page: WebPage,
        expectedDisplayPath: String
    ) async throws -> BridgeProductWebKitLiveFileLogicalSnapshot {
        let encodedState = try await WebPageEventWaits.waitForDocumentValue(
            page,
            reader: """
                const fileShell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
                if (fileShell === null) return null;
                const selectedPath = fileShell.getAttribute('data-selected-display-path');
                const openFilePath = fileShell.getAttribute('data-worktree-open-file-path');
                const openFileState = fileShell.getAttribute('data-worktree-open-file-state');
                if (selectedPath !== expectedDisplayPath || openFilePath !== expectedDisplayPath ||
                    openFileState !== 'ready') return null;
                return JSON.stringify({
                  displayItemCount: Number(fileShell.getAttribute('data-file-display-item-count') ?? '0'),
                  displaySourceId: fileShell.getAttribute('data-file-display-source-id'),
                  treeRowCount: Number(fileShell.getAttribute('data-file-display-tree-row-count') ?? '0'),
                  selectedPath,
                  openFilePath,
                  openFileState
                });
                """,
            arguments: ["expectedDisplayPath": expectedDisplayPath]
        )
        return try decodeLiveFileLogicalSnapshot(encodedState)
    }

    private func decodeLiveFileLogicalSnapshot(
        _ encodedState: Any?
    ) throws -> BridgeProductWebKitLiveFileLogicalSnapshot {
        guard let encodedState = encodedState as? String,
            let data = encodedState.data(using: .utf8)
        else {
            throw WebKitLiveProofError.fileLogicalStateWasNotReturned
        }
        return try JSONDecoder().decode(BridgeProductWebKitLiveFileLogicalSnapshot.self, from: data)
    }
}

private enum WebKitLiveProofError: Error {
    case fileIndexMissing
    case fileLogicalStateWasNotReturned
    case fileOpenDidNotReachReady
    case fileQueryDidNotReplaceTheIndex
    case fileRevealWasNotAccepted
    case fileSearchWasNotAccepted
}

func recordRealGitLiveProofStage(_ stage: String) {
    let marker = "[real-git-file-review] \(stage)\n"
    FileHandle.standardError.write(Data(marker.utf8))
    if let phaseFilePath = ProcessInfo.processInfo.environment["AGENTSTUDIO_B1_PHASE_FILE"] {
        let phaseFileURL = URL(fileURLWithPath: phaseFilePath)
        if FileManager.default.fileExists(atPath: phaseFileURL.path),
            let phaseFileHandle = try? FileHandle(forWritingTo: phaseFileURL)
        {
            _ = try? phaseFileHandle.seekToEnd()
            try? phaseFileHandle.write(contentsOf: Data(marker.utf8))
            try? phaseFileHandle.close()
        } else {
            try? Data(marker.utf8).write(to: phaseFileURL, options: .atomic)
        }
    }
}
