import AgentStudioProgrammaticControl
import Foundation
import Testing
import WebKit

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioTestSupport

private struct BridgeProductHiddenFileViewerState: Decodable, CustomStringConvertible {
    let documentVisibilityState: String
    let fileDisplayItemCount: Int
    let fileDisplayTreeRowCount: Int
    let fileViewerActive: Bool
    let frameLivenessRafAlive: String
    let frameLivenessRafFiredCount: Int
    let frameLivenessRafScheduledCount: Int
    let openFilePath: String?
    let openFileState: String?
    let selectedDisplayPath: String?

    var description: String {
        "visibility=\(documentVisibilityState),fileActive=\(fileViewerActive),items=\(fileDisplayItemCount),rows=\(fileDisplayTreeRowCount),selected=\(selectedDisplayPath ?? "none"),open=\(openFilePath ?? "none")/\(openFileState ?? "idle"),raf=\(frameLivenessRafFiredCount)/\(frameLivenessRafScheduledCount)/\(frameLivenessRafAlive)"
    }
}

private struct BridgeProductHiddenFileIPCProof {
    let controlResult: IPCBridgePageControlResult
    let displayPath: String
    let stateBeforeControl: BridgeProductHiddenFileViewerState
    let stateAfterQuery: BridgeProductHiddenFileViewerState
    let stateAfterOpen: BridgeProductHiddenFileViewerState
}

private struct BridgeProductHiddenFileIPCContext {
    let displayPath: String
    let stateBeforeControl: BridgeProductHiddenFileViewerState
}

@MainActor
extension WebKitSerializedTests.BridgeProductRealGitFileAndReviewWebKitTests {
    @Test("hidden Files query and native IPC reveal complete without an animation frame")
    func hiddenFilesIPCRevealCompletesSelectionAndOpenStateWithoutAnimationFrame() async throws {
        let repoURL = try await FilesystemTestGitRepo.create(
            named: "bridge-product-hidden-file-ipc-webkit"
        )
        defer { FilesystemTestGitRepo.destroy(repoURL) }
        try await FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repoURL)

        let traceRecorder = BridgeProductWebKitCarrierTraceRecorder()
        let controller = makeController(repoURL: repoURL, traceRecorder: traceRecorder)
        let run = try await runHiddenFileIPCProof(controller)
        expectHiddenFileIPCProof(run)
    }
}

@MainActor
private func runHiddenFileIPCProof(
    _ controller: BridgePaneController
) async throws -> BridgeProductWebKitCarrierRunResult<BridgeProductHiddenFileIPCProof> {
    guard let worktreeId = controller.filesBinding?.members.first?.id else {
        throw hiddenPageProofError("The receiver did not retain its Files member")
    }
    let relativePath = "untracked.txt"

    return try await BridgeProductWebKitCarrierTestSupport.withHostedController(
        controller,
        requireVisibleHost: true
    ) { hostedController, hostWindow in
        try await executeHiddenFileIPCJourney(
            hostedController,
            hostWindow: hostWindow,
            worktreeId: worktreeId,
            relativePath: relativePath
        )
    }
}

@MainActor
private func executeHiddenFileIPCJourney(
    _ controller: BridgePaneController,
    hostWindow: NSWindow,
    worktreeId: UUID,
    relativePath: String
) async throws -> BridgeProductHiddenFileIPCProof {
    let acceptedState = try await bootstrapVisibleFilesPage(controller)
    let context = try await hideFilesPageWithAcceptedMetadata(
        controller,
        hostWindow: hostWindow,
        worktreeId: worktreeId,
        relativePath: relativePath,
        acceptedState: acceptedState
    )
    let stateAfterQuery = try await searchHiddenFilesWithoutFrames(
        controller,
        context: context,
        searchText: relativePath
    )
    return try await revealFileAndAwaitOpenState(
        controller,
        context: context,
        stateAfterQuery: stateAfterQuery,
        relativePath: relativePath
    )
}

