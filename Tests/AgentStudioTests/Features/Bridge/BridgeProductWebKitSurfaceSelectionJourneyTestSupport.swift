import Foundation
import Testing
import WebKit

@testable import AgentStudio

struct BridgeProductWebKitSurfaceSelectionState: Decodable, Equatable, Sendable {
    let activeMode: String?
    let fileDisplayItemCount: Int?
    let fileDisplaySourceId: String?
    let fileDisplayStatus: String?
    let fileHostRetained: Bool
    let fileProjectedRowCount: Int?
    let fileTotalRowCount: Int?
    let reviewContentState: String?
    let reviewHostRetained: Bool
    let reviewSelectedItemId: String?
    let reviewSelectedPath: String?
}

struct BridgeProductWebKitSurfaceSelectionReceipt: Equatable, Sendable {
    let paneSessionId: String
    let requestId: String
    let selectionRevision: Int
    let surface: BridgeProductSurface
    let workerInstanceId: String

    init(_ request: BridgePaneSurfaceSelectionRequest) {
        paneSessionId = request.paneSessionId
        requestId = request.requestId
        selectionRevision = request.selectionRevision
        surface = request.surface
        workerInstanceId = request.workerInstanceId
    }
}

struct BridgeProductWebKitSurfaceSelectionJourneyProof: Sendable {
    let fileStateAfterFirstSelection: BridgeProductWebKitSurfaceSelectionState
    let finalFileState: BridgeProductWebKitSurfaceSelectionState
    let finalMetadataSequence: Int
    let finalWorkerInstanceId: String?
    let initialMetadataSequence: Int
    let initialReviewState: BridgeProductWebKitSurfaceSelectionState
    let initialWorkerInstanceId: String?
    let receipts: [BridgeProductWebKitSurfaceSelectionReceipt]
    let reviewStateAfterReturn: BridgeProductWebKitSurfaceSelectionState
    let teardownHasZeroResidue: Bool
}

@MainActor
enum BridgeProductWebKitSurfaceJourneyTestSupport {
    static func run() async throws -> BridgeProductWebKitSurfaceSelectionJourneyProof {
        let repoURL = try FilesystemTestGitRepo.create(
            named: "bridge-product-native-surface-selection-webkit"
        )
        defer { FilesystemTestGitRepo.destroy(repoURL) }
        try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repoURL)

        let controller = makeController(repoURL: repoURL)
        let run = try await BridgeProductWebKitCarrierTestSupport.withHostedController(
            controller
        ) { hostedController in
            hostedController.loadApp()
            try await establishHostIdentity(hostedController.page)
            let initialReviewState = try await requireReadyReview(hostedController)
            let initialNative = await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(
                hostedController
            )

            let fileReceipt = try await requestSurface(.file, controller: hostedController)
            let fileStateAfterFirstSelection = try await requireReadyFile(hostedController.page)

            let reviewReceipt = try await requestSurface(.review, controller: hostedController)
            let reviewStateAfterReturn = try await requireReviewState(
                initialReviewState,
                activeMode: "review",
                page: hostedController.page
            )

            let finalFileReceipt = try await requestSurface(.file, controller: hostedController)
            let finalFileState = try await requireRetainedState(
                fileState: fileStateAfterFirstSelection,
                reviewState: initialReviewState,
                page: hostedController.page
            )
            let finalNative = await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(
                hostedController
            )

            return BridgeProductWebKitSurfaceSelectionJourneyProof(
                fileStateAfterFirstSelection: fileStateAfterFirstSelection,
                finalFileState: finalFileState,
                finalMetadataSequence: finalNative.nextMetadataStreamSequence,
                finalWorkerInstanceId: finalNative.workerInstanceId,
                initialMetadataSequence: initialNative.nextMetadataStreamSequence,
                initialReviewState: initialReviewState,
                initialWorkerInstanceId: initialNative.workerInstanceId,
                receipts: [fileReceipt, reviewReceipt, finalFileReceipt],
                reviewStateAfterReturn: reviewStateAfterReturn,
                teardownHasZeroResidue: false
            )
        }

