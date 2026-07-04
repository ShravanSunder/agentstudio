extension BridgeReviewObservabilitySmokeRenderProof {
    // swiftlint:disable:next function_body_length
    init(
        snapshot: BridgeReviewObservabilitySmokeRenderSnapshot,
        expectedVisiblePaneCount: Int,
        expectedReviewItemCount: Int
    ) {
        self.init(
            expectedVisiblePaneCount: expectedVisiblePaneCount,
            expectedReviewItemCount: expectedReviewItemCount,
            hasReviewShell: snapshot.hasReviewShell,
            reviewShellState: snapshot.reviewShellState,
            hasCodeViewPanel: snapshot.hasCodeViewPanel,
            hasSelectedItem: snapshot.hasSelectedItem,
            hasSelectedDisplayPath: snapshot.hasSelectedDisplayPath,
            reviewShellHasSelectedDisplayPath: snapshot.reviewShellHasSelectedDisplayPath,
            reviewShellSelectedContentState: snapshot.reviewShellSelectedContentState,
            selectedDemandFailedCount: snapshot.selectedDemandFailedCount,
            selectedDemandDeferredCount: snapshot.selectedDemandDeferredCount,
            selectedDemandLoadedCount: snapshot.selectedDemandLoadedCount,
            selectedDemandResultReason: snapshot.selectedDemandResultReason,
            selectedDemandResultStatus: snapshot.selectedDemandResultStatus,
            selectedDemandLoadFailureKind: snapshot.selectedDemandLoadFailureKind,
            selectedChangeKind: snapshot.selectedChangeKind,
            reviewMetadataItemCount: snapshot.reviewMetadataItemCount,
            reviewMetadataTreeRowCount: snapshot.reviewMetadataTreeRowCount,
            hasSelectedContentText: snapshot.hasSelectedContentText,
            selectedContentState: snapshot.selectedContentState,
            selectedContentRoleCount: snapshot.selectedContentRoleCount,
            selectedContentCacheKeyCount: snapshot.selectedContentCacheKeyCount,
            selectedContentRoles: snapshot.selectedContentRoles,
            selectedContentCacheKeys: snapshot.selectedContentCacheKeys,
            selectedContentCharacterCount: snapshot.selectedContentCharacterCount,
            selectedContentLineCount: snapshot.selectedContentLineCount,
            selectedMaterializedUpdateResult: snapshot.selectedMaterializedUpdateResult,
            selectedMaterializedItemType: snapshot.selectedMaterializedItemType,
            selectedMaterializedItemVersion: snapshot.selectedMaterializedItemVersion,
            selectedMaterializedAdditionLineCount: snapshot.selectedMaterializedAdditionLineCount,
            selectedMaterializedDeletionLineCount: snapshot.selectedMaterializedDeletionLineCount,
            selectedMaterializedFileLineCount: snapshot.selectedMaterializedFileLineCount,
            pageErrorCount: snapshot.pageErrorCount,
            pageIssueLastKind: snapshot.pageIssueLastKind,
            pageIssueLastClass: snapshot.pageIssueLastClass,
            pageIssueDisallowedCount: snapshot.pageIssueDisallowedCount,
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
            codeShadowTextLength: snapshot.codeShadowTextLength,
            bridgeCommandCount: snapshot.bridgeCommandCount,
            reviewIntakeReadyCommandCount: snapshot.reviewIntakeReadyCommandCount,
            bridgeResponseCount: snapshot.bridgeResponseCount,
            intakeFrameCount: snapshot.intakeFrameCount,
            reviewIntakeSnapshotFrameCount: snapshot.reviewIntakeSnapshotFrameCount,
            reviewIntakeMetadataWindowFrameCount: snapshot.reviewIntakeMetadataWindowFrameCount,
            reviewIntakeLastFrameKind: snapshot.reviewIntakeLastFrameKind,
            reviewIntakeLastStreamIdMatches: snapshot.reviewIntakeLastStreamIdMatches,
            modifiedClickTargetPath: snapshot.modifiedClickTargetPath,
            modifiedClickFilterRequested: snapshot.modifiedClickFilterRequested,
            modifiedClickRenderedRowCount: snapshot.modifiedClickRenderedRowCount,
            modifiedClickFirstRenderedPath: snapshot.modifiedClickFirstRenderedPath,
            modifiedClickSetFilterStatus: snapshot.modifiedClickSetFilterStatus,
            modifiedClickSetFilterReason: snapshot.modifiedClickSetFilterReason,
            modifiedClickSelectedPath: snapshot.modifiedClickSelectedPath,
            modifiedClickShellSelectedMatchesTarget: snapshot.modifiedClickShellSelectedMatchesTarget,
            modifiedClickSelectedChangeKind: snapshot.modifiedClickSelectedChangeKind,
            modifiedClickSelectedContentState: snapshot.modifiedClickSelectedContentState,
            modifiedClickSelectedContentRoles: snapshot.modifiedClickSelectedContentRoles,
            modifiedClickSelectedContentCacheKeys: snapshot.modifiedClickSelectedContentCacheKeys,
            modifiedClickSelectedMaterializedItemType: snapshot.modifiedClickSelectedMaterializedItemType,
            modifiedClickSelectedMaterializedItemVersion: snapshot.modifiedClickSelectedMaterializedItemVersion,
            modifiedClickSelectedCharacterCount: snapshot.modifiedClickSelectedCharacterCount,
            modifiedClickAttemptCount: snapshot.modifiedClickAttemptCount
        )
        reviewCanvasBranch = snapshot.reviewCanvasBranch
        reviewTreeScrollStressCount = snapshot.reviewTreeScrollStressCount
        reviewTreeScrollStressReachedBottom = snapshot.reviewTreeScrollStressReachedBottom
        reviewTreeClientHeight = snapshot.reviewTreeClientHeight
        reviewTreeScrollHeight = snapshot.reviewTreeScrollHeight
        reviewTreeClickTargetPath = snapshot.reviewTreeClickTargetPath
        reviewTreeClickCurrentSelectedPath = snapshot.reviewTreeClickCurrentSelectedPath
        reviewTreeClickCurrentSelectedItemId = snapshot.reviewTreeClickCurrentSelectedItemId
        reviewTreeClickShellSelectedPath = snapshot.reviewTreeClickShellSelectedPath
        reviewTreeClickRenderedRowCount = snapshot.reviewTreeClickRenderedRowCount
        reviewTreeClickTargetRowIndex = snapshot.reviewTreeClickTargetRowIndex
        reviewTreeClickTargetRowVisible = snapshot.reviewTreeClickTargetRowVisible
        reviewTreeClickAttemptCount = snapshot.reviewTreeClickAttemptCount
        reviewTreeClickSelectedPath = snapshot.reviewTreeClickSelectedPath
        reviewTreeClickSelectedContentState = snapshot.reviewTreeClickSelectedContentState
        reviewTreeClickSelectedMaterializedItemType = snapshot.reviewTreeClickSelectedMaterializedItemType
        reviewTreeClickSelectedMaterializedItemVersion = snapshot.reviewTreeClickSelectedMaterializedItemVersion
        reviewTreeClickSelectedCharacterCount = snapshot.reviewTreeClickSelectedCharacterCount
        reviewTreeClickProbeTargetRowPathAtFind = snapshot.reviewTreeClickProbeTargetRowPathAtFind
        reviewTreeClickProbeTargetRowIdAtFind = snapshot.reviewTreeClickProbeTargetRowIdAtFind
        reviewTreeClickProbeTargetRowIdAtDispatch = snapshot.reviewTreeClickProbeTargetRowIdAtDispatch
        reviewTreeClickProbeTargetRowConnectedAtDispatch =
            snapshot
            .reviewTreeClickProbeTargetRowConnectedAtDispatch
        reviewTreeClickProbeTargetRowSameIdAtDispatch = snapshot.reviewTreeClickProbeTargetRowSameIdAtDispatch
        reviewTreeClickProbeRenderedRowCountAtFind = snapshot.reviewTreeClickProbeRenderedRowCountAtFind
        reviewTreeClickProbeRenderedRowCountAtDispatch =
            snapshot
            .reviewTreeClickProbeRenderedRowCountAtDispatch
        reviewTreeClickProbeRenderedRowCountDeltaBeforeDispatch =
            snapshot
            .reviewTreeClickProbeRenderedRowCountDeltaBeforeDispatch
        reviewTreeClickProbeDispatchResult = snapshot.reviewTreeClickProbeDispatchResult
        reviewTreeClickProbeSelectionPollTrace = snapshot.reviewTreeClickProbeSelectionPollTrace
        reviewTreeClickProbeSelectionPollCount = snapshot.reviewTreeClickProbeSelectionPollCount
        reviewTreeClickProbeSelectionPollLastIndex = snapshot.reviewTreeClickProbeSelectionPollLastIndex
        reviewTreeClickProbeSecondClickAttempted = snapshot.reviewTreeClickProbeSecondClickAttempted
        reviewTreeClickProbeHandlerInvokedDelta = snapshot.reviewTreeClickProbeHandlerInvokedDelta
        reviewTreeClickProbeSelectionCommandIssuedDelta =
            snapshot.reviewTreeClickProbeSelectionCommandIssuedDelta
        reviewTreeClickProbeSelectionCommandAcceptedCount =
            snapshot.reviewTreeClickProbeSelectionCommandAcceptedCount
        reviewTreeClickProbeSelectionCommandLastResult =
            snapshot.reviewTreeClickProbeSelectionCommandLastResult
        reviewTreeClickProbeLateSelectedMatches = snapshot.reviewTreeClickProbeLateSelectedMatches
        reviewTreeClickProbePollsToSelectionMatch = snapshot.reviewTreeClickProbePollsToSelectionMatch ?? -1
        reviewTreeClickProbeClickToSelectionMs = snapshot.reviewTreeClickProbeClickToSelectionMs ?? -1
        paintedProbeAnchoredDeliveryEntryCount = snapshot.paintedProbeAnchoredDeliveryEntryCount
        paintedProbeAnchoredDeliveryAnchorPresentCount =
            snapshot.paintedProbeAnchoredDeliveryAnchorPresentCount
        paintedProbeAnchoredDeliverySelectedMatchCount =
            snapshot.paintedProbeAnchoredDeliverySelectedMatchCount
        paintedProbeAnchoredDeliveryTelemetryRecorderPresentCount =
            snapshot.paintedProbeAnchoredDeliveryTelemetryRecorderPresentCount
        paintedProbeAlreadyPaintedByHydrationCount =
            snapshot.paintedProbeAlreadyPaintedByHydrationCount
        paintedProbeScheduleEnteredCount = snapshot.paintedProbeScheduleEnteredCount
        paintedProbeEarlyReturnCount = snapshot.paintedProbeEarlyReturnCount
        paintedProbeRafScheduledCount = snapshot.paintedProbeRafScheduledCount
        paintedProbeRafFiredCount = snapshot.paintedProbeRafFiredCount
        paintedProbeGenerationSupersededCount = snapshot.paintedProbeGenerationSupersededCount
        paintedProbeSampleRecordedCount = snapshot.paintedProbeSampleRecordedCount
        paintedProbeFlushCalledCount = snapshot.paintedProbeFlushCalledCount
        paintedProbeLastAnchoredDeliveryHadAnchor =
            snapshot.paintedProbeLastAnchoredDeliveryHadAnchor
        paintedProbeLastAnchoredDeliverySelectedMatched =
            snapshot.paintedProbeLastAnchoredDeliverySelectedMatched
        paintedProbeLastAnchoredDeliveryHadTelemetryRecorder =
            snapshot.paintedProbeLastAnchoredDeliveryHadTelemetryRecorder
        paintedProbeLastReason = snapshot.paintedProbeLastReason
        paintedProbeLastScheduleEarlyReturnReason =
            snapshot.paintedProbeLastScheduleEarlyReturnReason
        frameLivenessRafAlive = snapshot.frameLivenessRafAlive ?? "unknown"
        frameLivenessRafFiredLatencyBucket = snapshot.frameLivenessRafFiredLatencyBucket ?? "unknown"
    }
}
struct BridgeReviewObservabilitySmokeRenderSnapshot: Decodable, Equatable {
    let hasReviewShell: Bool
    let reviewShellState: String?
    let reviewCanvasBranch: String
    let hasCodeViewPanel: Bool
    let hasSelectedItem: Bool
    let hasSelectedDisplayPath: Bool
    let reviewShellHasSelectedDisplayPath: Bool
    let reviewShellSelectedContentState: String
    let selectedDemandFailedCount: Int
    let selectedDemandDeferredCount: Int
    let selectedDemandLoadedCount: Int
    let selectedDemandResultReason: String
    let selectedDemandResultStatus: String
    let selectedDemandLoadFailureKind: String
    let selectedChangeKind: String
    let reviewMetadataItemCount: Int
    let reviewMetadataTreeRowCount: Int
    let reviewTreeScrollStressCount: Int
    let reviewTreeScrollStressReachedBottom: Bool
    let reviewTreeClientHeight: Int
    let reviewTreeScrollHeight: Int
    let reviewTreeClickTargetPath: String
    let reviewTreeClickCurrentSelectedPath: String
    let reviewTreeClickCurrentSelectedItemId: String
    let reviewTreeClickShellSelectedPath: String
    let reviewTreeClickRenderedRowCount: Int
    let reviewTreeClickTargetRowIndex: Int
    let reviewTreeClickTargetRowVisible: Bool
    let reviewTreeClickAttemptCount: Int
    let reviewTreeClickSelectedPath: String
    let reviewTreeClickSelectedContentState: String
    let reviewTreeClickSelectedMaterializedItemType: String
    let reviewTreeClickSelectedMaterializedItemVersion: Int
    let reviewTreeClickSelectedCharacterCount: Int
    let reviewTreeClickProbeTargetRowPathAtFind: String
    let reviewTreeClickProbeTargetRowIdAtFind: String
    let reviewTreeClickProbeTargetRowIdAtDispatch: String
    let reviewTreeClickProbeTargetRowConnectedAtDispatch: Bool
    let reviewTreeClickProbeTargetRowSameIdAtDispatch: Bool
    let reviewTreeClickProbeRenderedRowCountAtFind: Int
    let reviewTreeClickProbeRenderedRowCountAtDispatch: Int
    let reviewTreeClickProbeRenderedRowCountDeltaBeforeDispatch: Int
    let reviewTreeClickProbeDispatchResult: String
    let reviewTreeClickProbeSelectionPollTrace: String
    let reviewTreeClickProbeSelectionPollCount: Int
    let reviewTreeClickProbeSelectionPollLastIndex: Int
    let reviewTreeClickProbeSecondClickAttempted: Bool
    let reviewTreeClickProbeHandlerInvokedDelta: Int
    let reviewTreeClickProbeSelectionCommandIssuedDelta: Int
    let reviewTreeClickProbeSelectionCommandAcceptedCount: Int
    let reviewTreeClickProbeSelectionCommandLastResult: String
    let reviewTreeClickProbeLateSelectedMatches: Bool
    let reviewTreeClickProbePollsToSelectionMatch: Int?
    let reviewTreeClickProbeClickToSelectionMs: Int?
    let hasSelectedContentText: Bool
    let selectedContentState: String
    let selectedContentRoleCount: Int
    let selectedContentCacheKeyCount: Int
    let selectedContentRoles: String
    let selectedContentCacheKeys: String
    let selectedContentCharacterCount: Int
    let selectedContentLineCount: Int
    let selectedMaterializedUpdateResult: String
    let selectedMaterializedItemType: String
    let selectedMaterializedItemVersion: Int
    let selectedMaterializedAdditionLineCount: Int
    let selectedMaterializedDeletionLineCount: Int
    let selectedMaterializedFileLineCount: Int
    let paintedProbeAnchoredDeliveryEntryCount: Int
    let paintedProbeAnchoredDeliveryAnchorPresentCount: Int
    let paintedProbeAnchoredDeliverySelectedMatchCount: Int
    let paintedProbeAnchoredDeliveryTelemetryRecorderPresentCount: Int
    let paintedProbeAlreadyPaintedByHydrationCount: Int
    let paintedProbeScheduleEnteredCount: Int
    let paintedProbeEarlyReturnCount: Int
    let paintedProbeRafScheduledCount: Int
    let paintedProbeRafFiredCount: Int
    let paintedProbeGenerationSupersededCount: Int
    let paintedProbeSampleRecordedCount: Int
    let paintedProbeFlushCalledCount: Int
    let paintedProbeLastAnchoredDeliveryHadAnchor: Bool
    let paintedProbeLastAnchoredDeliverySelectedMatched: Bool
    let paintedProbeLastAnchoredDeliveryHadTelemetryRecorder: Bool
    let paintedProbeLastReason: String
    let paintedProbeLastScheduleEarlyReturnReason: String
    var frameLivenessRafAlive: String?
    var frameLivenessRafFiredLatencyBucket: String?
    let pageErrorCount: Int
    let pageIssueLastKind: String
    let pageIssueLastClass: String
    let pageIssueDisallowedCount: Int
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
    let bridgeCommandCount: Int
    let reviewIntakeReadyCommandCount: Int
    let bridgeResponseCount: Int
    let intakeFrameCount: Int
    let reviewIntakeSnapshotFrameCount: Int
    let reviewIntakeMetadataWindowFrameCount: Int
    let reviewIntakeLastFrameKind: String
    let reviewIntakeLastStreamIdMatches: Bool
    let modifiedClickTargetPath: String
    let modifiedClickFilterRequested: Bool
    let modifiedClickRenderedRowCount: Int
    let modifiedClickFirstRenderedPath: String
    let modifiedClickSetFilterStatus: String
    let modifiedClickSetFilterReason: String
    let modifiedClickSelectedPath: String
    let modifiedClickShellSelectedMatchesTarget: Bool
    let modifiedClickSelectedChangeKind: String
    let modifiedClickSelectedContentState: String
    let modifiedClickSelectedContentRoles: String
    let modifiedClickSelectedContentCacheKeys: String
    let modifiedClickSelectedMaterializedItemType: String
    let modifiedClickSelectedMaterializedItemVersion: Int
    let modifiedClickSelectedCharacterCount: Int
    let modifiedClickAttemptCount: Int
}

