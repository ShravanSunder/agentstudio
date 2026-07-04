import AppKit
import Foundation

#if DEBUG
    @MainActor
    extension AppDelegate {
        func runBridgeFileViewObservabilitySmokeDiagnostic(
            action: AgentStudioStartupDiagnosticAction
        ) async {
            NSApp.activate(ignoringOtherApps: true)
            mainWindowController?.window?.makeKeyAndOrderFront(nil)
            await waitForStartupDiagnosticAppActivation()

            guard let terminalContainerBounds = await startupDiagnosticLaunchRestoreBounds() else {
                recordBridgeFileViewObservabilitySmokeSkipped(action: action, reason: "missing_bounds")
                return
            }

            if !launchRestoreObservationState.didComplete {
                await finishLaunchRestore(
                    using: terminalContainerBounds,
                    source: "bridgeFileViewObservabilitySmokePreflight"
                )
            }

            guard let worktreeId = bridgeFileViewObservabilitySmokeWorktreeId() else {
                recordBridgeFileViewObservabilitySmokeSkipped(action: action, reason: "missing_worktree")
                return
            }

            guard let pane = workspaceSurfaceCoordinator.openBridgeFileView(worktreeId: worktreeId) else {
                recordBridgeFileViewObservabilitySmokeSkipped(
                    action: action,
                    reason: "bridge_file_pane_creation_failed"
                )
                return
            }

            workspaceSurfaceCoordinator.restoreVisiblePaneIfNeeded(pane.id, forceWhenBoundsExist: true)
            await Task.yield()

            guard
                let bridgeView = viewRegistry.view(for: pane.id)?
                    .mountedContent(as: BridgePaneMountView.self)
            else {
                recordBridgeFileViewObservabilitySmokeSkipped(action: action, reason: "bridge_view_missing")
                return
            }

            let renderProof = await waitForBridgeFileViewObservabilitySmokeRenderProof(
                for: bridgeView.controller
            )
            recordBridgeFileViewObservabilitySmokeDiagnosticResult(
                action: action,
                outcome: renderProof.succeeded ? "succeeded" : "blocked",
                renderProof: renderProof
            )
        }

        func runBridgeFileViewCommandRouteObservabilitySmokeDiagnostic(
            action: AgentStudioStartupDiagnosticAction
        ) async {
            NSApp.activate(ignoringOtherApps: true)
            mainWindowController?.window?.makeKeyAndOrderFront(nil)
            await waitForStartupDiagnosticAppActivation()

            guard let terminalContainerBounds = await startupDiagnosticLaunchRestoreBounds() else {
                recordBridgeFileViewObservabilitySmokeSkipped(action: action, reason: "missing_bounds")
                return
            }

            if !launchRestoreObservationState.didComplete {
                await finishLaunchRestore(
                    using: terminalContainerBounds,
                    source: "bridgeFileViewCommandRouteObservabilitySmokePreflight"
                )
            }

            guard let folderURL = AgentStudioStartupDiagnosticAction.watchFolderURL() else {
                recordBridgeFileViewObservabilitySmokeSkipped(action: action, reason: "missing_watch_folder")
                return
            }

            _ = store.repositoryTopologyAtom.ensureMainWorktree(at: folderURL.standardizedFileURL)
            let worktreeCount = store.repositoryTopologyAtom.repos.flatMap(\.worktrees).count
            guard worktreeCount == 1 else {
                recordBridgeFileViewObservabilitySmokeSkipped(
                    action: action,
                    reason: "ambiguous_registered_worktree"
                )
                return
            }

            guard let pane = executor.openBridgeFileView() else {
                recordBridgeFileViewObservabilitySmokeSkipped(
                    action: action,
                    reason: "bridge_file_command_route_pane_creation_failed"
                )
                return
            }

            workspaceSurfaceCoordinator.restoreVisiblePaneIfNeeded(pane.id, forceWhenBoundsExist: true)
            await Task.yield()

            guard
                let bridgeView = viewRegistry.view(for: pane.id)?
                    .mountedContent(as: BridgePaneMountView.self)
            else {
                recordBridgeFileViewObservabilitySmokeSkipped(action: action, reason: "bridge_view_missing")
                return
            }

            let renderProof = await waitForBridgeFileViewObservabilitySmokeRenderProof(
                for: bridgeView.controller
            )
            recordBridgeFileViewObservabilitySmokeDiagnosticResult(
                action: action,
                outcome: renderProof.succeeded ? "succeeded" : "blocked",
                renderProof: renderProof
            )
        }

        func runBridgeFileViewTargetedRouteObservabilitySmokeDiagnostic(
            action: AgentStudioStartupDiagnosticAction
        ) async {
            NSApp.activate(ignoringOtherApps: true)
            mainWindowController?.window?.makeKeyAndOrderFront(nil)
            await waitForStartupDiagnosticAppActivation()

            guard let terminalContainerBounds = await startupDiagnosticLaunchRestoreBounds() else {
                recordBridgeFileViewObservabilitySmokeSkipped(action: action, reason: "missing_bounds")
                return
            }

            if !launchRestoreObservationState.didComplete {
                await finishLaunchRestore(
                    using: terminalContainerBounds,
                    source: "bridgeFileViewTargetedRouteObservabilitySmokePreflight"
                )
            }

            guard let folderURL = AgentStudioStartupDiagnosticAction.watchFolderURL() else {
                recordBridgeFileViewObservabilitySmokeSkipped(action: action, reason: "missing_watch_folder")
                return
            }

            let targetWorktree = store.repositoryTopologyAtom.ensureMainWorktree(
                at: folderURL.standardizedFileURL
            )

            let controlRepoURL =
                folderURL
                .deletingLastPathComponent()
                .appending(
                    path: "\(folderURL.lastPathComponent)-bridge-target-control"
                )
                .standardizedFileURL
            _ = store.repositoryTopologyAtom.addRepo(at: controlRepoURL)
            let registeredWorktreeCount = store.repositoryTopologyAtom.repos.flatMap(\.worktrees).count
            guard registeredWorktreeCount > 1 else {
                recordBridgeFileViewObservabilitySmokeSkipped(
                    action: action,
                    reason: "target_route_requires_multiple_worktrees"
                )
                return
            }

            guard let pane = workspaceSurfaceCoordinator.openBridgeFileView(worktreeId: targetWorktree.id) else {
                recordBridgeFileViewObservabilitySmokeSkipped(
                    action: action,
                    reason: "bridge_file_targeted_route_pane_creation_failed"
                )
                return
            }

            workspaceSurfaceCoordinator.restoreVisiblePaneIfNeeded(pane.id, forceWhenBoundsExist: true)
            await Task.yield()

            guard
                let bridgeView = viewRegistry.view(for: pane.id)?
                    .mountedContent(as: BridgePaneMountView.self)
            else {
                recordBridgeFileViewObservabilitySmokeSkipped(action: action, reason: "bridge_view_missing")
                return
            }

            let renderProof = await waitForBridgeFileViewObservabilitySmokeRenderProof(
                for: bridgeView.controller
            )
            recordBridgeFileViewObservabilitySmokeDiagnosticResult(
                action: action,
                outcome: renderProof.succeeded ? "succeeded" : "blocked",
                renderProof: renderProof
            )
        }

        func runBridgeReviewToFileViewObservabilitySmokeDiagnostic(
            action: AgentStudioStartupDiagnosticAction
        ) async {
            NSApp.activate(ignoringOtherApps: true)
            mainWindowController?.window?.makeKeyAndOrderFront(nil)
            await waitForStartupDiagnosticAppActivation()

            guard let terminalContainerBounds = await startupDiagnosticLaunchRestoreBounds() else {
                recordBridgeFileViewObservabilitySmokeSkipped(action: action, reason: "missing_bounds")
                return
            }

            if !launchRestoreObservationState.didComplete {
                await finishLaunchRestore(
                    using: terminalContainerBounds,
                    source: "bridgeReviewToFileViewObservabilitySmokePreflight"
                )
            }

            guard let worktreeId = bridgeFileViewObservabilitySmokeWorktreeId() else {
                recordBridgeFileViewObservabilitySmokeSkipped(action: action, reason: "missing_worktree")
                return
            }

            guard let pane = workspaceSurfaceCoordinator.openBridgeReview(worktreeId: worktreeId) else {
                recordBridgeFileViewObservabilitySmokeSkipped(
                    action: action,
                    reason: "bridge_review_pane_creation_failed"
                )
                return
            }

            workspaceSurfaceCoordinator.restoreVisiblePaneIfNeeded(pane.id, forceWhenBoundsExist: true)
            await Task.yield()

            guard
                let bridgeView = viewRegistry.view(for: pane.id)?
                    .mountedContent(as: BridgePaneMountView.self)
            else {
                recordBridgeFileViewObservabilitySmokeSkipped(action: action, reason: "bridge_view_missing")
                return
            }

            let renderProof = await waitForBridgeFileViewObservabilitySmokeRenderProof(
                for: bridgeView.controller,
                javaScript: Self.reviewToFileViewSmokeRenderJavaScript,
                expectedBootstrapProtocol: "review"
            )
            recordBridgeFileViewObservabilitySmokeDiagnosticResult(
                action: action,
                outcome: renderProof.succeeded ? "succeeded" : "blocked",
                renderProof: renderProof
            )
        }

        private func bridgeFileViewObservabilitySmokeWorktreeId() -> UUID? {
            if let folderURL = AgentStudioStartupDiagnosticAction.watchFolderURL() {
                return store.repositoryTopologyAtom.ensureMainWorktree(at: folderURL.standardizedFileURL).id
            }
            let worktrees = store.repositoryTopologyAtom.repos.flatMap(\.worktrees)
            return worktrees.count == 1 ? worktrees[0].id : nil
        }

        private func recordBridgeFileViewObservabilitySmokeSkipped(
            action: AgentStudioStartupDiagnosticAction,
            reason: String
        ) {
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.skipped",
                phase: "startup_diagnostic_action",
                outcome: "skipped",
                attributes: startupDiagnosticTraceAttributes(for: action).merging([
                    "agentstudio.startup_diagnostic.skip_reason": .string(reason)
                ]) { _, newValue in newValue }
            )
        }

        private func recordBridgeFileViewObservabilitySmokeDiagnosticResult(
            action: AgentStudioStartupDiagnosticAction,
            outcome: String,
            renderProof: BridgeFileViewObservabilitySmokeRenderProof
        ) {
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.command_exercised",
                phase: "startup_diagnostic_action",
                outcome: outcome,
                attributes: startupDiagnosticTraceAttributes(for: action).merging(
                    renderProof.attributes
                ) { _, newValue in newValue }
            )
            startupTraceRecorder.recordAppStartup(
                outcome == "succeeded"
                    ? "app.startup_diagnostic_action.completed"
                    : "app.startup_diagnostic_action.blocked",
                phase: "startup_diagnostic_action",
                outcome: outcome,
                attributes: startupDiagnosticTraceAttributes(for: action).merging(
                    renderProof.attributes
                ) { _, newValue in newValue }
            )
        }

        private func waitForBridgeFileViewObservabilitySmokeRenderProof(
            for controller: BridgePaneController,
            javaScript: String = AppDelegate.bridgeFileViewObservabilitySmokeRenderStateJavaScript,
            expectedBootstrapProtocol: String = "worktree-file"
        ) async -> BridgeFileViewObservabilitySmokeRenderProof {
            let clock = ContinuousClock()
            let start = clock.now
            var proof = await bridgeFileViewObservabilitySmokeRenderProof(
                for: controller,
                javaScript: javaScript,
                expectedBootstrapProtocol: expectedBootstrapProtocol
            )
            while !proof.succeeded
                && start.duration(to: clock.now) < AppPolicies.StartupDiagnostic.bridgeFileViewSmokeReadinessTimeout
            {
                try? await Task.sleep(nanoseconds: Duration.milliseconds(50).nanosecondsForTaskSleep)
                proof = await bridgeFileViewObservabilitySmokeRenderProof(
                    for: controller,
                    javaScript: javaScript,
                    expectedBootstrapProtocol: expectedBootstrapProtocol
                )
            }
            return proof
        }

        private func bridgeFileViewObservabilitySmokeRenderProof(
            for controller: BridgePaneController,
            javaScript: String,
            expectedBootstrapProtocol: String
        ) async -> BridgeFileViewObservabilitySmokeRenderProof {
            do {
                let result = try await controller.page.callJavaScript(
                    javaScript)
                guard let json = result as? String,
                    let data = json.data(using: .utf8)
                else {
                    return .unavailable()
                }
                let snapshot = try JSONDecoder().decode(
                    BridgeFileViewObservabilitySmokeRenderSnapshot.self,
                    from: data
                )
                return BridgeFileViewObservabilitySmokeRenderProof(
                    snapshot: snapshot,
                    expectedVisiblePaneCount: 1,
                    expectedBootstrapProtocol: expectedBootstrapProtocol
                )
            } catch {
                return .unavailable()
            }
        }

        nonisolated static var reviewToFileViewSmokeRenderJavaScript: String {
            """
            const bridgeFileViewModeSwitchTargets = ['file', 'review', 'file', 'review', 'file'];
            const bridgeFileViewModeSwitchProbe =
              window.__bridgeFileViewModeSwitchProbe &&
              typeof window.__bridgeFileViewModeSwitchProbe === 'object'
                ? window.__bridgeFileViewModeSwitchProbe
                : { count: 0 };
            const bridgeFileViewModeSwitchCount = Number.isFinite(Number(bridgeFileViewModeSwitchProbe.count))
              ? Number(bridgeFileViewModeSwitchProbe.count)
              : 0;
            if (bridgeFileViewModeSwitchCount < bridgeFileViewModeSwitchTargets.length) {
              const targetContext = bridgeFileViewModeSwitchTargets[bridgeFileViewModeSwitchCount];
              const targetContextButton = document.querySelector(
                `[data-testid="bridge-viewer-context-${targetContext}"]`
              );
              if (
                targetContextButton !== null &&
                targetContextButton.getAttribute('data-bridge-viewer-context-selected') !== 'true'
              ) {
                targetContextButton.click();
                window.__bridgeFileViewModeSwitchProbe = {
                  ...bridgeFileViewModeSwitchProbe,
                  count: bridgeFileViewModeSwitchCount + 1,
                  finalTarget: targetContext
                };
              }
            } else {
              const fileContextButton = document.querySelector('[data-testid="bridge-viewer-context-file"]');
              if (
                fileContextButton !== null &&
                fileContextButton.getAttribute('data-bridge-viewer-context-selected') !== 'true'
              ) {
                fileContextButton.click();
              }
            }
            \(bridgeFileViewObservabilitySmokeRenderStateJavaScript)
            """
        }

        nonisolated static var bridgeFileViewObservabilitySmokeRenderStateJavaScript: String {
            """
            return JSON.stringify((() => {
              const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
              const tree = document.querySelector('[data-testid="bridge-file-viewer-pierre-file-tree"]');
              const codeCanvas = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
              const codeViewPanel = document.querySelector('[data-testid="bridge-file-viewer-code-view"]');
              const bootstrapProtocol =
                document.documentElement.getAttribute('data-bridge-app-protocol') || 'missing';
              const bootstrapSourceSpecJSON =
                document.documentElement.getAttribute('data-bridge-worktree-file-source-spec');
              let bootstrapSourceSpecState = 'missing';
              let bootstrapSourceSpecLength = 0;
              if (bootstrapSourceSpecJSON !== null) {
                bootstrapSourceSpecLength = new TextEncoder().encode(bootstrapSourceSpecJSON).byteLength;
                try {
                  const parsedSourceSpec = JSON.parse(bootstrapSourceSpecJSON);
                  bootstrapSourceSpecState =
                    parsedSourceSpec &&
                    typeof parsedSourceSpec === 'object' &&
                    typeof parsedSourceSpec.clientRequestId === 'string' &&
                    typeof parsedSourceSpec.repoId === 'string' &&
                    typeof parsedSourceSpec.worktreeId === 'string' &&
                    typeof parsedSourceSpec.rootPathToken === 'string' &&
                    parsedSourceSpec.freshness === 'live'
                      ? 'parseable'
                      : 'invalid_shape';
                } catch {
                  bootstrapSourceSpecState = 'malformed_json';
                }
              }
              const filterCountText =
                document.querySelector('[data-testid="worktree-file-filter-count"]')?.textContent || '0/0';
              const descriptorCount = Number(filterCountText.split('/')[0] || '0');
              const totalDescriptorCount = Number(filterCountText.split('/')[1] || '0');
              const selectedDisplayPath = shell?.getAttribute('data-selected-display-path') || '';
              const treeExtentKind = shell?.getAttribute('data-worktree-tree-extent-kind') || 'missing';
              const treePathCount = Number(shell?.getAttribute('data-worktree-tree-path-count') || '0');
              const metadataTreeRowCount =
                Number(shell?.getAttribute('data-worktree-metadata-tree-row-count') || '0');
              const metadataFileRowCount =
                Number(shell?.getAttribute('data-worktree-metadata-file-row-count') || '0');
              const sourceState = shell?.getAttribute('data-worktree-source-state') || 'missing';
              const openFileState = codeCanvas?.getAttribute('data-worktree-open-file-state') || 'missing';
              const openFilePath = codeCanvas?.getAttribute('data-worktree-open-file-path') || '';
              const renderedFilePath = codeCanvas?.getAttribute('data-worktree-rendered-file-path') || '';
              const bodyPreviewLength =
                (codeCanvas?.getAttribute('data-worktree-open-file-body-preview') || '').length;
              const treeHeight = Math.round(Number(tree?.getAttribute('data-worktree-tree-total-size') || '0'));
              const codeViewPanelRect = codeViewPanel?.getBoundingClientRect();
              const queryRowsIncludingOpenShadowRoots = (root, selector) => {
                const rows = [];
                const pendingRoots = root === null ? [] : [root];
                while (pendingRoots.length > 0) {
                  const currentRoot = pendingRoots.shift();
                  rows.push(...currentRoot.querySelectorAll(selector));
                  for (const element of currentRoot.querySelectorAll('*')) {
                    if (element.shadowRoot !== null) {
                      pendingRoots.push(element.shadowRoot);
                    }
                  }
                }
                return rows;
              };
              const modeSwitchProbe =
                window.__bridgeFileViewModeSwitchProbe &&
                typeof window.__bridgeFileViewModeSwitchProbe === 'object'
                  ? window.__bridgeFileViewModeSwitchProbe
                  : {};
              const modeSwitchCount = Number.isFinite(Number(modeSwitchProbe.count))
                ? Number(modeSwitchProbe.count)
                : 0;
              const fileContextButton = document.querySelector('[data-testid="bridge-viewer-context-file"]');
              const finalFileContextSelected =
                fileContextButton?.getAttribute('data-bridge-viewer-context-selected') === 'true';
              const scrollStressProbe =
                window.__bridgeFileViewTreeScrollStressProbe &&
                typeof window.__bridgeFileViewTreeScrollStressProbe === 'object'
                  ? window.__bridgeFileViewTreeScrollStressProbe
                  : {};
              let treeScrollStressCount = Number.isFinite(Number(scrollStressProbe.count))
                ? Number(scrollStressProbe.count)
                : 0;
              let treeScrollStressReachedBottom = scrollStressProbe.reachedBottom === true;
              if (tree !== null && treeScrollStressCount < 4) {
                const scrollTargets = queryRowsIncludingOpenShadowRoots(
                  tree,
                  '[data-file-tree-virtualized-scroll="true"]'
                );
                const scrollTarget = scrollTargets[0] || tree;
                const maxTreeScrollTop = Math.max(0, scrollTarget.scrollHeight - scrollTarget.clientHeight);
                scrollTarget.scrollTop = treeScrollStressCount % 2 === 0 ? maxTreeScrollTop : 0;
                scrollTarget.dispatchEvent(new Event('scroll', { bubbles: true }));
                treeScrollStressReachedBottom =
                  treeScrollStressReachedBottom ||
                  maxTreeScrollTop === 0 ||
                  Math.abs(scrollTarget.scrollTop - maxTreeScrollTop) <= 2;
                treeScrollStressCount += 1;
                window.__bridgeFileViewTreeScrollStressProbe = {
                  count: treeScrollStressCount,
                  reachedBottom: treeScrollStressReachedBottom
                };
              }
                            const clickProbeState =
                              window.__bridgeFileViewClickProbe &&
                              typeof window.__bridgeFileViewClickProbe === 'object'
                                ? window.__bridgeFileViewClickProbe
                                : {};
                            let worktreeFileClickTargetPath =
                              typeof clickProbeState.targetPath === 'string' ? clickProbeState.targetPath : '';
                            let worktreeFileSecondClickTargetPath =
                              typeof clickProbeState.secondTargetPath === 'string' ? clickProbeState.secondTargetPath : '';
                            let worktreeFileSecondClickSelectedPath =
                              typeof clickProbeState.secondSelectedPath === 'string' ? clickProbeState.secondSelectedPath : '';
                            let worktreeFileSecondClickOpenFilePath =
                              typeof clickProbeState.secondOpenFilePath === 'string' ? clickProbeState.secondOpenFilePath : '';
                            let worktreeFileSecondClickRenderedFilePath =
                              typeof clickProbeState.secondRenderedFilePath === 'string' ? clickProbeState.secondRenderedFilePath : '';
                            let worktreeFileSecondClickBodyPreviewLength =
                              Number.isFinite(Number(clickProbeState.secondBodyPreviewLength))
                                ? Number(clickProbeState.secondBodyPreviewLength)
                                : 0;
                            let worktreeFileOffscreenClickTargetPath =
                              typeof clickProbeState.offscreenTargetPath === 'string' ? clickProbeState.offscreenTargetPath : '';
                            let worktreeFileOffscreenClickSelectedPath =
                              typeof clickProbeState.offscreenSelectedPath === 'string'
                                ? clickProbeState.offscreenSelectedPath
                                : '';
                            let worktreeFileOffscreenClickOpenFilePath =
                              typeof clickProbeState.offscreenOpenFilePath === 'string'
                                ? clickProbeState.offscreenOpenFilePath
                                : '';
                            let worktreeFileOffscreenClickRenderedFilePath =
                              typeof clickProbeState.offscreenRenderedFilePath === 'string'
                                ? clickProbeState.offscreenRenderedFilePath
                                : '';
                            let worktreeFileOffscreenClickBodyPreviewLength =
                              Number.isFinite(Number(clickProbeState.offscreenBodyPreviewLength))
                                ? Number(clickProbeState.offscreenBodyPreviewLength)
                                : 0;
                            let worktreeFileClickSelectedPath =
                              typeof clickProbeState.firstSelectedPath === 'string' ? clickProbeState.firstSelectedPath : '';
                            let worktreeFileClickOpenFilePath =
                              typeof clickProbeState.firstOpenFilePath === 'string' ? clickProbeState.firstOpenFilePath : '';
                            let worktreeFileClickRenderedFilePath =
                              typeof clickProbeState.firstRenderedFilePath === 'string' ? clickProbeState.firstRenderedFilePath : '';
                            let worktreeFileClickBodyPreviewLength =
                              Number.isFinite(Number(clickProbeState.firstBodyPreviewLength))
                                ? Number(clickProbeState.firstBodyPreviewLength)
                                : 0;
                            const firstClickHasConverged =
                              worktreeFileClickTargetPath.length > 0 &&
                              selectedDisplayPath === worktreeFileClickTargetPath &&
                              openFilePath === worktreeFileClickTargetPath &&
                              renderedFilePath === worktreeFileClickTargetPath &&
                              bodyPreviewLength > 0;
                            if (firstClickHasConverged && worktreeFileClickSelectedPath.length === 0) {
                              worktreeFileClickSelectedPath = selectedDisplayPath;
                              worktreeFileClickOpenFilePath = openFilePath;
                              worktreeFileClickRenderedFilePath = renderedFilePath;
                              worktreeFileClickBodyPreviewLength = bodyPreviewLength;
                              window.__bridgeFileViewClickProbe = {
                                ...clickProbeState,
                                targetPath: worktreeFileClickTargetPath,
                                firstSelectedPath: worktreeFileClickSelectedPath,
                                firstOpenFilePath: worktreeFileClickOpenFilePath,
                                firstRenderedFilePath: worktreeFileClickRenderedFilePath,
                                firstBodyPreviewLength: worktreeFileClickBodyPreviewLength
                              };
                            }
                            if (worktreeFileClickTargetPath.length === 0 && tree !== null && openFileState === 'ready') {
                              const fileRows = queryRowsIncludingOpenShadowRoots(
                                tree,
                                '[data-type="item"][data-item-type="file"][data-item-path]'
                              );
                const clickTarget = fileRows.find((row) => {
                  const path = row.getAttribute('data-item-path') || '';
                  return path.length > 0 && path !== selectedDisplayPath;
                });
                if (clickTarget !== undefined) {
                  worktreeFileClickTargetPath = clickTarget.getAttribute('data-item-path') || '';
                                window.__bridgeFileViewClickProbe = { targetPath: worktreeFileClickTargetPath };
                                clickTarget.scrollIntoView?.({ block: 'nearest' });
                                clickTarget.click();
                              }
                            }
                            if (
                              worktreeFileSecondClickTargetPath.length === 0 &&
                              firstClickHasConverged &&
                              tree !== null &&
                              openFileState === 'ready'
                            ) {
                              const fileRows = queryRowsIncludingOpenShadowRoots(
                                tree,
                                '[data-type="item"][data-item-type="file"][data-item-path]'
                              );
                              const secondClickTarget = fileRows.find((row) => {
                                const path = row.getAttribute('data-item-path') || '';
                                return (
                                  path.length > 0 &&
                                  path !== selectedDisplayPath &&
                                  path !== worktreeFileClickTargetPath
                                );
                              });
                              if (secondClickTarget !== undefined) {
                                worktreeFileSecondClickTargetPath =
                                  secondClickTarget.getAttribute('data-item-path') || '';
                                window.__bridgeFileViewClickProbe = {
                                  ...clickProbeState,
                                  targetPath: worktreeFileClickTargetPath,
                                  firstSelectedPath: worktreeFileClickSelectedPath,
                                  firstOpenFilePath: worktreeFileClickOpenFilePath,
                                  firstRenderedFilePath: worktreeFileClickRenderedFilePath,
                                  firstBodyPreviewLength: worktreeFileClickBodyPreviewLength,
                                  secondTargetPath: worktreeFileSecondClickTargetPath,
                                  secondSelectedPath: worktreeFileSecondClickSelectedPath,
                                  secondOpenFilePath: worktreeFileSecondClickOpenFilePath,
                                  secondRenderedFilePath: worktreeFileSecondClickRenderedFilePath,
                                  secondBodyPreviewLength: worktreeFileSecondClickBodyPreviewLength,
                                  offscreenTargetPath: worktreeFileOffscreenClickTargetPath,
                                  offscreenSelectedPath: worktreeFileOffscreenClickSelectedPath,
                                  offscreenOpenFilePath: worktreeFileOffscreenClickOpenFilePath,
                                  offscreenRenderedFilePath: worktreeFileOffscreenClickRenderedFilePath,
                                  offscreenBodyPreviewLength: worktreeFileOffscreenClickBodyPreviewLength
                                };
                                secondClickTarget.scrollIntoView?.({ block: 'nearest' });
                                secondClickTarget.click();
                              }
                            }
                            const secondClickHasConverged =
                              worktreeFileSecondClickTargetPath.length > 0 &&
                              selectedDisplayPath === worktreeFileSecondClickTargetPath &&
                              openFilePath === worktreeFileSecondClickTargetPath &&
                              renderedFilePath === worktreeFileSecondClickTargetPath &&
                              bodyPreviewLength > 0;
                            if (
                              secondClickHasConverged &&
                              worktreeFileSecondClickSelectedPath.length === 0
                            ) {
                              worktreeFileSecondClickSelectedPath = selectedDisplayPath;
                              worktreeFileSecondClickOpenFilePath = openFilePath;
                              worktreeFileSecondClickRenderedFilePath = renderedFilePath;
                              worktreeFileSecondClickBodyPreviewLength = bodyPreviewLength;
                              window.__bridgeFileViewClickProbe = {
                                ...clickProbeState,
                                targetPath: worktreeFileClickTargetPath,
                                firstSelectedPath: worktreeFileClickSelectedPath,
                                firstOpenFilePath: worktreeFileClickOpenFilePath,
                                firstRenderedFilePath: worktreeFileClickRenderedFilePath,
                                firstBodyPreviewLength: worktreeFileClickBodyPreviewLength,
                                secondTargetPath: worktreeFileSecondClickTargetPath,
                                secondSelectedPath: worktreeFileSecondClickSelectedPath,
                                secondOpenFilePath: worktreeFileSecondClickOpenFilePath,
                                secondRenderedFilePath: worktreeFileSecondClickRenderedFilePath,
                                secondBodyPreviewLength: worktreeFileSecondClickBodyPreviewLength,
                                offscreenTargetPath: worktreeFileOffscreenClickTargetPath,
                                offscreenSelectedPath: worktreeFileOffscreenClickSelectedPath,
                                offscreenOpenFilePath: worktreeFileOffscreenClickOpenFilePath,
                                offscreenRenderedFilePath: worktreeFileOffscreenClickRenderedFilePath,
                                offscreenBodyPreviewLength: worktreeFileOffscreenClickBodyPreviewLength
                              };
                            }
                            if (
                              worktreeFileOffscreenClickTargetPath.length === 0 &&
                              secondClickHasConverged &&
                              tree !== null &&
                              openFileState === 'ready'
                            ) {
                              const scrollTargets = queryRowsIncludingOpenShadowRoots(
                                tree,
                                '[data-file-tree-virtualized-scroll="true"]'
                              );
                              const scrollTarget = scrollTargets[0] || tree;
                              scrollTarget.scrollTop = scrollTarget.scrollHeight;
                              const fileRows = queryRowsIncludingOpenShadowRoots(
                                tree,
                                '[data-type="item"][data-item-type="file"][data-item-path]'
                              );
                              const offscreenClickTarget = [...fileRows].reverse().find((row) => {
                                const path = row.getAttribute('data-item-path') || '';
                                return (
                                  path.length > 0 &&
                                  path !== selectedDisplayPath &&
                                  path !== worktreeFileClickTargetPath &&
                                  path !== worktreeFileSecondClickTargetPath
                                );
                              });
                              if (offscreenClickTarget !== undefined) {
                                worktreeFileOffscreenClickTargetPath =
                                  offscreenClickTarget.getAttribute('data-item-path') || '';
                                window.__bridgeFileViewClickProbe = {
                                  ...clickProbeState,
                                  targetPath: worktreeFileClickTargetPath,
                                  firstSelectedPath: worktreeFileClickSelectedPath,
                                  firstOpenFilePath: worktreeFileClickOpenFilePath,
                                  firstRenderedFilePath: worktreeFileClickRenderedFilePath,
                                  firstBodyPreviewLength: worktreeFileClickBodyPreviewLength,
                                  secondTargetPath: worktreeFileSecondClickTargetPath,
                                  secondSelectedPath: worktreeFileSecondClickSelectedPath,
                                  secondOpenFilePath: worktreeFileSecondClickOpenFilePath,
                                  secondRenderedFilePath: worktreeFileSecondClickRenderedFilePath,
                                  secondBodyPreviewLength: worktreeFileSecondClickBodyPreviewLength,
                                  offscreenTargetPath: worktreeFileOffscreenClickTargetPath
                                };
                                offscreenClickTarget.scrollIntoView?.({ block: 'nearest' });
                                offscreenClickTarget.click();
                              }
                            }
                            const offscreenClickHasConverged =
                              worktreeFileOffscreenClickTargetPath.length > 0 &&
                              selectedDisplayPath === worktreeFileOffscreenClickTargetPath &&
                              openFilePath === worktreeFileOffscreenClickTargetPath &&
                              renderedFilePath === worktreeFileOffscreenClickTargetPath &&
                              bodyPreviewLength > 0;
                            if (
                              offscreenClickHasConverged &&
                              worktreeFileOffscreenClickSelectedPath.length === 0
                            ) {
                              worktreeFileOffscreenClickSelectedPath = selectedDisplayPath;
                              worktreeFileOffscreenClickOpenFilePath = openFilePath;
                              worktreeFileOffscreenClickRenderedFilePath = renderedFilePath;
                              worktreeFileOffscreenClickBodyPreviewLength = bodyPreviewLength;
                              window.__bridgeFileViewClickProbe = {
                                ...clickProbeState,
                                targetPath: worktreeFileClickTargetPath,
                                firstSelectedPath: worktreeFileClickSelectedPath,
                                firstOpenFilePath: worktreeFileClickOpenFilePath,
                                firstRenderedFilePath: worktreeFileClickRenderedFilePath,
                                firstBodyPreviewLength: worktreeFileClickBodyPreviewLength,
                                secondTargetPath: worktreeFileSecondClickTargetPath,
                                secondSelectedPath: worktreeFileSecondClickSelectedPath,
                                secondOpenFilePath: worktreeFileSecondClickOpenFilePath,
                                secondRenderedFilePath: worktreeFileSecondClickRenderedFilePath,
                                secondBodyPreviewLength: worktreeFileSecondClickBodyPreviewLength,
                                offscreenTargetPath: worktreeFileOffscreenClickTargetPath,
                                offscreenSelectedPath: worktreeFileOffscreenClickSelectedPath,
                                offscreenOpenFilePath: worktreeFileOffscreenClickOpenFilePath,
                                offscreenRenderedFilePath: worktreeFileOffscreenClickRenderedFilePath,
                                offscreenBodyPreviewLength: worktreeFileOffscreenClickBodyPreviewLength
                              };
                            }
                            const clickSelectedPath =
                              worktreeFileClickTargetPath.length > 0 ? worktreeFileClickSelectedPath : '';
                            const clickOpenFilePath =
                              worktreeFileClickTargetPath.length > 0 ? worktreeFileClickOpenFilePath : '';
                            const clickRenderedFilePath =
                              worktreeFileClickTargetPath.length > 0 ? worktreeFileClickRenderedFilePath : '';
                            const clickBodyPreviewLength =
                              worktreeFileClickTargetPath.length > 0 ? worktreeFileClickBodyPreviewLength : 0;
                            const secondClickSelectedPath =
                              worktreeFileSecondClickTargetPath.length > 0
                                ? worktreeFileSecondClickSelectedPath
                                : '';
                            const secondClickOpenFilePath =
                              worktreeFileSecondClickTargetPath.length > 0
                                ? worktreeFileSecondClickOpenFilePath
                                : '';
                            const secondClickRenderedFilePath =
                              worktreeFileSecondClickTargetPath.length > 0
                                ? worktreeFileSecondClickRenderedFilePath
                                : '';
                            const secondClickBodyPreviewLength =
                              worktreeFileSecondClickTargetPath.length > 0
                                ? worktreeFileSecondClickBodyPreviewLength
                                : 0;
                            const offscreenClickSelectedPath =
                              worktreeFileOffscreenClickTargetPath.length > 0
                                ? worktreeFileOffscreenClickSelectedPath
                                : '';
                            const offscreenClickOpenFilePath =
                              worktreeFileOffscreenClickTargetPath.length > 0
                                ? worktreeFileOffscreenClickOpenFilePath
                                : '';
                            const offscreenClickRenderedFilePath =
                              worktreeFileOffscreenClickTargetPath.length > 0
                                ? worktreeFileOffscreenClickRenderedFilePath
                                : '';
                            const offscreenClickBodyPreviewLength =
                              worktreeFileOffscreenClickTargetPath.length > 0
                                ? worktreeFileOffscreenClickBodyPreviewLength
                                : 0;
              const diffContainers = [...document.querySelectorAll('diffs-container')];
              const codeViewShadowText = diffContainers
                .map((element) => element.shadowRoot?.textContent || '')
                .join(' ');
              const codeText = `${codeCanvas?.textContent || ''} ${codeViewShadowText}`;
              const workerPoolState =
                document.documentElement.getAttribute('data-bridge-pierre-worker-pool-state') || 'missing';
              const workerPoolManagerState =
                document.documentElement.getAttribute('data-bridge-pierre-worker-pool-manager-state') || 'missing';
              const workerPoolWorkersFailed =
                document.documentElement.getAttribute('data-bridge-pierre-worker-pool-workers-failed') === 'true';
              const workerDiagnosticFileSuccessCount =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-file-success-count') || '0');
              const workerDiagnosticErrorCount =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-error-count') || '0');
              const errorProbe = Array.isArray(window.__bridgeErrorProbe)
                ? window.__bridgeErrorProbe
                : [];
              const commandProbe = Array.isArray(window.__bridgeCommandProbe)
                ? window.__bridgeCommandProbe
                : [];
              const intakeReadyCommandProbe = Array.isArray(window.__bridgeIntakeReadyCommandProbe)
                ? window.__bridgeIntakeReadyCommandProbe
                : [];
              const worktreeOpenSourceCommandProbe = Array.isArray(window.__bridgeWorktreeOpenSourceCommandProbe)
                ? window.__bridgeWorktreeOpenSourceCommandProbe
                : [];
              const worktreeDescriptorRequestCommandProbe = Array.isArray(window.__bridgeWorktreeDescriptorRequestCommandProbe)
                ? window.__bridgeWorktreeDescriptorRequestCommandProbe
                : [];
              const responseProbe = Array.isArray(window.__bridgeResponseProbe)
                ? window.__bridgeResponseProbe
                : [];
              const intakeProbe = Array.isArray(window.__bridgeIntakeProbe)
                ? window.__bridgeIntakeProbe
                : [];
              const nativeWorktreeProbe = Array.isArray(window.__bridgeNativeWorktreeFileProbe)
                ? window.__bridgeNativeWorktreeFileProbe
                : [];
              const lastNativeWorktreeProbeEntry = nativeWorktreeProbe.length > 0
                ? nativeWorktreeProbe[nativeWorktreeProbe.length - 1]
                : null;
              const clip = (value, limit) => String(value || '').slice(0, limit);
              const nativeWorktreeProbeFrameEvidenceCount = nativeWorktreeProbe.filter((entry) => {
                return (
                  clip(entry?.frameKind, 120).length > 0 &&
                  entry?.streamIdMatches === true
                );
              }).length;
              const nativeWorktreeProbeGeneration = (entry) => {
                const generation = Number(entry?.generation || 0);
                return Number.isFinite(generation) ? generation : 0;
              };
              const nativeWorktreeProbeReceiverGeneration = (entry) => {
                const generation = Number(entry?.receiverGeneration || 0);
                return Number.isFinite(generation) ? generation : 0;
              };
              const nativeWorktreeProbeHasFrameEvidence = (entry) => {
                return (
                  clip(entry?.frameKind, 120).length > 0 &&
                  entry?.streamIdMatches === true
                );
              };
              const nativeWorktreeProbeIsBenignOldGenerationCleanupDrop = (entry) => {
                return (
                  clip(entry?.reason, 120).startsWith('drop_') &&
                  clip(entry?.receiverReason, 120) === 'generation_mismatch' &&
                  nativeWorktreeProbeReceiverGeneration(entry) > nativeWorktreeProbeGeneration(entry)
                );
              };
              const nativeWorktreeProbeFailureDropCount = nativeWorktreeProbe.filter((entry) => {
                return (
                  clip(entry?.reason, 120).startsWith('drop_') &&
                  !nativeWorktreeProbeIsBenignOldGenerationCleanupDrop(entry)
                );
              }).length;
              const nativeWorktreeProbeFinalGeneration = nativeWorktreeProbe.reduce((maxGeneration, entry) => {
                return Math.max(
                  maxGeneration,
                  nativeWorktreeProbeGeneration(entry),
                  nativeWorktreeProbeReceiverGeneration(entry)
                );
              }, 0);
              const nativeWorktreeProbeFinalGenerationFrameEvidenceCount = nativeWorktreeProbe.filter((entry) => {
                return (
                  nativeWorktreeProbeHasFrameEvidence(entry) &&
                  nativeWorktreeProbeGeneration(entry) === nativeWorktreeProbeFinalGeneration
                );
              }).length;
              const classifyPageIssue = (entry) => {
                const kind = clip(entry?.kind, 80);
                const message = clip(entry?.message, 300);
                const worktreeFileFailureCode = message.match(/worktree_file\\.[a-z0-9_.-]+/u)?.[0] || '';
                if (worktreeFileFailureCode.length > 0) {
                  return worktreeFileFailureCode;
                }
                if (message.includes('Native Worktree/File command nonce is unavailable')) {
                  return 'native_command_nonce_unavailable';
                }
                if (message.includes('Native Worktree/File open stream timed out')) {
                  return 'native_open_timeout';
                }
                if (message.includes('Native Worktree/File open stream failed')) {
                  return 'native_open_failed';
                }
                if (message.includes('Native Worktree/File snapshot intake timed out')) {
                  return 'native_snapshot_intake_timeout';
                }
                if (message.includes('ZodError') || message.includes('Invalid input')) {
                  return 'schema_parse_failed';
                }
                if (kind === 'fetch_error') {
                  if (
                    message.includes('aborted') ||
                    message.includes('AbortError') ||
                    message.includes('concurrency_exceeded')
                  ) {
                    return 'context_switch_fetch_aborted';
                  }
                  return 'fetch_failed';
                }
                if (kind === 'unhandledrejection') {
                  return 'unhandled_rejection';
                }
                if (kind === 'error') {
                  return 'page_error';
                }
                return kind.length > 0 ? kind : 'none';
              };
              const lastPageIssue = errorProbe.length > 0
                ? errorProbe[errorProbe.length - 1]
                : null;
              const pageIssueLastKind = lastPageIssue === null
                ? 'none'
                : clip(lastPageIssue.kind, 80) || 'unknown';
              const pageIssueLastClass = lastPageIssue === null
                ? 'none'
                : classifyPageIssue(lastPageIssue);
              const pageIssueClasses = errorProbe.map(classifyPageIssue);
              const pageIssueDisallowedCount = pageIssueClasses.filter((pageIssueClass) => {
                return pageIssueClass !== 'context_switch_fetch_aborted';
              }).length;
              const worktreeOpenSourceCommandCount = worktreeOpenSourceCommandProbe.filter((entry) => {
                return entry?.method === 'worktreeFileSurface.openSourceStream';
              }).length;
              const intakeReadyCommandCount = intakeReadyCommandProbe.filter((entry) => {
                return entry?.method === 'bridge.intakeReady';
              }).length;
              const worktreeDescriptorRequestCommandCount = worktreeDescriptorRequestCommandProbe.filter((entry) => {
                return entry?.method === 'worktreeFileSurface.requestFileDescriptor';
              }).length;
              return {
                hasFileShell: shell !== null,
                hasTree: tree !== null,
                hasCodeViewPanel: codeViewPanel !== null,
                bootstrapProtocol,
                bootstrapSourceSpecState,
                bootstrapSourceSpecLength,
                descriptorCount,
                totalDescriptorCount,
                selectedDisplayPath,
                treeExtentKind,
                treePathCount,
                metadataTreeRowCount,
                metadataFileRowCount,
                sourceState,
                openFileState,
                openFilePath,
                renderedFilePath,
                bodyPreviewLength,
                clickTargetPath: worktreeFileClickTargetPath,
                clickSelectedPath,
                              clickOpenFilePath,
                              clickRenderedFilePath,
                              clickBodyPreviewLength,
                              secondClickTargetPath: worktreeFileSecondClickTargetPath,
                              secondClickSelectedPath,
                              secondClickOpenFilePath,
                              secondClickRenderedFilePath,
                              secondClickBodyPreviewLength,
                              offscreenClickTargetPath: worktreeFileOffscreenClickTargetPath,
                              offscreenClickSelectedPath,
                              offscreenClickOpenFilePath,
                              offscreenClickRenderedFilePath,
                              offscreenClickBodyPreviewLength,
                              modeSwitchCount,
                              finalFileContextSelected,
                              treeScrollStressCount,
                              treeScrollStressReachedBottom,
                              treeHeight,
                codeViewPanelWidth: Math.round(codeViewPanelRect?.width || 0),
                codeViewPanelHeight: Math.round(codeViewPanelRect?.height || 0),
                codeTextLength: codeText.length,
                workerPoolState,
                workerPoolManagerState,
                workerPoolWorkersFailed,
                workerDiagnosticFileSuccessCount,
                workerDiagnosticErrorCount,
                pageErrorCount: errorProbe.length,
                pageIssueLastKind,
                pageIssueLastClass,
                pageIssueDisallowedCount,
                bridgeCommandCount: commandProbe.length,
                worktreeOpenSourceCommandCount,
                intakeReadyCommandCount,
                worktreeDescriptorRequestCommandCount,
                bridgeResponseCount: responseProbe.length,
                intakeFrameCount: intakeProbe.length,
                nativeWorktreeProbeCount: nativeWorktreeProbe.length,
                nativeWorktreeProbeLastReason: clip(lastNativeWorktreeProbeEntry?.reason, 120) || 'none',
                nativeWorktreeProbeLastReceiverReason: clip(lastNativeWorktreeProbeEntry?.receiverReason, 120) || 'none',
                nativeWorktreeProbeLastFrameKind: clip(lastNativeWorktreeProbeEntry?.frameKind, 120) || 'none',
                nativeWorktreeProbeLastGeneration: Number(lastNativeWorktreeProbeEntry?.generation || 0),
                nativeWorktreeProbeLastReceiverGeneration: Number(lastNativeWorktreeProbeEntry?.receiverGeneration || 0),
                nativeWorktreeProbeLastSequence: Number(lastNativeWorktreeProbeEntry?.sequence || 0),
                nativeWorktreeProbeLastStreamIdMatches: lastNativeWorktreeProbeEntry?.streamIdMatches === true,
                nativeWorktreeProbeFrameEvidenceCount,
                nativeWorktreeProbeFinalGeneration,
                nativeWorktreeProbeFinalGenerationFrameEvidenceCount,
                nativeWorktreeProbeFailureDropCount
              };
            })())
            """
        }
    }
#endif