        return BridgeProductWebKitSurfaceSelectionJourneyProof(
            fileStateAfterFirstSelection: run.value.fileStateAfterFirstSelection,
            finalFileState: run.value.finalFileState,
            finalMetadataSequence: run.value.finalMetadataSequence,
            finalWorkerInstanceId: run.value.finalWorkerInstanceId,
            initialMetadataSequence: run.value.initialMetadataSequence,
            initialReviewState: run.value.initialReviewState,
            initialWorkerInstanceId: run.value.initialWorkerInstanceId,
            receipts: run.value.receipts,
            reviewStateAfterReturn: run.value.reviewStateAfterReturn,
            teardownHasZeroResidue: run.teardownSnapshot.hasZeroResidue
        )
    }

    static func assertProof(_ proof: BridgeProductWebKitSurfaceSelectionJourneyProof) {
        #expect(proof.initialWorkerInstanceId?.isEmpty == false)
        #expect(proof.finalWorkerInstanceId == proof.initialWorkerInstanceId)
        #expect(proof.finalMetadataSequence >= proof.initialMetadataSequence + 3)
        #expect(proof.receipts.map(\.surface) == [.file, .review, .file])
        #expect(Set(proof.receipts.map(\.requestId)).count == 3)
        #expect(proof.receipts.allSatisfy { !$0.requestId.isEmpty })
        #expect(Set(proof.receipts.map(\.paneSessionId)).count == 1)
        #expect(proof.receipts.allSatisfy { !$0.paneSessionId.isEmpty })
        let selectionRevisions = proof.receipts.map(\.selectionRevision)
        #expect(
            zip(selectionRevisions, selectionRevisions.dropFirst()).allSatisfy {
                $0.0 < $0.1
            }
        )
        #expect(
            proof.receipts.allSatisfy {
                $0.workerInstanceId == proof.initialWorkerInstanceId
            }
        )
        #expect(proof.initialReviewState.activeMode == "review")
        #expect(proof.initialReviewState.reviewContentState == "ready")
        #expect(proof.initialReviewState.reviewSelectedItemId?.isEmpty == false)
        #expect(proof.initialReviewState.reviewSelectedPath?.isEmpty == false)
        #expect(proof.fileStateAfterFirstSelection.activeMode == "file")
        #expect(proof.fileStateAfterFirstSelection.fileDisplayStatus == "ready")
        #expect(proof.fileStateAfterFirstSelection.fileDisplaySourceId?.isEmpty == false)
        #expect((proof.fileStateAfterFirstSelection.fileDisplayItemCount ?? 0) > 0)
        #expect((proof.fileStateAfterFirstSelection.fileProjectedRowCount ?? 0) > 0)
        #expect(proof.reviewStateAfterReturn.activeMode == "review")
        #expect(
            proof.reviewStateAfterReturn.reviewContentState
                == proof.initialReviewState.reviewContentState
        )
        #expect(
            proof.reviewStateAfterReturn.reviewSelectedItemId
                == proof.initialReviewState.reviewSelectedItemId
        )
        #expect(
            proof.reviewStateAfterReturn.reviewSelectedPath
                == proof.initialReviewState.reviewSelectedPath
        )
        #expect(proof.finalFileState.activeMode == "file")
        #expect(proof.finalFileState.fileHostRetained)
        #expect(proof.finalFileState.reviewHostRetained)
        #expect(
            proof.finalFileState.fileDisplaySourceId
                == proof.fileStateAfterFirstSelection.fileDisplaySourceId
        )
        #expect(
            proof.finalFileState.fileProjectedRowCount
                == proof.fileStateAfterFirstSelection.fileProjectedRowCount
        )
        #expect(
            proof.finalFileState.fileProjectedRowCount
                == proof.finalFileState.fileTotalRowCount
        )
        #expect(
            proof.finalFileState.reviewSelectedItemId
                == proof.initialReviewState.reviewSelectedItemId
        )
        #expect(
            proof.finalFileState.reviewSelectedPath
                == proof.initialReviewState.reviewSelectedPath
        )
        #expect(proof.teardownHasZeroResidue)
    }

    private static func requestSurface(
        _ surface: BridgeProductSurface,
        controller: BridgePaneController
    ) async throws -> BridgeProductWebKitSurfaceSelectionReceipt {
        let previousRevision =
            controller.surfaceSelectionAuthority.diagnosticSnapshot.lastAcceptedRequest?
            .selectionRevision ?? 0
        guard controller.requestViewerSurface(surface) else {
            throw JourneyError.conditionFailed("native \(surface) request was not admitted")
        }

        var acceptedRequest: BridgePaneSurfaceSelectionRequest?
        let accepted = await BridgeProductWebKitCarrierTestSupport.waitUntil(
            timeout: .seconds(15)
        ) {
            let snapshot = controller.surfaceSelectionAuthority.diagnosticSnapshot
            guard let lastAcceptedRequest = snapshot.lastAcceptedRequest else { return false }
            acceptedRequest = lastAcceptedRequest
            return snapshot.currentRequest == nil
                && lastAcceptedRequest.surface == surface
                && lastAcceptedRequest.selectionRevision > previousRevision
        }
        guard accepted, let acceptedRequest else {
            let snapshot = controller.surfaceSelectionAuthority.diagnosticSnapshot
            throw JourneyError.conditionFailed(
                "native \(surface) request did not receive its exact worker receipt; snapshot=\(snapshot)"
            )
        }
        try await requireActiveMode(surface, page: controller.page)
        return BridgeProductWebKitSurfaceSelectionReceipt(acceptedRequest)
    }

    private static func establishHostIdentity(_ page: WebPage) async throws {
        let established = await BridgeProductWebKitCarrierTestSupport.waitUntil(
            timeout: .seconds(15)
        ) {
            do {
                return try await page.callJavaScript(
                    """
                    const fileHost = document.querySelector('[data-testid="bridge-viewer-mode-host-file"]');
                    const reviewHost = document.querySelector('[data-testid="bridge-viewer-mode-host-review"]');
                    if (!(fileHost instanceof HTMLElement) || !(reviewHost instanceof HTMLElement)) {
                      return false;
                    }
                    globalThis.__bridgeHostedSurfaceSelectionHosts = { fileHost, reviewHost };
                    return true;
                    """
                ) as? Bool ?? false
            } catch {
                return false
            }
        }
        guard established else {
            throw JourneyError.conditionFailed("retained File and Review hosts were not mounted")
        }
    }

    private static func requireActiveMode(
        _ surface: BridgeProductSurface,
        page: WebPage
    ) async throws {
        let expectedMode = surface == .file ? "file" : "review"
        let activated = await BridgeProductWebKitCarrierTestSupport.waitUntil(
            timeout: .seconds(10)
        ) {
            (try? await state(page))?.activeMode == expectedMode
        }
        guard activated else {
            throw JourneyError.conditionFailed("retained \(expectedMode) host did not activate")
        }
    }

    private static func requireReadyReview(
        _ controller: BridgePaneController
    ) async throws -> BridgeProductWebKitSurfaceSelectionState {
        var observed: BridgeProductWebKitSurfaceSelectionState?
        let ready = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(25)) {
            let native = await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(controller)
            guard native.lifecycle == "active", let snapshot = try? await state(controller.page)
            else { return false }
            observed = snapshot
            return snapshot.activeMode == "review"
                && snapshot.reviewContentState == "ready"
                && snapshot.reviewSelectedItemId?.isEmpty == false
                && snapshot.reviewSelectedPath?.isEmpty == false
                && snapshot.fileHostRetained
                && snapshot.reviewHostRetained
        }
        guard ready, let observed else {
            throw JourneyError.conditionFailed("real-git Review did not become ready")
        }
        return observed
    }

    private static func requireReadyFile(
        _ page: WebPage
    ) async throws -> BridgeProductWebKitSurfaceSelectionState {
        var observed: BridgeProductWebKitSurfaceSelectionState?
        let ready = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(15)) {
            guard let snapshot = try? await state(page) else { return false }
            observed = snapshot
            guard let projectedRowCount = snapshot.fileProjectedRowCount,
                let totalRowCount = snapshot.fileTotalRowCount
            else { return false }
            return snapshot.activeMode == "file"
                && snapshot.fileDisplayStatus == "ready"
                && snapshot.fileDisplaySourceId?.isEmpty == false
                && snapshot.fileDisplayItemCount ?? 0 > 0
                && projectedRowCount > 0
                && projectedRowCount == totalRowCount
                && snapshot.fileHostRetained
                && snapshot.reviewHostRetained
        }
        guard ready, let observed else {
            throw JourneyError.conditionFailed("File display snapshot did not become complete")
        }
        return observed
    }

    private static func requireReviewState(
        _ expected: BridgeProductWebKitSurfaceSelectionState,
        activeMode: String,
        page: WebPage
    ) async throws -> BridgeProductWebKitSurfaceSelectionState {
        var observed: BridgeProductWebKitSurfaceSelectionState?
        let retained = await BridgeProductWebKitCarrierTestSupport.waitUntil(
            timeout: .seconds(10)
        ) {
            guard let snapshot = try? await state(page) else { return false }
            observed = snapshot
            return snapshot.activeMode == activeMode
                && snapshot.fileHostRetained
                && snapshot.reviewHostRetained
                && snapshot.reviewContentState == expected.reviewContentState
                && snapshot.reviewSelectedItemId == expected.reviewSelectedItemId
                && snapshot.reviewSelectedPath == expected.reviewSelectedPath
        }
        guard retained, let observed else {
            throw JourneyError.conditionFailed("Review state changed during native surface switches")
        }
        return observed
    }

    private static func requireRetainedState(
        fileState: BridgeProductWebKitSurfaceSelectionState,
        reviewState: BridgeProductWebKitSurfaceSelectionState,
        page: WebPage
    ) async throws -> BridgeProductWebKitSurfaceSelectionState {
        var observed: BridgeProductWebKitSurfaceSelectionState?
        let retained = await BridgeProductWebKitCarrierTestSupport.waitUntil(
            timeout: .seconds(10)
        ) {
            guard let snapshot = try? await state(page) else { return false }
            observed = snapshot
            return snapshot.activeMode == "file"
                && snapshot.fileHostRetained
                && snapshot.reviewHostRetained
                && snapshot.fileDisplayStatus == fileState.fileDisplayStatus
                && snapshot.fileDisplaySourceId == fileState.fileDisplaySourceId
                && snapshot.fileDisplayItemCount == fileState.fileDisplayItemCount
                && snapshot.fileProjectedRowCount == fileState.fileProjectedRowCount
                && snapshot.fileTotalRowCount == fileState.fileTotalRowCount
                && snapshot.reviewContentState == reviewState.reviewContentState
                && snapshot.reviewSelectedItemId == reviewState.reviewSelectedItemId
                && snapshot.reviewSelectedPath == reviewState.reviewSelectedPath
        }
        guard retained, let observed else {
            throw JourneyError.conditionFailed("retained File or Review state changed")
        }
        return observed
    }

    private static func state(
        _ page: WebPage
    ) async throws -> BridgeProductWebKitSurfaceSelectionState? {
        let encoded = try await page.callJavaScript(
            """
            const fileHost = document.querySelector('[data-testid="bridge-viewer-mode-host-file"]');
            const reviewHost = document.querySelector('[data-testid="bridge-viewer-mode-host-review"]');
            const retained = globalThis.__bridgeHostedSurfaceSelectionHosts;
            const fileShell = fileHost?.querySelector('[data-testid="bridge-file-viewer-shell"]');
            const reviewShell = reviewHost?.querySelector('[data-testid="review-viewer-shell"]');
            const reviewPanel = reviewHost?.querySelector('[data-testid="bridge-code-view-panel"]');
            const activeHost = document.querySelector('[data-bridge-viewer-mode-active="true"]');
            const filterCountText = fileHost?.querySelector(
              '[data-testid="worktree-file-filter-count"]'
            )?.textContent ?? '';
            const filterCounts = filterCountText.split('/').map((value) => Number(value));
            const projectedRowCount = Number(fileShell?.getAttribute('data-file-display-tree-row-count'));
            return JSON.stringify({
              activeMode: activeHost?.getAttribute('data-bridge-viewer-mode-host') ?? null,
              fileDisplayItemCount: Number.isSafeInteger(
                Number(fileShell?.getAttribute('data-file-display-item-count'))
              ) ? Number(fileShell?.getAttribute('data-file-display-item-count')) : null,
              fileDisplaySourceId: fileShell?.getAttribute('data-file-display-source-id') ?? null,
              fileDisplayStatus: fileShell?.getAttribute('data-file-display-status') ?? null,
              fileHostRetained: retained?.fileHost === fileHost,
              fileProjectedRowCount: Number.isSafeInteger(projectedRowCount)
                ? projectedRowCount
                : null,
              fileTotalRowCount: filterCounts.length === 2 && Number.isSafeInteger(filterCounts[1])
                ? filterCounts[1]
                : null,
              reviewContentState: reviewShell?.getAttribute('data-selected-content-state') ?? null,
              reviewHostRetained: retained?.reviewHost === reviewHost,
              reviewSelectedItemId: reviewPanel?.getAttribute('data-selected-item-id') ?? null,
              reviewSelectedPath: reviewShell?.getAttribute('data-selected-display-path') ?? null
            });
            """
        )
        guard let encoded = encoded as? String,
            let data = encoded.data(using: .utf8)
        else { return nil }
        return try JSONDecoder().decode(BridgeProductWebKitSurfaceSelectionState.self, from: data)
    }

    private static func makeController(repoURL: URL) -> BridgePaneController {
        let paneId = UUIDv7.generate()
        return BridgePaneController(
            paneId: paneId,
            state: BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(
                    rootPath: repoURL.path,
                    baseline: .localDefaultBranch(branchName: "main")
                )
            ),
            metadata: PaneMetadata(
                paneId: PaneId(uuid: paneId),
                contentType: .diff,
                launchDirectory: repoURL,
                title: "Bridge Native Surface Selection",
                facets: PaneContextFacets(
                    repoId: UUIDv7.generate(),
                    worktreeId: UUIDv7.generate(),
                    worktreeName: "bridge-native-surface-selection",
                    cwd: repoURL
                )
            ),
            reviewSourceProvider: BridgeReviewSourceProviderFactory.gitProvider(
                repositoryPath: repoURL
            ),
            telemetryRuntimePolicy: .live,
            telemetryScopeGate: BridgeTelemetryScopeGate(enabledScopes: []),
            initialPaneActivity: .foreground
        )
    }

    private enum JourneyError: Error {
        case conditionFailed(String)
    }
}