@MainActor
private func bootstrapVisibleFilesPage(
    _ controller: BridgePaneController
) async throws -> BridgeProductHiddenFileViewerState {
    recordHiddenFileProofStage("launch")
    controller.loadApp()
    await WebPageEventWaits.waitForNavigationToFinish(controller.page)
    recordHiddenFileProofStage("navigation-finished")

    let visibleDocumentState = try await WebPageEventWaits.waitForDocumentVisibility(
        controller.page,
        equals: "visible"
    )
    guard visibleDocumentState == "visible" else {
        throw hiddenPageProofError(
            "The Files page was not visible during bootstrap; observed \(visibleDocumentState)"
        )
    }
    recordHiddenFileProofStage("document-visible-before-bootstrap")

    try await WebPageEventWaits.waitForDocumentSelector(
        controller.page,
        "[data-testid=\"bridge-app-root\"]"
    )
    recordHiddenFileProofStage("app-root")
    try await WebPageEventWaits.waitForDocumentSelector(
        controller.page,
        "[data-testid=\"bridge-viewer-context-file\"]"
    )
    guard await BridgeProductWebKitCarrierTestSupport.activateFileMode(controller.page) else {
        throw hiddenPageProofError("The hidden Files surface did not activate")
    }
    recordHiddenFileProofStage("files-activated")

    recordHiddenFileProofStage("awaiting-logical-files-index")
    let acceptedState = try await waitForAcceptedHiddenFilesState(controller.page)
    recordHiddenFileProofStage("logical-files-index-ready")
    return acceptedState
}

@MainActor
private func hideFilesPageWithAcceptedMetadata(
    _ controller: BridgePaneController,
    hostWindow: NSWindow,
    worktreeId: UUID,
    relativePath: String,
    acceptedState: BridgeProductHiddenFileViewerState
) async throws -> BridgeProductHiddenFileIPCContext {
    let native = await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(controller)
    recordHiddenFileProofStage("native-file-metadata-snapshot")
    guard native.lifecycle == "active", native.fileWorkerDerivationEpoch > 0 else {
        throw hiddenPageProofError(
            "Native File metadata was not accepted before reveal; native=\(native)"
        )
    }
    guard
        let displayPath = await controller.fileCollectionDisplayPath(
            worktreeId: worktreeId,
            relativePath: relativePath
        )
    else {
        throw hiddenPageProofError("The native Files collection did not project \(relativePath)")
    }
    recordHiddenFileProofStage("native-file-path-projected")

    hostWindow.orderOut(nil)
    let hiddenVisibility = try await WebPageEventWaits.waitForDocumentVisibility(
        controller.page,
        equals: "hidden"
    )
    guard hiddenVisibility == "hidden" else {
        throw hiddenPageProofError(
            "The WebKit document did not become hidden before IPC; observed \(hiddenVisibility)"
        )
    }
    recordHiddenFileProofStage("document-hidden-before-control")

    guard let baselineDOM = await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page)
    else {
        throw hiddenPageProofError("The hidden-page DOM snapshot was unavailable")
    }
    guard baselineDOM.documentVisibilityState == "hidden",
        baselineDOM.frameLivenessRafAlive != "missing",
        baselineDOM.frameLivenessRafScheduledCount > 0
    else {
        throw hiddenPageProofError(
            "The hidden-page animation-frame probe was unavailable; dom=\(baselineDOM), files=\(acceptedState)"
        )
    }
    recordHiddenFileProofStage("zero-frame-baseline")

    return BridgeProductHiddenFileIPCContext(
        displayPath: displayPath,
        stateBeforeControl: BridgeProductHiddenFileViewerState(
            documentVisibilityState: hiddenVisibility,
            fileDisplayItemCount: acceptedState.fileDisplayItemCount,
            fileDisplayTreeRowCount: acceptedState.fileDisplayTreeRowCount,
            fileViewerActive: acceptedState.fileViewerActive,
            frameLivenessRafAlive: baselineDOM.frameLivenessRafAlive,
            frameLivenessRafFiredCount: baselineDOM.frameLivenessRafFiredCount,
            frameLivenessRafScheduledCount: baselineDOM.frameLivenessRafScheduledCount,
            openFilePath: acceptedState.openFilePath,
            openFileState: acceptedState.openFileState,
            selectedDisplayPath: acceptedState.selectedDisplayPath
        )
    )
}

@MainActor
private func searchHiddenFilesWithoutFrames(
    _ controller: BridgePaneController,
    context: BridgeProductHiddenFileIPCContext,
    searchText: String
) async throws -> BridgeProductHiddenFileViewerState {
    recordHiddenFileProofStage("issuing-hidden-query")
    let result = try await controller.applyPageControlForIPC(
        .fileTreeSearch(searchText: searchText),
        correlationId: nil
    )
    guard result.status == "accepted",
        result.method == IPCBridgePageControlCommand.fileTreeSearch(searchText: searchText).method
    else {
        throw hiddenPageProofError("The hidden Files search was not accepted; result=\(result)")
    }
    recordHiddenFileProofStage("hidden-query-control-replied")

    let state = try await waitForHiddenFileQueryState(
        controller.page,
        expectedRafFiredCount: context.stateBeforeControl.frameLivenessRafFiredCount
    )
    guard state.fileDisplayTreeRowCount < context.stateBeforeControl.fileDisplayTreeRowCount else {
        throw hiddenPageProofError(
            "The hidden query did not replace the logical Files rows; before=\(context.stateBeforeControl), after=\(state)"
        )
    }
    recordHiddenFileProofStage("hidden-query-logical-state-ready")
    return state
}

