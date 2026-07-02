import CoreGraphics
import Testing

@testable import AgentStudio

struct AgentStudioStartupDiagnosticActionTests {
    @Test("startup diagnostic action is disabled unless exact env value is present")
    func disabledUnlessExactEnvironmentValueIsPresent() {
        #expect(AgentStudioStartupDiagnosticAction.fromEnvironment([:]) == nil)
        #expect(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: "off"
            ]) == nil)
        #expect(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: "new-terminal"
            ]) == nil)
    }

    @Test("startup diagnostic action parses new tab command")
    func parsesNewTabCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " new-tab "
            ]))

        #expect(action.kind == .newTab)
        #expect(action.commandName == "newTab")
    }

    @Test("startup diagnostic action parses command bar repo filter command")
    func parsesCommandBarRepoFilterCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " command-bar-repo-filter "
            ]))

        #expect(action.kind == .commandBarRepoFilter)
        #expect(action.commandName == "commandBarRepoFilter")
    }

    @Test("startup diagnostic action parses cross-tab move geometry smoke command")
    func parsesCrossTabMoveGeometrySmokeCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " cross-tab-move-geometry-smoke "
            ]))

        #expect(action.kind == .crossTabMoveGeometrySmoke)
        #expect(action.commandName == "crossTabMoveGeometrySmoke")
    }

    @Test("startup diagnostic action parses ipc terminal smoke command")
    func parsesIPCTerminalSmokeCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " ipc-terminal-smoke "
            ]))

        #expect(action.kind == .ipcTerminalSmoke)
        #expect(action.commandName == "ipcTerminalSmoke")
    }

    @Test("startup diagnostic action parses bridge review observability smoke command")
    func parsesBridgeReviewObservabilitySmokeCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " bridge-review-observability-smoke "
            ]))

        #expect(action.kind == .bridgeReviewObservabilitySmoke)
        #expect(action.commandName == "bridgeReviewObservabilitySmoke")
    }

    @Test("startup diagnostic action parses bridge file view observability smoke command")
    func parsesBridgeFileViewObservabilitySmokeCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " bridge-file-view-observability-smoke "
            ]))

        #expect(action.kind == .bridgeFileViewObservabilitySmoke)
        #expect(action.commandName == "bridgeFileViewObservabilitySmoke")
        #expect(action.suppressesAutomaticLaunchPaneRestore)
    }

    @Test("startup diagnostic action parses bridge review to file view observability smoke command")
    func parsesBridgeReviewToFileViewObservabilitySmokeCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " bridge-review-to-file-view-observability-smoke "
            ]))

        #expect(action.kind == .bridgeReviewToFileViewObservabilitySmoke)
        #expect(action.commandName == "bridgeReviewToFileViewObservabilitySmoke")
        #expect(action.suppressesAutomaticLaunchPaneRestore)
    }

    @Test("startup diagnostic action parses bridge file view command route observability smoke command")
    func parsesBridgeFileViewCommandRouteObservabilitySmokeCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey:
                    " bridge-file-view-command-route-observability-smoke "
            ]))

        #expect(action.kind == .bridgeFileViewCommandRouteObservabilitySmoke)
        #expect(action.commandName == "bridgeFileViewCommandRouteObservabilitySmoke")
        #expect(action.suppressesAutomaticLaunchPaneRestore)
    }

    @Test("startup diagnostic action parses bridge file view targeted route observability smoke command")
    func parsesBridgeFileViewTargetedRouteObservabilitySmokeCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey:
                    " bridge-file-view-targeted-route-observability-smoke "
            ]))

        #expect(action.kind == .bridgeFileViewTargetedRouteObservabilitySmoke)
        #expect(action.commandName == "bridgeFileViewTargetedRouteObservabilitySmoke")
        #expect(action.suppressesAutomaticLaunchPaneRestore)
    }

    @Test("startup diagnostic action parses add watch folder command and path")
    func parsesAddWatchFolderCommandAndPath() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " add-watch-folder "
            ]))
        let folderURL = try #require(
            AgentStudioStartupDiagnosticAction.watchFolderURL(from: [
                AgentStudioStartupDiagnosticAction.watchFolderEnvironmentKey: " ~/agentstudio-fixture "
            ]))

        #expect(action.kind == .addWatchFolder)
        #expect(action.commandName == "addWatchFolder")
        #expect(folderURL.path.hasSuffix("/agentstudio-fixture"))
    }

    @Test("startup diagnostic watch folder path is optional")
    func watchFolderPathIsOptional() {
        #expect(AgentStudioStartupDiagnosticAction.watchFolderURL(from: [:]) == nil)
        #expect(
            AgentStudioStartupDiagnosticAction.watchFolderURL(from: [
                AgentStudioStartupDiagnosticAction.watchFolderEnvironmentKey: "   "
            ]) == nil)
    }

    @Test("cross-tab smoke render proof requires visible terminal views, mounted surfaces, and valid geometry")
    func crossTabSmokeRenderProofRequiresFullVisibleGeometry() {
        let proof = CrossTabMoveGeometrySmokeRenderProof(
            expectedVisiblePaneCount: 3,
            terminalViewCount: 3,
            surfaceIdCount: 3,
            mountedSurfaceCount: 3,
            validGeometryCount: 3
        )

        #expect(proof.succeeded)
        #expect(proof.attributes["agentstudio.startup_diagnostic.expected_visible_pane.count"] == .int(3))
        #expect(proof.attributes["agentstudio.startup_diagnostic.fixture.terminal_view.count"] == .int(3))
        #expect(proof.attributes["agentstudio.startup_diagnostic.fixture.surface_reference.count"] == .int(3))
        #expect(proof.attributes["agentstudio.startup_diagnostic.fixture.surface.count"] == .int(3))
        #expect(proof.attributes["agentstudio.startup_diagnostic.fixture.valid_geometry.count"] == .int(3))
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(true))
    }

    @Test("cross-tab smoke render proof fails when visible geometry is missing")
    func crossTabSmokeRenderProofFailsWhenVisibleGeometryIsMissing() {
        let proof = CrossTabMoveGeometrySmokeRenderProof(
            expectedVisiblePaneCount: 3,
            terminalViewCount: 3,
            surfaceIdCount: 3,
            mountedSurfaceCount: 3,
            validGeometryCount: 2
        )

        #expect(!proof.succeeded)
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(false))
    }

    @Test("Bridge smoke render proof requires hydrated selected content")
    func bridgeSmokeRenderProofRequiresHydratedSelectedContent() {
        let proof = makeFullyHydratedBridgeSmokeRenderProof()

        #expect(proof.succeeded)
        assertHydratedBridgeContentAttributes(proof.attributes)
        assertHydratedBridgeGeometryAttributes(proof.attributes)
        assertHydratedBridgeWorkerAttributes(proof.attributes)
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(true))
    }

    @Test("Bridge smoke render proof fails before streamed review metadata converges")
    func bridgeSmokeRenderProofFailsBeforeStreamedReviewMetadataConverges() {
        let proof = makeHydratedBridgeSmokeRenderProof(
            HydratedBridgeSmokeRenderProofOptions(
                expectedReviewItemCount: 3,
                reviewMetadataItemCount: 2,
                reviewMetadataTreeRowCount: 3,
                selectedContentLineCount: 7,
                codeLineCount: 0,
                firstDiffContainerHeight: 0,
                firstDiffContainerPreTextLength: 0,
                codeViewInstanceFirstItemHeight: 152,
                codeViewRenderedItemCount: 1,
                codeViewRenderedItemType: "diff",
                codeViewRenderedItemVersion: 5,
                codeTextLength: 1471,
                codeShadowTextLength: 1466
            )
        )

        #expect(!proof.succeeded)
        #expect(proof.attributes["agentstudio.startup_diagnostic.bridge.review_expected_item.count"] == .int(3))
        #expect(proof.attributes["agentstudio.startup_diagnostic.bridge.review_metadata_item.count"] == .int(2))
        #expect(proof.attributes["agentstudio.startup_diagnostic.bridge.review_metadata_tree_row.count"] == .int(3))
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(false))
    }

    @Test("Bridge smoke render proof fails before Review tree scroll stress converges")
    func bridgeSmokeRenderProofFailsBeforeReviewTreeScrollStressConverges() {
        var proof = makeHydratedBridgeSmokeRenderProof(
            HydratedBridgeSmokeRenderProofOptions(
                expectedReviewItemCount: 3,
                reviewMetadataItemCount: 3,
                reviewMetadataTreeRowCount: 4,
                selectedContentLineCount: 7,
                codeLineCount: 0,
                firstDiffContainerHeight: 0,
                firstDiffContainerPreTextLength: 0,
                codeViewInstanceFirstItemHeight: 152,
                codeViewRenderedItemCount: 1,
                codeViewRenderedItemType: "diff",
                codeViewRenderedItemVersion: 5,
                codeTextLength: 1471,
                codeShadowTextLength: 1466
            )
        )
        proof.reviewTreeScrollStressCount = 0
        proof.reviewTreeScrollStressReachedBottom = false
        proof.reviewTreeClientHeight = 480
        proof.reviewTreeScrollHeight = 1200

        #expect(!proof.succeeded)
        #expect(proof.attributes["agentstudio.startup_diagnostic.bridge.review_tree_scroll_stress.count"] == .int(0))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.review_tree_scroll_stress.reached_bottom"]
                == .bool(false))
    }

    @Test("Bridge smoke render proof fails before Review tree scroll click converges")
    func bridgeSmokeRenderProofFailsBeforeReviewTreeScrollClickConverges() {
        var proof = makeHydratedBridgeSmokeRenderProof(
            HydratedBridgeSmokeRenderProofOptions(
                expectedReviewItemCount: 3,
                reviewMetadataItemCount: 3,
                reviewMetadataTreeRowCount: 4,
                selectedContentLineCount: 7,
                codeLineCount: 0,
                firstDiffContainerHeight: 0,
                firstDiffContainerPreTextLength: 0,
                codeViewInstanceFirstItemHeight: 152,
                codeViewRenderedItemCount: 1,
                codeViewRenderedItemType: "diff",
                codeViewRenderedItemVersion: 5,
                codeTextLength: 1471,
                codeShadowTextLength: 1466
            )
        )
        proof.reviewTreeClickTargetPath = "Sources/App/ClickedAfterScroll.swift"
        proof.reviewTreeClickCurrentSelectedPath = ""
        proof.reviewTreeClickCurrentSelectedItemId = ""
        proof.reviewTreeClickShellSelectedPath = ""
        proof.reviewTreeClickRenderedRowCount = 0
        proof.reviewTreeClickTargetRowIndex = -1
        proof.reviewTreeClickTargetRowVisible = false
        proof.reviewTreeClickAttemptCount = 0
        proof.reviewTreeClickSelectedPath = ""
        proof.reviewTreeClickSelectedContentState = "missing"
        proof.reviewTreeClickSelectedMaterializedItemType = "missing"
        proof.reviewTreeClickSelectedMaterializedItemVersion = 0
        proof.reviewTreeClickSelectedCharacterCount = 0

        #expect(!proof.succeeded)
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.review_tree_click.current_selected_path"]
                == .string(""))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.review_tree_click.rendered_row.count"]
                == .int(0))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.review_tree_click.selected_content_state"]
                == .string("missing"))
    }

    @Test("Bridge smoke render proof fails before a modified review item click converges")
    func bridgeSmokeRenderProofFailsBeforeModifiedReviewItemClickConverges() {
        var proof = makeHydratedBridgeSmokeRenderProof(
            HydratedBridgeSmokeRenderProofOptions(
                expectedReviewItemCount: 3,
                reviewMetadataItemCount: 3,
                reviewMetadataTreeRowCount: 4,
                selectedContentLineCount: 7,
                codeLineCount: 0,
                firstDiffContainerHeight: 0,
                firstDiffContainerPreTextLength: 0,
                codeViewInstanceFirstItemHeight: 152,
                codeViewRenderedItemCount: 1,
                codeViewRenderedItemType: "diff",
                codeViewRenderedItemVersion: 5,
                codeTextLength: 1471,
                codeShadowTextLength: 1466
            )
        )
        proof.modifiedClickTargetPath = ""
        proof.modifiedClickSelectedPath = ""
        proof.modifiedClickSelectedChangeKind = "missing"
        proof.modifiedClickSelectedContentState = "missing"
        proof.modifiedClickSelectedContentRoles = ""
        proof.modifiedClickSelectedContentCacheKeys = ""
        proof.modifiedClickSelectedMaterializedItemType = "missing"
        proof.modifiedClickSelectedMaterializedItemVersion = 0
        proof.modifiedClickSelectedCharacterCount = 0

        #expect(!proof.succeeded)
    }

    @Test("Bridge smoke render proof reports modified click targeting diagnostics")
    func bridgeSmokeRenderProofReportsModifiedClickTargetingDiagnostics() {
        var proof = makeHydratedBridgeSmokeRenderProof(
            HydratedBridgeSmokeRenderProofOptions(
                expectedReviewItemCount: 3,
                reviewMetadataItemCount: 3,
                reviewMetadataTreeRowCount: 4,
                selectedContentLineCount: 7,
                codeLineCount: 0,
                firstDiffContainerHeight: 0,
                firstDiffContainerPreTextLength: 0,
                codeViewInstanceFirstItemHeight: 152,
                codeViewRenderedItemCount: 1,
                codeViewRenderedItemType: "diff",
                codeViewRenderedItemVersion: 5,
                codeTextLength: 1471,
                codeShadowTextLength: 1466
            )
        )
        proof.modifiedClickFilterRequested = true
        proof.modifiedClickRenderedRowCount = 2
        proof.modifiedClickFirstRenderedPath = "Sources/App/Modified.swift"
        proof.modifiedClickSetFilterStatus = "accepted"
        proof.modifiedClickSetFilterReason = "none"

        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.modified_click.filter_requested"]
                == .bool(true))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.modified_click.rendered_row.count"]
                == .int(2))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.modified_click.first_rendered_path"]
                == .string("Sources/App/Modified.swift"))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.modified_click.set_filter.status"]
                == .string("accepted"))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.modified_click.set_filter.reason"]
                == .string("none"))
    }

    @Test("Bridge smoke render proof allows context switch fetch aborts after modified review content converges")
    func bridgeSmokeRenderProofAllowsContextSwitchFetchAbortsAfterModifiedReviewContentConverges() {
        let proof = makeHydratedBridgeSmokeRenderProof(
            HydratedBridgeSmokeRenderProofOptions(
                expectedReviewItemCount: 3,
                reviewMetadataItemCount: 3,
                reviewMetadataTreeRowCount: 4,
                selectedContentLineCount: 7,
                pageErrorCount: 1,
                pageIssueLastKind: "fetch_error",
                pageIssueLastClass: "context_switch_fetch_aborted",
                pageIssueDisallowedCount: 0,
                codeLineCount: 0,
                firstDiffContainerHeight: 0,
                firstDiffContainerPreTextLength: 0,
                codeViewInstanceFirstItemHeight: 152,
                codeViewRenderedItemCount: 1,
                codeViewRenderedItemType: "diff",
                codeViewRenderedItemVersion: 5,
                codeTextLength: 1471,
                codeShadowTextLength: 1466
            )
        )

        #expect(proof.succeeded)
    }

    @Test("Bridge smoke render proof fails when a real page issue is masked by a later abort")
    func bridgeSmokeRenderProofFailsWhenRealPageIssueIsMaskedByLaterAbort() {
        let proof = makeHydratedBridgeSmokeRenderProof(
            HydratedBridgeSmokeRenderProofOptions(
                expectedReviewItemCount: 3,
                reviewMetadataItemCount: 3,
                reviewMetadataTreeRowCount: 4,
                selectedContentLineCount: 7,
                pageErrorCount: 2,
                pageIssueLastKind: "fetch_error",
                pageIssueLastClass: "context_switch_fetch_aborted",
                pageIssueDisallowedCount: 1,
                codeLineCount: 0,
                firstDiffContainerHeight: 0,
                firstDiffContainerPreTextLength: 0,
                codeViewInstanceFirstItemHeight: 152,
                codeViewRenderedItemCount: 1,
                codeViewRenderedItemType: "diff",
                codeViewRenderedItemVersion: 5,
                codeTextLength: 1471,
                codeShadowTextLength: 1466
            )
        )

        #expect(!proof.succeeded)
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.page_issue.disallowed.count"] == .int(1))
    }

    @Test("Bridge smoke render proof requires native review intake lineage")
    func bridgeSmokeRenderProofRequiresNativeReviewIntakeLineage() {
        let proof = makeBridgeSmokeRenderProofWithoutNativeReviewIntakeLineage()

        #expect(!proof.succeeded)
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.review_intake_ready_command.count"] == .int(0))
    }

    @Test("Bridge smoke render proof fails before selected content is visible")
    func bridgeSmokeRenderProofFailsBeforeSelectedContentIsVisible() {
        let proof = BridgeReviewObservabilitySmokeRenderProof(
            expectedVisiblePaneCount: 1,
            expectedReviewItemCount: 3,
            hasReviewShell: true,
            reviewShellState: "ready",
            hasCodeViewPanel: true,
            hasSelectedItem: true,
            hasSelectedDisplayPath: true,
            reviewMetadataItemCount: 3,
            reviewMetadataTreeRowCount: 3,
            hasSelectedContentText: false,
            selectedContentState: "pending",
            selectedContentRoleCount: 0,
            selectedContentCacheKeyCount: 0,
            selectedContentCharacterCount: 0,
            selectedContentLineCount: 0,
            selectedMaterializedUpdateResult: "not-run",
            selectedMaterializedItemType: "none",
            selectedMaterializedItemVersion: 0,
            selectedMaterializedAdditionLineCount: 0,
            selectedMaterializedDeletionLineCount: 0,
            selectedMaterializedFileLineCount: 0,
            pageErrorCount: 0,
            pageIssueLastKind: "none",
            pageIssueLastClass: "none",
            diffContainerCount: 1,
            codeLineCount: 0,
            codeViewPanelWidth: 900,
            codeViewPanelHeight: 700,
            firstDiffContainerWidth: 880,
            firstDiffContainerHeight: 0,
            codeViewScrollOwnerHeight: 700,
            codeViewScrollOwnerScrollHeight: 700,
            codeViewScrollOwnerChildCount: 1,
            codeViewScrollOwnerFirstChildTag: "diffs-container",
            codeViewInstanceHeight: 700,
            codeViewInstanceScrollHeight: 0,
            codeViewInstanceItemCount: 0,
            codeViewInstanceWindowTop: 0,
            codeViewInstanceWindowBottom: 700,
            codeViewInstanceFirstRenderedIndex: -1,
            codeViewInstanceLastRenderedIndex: -1,
            codeViewInstanceFirstItemHeight: 0,
            codeViewInstanceFirstItemTop: 0,
            codeViewRenderedItemCount: 0,
            codeViewRenderedItemElementHeight: 0,
            codeViewRenderedItemElementChildCount: 0,
            codeViewRenderedItemElementFirstChildTag: "missing",
            codeViewRenderedItemType: "missing",
            codeViewRenderedItemVersion: 0,
            firstDiffContainerShadowChildCount: 1,
            firstDiffContainerPreCount: 0,
            firstDiffContainerOffsetHeight: 0,
            firstDiffContainerScrollHeight: 0,
            firstDiffContainerPreHeight: 0,
            firstDiffContainerPreTextLength: 0,
            codeLineWithDataLineCount: 0,
            firstDiffContainerDisplay: "block",
            workerPoolState: "loading",
            workerPoolManagerState: "waiting",
            workerPoolWorkersFailed: false,
            workerPoolTotalWorkers: 0,
            workerPoolBusyWorkers: 0,
            workerPoolQueuedTasks: 0,
            workerPoolActiveTasks: 0,
            workerPoolFileCacheSize: 0,
            workerPoolDiffCacheSize: 0,
            workerPoolInitializationProbeStage: "idle",
            workerPoolInitializationProbeThemeCount: 0,
            workerPoolInitializationProbeLanguageCount: 0,
            workerPoolInitializationProbeFailureReason: "",
            workerDiagnosticBootstrapState: "missing",
            workerDiagnosticInitializeRequestIdState: "missing",
            workerDiagnosticLastMessageType: "missing",
            workerDiagnosticLastRequestType: "missing",
            workerDiagnosticLastSuccessMatchesInitializeRequest: "missing",
            workerDiagnosticLastSuccessIdState: "missing",
            workerDiagnosticLastSuccessIdPrefix: "none",
            workerDiagnosticLastSuccessRequestType: "missing",
            workerDiagnosticSuccessCount: 0,
            workerDiagnosticInitializeSuccessCount: 0,
            workerDiagnosticDiffSuccessCount: 0,
            workerDiagnosticFileSuccessCount: 0,
            workerDiagnosticForwardedMessageCount: 0,
            workerDiagnosticLastForwardResult: "none",
            workerDiagnosticErrorCount: 0,
            workerDiagnosticLastErrorKind: "none",
            codeTextLength: 0,
            codeShadowTextLength: 0
        )

        #expect(!proof.succeeded)
        #expect(proof.attributes["agentstudio.startup_diagnostic.bridge.selected_content.visible"] == .bool(false))
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(false))
    }

    @Test("Bridge smoke render probe reads Pierre CodeView shadow DOM")
    func bridgeSmokeRenderProbeReadsPierreCodeViewShadowDOM() {
        let probe = AppDelegate.bridgeReviewObservabilitySmokeRenderStateJavaScript

        #expect(probe.contains("diffs-container"))
        #expect(probe.contains("shadowRoot"))
        #expect(probe.contains("[data-line-index]"))
        #expect(probe.contains("data-selected-content-state"))
        #expect(probe.contains("data-selected-content-character-count"))
        #expect(probe.contains("data-selected-materialized-update-result"))
        #expect(probe.contains("selectedContentRoleCount > 0"))
        #expect(probe.contains("selectedContentCacheKeyCount > 0"))
        #expect(probe.contains("selectedContentCharacterCount > 0"))
        #expect(!probe.contains("selectedContentLineCount > 0"))
        #expect(probe.contains("selectedMaterializedLineCount > 0"))
        #expect(probe.contains("codeText.length > 0"))
        #expect(probe.contains("codeViewShadowText.length > 0"))
        #expect(probe.contains("codeViewScrollOwner"))
        #expect(probe.contains("window.__INSTANCE"))
        #expect(probe.contains("codeViewInstanceItemCount"))
        #expect(probe.contains("codeViewInstanceFirstRenderedIndex"))
        #expect(probe.contains("codeViewInstanceFirstItemHeight"))
        #expect(probe.contains("getRenderedItems"))
        #expect(probe.contains("reviewShellState"))
        #expect(probe.contains("bridge-review-projection-pending-shell"))
        #expect(probe.contains("bridge-review-projection-failed-shell"))
        #expect(probe.contains("pageIssueLastKind"))
        #expect(probe.contains("pageIssueLastClass"))
        #expect(probe.contains("pageIssueDisallowedCount"))
        #expect(probe.contains("__bridgeCommandProbe"))
        #expect(probe.contains("__bridgeIntakeReadyCommandProbe"))
        #expect(probe.contains("__bridgeIntakeProbe"))
        #expect(probe.contains("__bridgeReviewMetadataInterestProbe"))
        #expect(probe.contains("bridge.metadata_interest.update"))
        #expect(probe.contains("reviewIntakeMetadataWindowFrameCount === 0"))
        #expect(probe.contains("reviewIntakeReadyCommandCount"))
        #expect(probe.contains("reviewIntakeSnapshotFrameCount"))
        #expect(probe.contains("classifyPageIssue"))
        #expect(probe.contains("modifiedClickAttemptCount"))
        #expect(probe.contains("clickAttemptCount: modifiedClickAttemptCount"))
        #expect(probe.contains("codeViewRenderedItemElementHeight"))
        #expect(probe.contains("codeViewRenderedItemElementFirstChildTag"))
        #expect(probe.contains("firstDiffContainerPreCount"))
        #expect(probe.contains("firstDiffContainerPreHeight"))
        #expect(probe.contains("workerPoolState"))
        #expect(probe.contains("data-bridge-pierre-worker-pool-state"))
        #expect(probe.contains("workerPoolManagerState"))
        #expect(probe.contains("data-bridge-pierre-worker-pool-manager-state"))
        #expect(probe.contains("workerPoolQueuedTasks"))
        #expect(probe.contains("data-bridge-pierre-worker-pool-queued-tasks"))
        #expect(probe.contains("workerPoolInitializationProbeStage"))
        #expect(probe.contains("data-bridge-pierre-worker-pool-init-probe-stage"))
        #expect(probe.contains("workerDiagnosticBootstrapState"))
        #expect(probe.contains("data-bridge-pierre-worker-diagnostic-bootstrap-state"))
        #expect(probe.contains("workerDiagnosticInitializeRequestIdState"))
        #expect(probe.contains("data-bridge-pierre-worker-diagnostic-initialize-request-id-state"))
        #expect(probe.contains("workerDiagnosticLastRequestType"))
        #expect(probe.contains("data-bridge-pierre-worker-diagnostic-last-request-type"))
        #expect(probe.contains("workerDiagnosticLastSuccessMatchesInitializeRequest"))
        #expect(
            probe.contains(
                "data-bridge-pierre-worker-diagnostic-last-success-matches-initialize-request"))
        #expect(probe.contains("workerDiagnosticLastSuccessIdState"))
        #expect(probe.contains("data-bridge-pierre-worker-diagnostic-last-success-id-state"))
        #expect(probe.contains("workerDiagnosticLastSuccessIdPrefix"))
        #expect(probe.contains("data-bridge-pierre-worker-diagnostic-last-success-id-prefix"))
        #expect(probe.contains("workerDiagnosticLastSuccessRequestType"))
        #expect(probe.contains("data-bridge-pierre-worker-diagnostic-last-success-request-type"))
        #expect(probe.contains("workerDiagnosticDiffSuccessCount"))
        #expect(probe.contains("data-bridge-pierre-worker-diagnostic-diff-success-count"))
        #expect(probe.contains("workerDiagnosticErrorCount"))
        #expect(probe.contains("data-bridge-pierre-worker-diagnostic-error-count"))
        #expect(probe.contains("[data-line][data-line-index]"))
        #expect(probe.contains("getComputedStyle"))
        #expect(probe.contains("getBoundingClientRect"))
    }

    @Test("Bridge smoke render proof requires positive rendered line geometry")
    func bridgeSmokeRenderProofRequiresPositiveRenderedLineGeometry() {
        let proof = BridgeReviewObservabilitySmokeRenderProof(
            expectedVisiblePaneCount: 1,
            expectedReviewItemCount: 3,
            hasReviewShell: true,
            reviewShellState: "ready",
            hasCodeViewPanel: true,
            hasSelectedItem: true,
            hasSelectedDisplayPath: true,
            reviewMetadataItemCount: 3,
            reviewMetadataTreeRowCount: 3,
            hasSelectedContentText: true,
            selectedContentState: "ready",
            selectedContentRoleCount: 2,
            selectedContentCacheKeyCount: 2,
            selectedContentCharacterCount: 180,
            selectedContentLineCount: 12,
            selectedMaterializedUpdateResult: "updated",
            selectedMaterializedItemType: "diff",
            selectedMaterializedItemVersion: 3,
            selectedMaterializedAdditionLineCount: 4,
            selectedMaterializedDeletionLineCount: 2,
            selectedMaterializedFileLineCount: 0,
            pageErrorCount: 0,
            pageIssueLastKind: "none",
            pageIssueLastClass: "none",
            diffContainerCount: 1,
            codeLineCount: 0,
            codeViewPanelWidth: 900,
            codeViewPanelHeight: 700,
            firstDiffContainerWidth: 880,
            firstDiffContainerHeight: 0,
            codeViewScrollOwnerHeight: 700,
            codeViewScrollOwnerScrollHeight: 700,
            codeViewScrollOwnerChildCount: 1,
            codeViewScrollOwnerFirstChildTag: "diffs-container",
            codeViewInstanceHeight: 700,
            codeViewInstanceScrollHeight: 0,
            codeViewInstanceItemCount: 1,
            codeViewInstanceWindowTop: 0,
            codeViewInstanceWindowBottom: 700,
            codeViewInstanceFirstRenderedIndex: -1,
            codeViewInstanceLastRenderedIndex: -1,
            codeViewInstanceFirstItemHeight: 0,
            codeViewInstanceFirstItemTop: 0,
            codeViewRenderedItemCount: 1,
            codeViewRenderedItemElementHeight: 0,
            codeViewRenderedItemElementChildCount: 1,
            codeViewRenderedItemElementFirstChildTag: "diffs-container",
            codeViewRenderedItemType: "diff",
            codeViewRenderedItemVersion: 3,
            firstDiffContainerShadowChildCount: 1,
            firstDiffContainerPreCount: 0,
            firstDiffContainerOffsetHeight: 0,
            firstDiffContainerScrollHeight: 0,
            firstDiffContainerPreHeight: 0,
            firstDiffContainerPreTextLength: 0,
            codeLineWithDataLineCount: 0,
            firstDiffContainerDisplay: "block",
            workerPoolState: "ready",
            workerPoolManagerState: "initialized",
            workerPoolWorkersFailed: false,
            workerPoolTotalWorkers: 2,
            workerPoolBusyWorkers: 0,
            workerPoolQueuedTasks: 0,
            workerPoolActiveTasks: 1,
            workerPoolFileCacheSize: 0,
            workerPoolDiffCacheSize: 0,
            workerPoolInitializationProbeStage: "idle",
            workerPoolInitializationProbeThemeCount: 0,
            workerPoolInitializationProbeLanguageCount: 0,
            workerPoolInitializationProbeFailureReason: "",
            workerDiagnosticBootstrapState: "started",
            workerDiagnosticInitializeRequestIdState: "present",
            workerDiagnosticLastMessageType: "success",
            workerDiagnosticLastRequestType: "initialize",
            workerDiagnosticLastSuccessMatchesInitializeRequest: "invalid",
            workerDiagnosticLastSuccessIdState: "missing",
            workerDiagnosticLastSuccessIdPrefix: "none",
            workerDiagnosticLastSuccessRequestType: "initialize",
            workerDiagnosticSuccessCount: 1,
            workerDiagnosticInitializeSuccessCount: 1,
            workerDiagnosticDiffSuccessCount: 0,
            workerDiagnosticFileSuccessCount: 0,
            workerDiagnosticForwardedMessageCount: 1,
            workerDiagnosticLastForwardResult: "ok",
            workerDiagnosticErrorCount: 0,
            workerDiagnosticLastErrorKind: "none",
            codeTextLength: 120,
            codeShadowTextLength: 88
        )

        #expect(!proof.succeeded)
    }

    @Test("Bridge smoke render proof accepts current Pierre rendered text evidence")
    func bridgeSmokeRenderProofAcceptsCurrentPierreRenderedTextEvidence() {
        let proof = makeHydratedBridgeSmokeRenderProof(
            HydratedBridgeSmokeRenderProofOptions(
                expectedReviewItemCount: 3,
                reviewMetadataItemCount: 3,
                reviewMetadataTreeRowCount: 3,
                selectedContentLineCount: 7,
                codeLineCount: 0,
                firstDiffContainerHeight: 0,
                firstDiffContainerPreTextLength: 0,
                codeViewInstanceFirstItemHeight: 152,
                codeViewRenderedItemCount: 1,
                codeViewRenderedItemType: "diff",
                codeViewRenderedItemVersion: 5,
                codeTextLength: 1471,
                codeShadowTextLength: 1466
            )
        )

        #expect(proof.succeeded)
    }

    @Test("Bridge smoke render proof accepts native ready content with zero selected line metadata")
    func bridgeSmokeRenderProofAcceptsNativeReadyContentWithZeroSelectedLineMetadata() {
        let proof = makeHydratedBridgeSmokeRenderProof(
            HydratedBridgeSmokeRenderProofOptions(
                expectedReviewItemCount: 3,
                reviewMetadataItemCount: 3,
                reviewMetadataTreeRowCount: 3,
                selectedContentLineCount: 0,
                codeLineCount: 0,
                firstDiffContainerHeight: 0,
                firstDiffContainerPreTextLength: 0,
                codeViewInstanceFirstItemHeight: 112,
                codeViewRenderedItemCount: 1,
                codeViewRenderedItemType: "diff",
                codeViewRenderedItemVersion: 5,
                codeTextLength: 193,
                codeShadowTextLength: 188
            )
        )

        #expect(proof.succeeded)
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.selected_content_line.count"] == .int(0))
    }

    @Test("startup diagnostic finite frame check rejects invalid bounds")
    func finiteFrameCheckRejectsInvalidBounds() {
        #expect(AppDelegate.frameIsFiniteAndPositive(CGRect(x: 0, y: 0, width: 100, height: 50)))
        #expect(!AppDelegate.frameIsFiniteAndPositive(CGRect(x: 0, y: 0, width: 0, height: 50)))
        #expect(!AppDelegate.frameIsFiniteAndPositive(CGRect(x: 0, y: 0, width: -100, height: 50)))
        #expect(!AppDelegate.frameIsFiniteAndPositive(CGRect(x: CGFloat.infinity, y: 0, width: 100, height: 50)))
    }

    @Test("launch restore bounds reader returns the first emitted bounds")
    func launchRestoreBoundsReaderReturnsFirstEmittedBounds() async {
        let expectedBounds = CGRect(x: 10, y: 20, width: 300, height: 200)
        let stream = AsyncStream<CGRect> { continuation in
            continuation.yield(expectedBounds)
            continuation.finish()
        }

        let bounds = await AppDelegate.firstLaunchRestoreBounds(from: stream, timeout: .seconds(3))

        #expect(bounds == expectedBounds)
    }

    @Test("launch restore bounds reader returns nil when the stream finishes without bounds")
    func launchRestoreBoundsReaderReturnsNilForFinishedStream() async {
        let stream = AsyncStream<CGRect> { continuation in
            continuation.finish()
        }

        let bounds = await AppDelegate.firstLaunchRestoreBounds(from: stream, timeout: .seconds(3))

        #expect(bounds == nil)
    }
}

