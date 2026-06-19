import Foundation

struct CrossTabMoveGeometrySmokeFixture {
    let sourceTabId: UUID
    let destinationTabId: UUID
    let movedPaneId: UUID
    let sourceLeftPaneId: UUID
    let targetPaneId: UUID
    let otherDestinationPaneId: UUID

    var paneIds: [UUID] {
        [movedPaneId, sourceLeftPaneId, targetPaneId, otherDestinationPaneId]
    }

    var expectedVisiblePaneIdsAfterMove: [UUID] {
        [movedPaneId, targetPaneId, otherDestinationPaneId]
    }
}

struct CrossTabMoveGeometrySmokeRenderProof: Equatable {
    let expectedVisiblePaneCount: Int
    let terminalViewCount: Int
    let surfaceIdCount: Int
    let mountedSurfaceCount: Int
    let validGeometryCount: Int

    var succeeded: Bool {
        expectedVisiblePaneCount > 0
            && terminalViewCount == expectedVisiblePaneCount
            && mountedSurfaceCount == expectedVisiblePaneCount
            && validGeometryCount == expectedVisiblePaneCount
    }

    var attributes: [String: AgentStudioTraceValue] {
        [
            "agentstudio.startup_diagnostic.expected_visible_pane.count": .int(expectedVisiblePaneCount),
            "agentstudio.startup_diagnostic.fixture.terminal_view.count": .int(terminalViewCount),
            "agentstudio.startup_diagnostic.fixture.surface_reference.count": .int(surfaceIdCount),
            "agentstudio.startup_diagnostic.fixture.surface.count": .int(mountedSurfaceCount),
            "agentstudio.startup_diagnostic.fixture.valid_geometry.count": .int(validGeometryCount),
            "agentstudio.startup_diagnostic.render_proof.succeeded": .bool(succeeded),
        ]
    }
}

struct BridgeReviewObservabilitySmokeRenderSnapshot: Decodable, Equatable {
    let hasReviewShell: Bool
    let hasCodeViewPanel: Bool
    let hasSelectedItem: Bool
    let hasSelectedDisplayPath: Bool
    let hasSelectedContentText: Bool
    let selectedContentState: String
    let selectedContentRoleCount: Int
    let selectedContentCacheKeyCount: Int
    let selectedContentCharacterCount: Int
    let selectedContentLineCount: Int
    let selectedMaterializedUpdateResult: String
    let selectedMaterializedItemType: String
    let selectedMaterializedItemVersion: Int
    let selectedMaterializedAdditionLineCount: Int
    let selectedMaterializedDeletionLineCount: Int
    let selectedMaterializedFileLineCount: Int
    let pageErrorCount: Int
    let diffContainerCount: Int
    let codeLineCount: Int
    let codeViewPanelWidth: Int
    let codeViewPanelHeight: Int
    let firstDiffContainerWidth: Int
    let firstDiffContainerHeight: Int
    let codeViewScrollOwnerHeight: Int
    let codeViewScrollOwnerScrollHeight: Int
    let codeViewScrollOwnerChildCount: Int
    let codeViewScrollOwnerFirstChildTag: String
    let codeViewInstanceHeight: Int
    let codeViewInstanceScrollHeight: Int
    let codeViewInstanceItemCount: Int
    let codeViewInstanceWindowTop: Int
    let codeViewInstanceWindowBottom: Int
    let codeViewInstanceFirstRenderedIndex: Int
    let codeViewInstanceLastRenderedIndex: Int
    let codeViewInstanceFirstItemHeight: Int
    let codeViewInstanceFirstItemTop: Int
    let codeViewRenderedItemCount: Int
    let codeViewRenderedItemElementHeight: Int
    let codeViewRenderedItemElementChildCount: Int
    let codeViewRenderedItemElementFirstChildTag: String
    let codeViewRenderedItemType: String
    let codeViewRenderedItemVersion: Int
    let firstDiffContainerShadowChildCount: Int
    let firstDiffContainerPreCount: Int
    let firstDiffContainerOffsetHeight: Int
    let firstDiffContainerScrollHeight: Int
    let firstDiffContainerPreHeight: Int
    let firstDiffContainerPreTextLength: Int
    let codeLineWithDataLineCount: Int
    let firstDiffContainerDisplay: String
    let workerPoolState: String
    let workerPoolManagerState: String
    let workerPoolWorkersFailed: Bool
    let workerPoolTotalWorkers: Int
    let workerPoolBusyWorkers: Int
    let workerPoolQueuedTasks: Int
    let workerPoolActiveTasks: Int
    let workerPoolFileCacheSize: Int
    let workerPoolDiffCacheSize: Int
    let workerPoolInitializationProbeStage: String
    let workerPoolInitializationProbeThemeCount: Int
    let workerPoolInitializationProbeLanguageCount: Int
    let workerPoolInitializationProbeFailureReason: String
    let workerDiagnosticBootstrapState: String
    let workerDiagnosticInitializeRequestIdState: String
    let workerDiagnosticLastMessageType: String
    let workerDiagnosticLastRequestType: String
    let workerDiagnosticLastSuccessMatchesInitializeRequest: String
    let workerDiagnosticLastSuccessIdState: String
    let workerDiagnosticLastSuccessIdPrefix: String
    let workerDiagnosticLastSuccessRequestType: String
    let workerDiagnosticSuccessCount: Int
    let workerDiagnosticInitializeSuccessCount: Int
    let workerDiagnosticDiffSuccessCount: Int
    let workerDiagnosticFileSuccessCount: Int
    let workerDiagnosticForwardedMessageCount: Int
    let workerDiagnosticLastForwardResult: String
    let workerDiagnosticErrorCount: Int
    let workerDiagnosticLastErrorKind: String
    let codeTextLength: Int
    let codeShadowTextLength: Int
}

