import AppKit
import CryptoKit
import Foundation
import WebKit

#if DEBUG
    private struct BridgeProductPaintCorrelationSnapshot: Decodable {
        let activeViewerModeIsReview: Bool
        let decodedSourceCorrelationCount: Int
        let documentVisibilityState: String
        let fileModeActivated: Bool
        let fileModeLatestDispatchDisposition: String
        let fileModeSendAttemptCount: Int
        let fileModeSendSynchronousFailureCount: Int
        let fileIdentityChainMatched: Bool
        let filePaintedSourceMatched: Bool
        let filePaintedSourceMatchCount: Int
        let fileSelectionLatestDispatchDisposition: String
        let fileSelectionLatestLifecycleState: String
        let fileSelectedPathMatched: Bool
        let frameLivenessRafAlive: String
        let pageReadyState: String
        let paintedElementCount: Int
        let reviewCanaryCandidateCount: Int
        let reviewDigestCandidateCount: Int
        let reviewIdentityCandidateCount: Int
        let reviewIdentityChainMatched: Bool
        let reviewMetadataItemCount: Int
        let reviewPaintedDispositionCandidateCount: Int
        let reviewPaintedSourceMatched: Bool
        let reviewPaintedSourceMatchCount: Int
        let reviewSelectionDroppedCount: Int
        let reviewSelectionFirstFrameReachedCount: Int
        let reviewSelectionInitialRequestedCount: Int
        let reviewSelectionInitialSchedulingAcceptedCount: Int
        let reviewSelectionLatestDispatchDisposition: String
        let reviewSelectionLatestLifecycleState: String
        let reviewSelectionNativeBootstrapInstallAcceptedCount: Int
        let reviewSelectionNativeBootstrapInstallAttemptCount: Int
        let reviewSelectionNativeBootstrapInstallCount: Int
        let reviewSelectionNativeBootstrapInstallRejectedCount: Int
        let reviewSelectionQueuedCommandCount: Int
        let reviewSelectionReplacementRequestCount: Int
        let reviewSelectionSecondFrameReachedCount: Int
        let reviewSelectionScheduledCount: Int
        let reviewSelectionSessionState: String
        let reviewSelectionSubmittedCount: Int
        let reviewSelectedItemCandidateCount: Int
        let reviewSelectedItemPresent: Bool
        let reviewSelectedPathMatched: Bool
        let reviewSelectedPathPresent: Bool
        let reviewShellPresent: Bool
        let reviewSurfaceRoleCandidateCount: Int
        let reviewWholePositionCandidateCount: Int
    }

    private struct BridgeProductPaintCorrelationProof {
        let reloadReplaySucceeded: Bool
        let snapshot: BridgeProductPaintCorrelationSnapshot?
        let workerReplacementObserved: Bool

        init(
            snapshot: BridgeProductPaintCorrelationSnapshot?,
            reloadReplaySucceeded: Bool = false,
            workerReplacementObserved: Bool = false
        ) {
            self.reloadReplaySucceeded = reloadReplaySucceeded
            self.snapshot = snapshot
            self.workerReplacementObserved = workerReplacementObserved
        }

        var reviewCorrelationSucceeded: Bool {
            guard let snapshot else { return false }
            return snapshot.documentVisibilityState == "visible"
                && snapshot.frameLivenessRafAlive == "true"
                && snapshot.reviewSelectedPathMatched
                && snapshot.reviewIdentityChainMatched
                && snapshot.reviewPaintedSourceMatched
                && snapshot.reviewPaintedSourceMatchCount == 1
        }

        var surfaceCorrelationSucceeded: Bool {
            guard let snapshot else { return false }
            return reviewCorrelationSucceeded
                && snapshot.fileModeActivated
                && snapshot.fileSelectedPathMatched
                && snapshot.fileIdentityChainMatched
                && snapshot.filePaintedSourceMatched
                && snapshot.filePaintedSourceMatchCount == 1
        }

        var succeeded: Bool {
            surfaceCorrelationSucceeded
                && reloadReplaySucceeded
                && workerReplacementObserved
        }

        var attributes: [String: AgentStudioTraceValue] {
            let snapshot = snapshot
            return [
                "agentstudio.startup_diagnostic.bridge.product_paint.active_mode_review": .bool(
                    snapshot?.activeViewerModeIsReview == true),
                "agentstudio.startup_diagnostic.bridge.product_paint.decoded_correlation.count": .int(
                    snapshot?.decodedSourceCorrelationCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.document_visible": .bool(
                    snapshot?.documentVisibilityState == "visible"),
                "agentstudio.startup_diagnostic.bridge.product_paint.file_mode_activated": .bool(
                    snapshot?.fileModeActivated == true),
                "agentstudio.startup_diagnostic.bridge.product_paint.file_mode.latest_dispatch_disposition": .string(
                    snapshot?.fileModeLatestDispatchDisposition ?? "not_sent"),
                "agentstudio.startup_diagnostic.bridge.product_paint.file_mode.send_attempt.count": .int(
                    snapshot?.fileModeSendAttemptCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.file_mode.send_synchronous_failure.count": .int(
                    snapshot?.fileModeSendSynchronousFailureCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.file_identity_chain_matched": .bool(
                    snapshot?.fileIdentityChainMatched == true),
                "agentstudio.startup_diagnostic.bridge.product_paint.file_source_matched": .bool(
                    snapshot?.filePaintedSourceMatched == true),
                "agentstudio.startup_diagnostic.bridge.product_paint.file_source_match.count": .int(
                    snapshot?.filePaintedSourceMatchCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.file_selection.latest_dispatch_disposition":
                    .string(
                        snapshot?.fileSelectionLatestDispatchDisposition ?? "not_sent"),
                "agentstudio.startup_diagnostic.bridge.product_paint.file_selection.latest_lifecycle_state": .string(
                    snapshot?.fileSelectionLatestLifecycleState ?? "not_sent"),
                "agentstudio.startup_diagnostic.bridge.product_paint.file_selected_identity_matched": .bool(
                    snapshot?.fileSelectedPathMatched == true),
                "agentstudio.startup_diagnostic.bridge.product_paint.frame_live": .bool(
                    snapshot?.frameLivenessRafAlive == "true"),
                "agentstudio.startup_diagnostic.bridge.product_paint.painted_element.count": .int(
                    snapshot?.paintedElementCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.page_ready.state": .string(
                    snapshot?.pageReadyState ?? "awaiting"),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_candidate.canary.count": .int(
                    snapshot?.reviewCanaryCandidateCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_candidate.digest.count": .int(
                    snapshot?.reviewDigestCandidateCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_candidate.identity.count": .int(
                    snapshot?.reviewIdentityCandidateCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_candidate.painted_disposition.count": .int(
                    snapshot?.reviewPaintedDispositionCandidateCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_candidate.selected_item.count": .int(
                    snapshot?.reviewSelectedItemCandidateCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_candidate.surface_role.count": .int(
                    snapshot?.reviewSurfaceRoleCandidateCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_candidate.whole_position.count": .int(
                    snapshot?.reviewWholePositionCandidateCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_metadata_item.count": .int(
                    snapshot?.reviewMetadataItemCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_selection.initial_requested.count": .int(
                    snapshot?.reviewSelectionInitialRequestedCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_selection.initial_scheduling_accepted.count":
                    .int(
                        snapshot?.reviewSelectionInitialSchedulingAcceptedCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_selection.latest_dispatch_disposition":
                    .string(snapshot?.reviewSelectionLatestDispatchDisposition ?? "not_sent"),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_selection.latest_lifecycle_state":
                    .string(snapshot?.reviewSelectionLatestLifecycleState ?? "not_sent"),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_selection.scheduled.count": .int(
                    snapshot?.reviewSelectionScheduledCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_selection.first_frame_reached.count": .int(
                    snapshot?.reviewSelectionFirstFrameReachedCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_selection.second_frame_reached.count": .int(
                    snapshot?.reviewSelectionSecondFrameReachedCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_selection.submitted.count": .int(
                    snapshot?.reviewSelectionSubmittedCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_selection.dropped.count": .int(
                    snapshot?.reviewSelectionDroppedCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.comm_session.state": .string(
                    snapshot?.reviewSelectionSessionState ?? "awaiting_bootstrap"),
                "agentstudio.startup_diagnostic.bridge.product_paint.comm_session.queued_command.count": .int(
                    snapshot?.reviewSelectionQueuedCommandCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.comm_session.replacement_request.count": .int(
                    snapshot?.reviewSelectionReplacementRequestCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.comm_session.native_bootstrap_install.count": .int(
                    snapshot?.reviewSelectionNativeBootstrapInstallCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.runtime.native_bootstrap_install.attempt.count":
                    .int(
                        snapshot?.reviewSelectionNativeBootstrapInstallAttemptCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.runtime.native_bootstrap_install.accepted.count":
                    .int(snapshot?.reviewSelectionNativeBootstrapInstallAcceptedCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.runtime.native_bootstrap_install.rejected.count":
                    .int(snapshot?.reviewSelectionNativeBootstrapInstallRejectedCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_identity_chain_matched": .bool(
                    snapshot?.reviewIdentityChainMatched == true),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_source_matched": .bool(
                    snapshot?.reviewPaintedSourceMatched == true),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_source_match.count": .int(
                    snapshot?.reviewPaintedSourceMatchCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_selected_identity_matched": .bool(
                    snapshot?.reviewSelectedPathMatched == true),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_selected_item_present": .bool(
                    snapshot?.reviewSelectedItemPresent == true),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_selected_path_present": .bool(
                    snapshot?.reviewSelectedPathPresent == true),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_shell_present": .bool(
                    snapshot?.reviewShellPresent == true),
                "agentstudio.startup_diagnostic.bridge.product_paint.reload_replay_succeeded": .bool(
                    reloadReplaySucceeded),
                "agentstudio.startup_diagnostic.bridge.product_paint.worker_replacement_observed": .bool(
                    workerReplacementObserved),
                "agentstudio.startup_diagnostic.render_proof.succeeded": .bool(succeeded),
            ]
        }
    }

    @MainActor
    extension AppDelegate {
        nonisolated private static let bridgeProductPaintFixtureRelativePath = "tracked.txt"
        nonisolated private static let bridgeProductPaintFixtureCanary = "bridge-product-paint-canary"

        func runBridgeProductPaintCorrelationDiagnostic(
            action: AgentStudioStartupDiagnosticAction
        ) async {
            NSApp.activate(ignoringOtherApps: true)
            mainWindowController?.completeLaunchPresentation()
            await waitForStartupDiagnosticAppActivation()

            guard let terminalContainerBounds = await startupDiagnosticLaunchRestoreBounds() else {
                recordUnavailableBridgeProductPaintCorrelationResult(action: action)
                return
            }
            if !launchRestoreObservationState.didComplete {
                await finishLaunchRestore(
                    using: terminalContainerBounds,
                    source: "bridgeProductPaintCorrelationPreflight"
                )
            }

            guard let worktreeURL = AgentStudioStartupDiagnosticAction.watchFolderURL(),
                let oracle = Self.bridgeProductPaintCorrelationOracle(worktreeURL: worktreeURL)
            else {
                recordUnavailableBridgeProductPaintCorrelationResult(action: action)
                return
            }
            let worktree = store.repositoryTopologyAtom.ensureMainWorktree(at: worktreeURL)
            guard let pane = workspaceSurfaceCoordinator.openBridgeReviewInNewTab(worktreeId: worktree.id) else {
                recordUnavailableBridgeProductPaintCorrelationResult(action: action)
                return
            }
            workspaceSurfaceCoordinator.restoreVisiblePaneIfNeeded(pane.id, forceWhenBoundsExist: true)
            await Task.yield()

            guard
                let bridgeView = viewRegistry.view(for: pane.id)?
                    .mountedContent(as: BridgePaneMountView.self)
            else {
                recordUnavailableBridgeProductPaintCorrelationResult(action: action)
                return
            }

            paneTabViewController()?.execute(.focusPane, target: pane.id, targetType: .pane)
            let javaScript = Self.bridgeProductPaintCorrelationJavaScript(
                relativePath: Self.bridgeProductPaintFixtureRelativePath,
                sha256: oracle.sha256,
                canary: Self.bridgeProductPaintFixtureCanary
            )
            let initialDeadline =
                ContinuousClock.now
                + AppPolicies.StartupDiagnostic.bridgeFileViewSmokeReadinessTimeout
            let initialProof = await waitForBridgeProductPaintCorrelation(
                controller: bridgeView.controller,
                javaScript: javaScript,
                deadline: initialDeadline
            )
            guard initialProof.surfaceCorrelationSucceeded,
                let initialWorkerInstanceId = await bridgeView.controller.productSessionOwner
                    .activeBootstrap()?.workerInstanceId
            else {
                recordBridgeProductPaintCorrelationResult(action: action, proof: initialProof)
                return
            }

            let replayDeadline =
                ContinuousClock.now
                + AppPolicies.StartupDiagnostic.bridgeFileViewSmokeReadinessTimeout
            let reloadNavigationEvents = bridgeView.controller.loadApp()
            guard
                await waitForBridgeProductPaintNavigationFinished(
                    navigationEvents: reloadNavigationEvents,
                    deadline: replayDeadline
                )
            else {
                recordBridgeProductPaintCorrelationResult(action: action, proof: initialProof)
                return
            }
            guard
                let replayWorkerInstanceId = await waitForBridgeProductPaintWorkerReplacement(
                    controller: bridgeView.controller,
                    excluding: initialWorkerInstanceId,
                    deadline: replayDeadline
                )
            else {
                recordBridgeProductPaintCorrelationResult(action: action, proof: initialProof)
                return
            }
            guard bridgeView.controller.requestViewerSurface(.review) else {
                recordBridgeProductPaintCorrelationResult(action: action, proof: initialProof)
                return
            }
            let replayProof = await waitForBridgeProductPaintCorrelation(
                controller: bridgeView.controller,
                javaScript: javaScript,
                deadline: replayDeadline
            )
            recordBridgeProductPaintCorrelationResult(
                action: action,
                proof: BridgeProductPaintCorrelationProof(
                    snapshot: replayProof.snapshot,
                    reloadReplaySucceeded: replayProof.surfaceCorrelationSucceeded,
                    workerReplacementObserved: replayWorkerInstanceId != initialWorkerInstanceId
                )
            )
        }

        private func recordUnavailableBridgeProductPaintCorrelationResult(
            action: AgentStudioStartupDiagnosticAction
        ) {
            recordBridgeProductPaintCorrelationResult(
                action: action,
                proof: BridgeProductPaintCorrelationProof(snapshot: nil)
            )
        }

        private func waitForBridgeProductPaintNavigationFinished(
            navigationEvents: some AsyncSequence<WebPage.NavigationEvent, any Error>,
            deadline: ContinuousClock.Instant
        ) async -> Bool {
            let navigationTask = Task { @MainActor in
                do {
                    var didCommit = false
                    for try await navigationEvent in navigationEvents {
                        if Task.isCancelled { return false }
                        switch navigationEvent {
                        case .committed:
                            didCommit = true
                        case .finished:
                            return didCommit
                        default:
                            continue
                        }
                    }
                } catch {
                    return false
                }
                return false
            }

            return await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    await navigationTask.value
                }
                group.addTask {
                    do {
                        try await ContinuousClock().sleep(until: deadline)
                    } catch {
                        return false
                    }
                    return false
                }
                let navigationFinished = await group.next() ?? false
                group.cancelAll()
                navigationTask.cancel()
                return navigationFinished
            }
        }

        private func waitForBridgeProductPaintWorkerReplacement(
            controller: BridgePaneController,
            excluding initialWorkerInstanceId: String,
            deadline: ContinuousClock.Instant
        ) async -> String? {
            var workerInstanceId = await controller.productSessionOwner
                .activeBootstrap()?.workerInstanceId
            while (workerInstanceId == nil || workerInstanceId == initialWorkerInstanceId)
                && ContinuousClock.now < deadline
            {
                if Task.isCancelled { return nil }
                do {
                    try await Task.sleep(
                        nanoseconds: Duration.milliseconds(50).nanosecondsForTaskSleep)
                } catch {
                    return nil
                }
                guard !Task.isCancelled, ContinuousClock.now < deadline else { return nil }
                workerInstanceId = await controller.productSessionOwner
                    .activeBootstrap()?.workerInstanceId
            }
            guard !Task.isCancelled, let workerInstanceId,
                workerInstanceId != initialWorkerInstanceId
            else {
                return nil
            }
            return workerInstanceId
        }

        private func waitForBridgeProductPaintCorrelation(
            controller: BridgePaneController,
            javaScript: String,
            deadline: ContinuousClock.Instant
        ) async -> BridgeProductPaintCorrelationProof {
            var proof = await bridgeProductPaintCorrelationProof(
                controller: controller,
                javaScript: javaScript
            )
            while !proof.surfaceCorrelationSucceeded
                && ContinuousClock.now < deadline
            {
                do {
                    try await Task.sleep(
                        nanoseconds: Duration.milliseconds(50).nanosecondsForTaskSleep)
                } catch {
                    return proof
                }
                guard !Task.isCancelled, ContinuousClock.now < deadline else { return proof }
                proof = await bridgeProductPaintCorrelationProof(
                    controller: controller,
                    javaScript: javaScript
                )
            }
            return proof
        }

        private func bridgeProductPaintCorrelationProof(
            controller: BridgePaneController,
            javaScript: String
        ) async -> BridgeProductPaintCorrelationProof {
            do {
                let result = try await controller.page.callJavaScript(javaScript)
                guard let json = result as? String,
                    let data = json.data(using: .utf8)
                else { return BridgeProductPaintCorrelationProof(snapshot: nil) }
                return BridgeProductPaintCorrelationProof(
                    snapshot: try JSONDecoder().decode(
                        BridgeProductPaintCorrelationSnapshot.self,
                        from: data
                    )
                )
            } catch {
                return BridgeProductPaintCorrelationProof(snapshot: nil)
            }
        }

        private func recordBridgeProductPaintCorrelationResult(
            action: AgentStudioStartupDiagnosticAction,
            proof: BridgeProductPaintCorrelationProof
        ) {
            let outcome = proof.succeeded ? "succeeded" : "blocked"
            let attributes = startupDiagnosticTraceAttributes(for: action).merging(
                proof.attributes
            ) { _, newValue in newValue }
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.command_exercised",
                phase: "startup_diagnostic_action",
                outcome: outcome,
                attributes: attributes
            )
            startupTraceRecorder.recordAppStartup(
                proof.succeeded
                    ? "app.startup_diagnostic_action.completed"
                    : "app.startup_diagnostic_action.blocked",
                phase: "startup_diagnostic_action",
                outcome: outcome,
                attributes: attributes
            )
        }

        private nonisolated static func bridgeProductPaintCorrelationOracle(
            worktreeURL: URL
        ) -> (sha256: String, byteCount: Int)? {
            do {
                let fileURL = try BridgeSourcePathContainment.resolveRegularFile(
                    rootURL: worktreeURL,
                    relativePath: bridgeProductPaintFixtureRelativePath
                )
                let data = try Data(contentsOf: fileURL)
                guard data.contains(Data(bridgeProductPaintFixtureCanary.utf8)) else {
                    return nil
                }
                return (
                    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                    data.count
                )
            } catch {
                return nil
            }
        }

        // The embedded diagnostic program is kept together so its correlation state machine
        // remains auditable as one browser-side transaction.
        // swiftlint:disable:next function_body_length
        nonisolated static func bridgeProductPaintCorrelationJavaScript(
            relativePath: String,
            sha256: String,
            canary: String
        ) -> String {
            let relativePathLiteral = bridgeProductPaintJavaScriptLiteral(relativePath)
            let sha256Literal = bridgeProductPaintJavaScriptLiteral(sha256)
            let canaryLiteral = bridgeProductPaintJavaScriptLiteral(canary)
            return """
                return JSON.stringify((() => {
                  const relativePath = \(relativePathLiteral);
                  const expectedSha256 = \(sha256Literal);
                  const expectedCanary = \(canaryLiteral);
                  const prior = globalThis.__bridgeProductPaintCorrelationProbe ?? {};
                  const readableText = (root) => {
                    const parts = [];
                    const visit = (node) => {
                      if (node.nodeType === Node.TEXT_NODE) parts.push(node.textContent ?? '');
                      if (node instanceof Element && node.shadowRoot !== null) visit(node.shadowRoot);
                      for (const child of node.childNodes) visit(child);
                    };
                    visit(root);
                    return parts.join('');
                  };
                  const paintedElements = [];
                  const collectPainted = (root) => {
                    for (const element of root.querySelectorAll('*')) {
                      if (element.hasAttribute('data-bridge-painted-source-correlations')) {
                        paintedElements.push(element);
                      }
                      if (element.shadowRoot !== null) collectPainted(element.shadowRoot);
                    }
                  };
                  const queryOpenRoots = (root, selector) => {
                    const direct = root.querySelector(selector);
                    if (direct !== null) return direct;
                    for (const element of root.querySelectorAll('*')) {
                      if (element.shadowRoot === null) continue;
                      const match = queryOpenRoots(element.shadowRoot, selector);
                      if (match !== null) return match;
                    }
                    return null;
                  };
                  const fileShell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
                  const paintedCorrelationRoot =
                    prior.reviewPaintedSourceMatched === true && fileShell !== null
                      ? fileShell
                      : document;
                  collectPainted(paintedCorrelationRoot);
                  const correlations = paintedElements.flatMap((element) => {
                    try {
                      const values = JSON.parse(
                        element.getAttribute('data-bridge-painted-source-correlations') ?? '[]'
                      );
                      const paintedPublicationId =
                        element.getAttribute('data-bridge-painted-publication-id') ?? '';
                      const text = readableText(element);
                      return Array.isArray(values)
                        ? values.map((value) => ({ ...value, paintedPublicationId, text }))
                        : [];
                    } catch {
                      return [];
                    }
                  });
                  const identityChainMatches = (correlation) => {
                    const paintedPublicationId = correlation?.paintedPublicationId;
                    const pierreIdentityMatches = correlation?.surface === 'file'
                      ? correlation?.pierreItemId === `file:${correlation?.itemId}`
                      : correlation?.pierreItemId === correlation?.itemId;
                    return typeof correlation?.descriptorId === 'string' &&
                      correlation.descriptorId.length > 0 &&
                      typeof correlation?.requestId === 'string' &&
                      correlation.requestId.length > 0 &&
                      typeof correlation?.sourceIdentity === 'string' &&
                      correlation.sourceIdentity.length > 0 &&
                      typeof correlation?.position === 'string' &&
                      correlation.position.length > 0 &&
                      Number.isSafeInteger(correlation?.sourceGeneration) &&
                      correlation.sourceGeneration >= 0 &&
                      typeof correlation?.itemId === 'string' &&
                      correlation.itemId.length > 0 &&
                      correlation?.semanticItemId === correlation?.itemId &&
                      typeof correlation?.pierreItemId === 'string' &&
                      correlation.pierreItemId.length > 0 &&
                      pierreIdentityMatches &&
                      typeof paintedPublicationId === 'string' &&
                      paintedPublicationId.length > 0 &&
                      correlation?.publicationId === paintedPublicationId;
                  };
                  const sourceMatches = (correlation, surface, role, selectedItemId) =>
                    identityChainMatches(correlation) &&
                    correlation?.itemId === selectedItemId &&
                    correlation?.position === 'whole' &&
                    correlation?.surface === surface &&
                    correlation?.role === role &&
                    correlation?.observedSha256 === expectedSha256 &&
                    correlation?.disposition === 'painted' &&
                    correlation?.text?.includes(expectedCanary);
                  const appRoot = document.querySelector('[data-testid="bridge-app-root"]');
                  const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
                  const reviewSelectedPath =
                    reviewShell?.getAttribute('data-selected-display-path') ?? '';
                  const reviewSelectedItemId =
                    document.querySelector('[data-testid="bridge-code-view-panel"]')
                      ?.getAttribute('data-selected-item-id') ?? '';
                  const reviewSelectionProbe = globalThis.__bridgeReviewSelectionDiagnostic ?? {};
                  const retainedCount = (name, currentCount) => Math.max(
                    Number(prior[name] ?? 0),
                    currentCount
                  );
                  const reviewSelectionProbeCount = (name) => {
                    const value = Number(reviewSelectionProbe[name] ?? 0);
                    return Number.isSafeInteger(value) && value >= 0 ? value : 0;
                  };
                  const reviewSelectionProbeEnum = (name, allowed, fallback) => {
                    const value = reviewSelectionProbe[name];
                    return typeof value === 'string' && allowed.includes(value) ? value : fallback;
                  };
                  const paintedElementCount = retainedCount(
                    'paintedElementCount', paintedElements.length
                  );
                  const decodedSourceCorrelationCount = retainedCount(
                    'decodedSourceCorrelationCount', correlations.length
                  );
                  const reviewMetadataItemCount = retainedCount(
                    'reviewMetadataItemCount',
                    Number(reviewShell?.getAttribute('data-review-metadata-item-count') ?? 0)
                  );
                  const reviewSelectionInitialRequestedCount = retainedCount(
                    'reviewSelectionInitialRequestedCount',
                    reviewSelectionProbeCount('initialSelectionRequestedCount')
                  );
                  const reviewSelectionInitialSchedulingAcceptedCount = retainedCount(
                    'reviewSelectionInitialSchedulingAcceptedCount',
                    reviewSelectionProbeCount('initialSelectionSchedulingAcceptedCount')
                  );
                  const reviewSelectionScheduledCount = retainedCount(
                    'reviewSelectionScheduledCount',
                    reviewSelectionProbeCount('selectionScheduledCount')
                  );
                  const reviewSelectionFirstFrameReachedCount = retainedCount(
                    'reviewSelectionFirstFrameReachedCount',
                    reviewSelectionProbeCount('selectionFirstFrameReachedCount')
                  );
                  const reviewSelectionSecondFrameReachedCount = retainedCount(
                    'reviewSelectionSecondFrameReachedCount',
                    reviewSelectionProbeCount('selectionSecondFrameReachedCount')
                  );
                  const reviewSelectionSubmittedCount = retainedCount(
                    'reviewSelectionSubmittedCount',
                    reviewSelectionProbeCount('selectionSubmittedCount')
                  );
                  const reviewSelectionDroppedCount = retainedCount(
                    'reviewSelectionDroppedCount',
                    reviewSelectionProbeCount('selectionDroppedCount')
                  );
                  const reviewSelectionLatestDispatchDisposition = reviewSelectionProbeEnum(
                    'latestReviewSelectDispatchDisposition',
                    ['dropped_detached', 'queued_not_ready', 'posted'],
                    'not_sent'
                  );
                  const reviewSelectionLatestLifecycleState = reviewSelectionProbeEnum(
                    'latestReviewSelectLifecycleState',
                    ['not_sent', 'pending', 'acked', 'failed', 'timed_out', 'superseded'],
                    'not_sent'
                  );
                  const pageReadyState = reviewSelectionProbeEnum(
                    'pageReadyState',
                    ['awaiting', 'ready', 'failed'],
                    'awaiting'
                  );
                  const fileModeSendAttemptCount =
                    reviewSelectionProbeCount('fileModeSendAttemptCount');
                  const fileModeSendSynchronousFailureCount =
                    reviewSelectionProbeCount('fileModeSendSynchronousFailureCount');
                  const fileModeLatestDispatchDisposition = reviewSelectionProbeEnum(
                    'latestFileModeDispatchDisposition',
                    ['not_sent', 'dropped_detached', 'queued_not_ready', 'posted'],
                    'not_sent'
                  );
                  const fileSelectionLatestDispatchDisposition = reviewSelectionProbeEnum(
                    'latestFileSelectDispatchDisposition',
                    ['not_sent', 'dropped_detached', 'queued_not_ready', 'posted'],
                    'not_sent'
                  );
                  const fileSelectionLatestLifecycleState = reviewSelectionProbeEnum(
                    'latestFileSelectLifecycleState',
                    ['not_sent', 'pending', 'acked', 'failed', 'timed_out', 'superseded'],
                    'not_sent'
                  );
                  const reviewSelectionSessionState = reviewSelectionProbeEnum(
                    'sessionState',
                    [
                      'awaiting_bootstrap',
                      'bootstrapping',
                      'ready',
                      'replacement_requested',
                      'disposed'
                    ],
                    'awaiting_bootstrap'
                  );
                  const reviewSelectionQueuedCommandCount =
                    reviewSelectionProbeCount('queuedCommandCount');
                  const reviewSelectionReplacementRequestCount =
                    reviewSelectionProbeCount('replacementRequestCount');
                  const reviewSelectionNativeBootstrapInstallCount =
                    reviewSelectionProbeCount('nativeBootstrapInstallCount');
                  const reviewSelectionNativeBootstrapInstallAttemptCount =
                    reviewSelectionProbeCount('nativeBootstrapInstallAttemptCount');
                  const reviewSelectionNativeBootstrapInstallAcceptedCount =
                    reviewSelectionProbeCount('nativeBootstrapInstallAcceptedCount');
                  const reviewSelectionNativeBootstrapInstallRejectedCount =
                    reviewSelectionProbeCount('nativeBootstrapInstallRejectedCount');
                  const activeViewerModeIsReview =
                    prior.activeViewerModeIsReview === true ||
                    appRoot?.getAttribute('data-bridge-viewer-mode') === 'review';
                  const reviewShellPresent =
                    prior.reviewShellPresent === true || reviewShell !== null;
                  const reviewSelectedItemPresent =
                    prior.reviewSelectedItemPresent === true || reviewSelectedItemId.length > 0;
                  const reviewSelectedPathPresent =
                    prior.reviewSelectedPathPresent === true || reviewSelectedPath.length > 0;
                  const reviewSurfaceRoleCandidates = correlations.filter((value) =>
                    value?.surface === 'review' && value?.role === 'head'
                  );
                  const reviewSurfaceRoleCandidateCount = retainedCount(
                    'reviewSurfaceRoleCandidateCount', reviewSurfaceRoleCandidates.length
                  );
                  const reviewIdentityCandidateCount = retainedCount(
                    'reviewIdentityCandidateCount',
                    reviewSurfaceRoleCandidates.filter(identityChainMatches).length
                  );
                  const reviewSelectedItemCandidateCount = retainedCount(
                    'reviewSelectedItemCandidateCount',
                    reviewSurfaceRoleCandidates.filter((value) =>
                      value?.itemId === reviewSelectedItemId
                    ).length
                  );
                  const reviewWholePositionCandidateCount = retainedCount(
                    'reviewWholePositionCandidateCount',
                    reviewSurfaceRoleCandidates.filter((value) => value?.position === 'whole').length
                  );
                  const reviewDigestCandidateCount = retainedCount(
                    'reviewDigestCandidateCount',
                    reviewSurfaceRoleCandidates.filter((value) =>
                      value?.observedSha256 === expectedSha256
                    ).length
                  );
                  const reviewPaintedDispositionCandidateCount = retainedCount(
                    'reviewPaintedDispositionCandidateCount',
                    reviewSurfaceRoleCandidates.filter((value) =>
                      value?.disposition === 'painted'
                    ).length
                  );
                  const reviewCanaryCandidateCount = retainedCount(
                    'reviewCanaryCandidateCount',
                    reviewSurfaceRoleCandidates.filter((value) =>
                      value?.text?.includes(expectedCanary)
                    ).length
                  );
                  const reviewMatches = correlations.filter((value) =>
                    sourceMatches(value, 'review', 'head', reviewSelectedItemId)
                  );
                  const reviewPaintedSourceMatched =
                    prior.reviewPaintedSourceMatched === true || reviewMatches.length > 0;
                  const reviewIdentityChainMatched =
                    prior.reviewIdentityChainMatched === true ||
                    reviewIdentityCandidateCount > 0;
                  const reviewPaintedSourceMatchCount = Math.max(
                    Number(prior.reviewPaintedSourceMatchCount ?? 0),
                    reviewMatches.length
                  );
                  const reviewSelectedPathMatched =
                    prior.reviewSelectedPathMatched === true || reviewSelectedPath === relativePath;
                  const fileButton = document.querySelector('[data-testid="bridge-viewer-context-file"]');
                  if (reviewPaintedSourceMatched && fileButton instanceof HTMLElement) fileButton.click();
                  const fileViewerIsActive =
                    fileShell?.getAttribute('data-file-viewer-active') === 'true';
                  const fileSelectedPath = fileShell?.getAttribute('data-selected-display-path') ?? '';
                  const fileSelectedItemId =
                    document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]')
                      ?.getAttribute('data-worktree-rendered-item-id') ?? '';
                  const fileMatches = correlations.filter((value) =>
                    sourceMatches(value, 'file', 'file', fileSelectedItemId)
                  );
                  const filePaintedSourceMatched =
                    prior.filePaintedSourceMatched === true || fileMatches.length > 0;
                  let fileSelectionActivationAttempted =
                    prior.fileSelectionActivationAttempted === true;
                  if (
                    reviewPaintedSourceMatched &&
                    fileViewerIsActive &&
                    !filePaintedSourceMatched &&
                    !fileSelectionActivationAttempted
                  ) {
                    const selector =
                      `button[data-item-type="file"][data-item-path="${CSS.escape(relativePath)}"],` +
                      `[data-type="item"][data-item-type="file"][data-item-path="${CSS.escape(relativePath)}"]`;
                    const row = queryOpenRoots(fileShell, selector);
                    if (row instanceof HTMLElement) {
                      row.click();
                      fileSelectionActivationAttempted = true;
                    }
                  }
                  const fileIdentityChainMatched =
                    prior.fileIdentityChainMatched === true ||
                    fileMatches.some(identityChainMatches);
                  const filePaintedSourceMatchCount = Math.max(
                    Number(prior.filePaintedSourceMatchCount ?? 0),
                    fileMatches.length
                  );
                  const fileSelectedPathMatched =
                    prior.fileSelectedPathMatched === true || fileSelectedPath === relativePath;
                  const next = {
                    activeViewerModeIsReview,
                    paintedElementCount,
                    decodedSourceCorrelationCount,
                    reviewMetadataItemCount,
                    reviewSelectionInitialRequestedCount,
                    reviewSelectionInitialSchedulingAcceptedCount,
                    reviewSelectionScheduledCount,
                    reviewSelectionFirstFrameReachedCount,
                    reviewSelectionSecondFrameReachedCount,
                    reviewSelectionSubmittedCount,
                    reviewSelectionDroppedCount,
                    reviewShellPresent,
                    reviewSelectedItemPresent,
                    reviewSelectedPathPresent,
                    reviewSurfaceRoleCandidateCount,
                    reviewIdentityCandidateCount,
                    reviewSelectedItemCandidateCount,
                    reviewWholePositionCandidateCount,
                    reviewDigestCandidateCount,
                    reviewPaintedDispositionCandidateCount,
                    reviewCanaryCandidateCount,
                    reviewPaintedSourceMatched,
                    reviewIdentityChainMatched,
                    reviewPaintedSourceMatchCount,
                    reviewSelectedPathMatched,
                    filePaintedSourceMatched,
                    fileIdentityChainMatched,
                    filePaintedSourceMatchCount,
                    fileSelectedPathMatched,
                    fileSelectionActivationAttempted
                  };
                  globalThis.__bridgeProductPaintCorrelationProbe = next;
                  return {
                    activeViewerModeIsReview,
                    decodedSourceCorrelationCount,
                    documentVisibilityState: document.visibilityState,
                    fileModeActivated:
                      fileButton?.getAttribute('data-bridge-viewer-context-selected') === 'true',
                    fileModeLatestDispatchDisposition,
                    fileModeSendAttemptCount,
                    fileModeSendSynchronousFailureCount,
                    fileIdentityChainMatched,
                    filePaintedSourceMatched,
                    filePaintedSourceMatchCount,
                    fileSelectionLatestDispatchDisposition,
                    fileSelectionLatestLifecycleState,
                    fileSelectedPathMatched,
                    frameLivenessRafAlive:
                      globalThis.__bridgeFrameLivenessProbe?.rafAlive ?? 'missing',
                    pageReadyState,
                    paintedElementCount,
                    reviewCanaryCandidateCount,
                    reviewDigestCandidateCount,
                    reviewIdentityCandidateCount,
                    reviewIdentityChainMatched,
                    reviewMetadataItemCount,
                    reviewPaintedDispositionCandidateCount,
                    reviewPaintedSourceMatched,
                    reviewPaintedSourceMatchCount,
                    reviewSelectionDroppedCount,
                    reviewSelectionFirstFrameReachedCount,
                    reviewSelectionInitialRequestedCount,
                    reviewSelectionInitialSchedulingAcceptedCount,
                    reviewSelectionLatestDispatchDisposition,
                    reviewSelectionLatestLifecycleState,
                    reviewSelectionNativeBootstrapInstallAcceptedCount,
                    reviewSelectionNativeBootstrapInstallAttemptCount,
                    reviewSelectionNativeBootstrapInstallCount,
                    reviewSelectionNativeBootstrapInstallRejectedCount,
                    reviewSelectionQueuedCommandCount,
                    reviewSelectionReplacementRequestCount,
                    reviewSelectionSecondFrameReachedCount,
                    reviewSelectionScheduledCount,
                    reviewSelectionSessionState,
                    reviewSelectionSubmittedCount,
                    reviewSelectedItemCandidateCount,
                    reviewSelectedItemPresent,
                    reviewSelectedPathMatched,
                    reviewSelectedPathPresent,
                    reviewShellPresent,
                    reviewSurfaceRoleCandidateCount,
                    reviewWholePositionCandidateCount
                  };
                })())
                """
        }

        private nonisolated static func bridgeProductPaintJavaScriptLiteral(
            _ value: String
        ) -> String {
            guard let data = try? JSONEncoder().encode(value),
                let literal = String(data: data, encoding: .utf8)
            else { return "\"\"" }
            return literal
        }
    }
#endif