private func assertHydratedBridgeContentAttributes(
    _ attributes: [String: AgentStudioTraceValue]
) {
    #expect(attributes["agentstudio.startup_diagnostic.bridge.review_shell.visible"] == .bool(true))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.code_view.visible"] == .bool(true))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.selected_content.visible"] == .bool(true))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.selected_content.state"] == .string("ready"))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.selected_content_role.count"] == .int(2))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.selected_content_cache_key.count"] == .int(2))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.selected_content_character.count"] == .int(180))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.selected_content_line.count"] == .int(12))
    #expect(
        attributes["agentstudio.startup_diagnostic.bridge.selected_materialized.update_result"] == .string("updated"))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.selected_materialized.item_type"] == .string("diff"))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.selected_materialized.item_version"] == .int(3))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.selected_materialized.addition_line.count"] == .int(4))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.selected_materialized.deletion_line.count"] == .int(2))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.selected_materialized.file_line.count"] == .int(0))
}

private func assertHydratedBridgeGeometryAttributes(
    _ attributes: [String: AgentStudioTraceValue]
) {
    #expect(attributes["agentstudio.startup_diagnostic.bridge.diff_container.count"] == .int(1))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.code_line.count"] == .int(4))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.code_view_panel.width_px"] == .int(900))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.code_view_panel.height_px"] == .int(700))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.diff_container.width_px"] == .int(880))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.diff_container.height_px"] == .int(600))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.code_view_scroll_owner.height_px"] == .int(700))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.code_view_scroll_owner.scroll_height_px"] == .int(1200))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.code_view_scroll_owner.child.count"] == .int(1))
    #expect(
        attributes["agentstudio.startup_diagnostic.bridge.code_view_scroll_owner.first_child.tag"]
            == .string("diffs-container"))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.code_view.instance.height_px"] == .int(700))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.code_view.instance.scroll_height_px"] == .int(1200))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.code_view.instance.item.count"] == .int(1))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.code_view.instance.window.top_px"] == .int(0))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.code_view.instance.window.bottom_px"] == .int(700))
    #expect(
        attributes["agentstudio.startup_diagnostic.bridge.code_view.instance.render_state.first_index"] == .int(0))
    #expect(
        attributes["agentstudio.startup_diagnostic.bridge.code_view.instance.render_state.last_index"] == .int(0))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.code_view.instance.first_item.height_px"] == .int(600))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.code_view.instance.first_item.top_px"] == .int(0))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.code_view.rendered_item.count"] == .int(1))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.code_view.rendered_item.element.height_px"] == .int(600))
    #expect(
        attributes["agentstudio.startup_diagnostic.bridge.code_view.rendered_item.element.child.count"] == .int(1))
    #expect(
        attributes["agentstudio.startup_diagnostic.bridge.code_view.rendered_item.element.first_child.tag"]
            == .string("diffs-container"))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.code_view.rendered_item.type"] == .string("diff"))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.code_view.rendered_item.version"] == .int(3))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.diff_container.shadow_child.count"] == .int(3))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.diff_container.pre.count"] == .int(1))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.diff_container.offset_height_px"] == .int(600))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.diff_container.scroll_height_px"] == .int(1200))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.diff_container.pre.height_px"] == .int(560))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.diff_container.pre_text.length"] == .int(88))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.code_line_with_data_line.count"] == .int(4))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.diff_container.display"] == .string("block"))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.code_text.length"] == .int(120))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.code_shadow_text.length"] == .int(88))
}