struct BridgeReviewObservabilitySmokeRenderProof: Equatable {
    private static let reviewTreeClickSelectionPollBudget = 160

    let expectedVisiblePaneCount: Int
    let expectedReviewItemCount: Int
    let hasReviewShell: Bool
    let reviewShellState: String?
    var reviewCanvasBranch: String = "missing"
    let hasCodeViewPanel: Bool
    let hasSelectedItem: Bool
    let hasSelectedDisplayPath: Bool
    var reviewShellHasSelectedDisplayPath: Bool = false
    var reviewShellSelectedContentState: String = "missing"
    var selectedDemandFailedCount: Int = 0
    var selectedDemandDeferredCount: Int = 0
    var selectedDemandLoadedCount: Int = 0
    var selectedDemandResultReason: String = "missing"
    var selectedDemandResultStatus: String = "missing"
    var selectedDemandLoadFailureKind: String = "missing"
    var selectedChangeKind: String = "missing"
    let reviewMetadataItemCount: Int
    let reviewMetadataTreeRowCount: Int
    var reviewTreeScrollStressCount: Int = 4
    var reviewTreeScrollStressReachedBottom: Bool = true
    var reviewTreeClientHeight: Int = 1
    var reviewTreeScrollHeight: Int = 1
    var reviewTreeClickTargetPath: String = "Sources/App/ReviewTreeClick.swift"
    var reviewTreeClickCurrentSelectedPath: String = "Sources/App/ReviewTreeClick.swift"
    var reviewTreeClickCurrentSelectedItemId: String = "review-tree-click-item"
    var reviewTreeClickShellSelectedPath: String = "Sources/App/ReviewTreeClick.swift"
    var reviewTreeClickRenderedRowCount: Int = 1
    var reviewTreeClickTargetRowIndex: Int = 0
    var reviewTreeClickTargetRowVisible: Bool = true
    var reviewTreeClickAttemptCount: Int = 1
    var reviewTreeClickSelectedPath: String = "Sources/App/ReviewTreeClick.swift"
    var reviewTreeClickSelectedContentState: String = "ready"
    var reviewTreeClickSelectedMaterializedItemType: String = "diff"
    var reviewTreeClickSelectedMaterializedItemVersion: Int = 1
    var reviewTreeClickSelectedCharacterCount: Int = 1
    var reviewTreeClickProbeTargetRowPathAtFind: String = ""
    var reviewTreeClickProbeTargetRowIdAtFind: String = ""
    var reviewTreeClickProbeTargetRowIdAtDispatch: String = ""
    var reviewTreeClickProbeTargetRowConnectedAtDispatch: Bool = false
    var reviewTreeClickProbeTargetRowSameIdAtDispatch: Bool = false
    var reviewTreeClickProbeRenderedRowCountAtFind: Int = 0
    var reviewTreeClickProbeRenderedRowCountAtDispatch: Int = 0
    var reviewTreeClickProbeRenderedRowCountDeltaBeforeDispatch: Int = 0
    var reviewTreeClickProbeDispatchResult: String = "missing"
    var reviewTreeClickProbeSelectionPollTrace: String = ""
    var reviewTreeClickProbeSelectionPollCount: Int = 0
    var reviewTreeClickProbeSelectionPollLastIndex: Int = -1
    var reviewTreeClickProbeSecondClickAttempted: Bool = false
    var reviewTreeClickProbeHandlerInvokedDelta: Int = 0
    var reviewTreeClickProbeSelectionCommandIssuedDelta: Int = 0
    var reviewTreeClickProbeSelectionCommandAcceptedCount: Int = 0
    var reviewTreeClickProbeSelectionCommandLastResult: String = "missing"
    var reviewTreeClickProbeLateSelectedMatches: Bool = false
    var reviewTreeClickProbePollsToSelectionMatch: Int = -1
    var reviewTreeClickProbeClickToSelectionMs: Int = -1
    let hasSelectedContentText: Bool
    let selectedContentState: String
    let selectedContentRoleCount: Int
    let selectedContentCacheKeyCount: Int
    var selectedContentRoles: String = ""
    var selectedContentCacheKeys: String = ""
    let selectedContentCharacterCount: Int
    let selectedContentLineCount: Int
    let selectedMaterializedUpdateResult: String
    let selectedMaterializedItemType: String
    let selectedMaterializedItemVersion: Int
    let selectedMaterializedAdditionLineCount: Int
    let selectedMaterializedDeletionLineCount: Int
    let selectedMaterializedFileLineCount: Int
    var paintedProbeAnchoredDeliveryEntryCount: Int = 0
    var paintedProbeAnchoredDeliveryAnchorPresentCount: Int = 0
    var paintedProbeAnchoredDeliverySelectedMatchCount: Int = 0
    var paintedProbeAnchoredDeliveryTelemetryRecorderPresentCount: Int = 0
    var paintedProbeAlreadyPaintedByHydrationCount: Int = 0
    var paintedProbeScheduleEnteredCount: Int = 0
    var paintedProbeEarlyReturnCount: Int = 0
    var paintedProbeRafScheduledCount: Int = 0
    var paintedProbeRafFiredCount: Int = 0
    var paintedProbeGenerationSupersededCount: Int = 0
    var paintedProbeSampleRecordedCount: Int = 0
    var paintedProbeFlushCalledCount: Int = 0
    var paintedProbeLastAnchoredDeliveryHadAnchor: Bool = false
    var paintedProbeLastAnchoredDeliverySelectedMatched: Bool = false
    var paintedProbeLastAnchoredDeliveryHadTelemetryRecorder: Bool = false
    var paintedProbeLastReason: String = "none"
    var paintedProbeLastScheduleEarlyReturnReason: String = "none"
    var frameLivenessRafAlive: String = "unknown"
    var frameLivenessRafFiredLatencyBucket: String = "unknown"
    let pageErrorCount: Int
    let pageIssueLastKind: String
    let pageIssueLastClass: String
    var pageIssueDisallowedCount: Int = 0
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
    var bridgeCommandCount: Int = 1
    var reviewIntakeReadyCommandCount: Int = 1
    var bridgeResponseCount: Int = 1
    var intakeFrameCount: Int = 1
    var reviewIntakeSnapshotFrameCount: Int = 1
    var reviewIntakeMetadataWindowFrameCount: Int = 1
    var reviewIntakeLastFrameKind: String = "review.metadataWindow"
    var reviewIntakeLastStreamIdMatches: Bool = true
    var modifiedClickTargetPath: String = ""
    var modifiedClickFilterRequested: Bool = false
    var modifiedClickRenderedRowCount: Int = 0
    var modifiedClickFirstRenderedPath: String = ""
    var modifiedClickSetFilterStatus: String = "missing"
    var modifiedClickSetFilterReason: String = "missing"
    var modifiedClickSelectedPath: String = ""
    var modifiedClickShellSelectedMatchesTarget: Bool = false
    var modifiedClickSelectedChangeKind: String = "missing"
    var modifiedClickSelectedContentState: String = "missing"
    var modifiedClickSelectedContentRoles: String = ""
    var modifiedClickSelectedContentCacheKeys: String = ""
    var modifiedClickSelectedMaterializedItemType: String = "missing"
    var modifiedClickSelectedMaterializedItemVersion: Int = 0
    var modifiedClickSelectedCharacterCount: Int = 0
    var modifiedClickAttemptCount: Int = 0

