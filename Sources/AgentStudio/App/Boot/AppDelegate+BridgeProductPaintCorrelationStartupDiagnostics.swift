import AppKit
import CryptoKit
import Foundation

#if DEBUG
    private struct BridgeProductPaintCorrelationSnapshot: Decodable {
        let documentVisibilityState: String
        let fileModeActivated: Bool
        let filePaintedSourceMatched: Bool
        let filePaintedSourceMatchCount: Int
        let fileSelectedPathMatched: Bool
        let frameLivenessRafAlive: String
        let reviewPaintedSourceMatched: Bool
        let reviewPaintedSourceMatchCount: Int
        let reviewSelectedPathMatched: Bool
    }

    private struct BridgeProductPaintCorrelationProof {
        let snapshot: BridgeProductPaintCorrelationSnapshot?

        var succeeded: Bool {
            guard let snapshot else { return false }
            return snapshot.documentVisibilityState == "visible"
                && snapshot.frameLivenessRafAlive == "true"
                && snapshot.reviewSelectedPathMatched
                && snapshot.reviewPaintedSourceMatched
                && snapshot.reviewPaintedSourceMatchCount > 0
                && snapshot.fileModeActivated
                && snapshot.fileSelectedPathMatched
                && snapshot.filePaintedSourceMatched
                && snapshot.filePaintedSourceMatchCount > 0
        }

        var attributes: [String: AgentStudioTraceValue] {
            let snapshot = snapshot
            return [
                "agentstudio.startup_diagnostic.bridge.product_paint.document_visible": .bool(
                    snapshot?.documentVisibilityState == "visible"),
                "agentstudio.startup_diagnostic.bridge.product_paint.file_mode_activated": .bool(
                    snapshot?.fileModeActivated == true),
                "agentstudio.startup_diagnostic.bridge.product_paint.file_source_matched": .bool(
                    snapshot?.filePaintedSourceMatched == true),
                "agentstudio.startup_diagnostic.bridge.product_paint.file_source_match.count": .int(
                    snapshot?.filePaintedSourceMatchCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.file_selected_identity_matched": .bool(
                    snapshot?.fileSelectedPathMatched == true),
                "agentstudio.startup_diagnostic.bridge.product_paint.frame_live": .bool(
                    snapshot?.frameLivenessRafAlive == "true"),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_source_matched": .bool(
                    snapshot?.reviewPaintedSourceMatched == true),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_source_match.count": .int(
                    snapshot?.reviewPaintedSourceMatchCount ?? 0),
                "agentstudio.startup_diagnostic.bridge.product_paint.review_selected_identity_matched": .bool(
                    snapshot?.reviewSelectedPathMatched == true),
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
            mainWindowController?.window?.makeKeyAndOrderFront(nil)
            await waitForStartupDiagnosticAppActivation()

            guard let terminalContainerBounds = await startupDiagnosticLaunchRestoreBounds() else {
                recordBridgeProductPaintCorrelationResult(
                    action: action,
                    proof: BridgeProductPaintCorrelationProof(snapshot: nil)
                )
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
                recordBridgeProductPaintCorrelationResult(
                    action: action,
                    proof: BridgeProductPaintCorrelationProof(snapshot: nil)
                )
                return
            }
            let worktree = store.repositoryTopologyAtom.ensureMainWorktree(at: worktreeURL)
            guard let pane = workspaceSurfaceCoordinator.openBridgeReviewInNewTab(worktreeId: worktree.id) else {
                recordBridgeProductPaintCorrelationResult(
                    action: action,
                    proof: BridgeProductPaintCorrelationProof(snapshot: nil)
                )
                return
            }
            workspaceSurfaceCoordinator.restoreVisiblePaneIfNeeded(pane.id, forceWhenBoundsExist: true)
            await Task.yield()

            guard
                let bridgeView = viewRegistry.view(for: pane.id)?
                    .mountedContent(as: BridgePaneMountView.self)
            else {
                recordBridgeProductPaintCorrelationResult(
                    action: action,
                    proof: BridgeProductPaintCorrelationProof(snapshot: nil)
                )
                return
            }

            let javaScript = Self.bridgeProductPaintCorrelationJavaScript(
                relativePath: Self.bridgeProductPaintFixtureRelativePath,
                sha256: oracle.sha256,
                canary: Self.bridgeProductPaintFixtureCanary
            )
            let proof = await waitForBridgeProductPaintCorrelation(
                controller: bridgeView.controller,
                javaScript: javaScript
            )
            recordBridgeProductPaintCorrelationResult(action: action, proof: proof)
        }

        private func waitForBridgeProductPaintCorrelation(
            controller: BridgePaneController,
            javaScript: String
        ) async -> BridgeProductPaintCorrelationProof {
            let start = ContinuousClock.now
            var proof = await bridgeProductPaintCorrelationProof(
                controller: controller,
                javaScript: javaScript
            )
            while !proof.succeeded
                && start.duration(to: ContinuousClock.now)
                    < AppPolicies.StartupDiagnostic.bridgeFileViewSmokeReadinessTimeout
            {
                try? await Task.sleep(nanoseconds: Duration.milliseconds(50).nanosecondsForTaskSleep)
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
                    return parts.join(' ');
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
                  collectPainted(document);
                  const correlations = paintedElements.flatMap((element) => {
                    try {
                      const values = JSON.parse(
                        element.getAttribute('data-bridge-painted-source-correlations') ?? '[]'
                      );
                      const text = readableText(element);
                      return Array.isArray(values) ? values.map((value) => ({ ...value, text })) : [];
                    } catch {
                      return [];
                    }
                  });
                  const sourceMatches = (correlation, surface, role) =>
                    correlation?.surface === surface &&
                    correlation?.role === role &&
                    correlation?.observedSha256 === expectedSha256 &&
                    correlation?.disposition === 'painted' &&
                    correlation?.text?.includes(expectedCanary);
                  const reviewMatches = correlations.filter((value) => sourceMatches(value, 'review', 'head'));
                  const reviewSelectedPath =
                    document.querySelector('[data-testid="review-viewer-shell"]')
                      ?.getAttribute('data-selected-display-path') ?? '';
                  const reviewPaintedSourceMatched =
                    prior.reviewPaintedSourceMatched === true || reviewMatches.length > 0;
                  const reviewPaintedSourceMatchCount = Math.max(
                    Number(prior.reviewPaintedSourceMatchCount ?? 0),
                    reviewMatches.length
                  );
                  const reviewSelectedPathMatched =
                    prior.reviewSelectedPathMatched === true || reviewSelectedPath === relativePath;
                  const fileButton = document.querySelector('[data-testid="bridge-viewer-context-file"]');
                  if (reviewPaintedSourceMatched && fileButton instanceof HTMLElement) fileButton.click();
                  const fileShell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
                  const fileSelectedPath = fileShell?.getAttribute('data-selected-display-path') ?? '';
                  if (reviewPaintedSourceMatched && fileSelectedPath !== relativePath) {
                    const selector =
                      `button[data-type="item"][data-item-type="file"][data-item-path="${CSS.escape(relativePath)}"]`;
                    const row = queryOpenRoots(document, selector);
                    if (row instanceof HTMLElement) row.click();
                  }
                  const fileMatches = correlations.filter((value) => sourceMatches(value, 'file', 'file'));
                  const filePaintedSourceMatched =
                    prior.filePaintedSourceMatched === true || fileMatches.length > 0;
                  const filePaintedSourceMatchCount = Math.max(
                    Number(prior.filePaintedSourceMatchCount ?? 0),
                    fileMatches.length
                  );
                  const fileSelectedPathMatched =
                    prior.fileSelectedPathMatched === true || fileSelectedPath === relativePath;
                  const next = {
                    reviewPaintedSourceMatched,
                    reviewPaintedSourceMatchCount,
                    reviewSelectedPathMatched,
                    filePaintedSourceMatched,
                    filePaintedSourceMatchCount,
                    fileSelectedPathMatched
                  };
                  globalThis.__bridgeProductPaintCorrelationProbe = next;
                  return {
                    documentVisibilityState: document.visibilityState,
                    fileModeActivated:
                      fileButton?.getAttribute('data-bridge-viewer-context-selected') === 'true',
                    filePaintedSourceMatched,
                    filePaintedSourceMatchCount,
                    fileSelectedPathMatched,
                    frameLivenessRafAlive:
                      globalThis.__bridgeFrameLivenessProbe?.rafAlive ?? 'missing',
                    reviewPaintedSourceMatched,
                    reviewPaintedSourceMatchCount,
                    reviewSelectedPathMatched
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