struct BridgeReviewObservabilitySmokeRenderProof: Equatable {
    let expectedVisiblePaneCount: Int
    let hasReviewShell: Bool
    let hasCodeViewPanel: Bool
    let hasSelectedItem: Bool
    let hasSelectedDisplayPath: Bool
    let hasSelectedContentText: Bool
    let selectedContentState: String
    let selectedContentRoleCount: Int
    let selectedContentCacheKeyCount: Int
    let selectedContentCharacterCount: Int
    let selectedContentLineCount: Int
    let selectedMaterializedUpdateResult: String
    let selectedMaterializedItemType: String
    let selectedMaterializedItemVersion: Int
    let selectedMaterializedAdditionLineCount: Int
    let selectedMaterializedDeletionLineCount: Int
    let selectedMaterializedFileLineCount: Int
    let pageErrorCount: Int
    let diffContainerCount: Int
    let codeLineCount: Int
    let codeViewPanelWidth: Int
    let codeViewPanelHeight: Int
    let firstDiffContainerWidth: Int
    let firstDiffContainerHeight: Int
    let codeViewScrollOwnerHeight: Int
    let codeViewScrollOwnerScrollHeight: Int
    let codeViewScrollOwnerChildCount: Int
    let codeViewScrollOwnerFirstChildTag: String
    let codeViewInstanceHeight: Int
    let codeViewInstanceScrollHeight: Int
    let codeViewInstanceItemCount: Int
    let codeViewInstanceWindowTop: Int
    let codeViewInstanceWindowBottom: Int
    let codeViewInstanceFirstRenderedIndex: Int
    let codeViewInstanceLastRenderedIndex: Int
    let codeViewInstanceFirstItemHeight: Int
    let codeViewInstanceFirstItemTop: Int
    let codeViewRenderedItemCount: Int
    let codeViewRenderedItemElementHeight: Int
    let codeViewRenderedItemElementChildCount: Int
    let codeViewRenderedItemElementFirstChildTag: String
    let codeViewRenderedItemType: String
    let codeViewRenderedItemVersion: Int
    let firstDiffContainerShadowChildCount: Int
    let firstDiffContainerPreCount: Int
    let firstDiffContainerOffsetHeight: Int
    let firstDiffContainerScrollHeight: Int
    let firstDiffContainerPreHeight: Int
    let firstDiffContainerPreTextLength: Int
    let codeLineWithDataLineCount: Int
    let firstDiffContainerDisplay: String
    let workerPoolState: String
    let workerPoolManagerState: String
    let workerPoolWorkersFailed: Bool
    let workerPoolTotalWorkers: Int
    let workerPoolBusyWorkers: Int
    let workerPoolQueuedTasks: Int
    let workerPoolActiveTasks: Int
    let workerPoolFileCacheSize: Int
    let workerPoolDiffCacheSize: Int
    let workerPoolInitializationProbeStage: String
    let workerPoolInitializationProbeThemeCount: Int
    let workerPoolInitializationProbeLanguageCount: Int
    let workerPoolInitializationProbeFailureReason: String
    let workerDiagnosticBootstrapState: String
    let workerDiagnosticInitializeRequestIdState: String
    let workerDiagnosticLastMessageType: String
    let workerDiagnosticLastRequestType: String
    let workerDiagnosticLastSuccessMatchesInitializeRequest: String
    let workerDiagnosticLastSuccessIdState: String
    let workerDiagnosticLastSuccessIdPrefix: String
    let workerDiagnosticLastSuccessRequestType: String
    let workerDiagnosticSuccessCount: Int
    let workerDiagnosticInitializeSuccessCount: Int
    let workerDiagnosticDiffSuccessCount: Int
    let workerDiagnosticFileSuccessCount: Int
    let workerDiagnosticForwardedMessageCount: Int
    let workerDiagnosticLastForwardResult: String
    let workerDiagnosticErrorCount: Int
    let workerDiagnosticLastErrorKind: String
    let codeTextLength: Int
    let codeShadowTextLength: Int