    var succeeded: Bool {
        let selectedMaterializedLineCount =
            selectedMaterializedAdditionLineCount
            + selectedMaterializedDeletionLineCount
            + selectedMaterializedFileLineCount
        let modifiedClickRoles = Set(
            modifiedClickSelectedContentRoles
                .split(separator: ",")
                .map(String.init)
        )
        let modifiedClickConverged =
            !modifiedClickTargetPath.isEmpty
            && modifiedClickSelectedPath == modifiedClickTargetPath
            && modifiedClickSelectedChangeKind == "modified"
            && modifiedClickSelectedContentState == "ready"
            && modifiedClickSelectedMaterializedItemType == "diff"
            && modifiedClickSelectedMaterializedItemVersion > 0
            && modifiedClickSelectedCharacterCount > 0
            && modifiedClickRoles.contains("base")
            && modifiedClickRoles.contains("head")
            && modifiedClickSelectedContentCacheKeys.contains("base:")
            && modifiedClickSelectedContentCacheKeys.contains("head:")
        let hasOnlyAllowedPageIssues = pageIssueDisallowedCount == 0
        let hasNativeReviewIntakeLineage =
            bridgeCommandCount > 0
            && reviewIntakeReadyCommandCount > 0
            && bridgeResponseCount > 0
            && intakeFrameCount > 0
            && reviewIntakeSnapshotFrameCount > 0
            && reviewIntakeMetadataWindowFrameCount > 0
            && reviewIntakeLastFrameKind != "none"
            && reviewIntakeLastStreamIdMatches
        let reviewTreeScrollStressConverged =
            reviewTreeScrollStressCount >= 4
            && reviewTreeScrollStressReachedBottom
            && reviewTreeClientHeight > 0
            && reviewTreeScrollHeight >= reviewTreeClientHeight
        let reviewTreeClickSelectionMatchedWithinBudget =
            reviewTreeClickProbePollsToSelectionMatch >= 0
            && reviewTreeClickProbePollsToSelectionMatch < Self.reviewTreeClickSelectionPollBudget
        let reviewTreeClickSelectedPathMatches =
            !reviewTreeClickTargetPath.isEmpty
            && reviewTreeClickSelectedPath == reviewTreeClickTargetPath
        let reviewTreeClickConverged =
            !reviewTreeClickTargetPath.isEmpty
            && (reviewTreeClickSelectedPathMatches
                || reviewTreeClickSelectionMatchedWithinBudget
                || reviewTreeClickProbeLateSelectedMatches)
        return expectedVisiblePaneCount == 1
            && expectedReviewItemCount > 0
            && hasReviewShell
            && hasCodeViewPanel
            && hasSelectedItem
            && hasSelectedDisplayPath
            && reviewMetadataItemCount > 0
            && reviewMetadataItemCount == expectedReviewItemCount
            && reviewMetadataTreeRowCount >= reviewMetadataItemCount
            && hasSelectedContentText
            && selectedContentState == "ready"
            && selectedContentRoleCount > 0
            && selectedContentCacheKeyCount > 0
            && selectedContentCharacterCount > 0
            && selectedMaterializedUpdateResult == "updated"
            && selectedMaterializedItemVersion > 0
            && selectedMaterializedLineCount > 0
            && diffContainerCount > 0
            && codeViewPanelWidth > 0
            && codeViewPanelHeight > 0
            && firstDiffContainerWidth > 0
            && codeViewInstanceFirstItemHeight > 0
            && codeViewRenderedItemCount > 0
            && codeViewRenderedItemType == selectedMaterializedItemType
            && codeViewRenderedItemVersion == selectedMaterializedItemVersion
            && codeTextLength > 0
            && codeShadowTextLength > 0
            && workerPoolState == "ready"
            && workerPoolManagerState == "initialized"
            && !workerPoolWorkersFailed
            && workerDiagnosticDiffSuccessCount > 0
            && workerDiagnosticErrorCount == 0
            && hasOnlyAllowedPageIssues
            && reviewTreeScrollStressConverged
            && reviewTreeClickConverged
            && modifiedClickConverged
            && hasNativeReviewIntakeLineage
    }

