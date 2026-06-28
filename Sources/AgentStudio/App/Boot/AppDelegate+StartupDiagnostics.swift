import AppKit
import Foundation

@MainActor
extension AppDelegate {
    func runStartupDiagnosticActionIfRequested() {
        guard let action = AgentStudioStartupDiagnosticAction.fromEnvironment() else { return }
        startupTraceRecorder.recordAppStartup(
            "app.startup_diagnostic_action.requested",
            phase: "startup_diagnostic_action",
            attributes: startupDiagnosticTraceAttributes(for: action)
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.dispatched",
                phase: "startup_diagnostic_action",
                attributes: self.startupDiagnosticTraceAttributes(for: action)
            )
            switch action.kind {
            case .newTab:
                AppCommandDispatcher.shared.dispatch(.newTab)
            case .commandBarRepoFilter:
                AppCommandDispatcher.shared.dispatch(.showCommandBarEverything)
                await Task.yield()
                self.commandBarController.state.rawInput = "# repo"
            #if DEBUG
                case .crossTabMoveGeometrySmoke:
                    await self.runCrossTabMoveGeometrySmokeDiagnostic(action: action)
                case .ipcTerminalSmoke:
                    await self.runIPCTerminalSmokeDiagnostic(action: action)
                case .bridgeReviewObservabilitySmoke:
                    await self.runBridgeReviewObservabilitySmokeDiagnostic(action: action)
            #endif
            case .addWatchFolder:
                guard let folderURL = AgentStudioStartupDiagnosticAction.watchFolderURL() else {
                    self.startupTraceRecorder.recordAppStartup(
                        "app.startup_diagnostic_action.skipped",
                        phase: "startup_diagnostic_action",
                        attributes: self.startupDiagnosticTraceAttributes(for: action).merging([
                            "agentstudio.startup_diagnostic.skip_reason": .string("missing_watch_folder")
                        ]) { _, newValue in newValue }
                    )
                    return
                }
                await self.handleWatchFolderRequested(startingAt: folderURL)
            }
        }
    }

    #if DEBUG
        private func runIPCTerminalSmokeDiagnostic(
            action: AgentStudioStartupDiagnosticAction
        ) async {
            NSApp.activate(ignoringOtherApps: true)
            mainWindowController?.window?.makeKeyAndOrderFront(nil)
            await waitForStartupDiagnosticAppActivation()

            guard let terminalContainerBounds = await startupDiagnosticLaunchRestoreBounds() else {
                startupTraceRecorder.recordAppStartup(
                    "app.startup_diagnostic_action.skipped",
                    phase: "startup_diagnostic_action",
                    outcome: "skipped",
                    attributes: startupDiagnosticTraceAttributes(for: action).merging([
                        "agentstudio.startup_diagnostic.skip_reason": .string("missing_bounds")
                    ]) { _, newValue in newValue }
                )
                return
            }

            if !launchRestoreObservationState.didComplete {
                await finishLaunchRestore(
                    using: terminalContainerBounds,
                    source: "ipcTerminalSmokePreflight"
                )
            }

            guard
                let pane = workspaceSurfaceCoordinator.openFloatingTerminal(
                    launchDirectory: FileManager.default.homeDirectoryForCurrentUser,
                    title: "IPC Smoke Terminal"
                )
            else {
                startupTraceRecorder.recordAppStartup(
                    "app.startup_diagnostic_action.blocked",
                    phase: "startup_diagnostic_action",
                    outcome: "blocked",
                    attributes: startupDiagnosticTraceAttributes(for: action).merging([
                        "agentstudio.startup_diagnostic.skip_reason": .string("terminal_open_failed")
                    ]) { _, newValue in newValue }
                )
                return
            }

            await workspaceSurfaceCoordinator.restoreAllViews(in: terminalContainerBounds)
            await Task.yield()
            mainWindowController?.syncVisibleTerminalGeometry(reason: "ipcTerminalSmoke")
            let renderProof = await waitForIPCTerminalSmokeRenderProof(for: pane.id)
            guard renderProof.succeeded else {
                startupTraceRecorder.recordAppStartup(
                    "app.startup_diagnostic_action.blocked",
                    phase: "startup_diagnostic_action",
                    outcome: "blocked",
                    attributes: startupDiagnosticTraceAttributes(for: action).merging(
                        [
                            "agentstudio.startup_diagnostic.created_pane.count": .int(1),
                            "agentstudio.startup_diagnostic.pane.id": .string(pane.id.uuidString),
                        ].merging(renderProof.attributes) { _, newValue in newValue }
                    ) { _, newValue in newValue }
                )
                return
            }
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.command_exercised",
                phase: "startup_diagnostic_action",
                outcome: "succeeded",
                attributes: startupDiagnosticTraceAttributes(for: action).merging(
                    [
                        "agentstudio.startup_diagnostic.created_pane.count": .int(1),
                        "agentstudio.startup_diagnostic.pane.id": .string(pane.id.uuidString),
                    ].merging(renderProof.attributes) { _, newValue in newValue }
                ) { _, newValue in newValue }
            )
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.completed",
                phase: "startup_diagnostic_action",
                outcome: "succeeded",
                attributes: startupDiagnosticTraceAttributes(for: action).merging(
                    [
                        "agentstudio.startup_diagnostic.created_pane.count": .int(1),
                        "agentstudio.startup_diagnostic.pane.id": .string(pane.id.uuidString),
                    ].merging(renderProof.attributes) { _, newValue in newValue }
                ) { _, newValue in newValue }
            )
        }

        private func runBridgeReviewObservabilitySmokeDiagnostic(
            action: AgentStudioStartupDiagnosticAction
        ) async {
            recordBridgeReviewObservabilitySmokePhase("activation_started", action: action)
            NSApp.activate(ignoringOtherApps: true)
            mainWindowController?.window?.makeKeyAndOrderFront(nil)
            recordBridgeReviewObservabilitySmokePhase("window_ordered", action: action)
            await waitForStartupDiagnosticAppActivation()
            recordBridgeReviewObservabilitySmokePhase("activation_wait_finished", action: action)
            recordBridgeReviewObservabilitySmokePhase("bounds_wait_started", action: action)

            guard let terminalContainerBounds = await startupDiagnosticLaunchRestoreBounds() else {
                startupTraceRecorder.recordAppStartup(
                    "app.startup_diagnostic_action.skipped",
                    phase: "startup_diagnostic_action",
                    outcome: "skipped",
                    attributes: startupDiagnosticTraceAttributes(for: action).merging([
                        "agentstudio.startup_diagnostic.skip_reason": .string("missing_bounds")
                    ]) { _, newValue in newValue }
                )
                return
            }
            recordBridgeReviewObservabilitySmokePhase("bounds_ready", action: action)

            if !launchRestoreObservationState.didComplete {
                recordBridgeReviewObservabilitySmokePhase("launch_restore_started", action: action)
                await finishLaunchRestore(
                    using: terminalContainerBounds,
                    source: "bridgeReviewObservabilitySmokePreflight"
                )
                recordBridgeReviewObservabilitySmokePhase("launch_restore_finished", action: action)
            }

            recordBridgeReviewObservabilitySmokePhase("pane_open_started", action: action)
            guard let pane = workspaceSurfaceCoordinator.openBridgeReviewObservabilitySmoke() else {
                startupTraceRecorder.recordAppStartup(
                    "app.startup_diagnostic_action.blocked",
                    phase: "startup_diagnostic_action",
                    outcome: "blocked",
                    attributes: startupDiagnosticTraceAttributes(for: action).merging([
                        "agentstudio.startup_diagnostic.skip_reason": .string("bridge_pane_creation_failed")
                    ]) { _, newValue in newValue }
                )
                return
            }
            recordBridgeReviewObservabilitySmokePhase("pane_opened", action: action)

            recordBridgeReviewObservabilitySmokePhase("restore_views_started", action: action)
            workspaceSurfaceCoordinator.restoreVisiblePaneIfNeeded(pane.id, forceWhenBoundsExist: true)
            await Task.yield()
            recordBridgeReviewObservabilitySmokePhase("restore_views_finished", action: action)

            guard
                let bridgeView = viewRegistry.view(for: pane.id)?
                    .mountedContent(as: BridgePaneMountView.self)
            else {
                startupTraceRecorder.recordAppStartup(
                    "app.startup_diagnostic_action.blocked",
                    phase: "startup_diagnostic_action",
                    outcome: "blocked",
                    attributes: startupDiagnosticTraceAttributes(for: action).merging([
                        "agentstudio.startup_diagnostic.skip_reason": .string("bridge_view_missing")
                    ]) { _, newValue in newValue }
                )
                return
            }
            recordBridgeReviewObservabilitySmokePhase("bridge_view_mounted", action: action)

            let commandId = UUIDv7.generate()
            recordBridgeReviewObservabilitySmokePhase("load_diff_started", action: action)
            let result = await bridgeView.controller.handleDiffCommand(
                .loadDiff(
                    DiffArtifact(
                        diffId: BridgeObservabilitySmokeReviewSourceProvider.diffId,
                        worktreeId: BridgeObservabilitySmokeReviewSourceProvider.worktreeId,
                        patchData: Data()
                    )
                ),
                commandId: commandId,
                correlationId: nil
            )
            recordBridgeReviewObservabilitySmokePhase("load_diff_finished", action: action)
            switch result {
            case .failure where bridgeView.controller.paneState.diff.status == .error:
                let renderProof = BridgeReviewObservabilitySmokeRenderProof.unavailable()
                recordBridgeReviewObservabilitySmokeDiagnosticResult(
                    action: action,
                    outcome: "blocked",
                    renderProof: renderProof
                )
                return
            case .success, .queued, .failure:
                recordBridgeReviewObservabilitySmokePhase("render_proof_started", action: action)
                let renderProof = await waitForBridgeReviewObservabilitySmokeRenderProof(
                    for: bridgeView.controller
                )
                recordBridgeReviewObservabilitySmokePhase("render_proof_finished", action: action)
                recordBridgeReviewObservabilitySmokeDiagnosticResult(
                    action: action,
                    outcome: renderProof.succeeded ? "succeeded" : "blocked",
                    renderProof: renderProof
                )
                return
            }
        }

        private func recordBridgeReviewObservabilitySmokePhase(
            _ phase: String,
            action: AgentStudioStartupDiagnosticAction
        ) {
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.bridge_smoke.\(phase)",
                phase: "startup_diagnostic_action",
                attributes: startupDiagnosticTraceAttributes(for: action)
            )
        }

        private func recordBridgeReviewObservabilitySmokeDiagnosticResult(
            action: AgentStudioStartupDiagnosticAction,
            outcome: String,
            renderProof: BridgeReviewObservabilitySmokeRenderProof
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

        private func waitForBridgeReviewObservabilitySmokeRenderProof(
            for controller: BridgePaneController
        ) async -> BridgeReviewObservabilitySmokeRenderProof {
            let clock = ContinuousClock()
            let start = clock.now
            var proof = await bridgeReviewObservabilitySmokeRenderProof(for: controller)
            while !proof.succeeded
                && start.duration(to: clock.now) < AppPolicies.StartupDiagnostic.ipcTerminalSmokeReadinessTimeout
            {
                try? await Task.sleep(nanoseconds: Duration.milliseconds(50).nanosecondsForTaskSleep)
                proof = await bridgeReviewObservabilitySmokeRenderProof(for: controller)
            }
            return proof
        }

        private func bridgeReviewObservabilitySmokeRenderProof(
            for controller: BridgePaneController
        ) async -> BridgeReviewObservabilitySmokeRenderProof {
            do {
                let result = try await controller.page.callJavaScript(
                    Self.bridgeReviewObservabilitySmokeRenderStateJavaScript)
                guard let json = result as? String,
                    let data = json.data(using: .utf8)
                else {
                    return .unavailable()
                }
                let snapshot = try JSONDecoder().decode(
                    BridgeReviewObservabilitySmokeRenderSnapshot.self,
                    from: data
                )
                return BridgeReviewObservabilitySmokeRenderProof(
                    expectedVisiblePaneCount: 1,
                    hasReviewShell: snapshot.hasReviewShell,
                    hasCodeViewPanel: snapshot.hasCodeViewPanel,
                    hasSelectedItem: snapshot.hasSelectedItem,
                    hasSelectedDisplayPath: snapshot.hasSelectedDisplayPath,
                    hasSelectedContentText: snapshot.hasSelectedContentText,
                    selectedContentState: snapshot.selectedContentState,
                    selectedContentRoleCount: snapshot.selectedContentRoleCount,
                    selectedContentCacheKeyCount: snapshot.selectedContentCacheKeyCount,
                    selectedContentCharacterCount: snapshot.selectedContentCharacterCount,
                    selectedContentLineCount: snapshot.selectedContentLineCount,
                    selectedMaterializedUpdateResult: snapshot.selectedMaterializedUpdateResult,
                    selectedMaterializedItemType: snapshot.selectedMaterializedItemType,
                    selectedMaterializedItemVersion: snapshot.selectedMaterializedItemVersion,
                    selectedMaterializedAdditionLineCount: snapshot.selectedMaterializedAdditionLineCount,
                    selectedMaterializedDeletionLineCount: snapshot.selectedMaterializedDeletionLineCount,
                    selectedMaterializedFileLineCount: snapshot.selectedMaterializedFileLineCount,
                    pageErrorCount: snapshot.pageErrorCount,
                    diffContainerCount: snapshot.diffContainerCount,
                    codeLineCount: snapshot.codeLineCount,
                    codeViewPanelWidth: snapshot.codeViewPanelWidth,
                    codeViewPanelHeight: snapshot.codeViewPanelHeight,
                    firstDiffContainerWidth: snapshot.firstDiffContainerWidth,
                    firstDiffContainerHeight: snapshot.firstDiffContainerHeight,
                    codeViewScrollOwnerHeight: snapshot.codeViewScrollOwnerHeight,
                    codeViewScrollOwnerScrollHeight: snapshot.codeViewScrollOwnerScrollHeight,
                    codeViewScrollOwnerChildCount: snapshot.codeViewScrollOwnerChildCount,
                    codeViewScrollOwnerFirstChildTag: snapshot.codeViewScrollOwnerFirstChildTag,
                    codeViewInstanceHeight: snapshot.codeViewInstanceHeight,
                    codeViewInstanceScrollHeight: snapshot.codeViewInstanceScrollHeight,
                    codeViewInstanceItemCount: snapshot.codeViewInstanceItemCount,
                    codeViewInstanceWindowTop: snapshot.codeViewInstanceWindowTop,
                    codeViewInstanceWindowBottom: snapshot.codeViewInstanceWindowBottom,
                    codeViewInstanceFirstRenderedIndex: snapshot.codeViewInstanceFirstRenderedIndex,
                    codeViewInstanceLastRenderedIndex: snapshot.codeViewInstanceLastRenderedIndex,
                    codeViewInstanceFirstItemHeight: snapshot.codeViewInstanceFirstItemHeight,
                    codeViewInstanceFirstItemTop: snapshot.codeViewInstanceFirstItemTop,
                    codeViewRenderedItemCount: snapshot.codeViewRenderedItemCount,
                    codeViewRenderedItemElementHeight: snapshot.codeViewRenderedItemElementHeight,
                    codeViewRenderedItemElementChildCount: snapshot.codeViewRenderedItemElementChildCount,
                    codeViewRenderedItemElementFirstChildTag: snapshot.codeViewRenderedItemElementFirstChildTag,
                    codeViewRenderedItemType: snapshot.codeViewRenderedItemType,
                    codeViewRenderedItemVersion: snapshot.codeViewRenderedItemVersion,
                    firstDiffContainerShadowChildCount: snapshot.firstDiffContainerShadowChildCount,
                    firstDiffContainerPreCount: snapshot.firstDiffContainerPreCount,
                    firstDiffContainerOffsetHeight: snapshot.firstDiffContainerOffsetHeight,
                    firstDiffContainerScrollHeight: snapshot.firstDiffContainerScrollHeight,
                    firstDiffContainerPreHeight: snapshot.firstDiffContainerPreHeight,
                    firstDiffContainerPreTextLength: snapshot.firstDiffContainerPreTextLength,
                    codeLineWithDataLineCount: snapshot.codeLineWithDataLineCount,
                    firstDiffContainerDisplay: snapshot.firstDiffContainerDisplay,
                    workerPoolState: snapshot.workerPoolState,
                    workerPoolManagerState: snapshot.workerPoolManagerState,
                    workerPoolWorkersFailed: snapshot.workerPoolWorkersFailed,
                    workerPoolTotalWorkers: snapshot.workerPoolTotalWorkers,
                    workerPoolBusyWorkers: snapshot.workerPoolBusyWorkers,
                    workerPoolQueuedTasks: snapshot.workerPoolQueuedTasks,
                    workerPoolActiveTasks: snapshot.workerPoolActiveTasks,
                    workerPoolFileCacheSize: snapshot.workerPoolFileCacheSize,
                    workerPoolDiffCacheSize: snapshot.workerPoolDiffCacheSize,
                    workerPoolInitializationProbeStage: snapshot.workerPoolInitializationProbeStage,
                    workerPoolInitializationProbeThemeCount: snapshot.workerPoolInitializationProbeThemeCount,
                    workerPoolInitializationProbeLanguageCount: snapshot.workerPoolInitializationProbeLanguageCount,
                    workerPoolInitializationProbeFailureReason: snapshot.workerPoolInitializationProbeFailureReason,
                    workerDiagnosticBootstrapState: snapshot.workerDiagnosticBootstrapState,
                    workerDiagnosticInitializeRequestIdState: snapshot.workerDiagnosticInitializeRequestIdState,
                    workerDiagnosticLastMessageType: snapshot.workerDiagnosticLastMessageType,
                    workerDiagnosticLastRequestType: snapshot.workerDiagnosticLastRequestType,
                    workerDiagnosticLastSuccessMatchesInitializeRequest: snapshot
                        .workerDiagnosticLastSuccessMatchesInitializeRequest,
                    workerDiagnosticLastSuccessIdState: snapshot.workerDiagnosticLastSuccessIdState,
                    workerDiagnosticLastSuccessIdPrefix: snapshot.workerDiagnosticLastSuccessIdPrefix,
                    workerDiagnosticLastSuccessRequestType: snapshot.workerDiagnosticLastSuccessRequestType,
                    workerDiagnosticSuccessCount: snapshot.workerDiagnosticSuccessCount,
                    workerDiagnosticInitializeSuccessCount: snapshot.workerDiagnosticInitializeSuccessCount,
                    workerDiagnosticDiffSuccessCount: snapshot.workerDiagnosticDiffSuccessCount,
                    workerDiagnosticFileSuccessCount: snapshot.workerDiagnosticFileSuccessCount,
                    workerDiagnosticForwardedMessageCount: snapshot.workerDiagnosticForwardedMessageCount,
                    workerDiagnosticLastForwardResult: snapshot.workerDiagnosticLastForwardResult,
                    workerDiagnosticErrorCount: snapshot.workerDiagnosticErrorCount,
                    workerDiagnosticLastErrorKind: snapshot.workerDiagnosticLastErrorKind,
                    codeTextLength: snapshot.codeTextLength,
                    codeShadowTextLength: snapshot.codeShadowTextLength
                )
            } catch {
                return .unavailable()
            }
        }

        nonisolated static var bridgeReviewObservabilitySmokeRenderStateJavaScript: String {
            """
            return JSON.stringify((() => {
              const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
              const codeViewPanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
              const codeViewScrollOwner = document.querySelector('.bridge-code-view-scroll-owner');
              const codeViewInstance = window.__INSTANCE || null;
              const codeViewWindowSpecs = codeViewInstance?.getWindowSpecs?.() || null;
              const codeViewRenderState = codeViewInstance?.renderState || null;
              const firstCodeViewInstanceItem = codeViewInstance?.items?.[0] || null;
              const codeViewRenderedItems = codeViewInstance?.getRenderedItems?.() || [];
              const firstCodeViewRenderedItem = codeViewRenderedItems[0] || null;
              const firstCodeViewRenderedItemElement = firstCodeViewRenderedItem?.element || null;
              const firstCodeViewRenderedItemElementRect = firstCodeViewRenderedItemElement?.getBoundingClientRect();
              const selectedItemId = codeViewPanel?.getAttribute('data-selected-item-id') || '';
              const selectedDisplayPath = codeViewPanel?.getAttribute('data-selected-display-path') || '';
              const selectedContentState = codeViewPanel?.getAttribute('data-selected-content-state') || 'missing';
              const selectedContentRoleCount = Number(codeViewPanel?.getAttribute('data-selected-content-role-count') || '0');
              const selectedContentCacheKeyCount = Number(codeViewPanel?.getAttribute('data-selected-content-cache-key-count') || '0');
              const selectedContentCharacterCount = Number(codeViewPanel?.getAttribute('data-selected-content-character-count') || '0');
              const selectedContentLineCount = Number(codeViewPanel?.getAttribute('data-selected-content-line-count') || '0');
              const selectedMaterializedUpdateResult = codeViewPanel?.getAttribute('data-selected-materialized-update-result') || 'missing';
              const selectedMaterializedItemType = codeViewPanel?.getAttribute('data-selected-materialized-item-type') || 'missing';
              const selectedMaterializedItemVersion = Number(codeViewPanel?.getAttribute('data-selected-materialized-item-version') || '0');
              const selectedMaterializedAdditionLineCount = Number(codeViewPanel?.getAttribute('data-selected-materialized-addition-line-count') || '0');
              const selectedMaterializedDeletionLineCount = Number(codeViewPanel?.getAttribute('data-selected-materialized-deletion-line-count') || '0');
              const selectedMaterializedFileLineCount = Number(codeViewPanel?.getAttribute('data-selected-materialized-file-line-count') || '0');
              const selectedMaterializedLineCount =
                selectedMaterializedAdditionLineCount +
                selectedMaterializedDeletionLineCount +
                selectedMaterializedFileLineCount;
              const panelRect = codeViewPanel?.getBoundingClientRect();
              const codeViewScrollOwnerRect = codeViewScrollOwner?.getBoundingClientRect();
              const diffContainers = [...document.querySelectorAll('diffs-container')];
              const firstDiffContainer = diffContainers[0] || null;
              const firstDiffContainerRect = diffContainers[0]?.getBoundingClientRect();
              const firstDiffContainerPre = firstDiffContainer?.shadowRoot?.querySelector('pre') || null;
              const firstDiffContainerPreRect = firstDiffContainerPre?.getBoundingClientRect();
              const codeLineElements = diffContainers.flatMap((element) =>
                element.shadowRoot === null ? [] : [...element.shadowRoot.querySelectorAll('[data-line-index]')]
              );
              const codeLineWithDataLineElements = diffContainers.flatMap((element) =>
                element.shadowRoot === null ? [] : [...element.shadowRoot.querySelectorAll('[data-line][data-line-index]')]
              );
              const firstShadowRoot = firstDiffContainer?.shadowRoot || null;
              const codeViewPanelWidth = Math.round(panelRect?.width || 0);
              const codeViewPanelHeight = Math.round(panelRect?.height || 0);
              const codeViewScrollOwnerHeight = Math.round(codeViewScrollOwnerRect?.height || 0);
              const codeViewScrollOwnerScrollHeight = Math.round(codeViewScrollOwner?.scrollHeight || 0);
              const codeViewScrollOwnerChildCount = codeViewScrollOwner?.children.length || 0;
              const codeViewScrollOwnerFirstChildTag =
                codeViewScrollOwner?.firstElementChild?.tagName?.toLowerCase() || 'missing';
              const codeViewInstanceHeight = Math.round(codeViewInstance?.getHeight?.() || 0);
              const codeViewInstanceScrollHeight = Math.round(codeViewInstance?.getScrollHeight?.() || 0);
              const codeViewInstanceItemCount = codeViewInstance?.items?.length || 0;
              const codeViewInstanceWindowTop = Math.round(codeViewWindowSpecs?.top || 0);
              const codeViewInstanceWindowBottom = Math.round(codeViewWindowSpecs?.bottom || 0);
              const codeViewInstanceFirstRenderedIndex = Number(codeViewRenderState?.firstIndex ?? -1);
              const codeViewInstanceLastRenderedIndex = Number(codeViewRenderState?.lastIndex ?? -1);
              const codeViewInstanceFirstItemHeight = Math.round(firstCodeViewInstanceItem?.height || 0);
              const codeViewInstanceFirstItemTop = Math.round(firstCodeViewInstanceItem?.top || 0);
              const codeViewRenderedItemCount = codeViewRenderedItems.length;
              const codeViewRenderedItemElementHeight = Math.round(firstCodeViewRenderedItemElementRect?.height || 0);
              const codeViewRenderedItemElementChildCount = firstCodeViewRenderedItemElement?.children.length || 0;
              const codeViewRenderedItemElementFirstChildTag =
                firstCodeViewRenderedItemElement?.firstElementChild?.tagName?.toLowerCase() || 'missing';
              const codeViewRenderedItemType = firstCodeViewRenderedItem?.type || 'missing';
              const codeViewRenderedItemVersion = Number(firstCodeViewRenderedItem?.version || 0);
              const firstDiffContainerWidth = Math.round(firstDiffContainerRect?.width || 0);
              const firstDiffContainerHeight = Math.round(firstDiffContainerRect?.height || 0);
              const firstDiffContainerOffsetHeight = Math.round(firstDiffContainer?.offsetHeight || 0);
              const firstDiffContainerScrollHeight = Math.round(firstDiffContainer?.scrollHeight || 0);
              const firstDiffContainerShadowChildCount = firstShadowRoot?.children.length || 0;
              const firstDiffContainerPreCount = firstShadowRoot?.querySelectorAll('pre').length || 0;
              const firstDiffContainerPreHeight = Math.round(firstDiffContainerPreRect?.height || 0);
              const firstDiffContainerPreTextLength = firstDiffContainerPre?.textContent?.length || 0;
              const firstDiffContainerDisplay =
                firstDiffContainer === null ? 'missing' : window.getComputedStyle(firstDiffContainer).display;
              const workerPoolState =
                document.documentElement.getAttribute('data-bridge-pierre-worker-pool-state') || 'missing';
              const workerPoolManagerState =
                document.documentElement.getAttribute('data-bridge-pierre-worker-pool-manager-state') || 'missing';
              const workerPoolWorkersFailed =
                document.documentElement.getAttribute('data-bridge-pierre-worker-pool-workers-failed') === 'true';
              const workerPoolTotalWorkers =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-pool-total-workers') || '0');
              const workerPoolBusyWorkers =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-pool-busy-workers') || '0');
              const workerPoolQueuedTasks =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-pool-queued-tasks') || '0');
              const workerPoolActiveTasks =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-pool-active-tasks') || '0');
              const workerPoolFileCacheSize =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-pool-file-cache-size') || '0');
              const workerPoolDiffCacheSize =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-pool-diff-cache-size') || '0');
              const workerPoolInitializationProbeStage =
                document.documentElement.getAttribute('data-bridge-pierre-worker-pool-init-probe-stage') || 'missing';
              const workerPoolInitializationProbeThemeCount =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-pool-init-probe-theme-count') || '0');
              const workerPoolInitializationProbeLanguageCount =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-pool-init-probe-language-count') || '0');
              const workerPoolInitializationProbeFailureReason =
                document.documentElement.getAttribute('data-bridge-pierre-worker-pool-init-probe-failure-reason') || '';
              const workerDiagnosticBootstrapState =
                document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-bootstrap-state') || 'missing';
              const workerDiagnosticInitializeRequestIdState =
                document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-initialize-request-id-state') || 'missing';
              const workerDiagnosticLastMessageType =
                document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-last-message-type') || 'missing';
              const workerDiagnosticLastRequestType =
                document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-last-request-type') || 'missing';
              const workerDiagnosticLastSuccessMatchesInitializeRequest =
                document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-last-success-matches-initialize-request') || 'missing';
              const workerDiagnosticLastSuccessIdState =
                document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-last-success-id-state') || 'missing';
              const workerDiagnosticLastSuccessIdPrefix =
                document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-last-success-id-prefix') || 'none';
              const workerDiagnosticLastSuccessRequestType =
                document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-last-success-request-type') || 'missing';
              const workerDiagnosticSuccessCount =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-success-count') || '0');
              const workerDiagnosticInitializeSuccessCount =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-initialize-success-count') || '0');
              const workerDiagnosticDiffSuccessCount =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-diff-success-count') || '0');
              const workerDiagnosticFileSuccessCount =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-file-success-count') || '0');
              const workerDiagnosticForwardedMessageCount =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-forwarded-message-count') || '0');
              const workerDiagnosticLastForwardResult =
                document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-last-forward-result') || 'missing';
              const workerDiagnosticErrorCount =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-error-count') || '0');
              const workerDiagnosticLastErrorKind =
                document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-last-error-kind') || 'none';
              const codeViewShadowText = diffContainers
                .map((element) => element.shadowRoot?.textContent || '')
                .join(' ');
              const codeText = `${codeViewPanel?.textContent || ''} ${codeViewShadowText}`;
              const errorProbe = Array.isArray(window.__bridgeErrorProbe)
                ? window.__bridgeErrorProbe
                : [];
              return {
                hasReviewShell: reviewShell !== null,
                hasCodeViewPanel: codeViewPanel !== null,
                hasSelectedItem: selectedItemId.length > 0,
                hasSelectedDisplayPath: selectedDisplayPath.length > 0,
                hasSelectedContentText:
                  selectedContentState === 'ready' &&
                  selectedContentRoleCount > 0 &&
                  selectedContentCacheKeyCount > 0 &&
                  selectedContentCharacterCount > 0 &&
                  selectedContentLineCount > 0 &&
                  selectedMaterializedUpdateResult === 'updated' &&
                  selectedMaterializedItemVersion > 0 &&
                  selectedMaterializedLineCount > 0 &&
                  codeViewRenderedItemCount > 0 &&
                  codeViewInstanceFirstItemHeight > 0 &&
                  codeText.length > 0 &&
                  codeViewShadowText.length > 0 &&
                  firstDiffContainerWidth > 0 &&
                  workerPoolState === 'ready',
                selectedContentState,
                selectedContentRoleCount,
                selectedContentCacheKeyCount,
                selectedContentCharacterCount,
                selectedContentLineCount,
                selectedMaterializedUpdateResult,
                selectedMaterializedItemType,
                selectedMaterializedItemVersion,
                selectedMaterializedAdditionLineCount,
                selectedMaterializedDeletionLineCount,
                selectedMaterializedFileLineCount,
                pageErrorCount: errorProbe.length,
                diffContainerCount: diffContainers.length,
                codeLineCount: codeLineElements.length,
                codeViewPanelWidth,
                codeViewPanelHeight,
                firstDiffContainerWidth,
                firstDiffContainerHeight,
                codeViewScrollOwnerHeight,
                codeViewScrollOwnerScrollHeight,
                codeViewScrollOwnerChildCount,
                codeViewScrollOwnerFirstChildTag,
                codeViewInstanceHeight,
                codeViewInstanceScrollHeight,
                codeViewInstanceItemCount,
                codeViewInstanceWindowTop,
                codeViewInstanceWindowBottom,
                codeViewInstanceFirstRenderedIndex,
                codeViewInstanceLastRenderedIndex,
                codeViewInstanceFirstItemHeight,
                codeViewInstanceFirstItemTop,
                codeViewRenderedItemCount,
                codeViewRenderedItemElementHeight,
                codeViewRenderedItemElementChildCount,
                codeViewRenderedItemElementFirstChildTag,
                codeViewRenderedItemType,
                codeViewRenderedItemVersion,
                firstDiffContainerShadowChildCount,
                firstDiffContainerPreCount,
                firstDiffContainerOffsetHeight,
                firstDiffContainerScrollHeight,
                firstDiffContainerPreHeight,
                firstDiffContainerPreTextLength,
                codeLineWithDataLineCount: codeLineWithDataLineElements.length,
                firstDiffContainerDisplay,
                workerPoolState,
                workerPoolManagerState,
                workerPoolWorkersFailed,
                workerPoolTotalWorkers,
                workerPoolBusyWorkers,
                workerPoolQueuedTasks,
                workerPoolActiveTasks,
                workerPoolFileCacheSize,
                workerPoolDiffCacheSize,
                workerPoolInitializationProbeStage,
                workerPoolInitializationProbeThemeCount,
                workerPoolInitializationProbeLanguageCount,
                workerPoolInitializationProbeFailureReason,
                workerDiagnosticBootstrapState,
                workerDiagnosticInitializeRequestIdState,
                workerDiagnosticLastMessageType,
                workerDiagnosticLastRequestType,
                workerDiagnosticLastSuccessMatchesInitializeRequest,
                workerDiagnosticLastSuccessIdState,
                workerDiagnosticLastSuccessIdPrefix,
                workerDiagnosticLastSuccessRequestType,
                workerDiagnosticSuccessCount,
                workerDiagnosticInitializeSuccessCount,
                workerDiagnosticDiffSuccessCount,
                workerDiagnosticFileSuccessCount,
                workerDiagnosticForwardedMessageCount,
                workerDiagnosticLastForwardResult,
                workerDiagnosticErrorCount,
                workerDiagnosticLastErrorKind,
                codeTextLength: codeText.length,
                codeShadowTextLength: codeViewShadowText.length
              };
            })())
            """
        }
    #endif

    private func runCrossTabMoveGeometrySmokeDiagnostic(
        action: AgentStudioStartupDiagnosticAction
    ) async {
        guard let terminalContainerBounds = await startupDiagnosticLaunchRestoreBounds() else {
            RestoreTrace.log("StartupDiagnostic.crossTabMoveGeometrySmoke skipped reason=missingBounds")
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.skipped",
                phase: "startup_diagnostic_action",
                outcome: "skipped",
                attributes: startupDiagnosticTraceAttributes(for: action).merging([
                    "agentstudio.startup_diagnostic.skip_reason": .string("missing_bounds")
                ]) { _, newValue in newValue }
            )
            return
        }

        if !launchRestoreObservationState.didComplete {
            await finishLaunchRestore(
                using: terminalContainerBounds,
                source: "crossTabMoveGeometrySmokePreflight"
            )
        }

        let fixture = createCrossTabMoveGeometrySmokeFixture()
        RestoreTrace.log(
            """
            StartupDiagnostic.crossTabMoveGeometrySmoke prepared sourceTab=\(fixture.sourceTabId) \
            destTab=\(fixture.destinationTabId) movedPane=\(fixture.movedPaneId) \
            sourceLeftPane=\(fixture.sourceLeftPaneId) targetPane=\(fixture.targetPaneId) \
            otherDestinationPane=\(fixture.otherDestinationPaneId) bounds=\(NSStringFromRect(terminalContainerBounds))
            """
        )

        await workspaceSurfaceCoordinator.restoreAllViews(in: terminalContainerBounds)
        mainWindowController?.syncVisibleTerminalGeometry(reason: "crossTabMoveGeometrySmokeBefore")
        await Task.yield()
        workspaceSurfaceCoordinator.execute(
            .movePaneAcrossTabs(
                CrossTabPaneMoveRequest(
                    paneId: fixture.movedPaneId,
                    sourceTabId: fixture.sourceTabId,
                    destTabId: fixture.destinationTabId,
                    targetPaneId: fixture.targetPaneId,
                    direction: .horizontal,
                    position: .after
                )
            )
        )
        await Task.yield()
        mainWindowController?.syncVisibleTerminalGeometry(reason: "crossTabMoveGeometrySmokeAfter")
        let renderProof = crossTabMoveGeometrySmokeRenderProof(for: fixture)
        startupTraceRecorder.recordAppStartup(
            "app.startup_diagnostic_action.command_exercised",
            phase: "startup_diagnostic_action",
            outcome: "succeeded",
            attributes: startupDiagnosticTraceAttributes(for: action).merging(
                [
                    "agentstudio.startup_diagnostic.created_pane.count": .int(fixture.paneIds.count),
                    "agentstudio.startup_diagnostic.destination_initial_pane.count": .int(2),
                    "agentstudio.startup_diagnostic.fixture.tab.count": .int(2),
                ].merging(renderProof.attributes) { _, newValue in newValue }
            ) { _, newValue in newValue }
        )
        let renderProofSucceeded = renderProof.succeeded
        let finalMessage =
            renderProofSucceeded
            ? "app.startup_diagnostic_action.completed"
            : "app.startup_diagnostic_action.blocked"
        let finalOutcome = renderProofSucceeded ? "succeeded" : "blocked"
        RestoreTrace.log(
            """
            StartupDiagnostic.crossTabMoveGeometrySmoke \(finalOutcome) activeTab=\(store.tabLayoutAtom.activeTabId?.uuidString ?? "nil") \
            expectedVisiblePanes=\(renderProof.expectedVisiblePaneCount) fixtureTerminalViews=\(renderProof.terminalViewCount) \
            fixtureSurfaceIds=\(renderProof.surfaceIdCount) fixtureMountedSurfaces=\(renderProof.mountedSurfaceCount) \
            validGeometry=\(renderProof.validGeometryCount) fixturePanes=\(fixture.paneIds.count)
            """
        )
        startupTraceRecorder.recordAppStartup(
            finalMessage,
            phase: "startup_diagnostic_action",
            outcome: finalOutcome,
            attributes: startupDiagnosticTraceAttributes(for: action).merging(
                [
                    "agentstudio.startup_diagnostic.created_pane.count": .int(fixture.paneIds.count),
                    "agentstudio.startup_diagnostic.destination_initial_pane.count": .int(2),
                    "agentstudio.startup_diagnostic.fixture.tab.count": .int(2),
                ].merging(renderProof.attributes) { _, newValue in newValue }
            ) { _, newValue in newValue }
        )
    }

    private func waitForStartupDiagnosticAppActivation() async {
        let clock = ContinuousClock()
        let start = clock.now
        while !NSApp.isActive
            && !Task.isCancelled
            && start.duration(to: clock.now) < AppPolicies.StartupDiagnostic.appActivationTimeout
        {
            do {
                try await Task.sleep(nanoseconds: Duration.milliseconds(50).nanosecondsForTaskSleep)
            } catch {
                return
            }
        }
    }

    private func startupDiagnosticLaunchRestoreBounds() async -> CGRect? {
        if windowLifecycleStore.isReadyForLaunchRestore {
            return windowLifecycleStore.terminalContainerBounds
        }

        let bridge = WindowRestoreBridge(windowLifecycleStore: windowLifecycleStore)
        return await Self.firstLaunchRestoreBounds(
            from: bridge.stream,
            timeout: AppPolicies.StartupDiagnostic.launchRestoreBoundsTimeout
        )
    }

    nonisolated static func firstLaunchRestoreBounds(
        from stream: AsyncStream<CGRect>,
        timeout: Duration
    ) async -> CGRect? {
        await withTaskGroup(of: CGRect?.self, returning: CGRect?.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: timeout.nanosecondsForTaskSleep)
                } catch {
                    return nil
                }
                return nil
            }

            guard let firstResult = await group.next() else {
                group.cancelAll()
                return nil
            }
            group.cancelAll()
            return firstResult
        }
    }

    private func crossTabMoveGeometrySmokeRenderProof(
        for fixture: CrossTabMoveGeometrySmokeFixture
    ) -> CrossTabMoveGeometrySmokeRenderProof {
        let expectedVisiblePaneIds = fixture.expectedVisiblePaneIdsAfterMove
        let terminalViews = expectedVisiblePaneIds.compactMap { viewRegistry.terminalView(for: $0) }
        let mountedSurfaces = terminalViews.compactMap(\.ghosttySurface)
        let validGeometryCount = mountedSurfaces.filter(Self.surfaceHasValidSmokeGeometry).count

        return CrossTabMoveGeometrySmokeRenderProof(
            expectedVisiblePaneCount: expectedVisiblePaneIds.count,
            terminalViewCount: terminalViews.count,
            surfaceIdCount: expectedVisiblePaneIds.compactMap { viewRegistry.terminalView(for: $0)?.surfaceId }.count,
            mountedSurfaceCount: mountedSurfaces.count,
            validGeometryCount: validGeometryCount
        )
    }

    private func ipcTerminalSmokeRenderProof(for paneId: UUID) -> CrossTabMoveGeometrySmokeRenderProof {
        let terminalView = viewRegistry.terminalView(for: paneId)
        let mountedSurfaces = [terminalView?.ghosttySurface].compactMap { $0 }
        let validGeometryCount = mountedSurfaces.filter(Self.surfaceHasValidSmokeGeometry).count
        let runtime = workspaceSurfaceCoordinator.runtimeForPane(PaneId(uuid: paneId))

        return CrossTabMoveGeometrySmokeRenderProof(
            expectedVisiblePaneCount: 1,
            terminalViewCount: terminalView == nil ? 0 : 1,
            surfaceIdCount: terminalView?.surfaceId == nil ? 0 : 1,
            mountedSurfaceCount: mountedSurfaces.count,
            validGeometryCount: runtime?.lifecycle == .ready ? validGeometryCount : 0
        )
    }

    private func waitForIPCTerminalSmokeRenderProof(for paneId: UUID) async -> CrossTabMoveGeometrySmokeRenderProof {
        let clock = ContinuousClock()
        let start = clock.now
        var proof = ipcTerminalSmokeRenderProof(for: paneId)
        while !proof.succeeded
            && !Task.isCancelled
            && start.duration(to: clock.now) < AppPolicies.StartupDiagnostic.ipcTerminalSmokeReadinessTimeout
        {
            do {
                try await Task.sleep(nanoseconds: Duration.milliseconds(50).nanosecondsForTaskSleep)
            } catch {
                return proof
            }
            mainWindowController?.syncVisibleTerminalGeometry(reason: "ipcTerminalSmokeReadiness")
            proof = ipcTerminalSmokeRenderProof(for: paneId)
        }
        return proof
    }

    private static func surfaceHasValidSmokeGeometry(_ surface: Ghostty.SurfaceView) -> Bool {
        frameIsFiniteAndPositive(surface.frame) && frameIsFiniteAndPositive(surface.bounds)
    }

    nonisolated static func frameIsFiniteAndPositive(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite
            && rect.origin.y.isFinite
            && rect.size.width.isFinite
            && rect.size.height.isFinite
            && rect.size.width > 0
            && rect.size.height > 0
    }

    private func createCrossTabMoveGeometrySmokeFixture() -> CrossTabMoveGeometrySmokeFixture {
        let movedPane = createCrossTabMoveGeometrySmokePane(title: "Smoke Move Source")
        let sourceLeftPane = createCrossTabMoveGeometrySmokePane(title: "Smoke Source Left")
        let targetPane = createCrossTabMoveGeometrySmokePane(title: "Smoke Destination Target")
        let otherDestinationPane = createCrossTabMoveGeometrySmokePane(title: "Smoke Destination Peer")
        for paneId in [movedPane.id, sourceLeftPane.id, targetPane.id, otherDestinationPane.id] {
            viewRegistry.ensureSlot(for: paneId)
        }

        viewRegistry.beginInitialRestore()
        let sourceTab = Tab(paneId: movedPane.id, name: "Smoke Source")
        let destinationTab = Tab(paneId: targetPane.id, name: "Smoke Destination")
        store.tabLayoutAtom.appendTab(sourceTab)
        store.tabLayoutAtom.appendTab(destinationTab)
        _ = store.tabLayoutAtom.insertPane(
            sourceLeftPane.id,
            inTab: sourceTab.id,
            at: movedPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        _ = store.tabLayoutAtom.insertPane(
            otherDestinationPane.id,
            inTab: destinationTab.id,
            at: targetPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        store.tabLayoutAtom.setActiveTab(destinationTab.id)

        return CrossTabMoveGeometrySmokeFixture(
            sourceTabId: sourceTab.id,
            destinationTabId: destinationTab.id,
            movedPaneId: movedPane.id,
            sourceLeftPaneId: sourceLeftPane.id,
            targetPaneId: targetPane.id,
            otherDestinationPaneId: otherDestinationPane.id
        )
    }

    private func createCrossTabMoveGeometrySmokePane(title: String) -> Pane {
        store.paneAtom.createPane(
            title: title,
            provider: .zmx,
            lifetime: .temporary
        )
    }

    private func startupDiagnosticTraceAttributes(
        for action: AgentStudioStartupDiagnosticAction
    ) -> [String: AgentStudioTraceValue] {
        [
            "agentstudio.command.source": .string("startup_diagnostic"),
            "agentstudio.command.name": .string(action.commandName),
            "agentstudio.startup_diagnostic.action": .string(action.kind.rawValue),
        ]
    }
}