@MainActor
private func revealFileAndAwaitOpenState(
    _ controller: BridgePaneController,
    context: BridgeProductHiddenFileIPCContext,
    stateAfterQuery: BridgeProductHiddenFileViewerState,
    relativePath: String
) async throws -> BridgeProductHiddenFileIPCProof {
    recordHiddenFileProofStage("issuing-ipc-reveal")
    let controlResult = try await controller.applyPageControlForIPC(
        .fileTreeRevealPath(path: relativePath),
        correlationId: nil
    )
    recordHiddenFileProofStage("control-reply")
    guard controlResult.status == "accepted",
        controlResult.method
            == IPCBridgePageControlCommand.fileTreeRevealPath(path: relativePath).method,
        controlResult.path == context.displayPath,
        controlResult.itemId?.isEmpty == false
    else {
        throw hiddenPageProofError(
            "Native IPC reveal was not accepted for \(context.displayPath); result=\(controlResult)"
        )
    }

    recordHiddenFileProofStage("awaiting-document-open-ready")
    let openedState = try await waitForHiddenFileOpenState(
        controller.page,
        expectedPath: context.displayPath
    )
    recordHiddenFileProofStage("document-open-ready")
    return BridgeProductHiddenFileIPCProof(
        controlResult: controlResult,
        displayPath: context.displayPath,
        stateBeforeControl: context.stateBeforeControl,
        stateAfterQuery: stateAfterQuery,
        stateAfterOpen: openedState
    )
}

private func expectHiddenFileIPCProof(
    _ run: BridgeProductWebKitCarrierRunResult<BridgeProductHiddenFileIPCProof>
) {
    #expect(!run.hostSnapshot.windowIsVisible)
    #expect(run.value.controlResult.status == "accepted")
    #expect(run.value.controlResult.path == run.value.displayPath)
    #expect(run.value.stateBeforeControl.documentVisibilityState == "hidden")
    #expect(run.value.stateAfterQuery.documentVisibilityState == "hidden")
    #expect(run.value.stateAfterOpen.documentVisibilityState == "hidden")
    #expect(run.value.stateAfterQuery.fileDisplayTreeRowCount == 1)
    #expect(run.value.stateAfterOpen.selectedDisplayPath == run.value.displayPath)
    #expect(run.value.stateAfterOpen.openFilePath == run.value.displayPath)
    #expect(run.value.stateAfterOpen.openFileState == "ready")
    #expect(run.value.stateBeforeControl.frameLivenessRafFiredCount == 0)
    #expect(
        run.value.stateAfterQuery.frameLivenessRafFiredCount
            == run.value.stateBeforeControl.frameLivenessRafFiredCount
    )
    #expect(
        run.value.stateAfterOpen.frameLivenessRafFiredCount
            == run.value.stateBeforeControl.frameLivenessRafFiredCount
    )
    #expect(run.teardownSnapshot.hasZeroResidue)
}

@MainActor
private func waitForHiddenFileQueryState(
    _ page: WebPage,
    expectedRafFiredCount: Int
) async throws -> BridgeProductHiddenFileViewerState {
    let encodedState = try await WebPageEventWaits.waitForDocumentValue(
        page,
        reader: """
            const fileShell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
            if (fileShell === null || document.visibilityState !== 'hidden') return null;
            const fileDisplayTreeRowCount = Number(fileShell.getAttribute('data-file-display-tree-row-count') ?? '0');
            if (fileDisplayTreeRowCount !== 1) return null;
            const probe = window.__bridgeFrameLivenessProbe;
            const frameLivenessRafFiredCount = probe?.rafFiredCount ?? 0;
            if (frameLivenessRafFiredCount !== expectedRafFiredCount) return null;
            return JSON.stringify({
              documentVisibilityState: document.visibilityState,
              fileDisplayItemCount: Number(fileShell.getAttribute('data-file-display-item-count') ?? '0'),
              fileDisplayTreeRowCount,
              fileViewerActive: fileShell.getAttribute('data-file-viewer-active') === 'true',
              frameLivenessRafAlive: probe?.rafAlive ?? 'missing',
              frameLivenessRafFiredCount,
              frameLivenessRafScheduledCount: probe?.rafScheduledCount ?? 0,
              openFilePath: fileShell.getAttribute('data-worktree-open-file-path'),
              openFileState: fileShell.getAttribute('data-worktree-open-file-state'),
              selectedDisplayPath: fileShell.getAttribute('data-selected-display-path')
            });
            """,
        arguments: ["expectedRafFiredCount": expectedRafFiredCount]
    )
    return try decodeHiddenFileViewerState(encodedState)
}