    var attributes: [String: AgentStudioTraceValue] {
        [
            "agentstudio.startup_diagnostic.expected_visible_pane.count": .int(expectedVisiblePaneCount),
            "agentstudio.startup_diagnostic.bridge.review_expected_item.count": .int(expectedReviewItemCount),
            "agentstudio.startup_diagnostic.bridge.review_shell.visible": .bool(hasReviewShell),
            "agentstudio.startup_diagnostic.bridge.review_shell.state": .string(
                reviewShellState ?? (hasReviewShell ? "ready" : "missing")),
            "agentstudio.startup_diagnostic.bridge.review_canvas.branch": .string(reviewCanvasBranch),
            "agentstudio.startup_diagnostic.bridge.code_view.visible": .bool(hasCodeViewPanel),
            "agentstudio.startup_diagnostic.bridge.selected_item.visible": .bool(hasSelectedItem),
            "agentstudio.startup_diagnostic.bridge.selected_path.visible": .bool(hasSelectedDisplayPath),
            "agentstudio.startup_diagnostic.bridge.review_shell.selected_path.visible": .bool(
                reviewShellHasSelectedDisplayPath),
            "agentstudio.startup_diagnostic.bridge.review_shell.selected_content.state": .string(
                reviewShellSelectedContentState),
            "agentstudio.startup_diagnostic.bridge.selected_demand.failed.count": .int(
                selectedDemandFailedCount),
            "agentstudio.startup_diagnostic.bridge.selected_demand.deferred.count": .int(
                selectedDemandDeferredCount),
            "agentstudio.startup_diagnostic.bridge.selected_demand.loaded.count": .int(
                selectedDemandLoadedCount),
            "agentstudio.startup_diagnostic.bridge.selected_demand.result.reason": .string(
                selectedDemandResultReason),
            "agentstudio.startup_diagnostic.bridge.selected_demand.result.status": .string(
                selectedDemandResultStatus),
            "agentstudio.startup_diagnostic.bridge.selected_demand.load_failure.kind": .string(
                selectedDemandLoadFailureKind),
            "agentstudio.startup_diagnostic.bridge.selected_change_kind": .string(selectedChangeKind),
            "agentstudio.startup_diagnostic.bridge.review_metadata_item.count": .int(reviewMetadataItemCount),
            "agentstudio.startup_diagnostic.bridge.review_metadata_tree_row.count": .int(reviewMetadataTreeRowCount),
            "agentstudio.startup_diagnostic.bridge.review_metadata.converged": .bool(
                reviewMetadataItemCount == expectedReviewItemCount),
            "agentstudio.startup_diagnostic.bridge.review_tree_scroll_stress.count": .int(
                reviewTreeScrollStressCount),
            "agentstudio.startup_diagnostic.bridge.review_tree_scroll_stress.reached_bottom": .bool(
                reviewTreeScrollStressReachedBottom),
            "agentstudio.startup_diagnostic.bridge.review_tree.client_height_px": .int(reviewTreeClientHeight),
            "agentstudio.startup_diagnostic.bridge.review_tree.scroll_height_px": .int(reviewTreeScrollHeight),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.target_path": .string(
                reviewTreeClickTargetPath),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.current_selected_path": .string(
                reviewTreeClickCurrentSelectedPath),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.current_selected_item_id": .string(
                reviewTreeClickCurrentSelectedItemId),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.shell_selected_path": .string(
                reviewTreeClickShellSelectedPath),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.rendered_row.count": .int(
                reviewTreeClickRenderedRowCount),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.target_row.index": .int(
                reviewTreeClickTargetRowIndex),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.target_row.visible": .bool(
                reviewTreeClickTargetRowVisible),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.click_attempt.count": .int(
                reviewTreeClickAttemptCount),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.selected_path": .string(
                reviewTreeClickSelectedPath),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.selected_matches_target": .bool(
                !reviewTreeClickTargetPath.isEmpty && reviewTreeClickSelectedPath == reviewTreeClickTargetPath),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.selected_content_state": .string(
                reviewTreeClickSelectedContentState),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.selected_materialized.item_type": .string(
                reviewTreeClickSelectedMaterializedItemType),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.selected_materialized.item_version": .int(
                reviewTreeClickSelectedMaterializedItemVersion),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.selected_content_character.count": .int(
                reviewTreeClickSelectedCharacterCount),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.target_row_path_at_find": .string(
                reviewTreeClickProbeTargetRowPathAtFind),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.target_row_id_at_find": .string(
                reviewTreeClickProbeTargetRowIdAtFind),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.target_row_id_at_dispatch": .string(
                reviewTreeClickProbeTargetRowIdAtDispatch),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.target_row_connected_at_dispatch": .bool(
                reviewTreeClickProbeTargetRowConnectedAtDispatch),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.target_row_same_id_at_dispatch": .bool(
                reviewTreeClickProbeTargetRowSameIdAtDispatch),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.rendered_row_count_at_find": .int(
                reviewTreeClickProbeRenderedRowCountAtFind),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.rendered_row_count_at_dispatch": .int(
                reviewTreeClickProbeRenderedRowCountAtDispatch),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.rendered_row_count_delta_before_dispatch":
                .int(reviewTreeClickProbeRenderedRowCountDeltaBeforeDispatch),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.dispatch_result": .string(
                reviewTreeClickProbeDispatchResult),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.selection_poll_trace": .string(
                reviewTreeClickProbeSelectionPollTrace),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.selection_poll.count": .int(
                reviewTreeClickProbeSelectionPollCount),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.selection_poll.last_index": .int(
                reviewTreeClickProbeSelectionPollLastIndex),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.second_click_attempted": .bool(
                reviewTreeClickProbeSecondClickAttempted),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.handler_invoked_delta": .int(
                reviewTreeClickProbeHandlerInvokedDelta),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.selection_command_issued_delta": .int(
                reviewTreeClickProbeSelectionCommandIssuedDelta),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.selection_command_accepted.count": .int(
                reviewTreeClickProbeSelectionCommandAcceptedCount),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.selection_command.last_result": .string(
                reviewTreeClickProbeSelectionCommandLastResult),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.late_selected_matches": .bool(
                reviewTreeClickProbeLateSelectedMatches),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.polls_to_selection_match": .int(
                reviewTreeClickProbePollsToSelectionMatch),
            "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.click_to_selection_ms": .int(
                reviewTreeClickProbeClickToSelectionMs),
            "agentstudio.startup_diagnostic.bridge.selected_content.visible": .bool(hasSelectedContentText),
            "agentstudio.startup_diagnostic.bridge.selected_content.state": .string(selectedContentState),
            "agentstudio.startup_diagnostic.bridge.selected_content_role.count": .int(selectedContentRoleCount),
            "agentstudio.startup_diagnostic.bridge.selected_content_cache_key.count": .int(
                selectedContentCacheKeyCount),
            "agentstudio.startup_diagnostic.bridge.selected_content.roles": .string(selectedContentRoles),
            "agentstudio.startup_diagnostic.bridge.selected_content.cache_keys": .string(selectedContentCacheKeys),
            "agentstudio.startup_diagnostic.bridge.selected_content.cache_keys_present": .bool(
                selectedContentCacheKeys.contains("base:") || selectedContentCacheKeys.contains("head:")),
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
            "agentstudio.startup_diagnostic.bridge.painted_probe.anchored_delivery_entry.count": .int(
                paintedProbeAnchoredDeliveryEntryCount),
            "agentstudio.startup_diagnostic.bridge.painted_probe.anchored_delivery_anchor_present.count": .int(
                paintedProbeAnchoredDeliveryAnchorPresentCount),
            "agentstudio.startup_diagnostic.bridge.painted_probe.anchored_delivery_selected_match.count": .int(
                paintedProbeAnchoredDeliverySelectedMatchCount),
            "agentstudio.startup_diagnostic.bridge.painted_probe.anchored_delivery_recorder_present.count": .int(
                paintedProbeAnchoredDeliveryTelemetryRecorderPresentCount),
            "agentstudio.startup_diagnostic.bridge.painted_probe.already_painted_by_hydration.count": .int(
                paintedProbeAlreadyPaintedByHydrationCount),
            "agentstudio.startup_diagnostic.bridge.painted_probe.schedule_entered.count": .int(
                paintedProbeScheduleEnteredCount),
            "agentstudio.startup_diagnostic.bridge.painted_probe.early_return.count": .int(
                paintedProbeEarlyReturnCount),
            "agentstudio.startup_diagnostic.bridge.painted_probe.raf_scheduled.count": .int(
                paintedProbeRafScheduledCount),
            "agentstudio.startup_diagnostic.bridge.painted_probe.raf_fired.count": .int(
                paintedProbeRafFiredCount),
            "agentstudio.startup_diagnostic.bridge.painted_probe.generation_superseded.count": .int(
                paintedProbeGenerationSupersededCount),
            "agentstudio.startup_diagnostic.bridge.painted_probe.sample_recorded.count": .int(
                paintedProbeSampleRecordedCount),
            "agentstudio.startup_diagnostic.bridge.painted_probe.flush_called.count": .int(
                paintedProbeFlushCalledCount),
            "agentstudio.startup_diagnostic.bridge.painted_probe.last_anchored_delivery.had_anchor": .bool(
                paintedProbeLastAnchoredDeliveryHadAnchor),
            "agentstudio.startup_diagnostic.bridge.painted_probe.last_anchored_delivery.selected_matched": .bool(
                paintedProbeLastAnchoredDeliverySelectedMatched),
            "agentstudio.startup_diagnostic.bridge.painted_probe.last_anchored_delivery.had_recorder": .bool(
                paintedProbeLastAnchoredDeliveryHadTelemetryRecorder),
            "agentstudio.startup_diagnostic.bridge.painted_probe.last_reason": .string(
                paintedProbeLastReason),
            "agentstudio.startup_diagnostic.bridge.painted_probe.last_schedule_early_return.reason": .string(
                paintedProbeLastScheduleEarlyReturnReason),
            "agentstudio.startup_diagnostic.bridge.frame_liveness.raf_alive": .string(
                frameLivenessRafAlive),
            "agentstudio.startup_diagnostic.bridge.frame_liveness.raf_fired_latency.bucket": .string(
                frameLivenessRafFiredLatencyBucket),
            "agentstudio.startup_diagnostic.bridge.page_issue.count": .int(pageErrorCount),
            "agentstudio.startup_diagnostic.bridge.page_issue.last_kind": .string(pageIssueLastKind),
            "agentstudio.startup_diagnostic.bridge.page_issue.last_class": .string(pageIssueLastClass),
            "agentstudio.startup_diagnostic.bridge.page_issue.disallowed.count": .int(pageIssueDisallowedCount),
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
            "agentstudio.startup_diagnostic.bridge.bridge_command.count": .int(bridgeCommandCount),
            "agentstudio.startup_diagnostic.bridge.review_intake_ready_command.count": .int(
                reviewIntakeReadyCommandCount),
            "agentstudio.startup_diagnostic.bridge.bridge_response.count": .int(bridgeResponseCount),
            "agentstudio.startup_diagnostic.bridge.intake_frame.count": .int(intakeFrameCount),
            "agentstudio.startup_diagnostic.bridge.review_intake_snapshot_frame.count": .int(
                reviewIntakeSnapshotFrameCount),
            "agentstudio.startup_diagnostic.bridge.review_intake_metadata_window_frame.count": .int(
                reviewIntakeMetadataWindowFrameCount),
            "agentstudio.startup_diagnostic.bridge.review_intake.last_frame_kind": .string(
                reviewIntakeLastFrameKind),
            "agentstudio.startup_diagnostic.bridge.review_intake.last_stream_id_matches": .bool(
                reviewIntakeLastStreamIdMatches),
            "agentstudio.startup_diagnostic.bridge.modified_click.target_path": .string(modifiedClickTargetPath),
            "agentstudio.startup_diagnostic.bridge.modified_click.filter_requested": .bool(
                modifiedClickFilterRequested),
            "agentstudio.startup_diagnostic.bridge.modified_click.click_attempt.count": .int(
                modifiedClickAttemptCount),
            "agentstudio.startup_diagnostic.bridge.modified_click.target_found": .bool(
                !modifiedClickTargetPath.isEmpty),
            "agentstudio.startup_diagnostic.bridge.modified_click.rendered_row.count": .int(
                modifiedClickRenderedRowCount),
            "agentstudio.startup_diagnostic.bridge.modified_click.first_rendered_present": .bool(
                !modifiedClickFirstRenderedPath.isEmpty),
            "agentstudio.startup_diagnostic.bridge.modified_click.first_rendered_path": .string(
                modifiedClickFirstRenderedPath),
            "agentstudio.startup_diagnostic.bridge.modified_click.set_filter.status": .string(
                modifiedClickSetFilterStatus),
            "agentstudio.startup_diagnostic.bridge.modified_click.set_filter.reason": .string(
                modifiedClickSetFilterReason),
            "agentstudio.startup_diagnostic.bridge.modified_click.selected_path": .string(
                modifiedClickSelectedPath),
            "agentstudio.startup_diagnostic.bridge.modified_click.selected_matches_target": .bool(
                !modifiedClickTargetPath.isEmpty && modifiedClickSelectedPath == modifiedClickTargetPath),
            "agentstudio.startup_diagnostic.bridge.modified_click.shell_selected_matches_target": .bool(
                modifiedClickShellSelectedMatchesTarget),
            "agentstudio.startup_diagnostic.bridge.modified_click.selected_change_kind": .string(
                modifiedClickSelectedChangeKind),
            "agentstudio.startup_diagnostic.bridge.modified_click.selected_content_state": .string(
                modifiedClickSelectedContentState),
            "agentstudio.startup_diagnostic.bridge.modified_click.selected_content.roles": .string(
                modifiedClickSelectedContentRoles),
            "agentstudio.startup_diagnostic.bridge.modified_click.selected_content.cache_keys": .string(
                modifiedClickSelectedContentCacheKeys),
            "agentstudio.startup_diagnostic.bridge.modified_click.selected_content.cache_keys_present": .bool(
                modifiedClickSelectedContentCacheKeys.contains("base:")
                    || modifiedClickSelectedContentCacheKeys.contains("head:")),
            "agentstudio.startup_diagnostic.bridge.modified_click.selected_materialized.item_type": .string(
                modifiedClickSelectedMaterializedItemType),
            "agentstudio.startup_diagnostic.bridge.modified_click.selected_materialized.item_version": .int(
                modifiedClickSelectedMaterializedItemVersion),
            "agentstudio.startup_diagnostic.bridge.modified_click.selected_content_character.count": .int(
                modifiedClickSelectedCharacterCount),
            "agentstudio.startup_diagnostic.render_proof.succeeded": .bool(succeeded),
        ]
    }

}