private func assertHydratedBridgeWorkerAttributes(
    _ attributes: [String: AgentStudioTraceValue]
) {
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_pool.state"] == .string("ready"))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_pool.manager_state"] == .string("initialized"))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_pool.workers_failed"] == .bool(false))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_pool.total_workers"] == .int(2))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_pool.busy_workers"] == .int(0))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_pool.queued_tasks"] == .int(0))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_pool.active_tasks"] == .int(0))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_pool.file_cache_size"] == .int(1))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_pool.diff_cache_size"] == .int(1))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_pool.init_probe.stage"] == .string("idle"))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_pool.init_probe.theme_count"] == .int(0))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_pool.init_probe.language_count"] == .int(0))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_pool.init_probe.failure_reason"] == .string(""))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_diagnostic.bootstrap_state"] == .string("started"))
    #expect(
        attributes["agentstudio.startup_diagnostic.bridge.worker_diagnostic.initialize_request_id_state"]
            == .string("present"))
    #expect(
        attributes["agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_message_type"] == .string("success"))
    #expect(
        attributes["agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_request_type"] == .string("initialize")
    )
    #expect(
        attributes["agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_success_matches_initialize_request"]
            == .string("yes"))
    #expect(
        attributes["agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_success_id_state"]
            == .string("present"))
    #expect(
        attributes["agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_success_id_prefix"] == .string("req"))
    #expect(
        attributes["agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_success_request_type"]
            == .string("diff"))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_diagnostic.success_count"] == .int(2))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_diagnostic.initialize_success_count"] == .int(1))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_diagnostic.diff_success_count"] == .int(1))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_diagnostic.file_success_count"] == .int(0))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_diagnostic.forwarded_message_count"] == .int(2))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_forward_result"] == .string("ok"))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_diagnostic.failure_count"] == .int(0))
    #expect(attributes["agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_failure_kind"] == .string("none"))
}