private func recordHiddenFileProofStage(_ stage: String) {
    FileHandle.standardError.write(Data("[hidden-file-ipc] \(stage)\n".utf8))
}

@MainActor
private func waitForAcceptedHiddenFilesState(
    _ page: WebPage
) async throws -> BridgeProductHiddenFileViewerState {
    let encodedState = try await WebPageEventWaits.waitForDocumentValue(
        page,
        reader: """
            const fileShell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
            if (fileShell === null) return null;
            const fileViewerActive = fileShell.getAttribute('data-file-viewer-active') === 'true';
            const fileDisplaySourceId = fileShell.getAttribute('data-file-display-source-id');
            const fileDisplayItemCount = Number(fileShell.getAttribute('data-file-display-item-count') ?? '0');
            const fileDisplayTreeRowCount = Number(fileShell.getAttribute('data-file-display-tree-row-count') ?? '0');
            if (!fileViewerActive || fileDisplaySourceId === null || fileDisplayItemCount < 2 || fileDisplayTreeRowCount < 2) {
              return null;
            }
            const probe = window.__bridgeFrameLivenessProbe;
            return JSON.stringify({
              documentVisibilityState: document.visibilityState,
              fileDisplayItemCount,
              fileDisplayTreeRowCount,
              fileViewerActive,
              frameLivenessRafAlive: probe?.rafAlive ?? 'missing',
              frameLivenessRafFiredCount: probe?.rafFiredCount ?? 0,
              frameLivenessRafScheduledCount: probe?.rafScheduledCount ?? 0,
              openFilePath: fileShell.getAttribute('data-worktree-open-file-path'),
              openFileState: fileShell.getAttribute('data-worktree-open-file-state'),
              selectedDisplayPath: fileShell.getAttribute('data-selected-display-path')
            });
            """,
        arguments: [:]
    )
    return try decodeHiddenFileViewerState(encodedState)
}

@MainActor
private func waitForHiddenFileOpenState(
    _ page: WebPage,
    expectedPath: String
) async throws -> BridgeProductHiddenFileViewerState {
    let encodedState = try await WebPageEventWaits.waitForDocumentValue(
        page,
        reader: """
            const fileShell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
            if (fileShell === null) return null;
            const openFilePath = fileShell.getAttribute('data-worktree-open-file-path');
            const openFileState = fileShell.getAttribute('data-worktree-open-file-state');
            const selectedDisplayPath = fileShell.getAttribute('data-selected-display-path');
            if (
              document.visibilityState !== 'hidden' ||
              selectedDisplayPath !== expectedPath ||
              openFilePath !== expectedPath ||
              openFileState !== 'ready'
            ) {
              return null;
            }
            const probe = window.__bridgeFrameLivenessProbe;
            return JSON.stringify({
              documentVisibilityState: document.visibilityState,
              fileDisplayItemCount: Number(fileShell.getAttribute('data-file-display-item-count') ?? '0'),
              fileDisplayTreeRowCount: Number(fileShell.getAttribute('data-file-display-tree-row-count') ?? '0'),
              fileViewerActive: fileShell.getAttribute('data-file-viewer-active') === 'true',
              frameLivenessRafAlive: probe?.rafAlive ?? 'missing',
              frameLivenessRafFiredCount: probe?.rafFiredCount ?? 0,
              frameLivenessRafScheduledCount: probe?.rafScheduledCount ?? 0,
              openFilePath,
              openFileState,
              selectedDisplayPath
            });
            """,
        arguments: ["expectedPath": expectedPath]
    )
    return try decodeHiddenFileViewerState(encodedState)
}

private func decodeHiddenFileViewerState(
    _ encodedState: Any?
) throws -> BridgeProductHiddenFileViewerState {
    guard let encodedState = encodedState as? String,
        let data = encodedState.data(using: .utf8)
    else {
        throw hiddenPageProofError("Hidden Files state was not returned as JSON")
    }
    return try JSONDecoder().decode(BridgeProductHiddenFileViewerState.self, from: data)
}

private func hiddenPageProofError(_ message: String) -> NSError {
    NSError(
        domain: "BridgeProductRealGitHiddenFileIPCWebKitProof",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: message]
    )
}