    var succeeded: Bool {
        expectedVisiblePaneCount == 1
            && hasReviewShell
            && hasCodeViewPanel
            && hasSelectedItem
            && hasSelectedDisplayPath
            && hasSelectedContentText
            && selectedContentState == "ready"
            && selectedContentRoleCount > 0
            && diffContainerCount > 0
            && codeLineCount > 0
            && codeViewPanelWidth > 0
            && codeViewPanelHeight > 0
            && firstDiffContainerWidth > 0
            && firstDiffContainerHeight > 0
            && pageErrorCount == 0
    }

    var attributes: [String: AgentStudioTraceValue] {
        [
            "agentstudio.startup_diagnostic.expected_visible_pane.count": .int(expectedVisiblePaneCount),
            "agentstudio.startup_diagnostic.bridge.review_shell.visible": .bool(hasReviewShell),
            "agentstudio.startup_diagnostic.bridge.code_view.visible": .bool(hasCodeViewPanel),
            "agentstudio.startup_diagnostic.bridge.selected_item.visible": .bool(hasSelectedItem),
            "agentstudio.startup_diagnostic.bridge.selected_path.visible": .bool(hasSelectedDisplayPath),
            "agentstudio.startup_diagnostic.bridge.selected_content.visible": .bool(hasSelectedContentText),
            "agentstudio.startup_diagnostic.bridge.selected_content.state": .string(selectedContentState),
            "agentstudio.startup_diagnostic.bridge.selected_content_role.count": .int(selectedContentRoleCount),
            "agentstudio.startup_diagnostic.bridge.selected_content_cache_key.count": .int(
                selectedContentCacheKeyCount),
            "agentstudio.startup_diagnostic.bridge.selected_content_character.count": .int(
                selectedContentCharacterCount),
            "agentstudio.startup_diagnostic.bridge.selected_content_line.count": .int(selectedContentLineCount),
            "agentstudio.startup_diagnostic.bridge.selected_materialized.update_result": .string(
                selectedMaterializedUpdateResult),
            "agentstudio.startup_diagnostic.bridge.selected_materialized.item_type": .string(
                selectedMaterializedItemType),
            "agentstudio.startup_diagnostic.bridge.selected_materialized.item_version": .int(
                selectedMaterializedItemVersion),
            "agentstudio.startup_diagnostic.bridge.selected_materialized.addition_line.count": .int(
                selectedMaterializedAdditionLineCount),
            "agentstudio.startup_diagnostic.bridge.selected_materialized.deletion_line.count": .int(
                selectedMaterializedDeletionLineCount),
            "agentstudio.startup_diagnostic.bridge.selected_materialized.file_line.count": .int(
                selectedMaterializedFileLineCount),
            "agentstudio.startup_diagnostic.bridge.page_issue.count": .int(pageErrorCount),
            "agentstudio.startup_diagnostic.bridge.diff_container.count": .int(diffContainerCount),
            "agentstudio.startup_diagnostic.bridge.code_line.count": .int(codeLineCount),
            "agentstudio.startup_diagnostic.bridge.code_view_panel.width_px": .int(codeViewPanelWidth),
            "agentstudio.startup_diagnostic.bridge.code_view_panel.height_px": .int(codeViewPanelHeight),
            "agentstudio.startup_diagnostic.bridge.diff_container.width_px": .int(firstDiffContainerWidth),
            "agentstudio.startup_diagnostic.bridge.diff_container.height_px": .int(firstDiffContainerHeight),
            "agentstudio.startup_diagnostic.bridge.code_view_scroll_owner.height_px": .int(codeViewScrollOwnerHeight),
            "agentstudio.startup_diagnostic.bridge.code_view_scroll_owner.scroll_height_px": .int(
                codeViewScrollOwnerScrollHeight),
            "agentstudio.startup_diagnostic.bridge.code_view_scroll_owner.child.count": .int(
                codeViewScrollOwnerChildCount),
            "agentstudio.startup_diagnostic.bridge.code_view_scroll_owner.first_child.tag": .string(
                codeViewScrollOwnerFirstChildTag),
            "agentstudio.startup_diagnostic.bridge.code_view.instance.height_px": .int(codeViewInstanceHeight),
            "agentstudio.startup_diagnostic.bridge.code_view.instance.scroll_height_px": .int(
                codeViewInstanceScrollHeight),
            "agentstudio.startup_diagnostic.bridge.code_view.instance.item.count": .int(codeViewInstanceItemCount),
            "agentstudio.startup_diagnostic.bridge.code_view.instance.window.top_px": .int(codeViewInstanceWindowTop),
            "agentstudio.startup_diagnostic.bridge.code_view.instance.window.bottom_px": .int(
                codeViewInstanceWindowBottom),
            "agentstudio.startup_diagnostic.bridge.code_view.instance.render_state.first_index": .int(
                codeViewInstanceFirstRenderedIndex),
            "agentstudio.startup_diagnostic.bridge.code_view.instance.render_state.last_index": .int(
                codeViewInstanceLastRenderedIndex),
            "agentstudio.startup_diagnostic.bridge.code_view.instance.first_item.height_px": .int(
                codeViewInstanceFirstItemHeight),
            "agentstudio.startup_diagnostic.bridge.code_view.instance.first_item.top_px": .int(
                codeViewInstanceFirstItemTop),
            "agentstudio.startup_diagnostic.bridge.code_view.rendered_item.count": .int(codeViewRenderedItemCount),
            "agentstudio.startup_diagnostic.bridge.code_view.rendered_item.element.height_px": .int(
                codeViewRenderedItemElementHeight),
            "agentstudio.startup_diagnostic.bridge.code_view.rendered_item.element.child.count": .int(
                codeViewRenderedItemElementChildCount),
            "agentstudio.startup_diagnostic.bridge.code_view.rendered_item.element.first_child.tag": .string(
                codeViewRenderedItemElementFirstChildTag),
            "agentstudio.startup_diagnostic.bridge.code_view.rendered_item.type": .string(codeViewRenderedItemType),
            "agentstudio.startup_diagnostic.bridge.code_view.rendered_item.version": .int(codeViewRenderedItemVersion),
            "agentstudio.startup_diagnostic.bridge.diff_container.shadow_child.count": .int(
                firstDiffContainerShadowChildCount),
            "agentstudio.startup_diagnostic.bridge.diff_container.pre.count": .int(firstDiffContainerPreCount),
            "agentstudio.startup_diagnostic.bridge.diff_container.offset_height_px": .int(
                firstDiffContainerOffsetHeight),
            "agentstudio.startup_diagnostic.bridge.diff_container.scroll_height_px": .int(
                firstDiffContainerScrollHeight),
            "agentstudio.startup_diagnostic.bridge.diff_container.pre.height_px": .int(firstDiffContainerPreHeight),
            "agentstudio.startup_diagnostic.bridge.diff_container.pre_text.length": .int(
                firstDiffContainerPreTextLength),
            "agentstudio.startup_diagnostic.bridge.code_line_with_data_line.count": .int(codeLineWithDataLineCount),
            "agentstudio.startup_diagnostic.bridge.diff_container.display": .string(firstDiffContainerDisplay),
            "agentstudio.startup_diagnostic.bridge.worker_pool.state": .string(workerPoolState),
            "agentstudio.startup_diagnostic.bridge.worker_pool.manager_state": .string(workerPoolManagerState),
            "agentstudio.startup_diagnostic.bridge.worker_pool.workers_failed": .bool(workerPoolWorkersFailed),
            "agentstudio.startup_diagnostic.bridge.worker_pool.total_workers": .int(workerPoolTotalWorkers),
            "agentstudio.startup_diagnostic.bridge.worker_pool.busy_workers": .int(workerPoolBusyWorkers),
            "agentstudio.startup_diagnostic.bridge.worker_pool.queued_tasks": .int(workerPoolQueuedTasks),
            "agentstudio.startup_diagnostic.bridge.worker_pool.active_tasks": .int(workerPoolActiveTasks),
            "agentstudio.startup_diagnostic.bridge.worker_pool.file_cache_size": .int(workerPoolFileCacheSize),
            "agentstudio.startup_diagnostic.bridge.worker_pool.diff_cache_size": .int(workerPoolDiffCacheSize),
            "agentstudio.startup_diagnostic.bridge.worker_pool.init_probe.stage": .string(
                workerPoolInitializationProbeStage),
            "agentstudio.startup_diagnostic.bridge.worker_pool.init_probe.theme_count": .int(
                workerPoolInitializationProbeThemeCount),
            "agentstudio.startup_diagnostic.bridge.worker_pool.init_probe.language_count": .int(
                workerPoolInitializationProbeLanguageCount),
            "agentstudio.startup_diagnostic.bridge.worker_pool.init_probe.failure_reason": .string(
                workerPoolInitializationProbeFailureReason),
            "agentstudio.startup_diagnostic.bridge.worker_diagnostic.bootstrap_state": .string(
                workerDiagnosticBootstrapState),
            "agentstudio.startup_diagnostic.bridge.worker_diagnostic.initialize_request_id_state": .string(
                workerDiagnosticInitializeRequestIdState),
            "agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_message_type": .string(
                workerDiagnosticLastMessageType),
            "agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_request_type": .string(
                workerDiagnosticLastRequestType),
            "agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_success_matches_initialize_request": .string(
                workerDiagnosticLastSuccessMatchesInitializeRequest),
            "agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_success_id_state": .string(
                workerDiagnosticLastSuccessIdState),
            "agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_success_id_prefix": .string(
                workerDiagnosticLastSuccessIdPrefix),
            "agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_success_request_type": .string(
                workerDiagnosticLastSuccessRequestType),
            "agentstudio.startup_diagnostic.bridge.worker_diagnostic.success_count": .int(
                workerDiagnosticSuccessCount),
            "agentstudio.startup_diagnostic.bridge.worker_diagnostic.initialize_success_count": .int(
                workerDiagnosticInitializeSuccessCount),
            "agentstudio.startup_diagnostic.bridge.worker_diagnostic.diff_success_count": .int(
                workerDiagnosticDiffSuccessCount),
            "agentstudio.startup_diagnostic.bridge.worker_diagnostic.file_success_count": .int(
                workerDiagnosticFileSuccessCount),
            "agentstudio.startup_diagnostic.bridge.worker_diagnostic.forwarded_message_count": .int(
                workerDiagnosticForwardedMessageCount),
            "agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_forward_result": .string(
                workerDiagnosticLastForwardResult),
            "agentstudio.startup_diagnostic.bridge.worker_diagnostic.failure_count": .int(workerDiagnosticErrorCount),
            "agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_failure_kind": .string(
                workerDiagnosticLastErrorKind),
            "agentstudio.startup_diagnostic.bridge.code_text.length": .int(codeTextLength),
            "agentstudio.startup_diagnostic.bridge.code_shadow_text.length": .int(codeShadowTextLength),
            "agentstudio.startup_diagnostic.render_proof.succeeded": .bool(succeeded),
        ]
    }

    static func unavailable() -> Self {
        Self(
            expectedVisiblePaneCount: 1,
            hasReviewShell: false,
            hasCodeViewPanel: false,
            hasSelectedItem: false,
            hasSelectedDisplayPath: false,
            hasSelectedContentText: false,
            selectedContentState: "unavailable",
            selectedContentRoleCount: 0,
            selectedContentCacheKeyCount: 0,
            selectedContentCharacterCount: 0,
            selectedContentLineCount: 0,
            selectedMaterializedUpdateResult: "unavailable",
            selectedMaterializedItemType: "none",
            selectedMaterializedItemVersion: 0,
            selectedMaterializedAdditionLineCount: 0,
            selectedMaterializedDeletionLineCount: 0,
            selectedMaterializedFileLineCount: 0,
            pageErrorCount: 0,
            diffContainerCount: 0,
            codeLineCount: 0,
            codeViewPanelWidth: 0,
            codeViewPanelHeight: 0,
            firstDiffContainerWidth: 0,
            firstDiffContainerHeight: 0,
            codeViewScrollOwnerHeight: 0,
            codeViewScrollOwnerScrollHeight: 0,
            codeViewScrollOwnerChildCount: 0,
            codeViewScrollOwnerFirstChildTag: "unavailable",
            codeViewInstanceHeight: 0,
            codeViewInstanceScrollHeight: 0,
            codeViewInstanceItemCount: 0,
            codeViewInstanceWindowTop: 0,
            codeViewInstanceWindowBottom: 0,
            codeViewInstanceFirstRenderedIndex: -1,
            codeViewInstanceLastRenderedIndex: -1,
            codeViewInstanceFirstItemHeight: 0,
            codeViewInstanceFirstItemTop: 0,
            codeViewRenderedItemCount: 0,
            codeViewRenderedItemElementHeight: 0,
            codeViewRenderedItemElementChildCount: 0,
            codeViewRenderedItemElementFirstChildTag: "unavailable",
            codeViewRenderedItemType: "unavailable",
            codeViewRenderedItemVersion: 0,
            firstDiffContainerShadowChildCount: 0,
            firstDiffContainerPreCount: 0,
            firstDiffContainerOffsetHeight: 0,
            firstDiffContainerScrollHeight: 0,
            firstDiffContainerPreHeight: 0,
            firstDiffContainerPreTextLength: 0,
            codeLineWithDataLineCount: 0,
            firstDiffContainerDisplay: "unavailable",
            workerPoolState: "unavailable",
            workerPoolManagerState: "unavailable",
            workerPoolWorkersFailed: false,
            workerPoolTotalWorkers: 0,
            workerPoolBusyWorkers: 0,
            workerPoolQueuedTasks: 0,
            workerPoolActiveTasks: 0,
            workerPoolFileCacheSize: 0,
            workerPoolDiffCacheSize: 0,
            workerPoolInitializationProbeStage: "unavailable",
            workerPoolInitializationProbeThemeCount: 0,
            workerPoolInitializationProbeLanguageCount: 0,
            workerPoolInitializationProbeFailureReason: "",
            workerDiagnosticBootstrapState: "unavailable",
            workerDiagnosticInitializeRequestIdState: "unavailable",
            workerDiagnosticLastMessageType: "unavailable",
            workerDiagnosticLastRequestType: "unavailable",
            workerDiagnosticLastSuccessMatchesInitializeRequest: "unavailable",
            workerDiagnosticLastSuccessIdState: "unavailable",
            workerDiagnosticLastSuccessIdPrefix: "none",
            workerDiagnosticLastSuccessRequestType: "unavailable",
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
    }
}
