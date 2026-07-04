struct BridgeFileViewObservabilitySmokeRenderSnapshot: Decodable, Equatable {
    let hasFileShell: Bool
    let hasTree: Bool
    let hasCodeViewPanel: Bool
    let bootstrapProtocol: String
    let bootstrapSourceSpecState: String
    let bootstrapSourceSpecLength: Int
    let descriptorCount: Int
    let totalDescriptorCount: Int
    let selectedDisplayPath: String
    let treeExtentKind: String
    let treePathCount: Int
    let metadataTreeRowCount: Int
    let metadataFileRowCount: Int
    let sourceState: String
    let openFileState: String
    let openFilePath: String
    let renderedFilePath: String
    let bodyPreviewLength: Int
    var clickTargetPath: String?
    var clickSelectedPath: String?
    var clickOpenFilePath: String?
    var clickRenderedFilePath: String?
    var clickBodyPreviewLength: Int?
    var secondClickTargetPath: String?
    var secondClickSelectedPath: String?
    var secondClickOpenFilePath: String?
    var secondClickRenderedFilePath: String?
    var secondClickBodyPreviewLength: Int?
    var offscreenClickTargetPath: String?
    var offscreenClickSelectedPath: String?
    var offscreenClickOpenFilePath: String?
    var offscreenClickRenderedFilePath: String?
    var offscreenClickBodyPreviewLength: Int?
    let modeSwitchCount: Int
    let finalFileContextSelected: Bool
    let treeScrollStressCount: Int
    let treeScrollStressReachedBottom: Bool
    let treeHeight: Int
    let codeViewPanelWidth: Int
    let codeViewPanelHeight: Int
    let codeTextLength: Int
    let workerPoolState: String
    let workerPoolManagerState: String
    let workerPoolWorkersFailed: Bool
    let workerDiagnosticFileSuccessCount: Int
    let workerDiagnosticErrorCount: Int
    var frameLivenessRafAlive: String?
    var frameLivenessRafFiredLatencyBucket: String?
    let pageErrorCount: Int
    let pageIssueLastKind: String
    let pageIssueLastClass: String
    let pageIssueDisallowedCount: Int
    let bridgeCommandCount: Int
    let worktreeOpenSourceCommandCount: Int
    let intakeReadyCommandCount: Int
    let worktreeDescriptorRequestCommandCount: Int
    let bridgeResponseCount: Int
    let intakeFrameCount: Int
    let nativeWorktreeProbeCount: Int
    let nativeWorktreeProbeLastReason: String
    let nativeWorktreeProbeLastReceiverReason: String
    let nativeWorktreeProbeLastFrameKind: String
    let nativeWorktreeProbeLastGeneration: Int
    let nativeWorktreeProbeLastReceiverGeneration: Int
    let nativeWorktreeProbeLastSequence: Int
    let nativeWorktreeProbeLastStreamIdMatches: Bool
    let nativeWorktreeProbeFrameEvidenceCount: Int
    let nativeWorktreeProbeFinalGeneration: Int
    let nativeWorktreeProbeFinalGenerationFrameEvidenceCount: Int
    let nativeWorktreeProbeBenignReceiverGenerationBucketDropCount: Int
    let nativeWorktreeProbeFailureDropCount: Int
    let nativeWorktreeProbeFinalGenerationFailureDropCount: Int
}

struct BridgeFileViewObservabilitySmokeRenderProof: Equatable {
    private static let startupTreeWindowRowLimit = 200

    let expectedVisiblePaneCount: Int
    let expectedBootstrapProtocol: String
    let hasFileShell: Bool
    let hasTree: Bool
    let hasCodeViewPanel: Bool
    let bootstrapProtocol: String
    let bootstrapSourceSpecState: String
    let bootstrapSourceSpecLength: Int
    let descriptorCount: Int
    let totalDescriptorCount: Int
    let selectedDisplayPath: String
    let treeExtentKind: String
    let treePathCount: Int
    let metadataTreeRowCount: Int
    let metadataFileRowCount: Int
    let sourceState: String
    let openFileState: String
    let openFilePath: String
    let renderedFilePath: String
    let bodyPreviewLength: Int
    let clickTargetPath: String?
    let clickSelectedPath: String?
    let clickOpenFilePath: String?
    let clickRenderedFilePath: String?
    let clickBodyPreviewLength: Int?
    let secondClickTargetPath: String?
    let secondClickSelectedPath: String?
    let secondClickOpenFilePath: String?
    let secondClickRenderedFilePath: String?
    let secondClickBodyPreviewLength: Int?
    let offscreenClickTargetPath: String?
    let offscreenClickSelectedPath: String?
    let offscreenClickOpenFilePath: String?
    let offscreenClickRenderedFilePath: String?
    let offscreenClickBodyPreviewLength: Int?
    let modeSwitchCount: Int
    let finalFileContextSelected: Bool
    let treeScrollStressCount: Int
    let treeScrollStressReachedBottom: Bool
    let treeHeight: Int
    let codeViewPanelWidth: Int
    let codeViewPanelHeight: Int
    let codeTextLength: Int
    let workerPoolState: String
    let workerPoolManagerState: String
    let workerPoolWorkersFailed: Bool
    let workerDiagnosticFileSuccessCount: Int
    let workerDiagnosticErrorCount: Int
    let frameLivenessRafAlive: String
    let frameLivenessRafFiredLatencyBucket: String
    let pageErrorCount: Int
    let pageIssueLastKind: String
    let pageIssueLastClass: String
    let pageIssueDisallowedCount: Int
    let bridgeCommandCount: Int
    let worktreeOpenSourceCommandCount: Int
    let intakeReadyCommandCount: Int
    let worktreeDescriptorRequestCommandCount: Int
    let bridgeResponseCount: Int
    let intakeFrameCount: Int
    let nativeWorktreeProbeCount: Int
    let nativeWorktreeProbeLastReason: String
    let nativeWorktreeProbeLastReceiverReason: String
    let nativeWorktreeProbeLastFrameKind: String
    let nativeWorktreeProbeLastGeneration: Int
    let nativeWorktreeProbeLastReceiverGeneration: Int
    let nativeWorktreeProbeLastSequence: Int
    let nativeWorktreeProbeLastStreamIdMatches: Bool
    let nativeWorktreeProbeFrameEvidenceCount: Int
    let nativeWorktreeProbeFinalGeneration: Int
    let nativeWorktreeProbeFinalGenerationFrameEvidenceCount: Int
    let nativeWorktreeProbeBenignReceiverGenerationBucketDropCount: Int
    let nativeWorktreeProbeFailureDropCount: Int
    let nativeWorktreeProbeFinalGenerationFailureDropCount: Int

    init(
        snapshot: BridgeFileViewObservabilitySmokeRenderSnapshot,
        expectedVisiblePaneCount: Int,
        expectedBootstrapProtocol: String = "worktree-file"
    ) {
        self.expectedVisiblePaneCount = expectedVisiblePaneCount
        self.expectedBootstrapProtocol = expectedBootstrapProtocol
        hasFileShell = snapshot.hasFileShell
        hasTree = snapshot.hasTree
        hasCodeViewPanel = snapshot.hasCodeViewPanel
        bootstrapProtocol = snapshot.bootstrapProtocol
        bootstrapSourceSpecState = snapshot.bootstrapSourceSpecState
        bootstrapSourceSpecLength = snapshot.bootstrapSourceSpecLength
        descriptorCount = snapshot.descriptorCount
        totalDescriptorCount = snapshot.totalDescriptorCount
        selectedDisplayPath = snapshot.selectedDisplayPath
        treeExtentKind = snapshot.treeExtentKind
        treePathCount = snapshot.treePathCount
        metadataTreeRowCount = snapshot.metadataTreeRowCount
        metadataFileRowCount = snapshot.metadataFileRowCount
        sourceState = snapshot.sourceState
        openFileState = snapshot.openFileState
        openFilePath = snapshot.openFilePath
        renderedFilePath = snapshot.renderedFilePath
        bodyPreviewLength = snapshot.bodyPreviewLength
        clickTargetPath = snapshot.clickTargetPath
        clickSelectedPath = snapshot.clickSelectedPath
        clickOpenFilePath = snapshot.clickOpenFilePath
        clickRenderedFilePath = snapshot.clickRenderedFilePath
        clickBodyPreviewLength = snapshot.clickBodyPreviewLength
        secondClickTargetPath = snapshot.secondClickTargetPath
        secondClickSelectedPath = snapshot.secondClickSelectedPath
        secondClickOpenFilePath = snapshot.secondClickOpenFilePath
        secondClickRenderedFilePath = snapshot.secondClickRenderedFilePath
        secondClickBodyPreviewLength = snapshot.secondClickBodyPreviewLength
        offscreenClickTargetPath = snapshot.offscreenClickTargetPath
        offscreenClickSelectedPath = snapshot.offscreenClickSelectedPath
        offscreenClickOpenFilePath = snapshot.offscreenClickOpenFilePath
        offscreenClickRenderedFilePath = snapshot.offscreenClickRenderedFilePath
        offscreenClickBodyPreviewLength = snapshot.offscreenClickBodyPreviewLength
        modeSwitchCount = snapshot.modeSwitchCount
        finalFileContextSelected = snapshot.finalFileContextSelected
        treeScrollStressCount = snapshot.treeScrollStressCount
        treeScrollStressReachedBottom = snapshot.treeScrollStressReachedBottom
        treeHeight = snapshot.treeHeight
        codeViewPanelWidth = snapshot.codeViewPanelWidth
        codeViewPanelHeight = snapshot.codeViewPanelHeight
        codeTextLength = snapshot.codeTextLength
        workerPoolState = snapshot.workerPoolState
        workerPoolManagerState = snapshot.workerPoolManagerState
        workerPoolWorkersFailed = snapshot.workerPoolWorkersFailed
        workerDiagnosticFileSuccessCount = snapshot.workerDiagnosticFileSuccessCount
        workerDiagnosticErrorCount = snapshot.workerDiagnosticErrorCount
        frameLivenessRafAlive = snapshot.frameLivenessRafAlive ?? "unknown"
        frameLivenessRafFiredLatencyBucket = snapshot.frameLivenessRafFiredLatencyBucket ?? "unknown"
        pageErrorCount = snapshot.pageErrorCount
        pageIssueLastKind = snapshot.pageIssueLastKind
        pageIssueLastClass = snapshot.pageIssueLastClass
        pageIssueDisallowedCount = snapshot.pageIssueDisallowedCount
        bridgeCommandCount = snapshot.bridgeCommandCount
        worktreeOpenSourceCommandCount = snapshot.worktreeOpenSourceCommandCount
        intakeReadyCommandCount = snapshot.intakeReadyCommandCount
        worktreeDescriptorRequestCommandCount = snapshot.worktreeDescriptorRequestCommandCount
        bridgeResponseCount = snapshot.bridgeResponseCount
        intakeFrameCount = snapshot.intakeFrameCount
        nativeWorktreeProbeCount = snapshot.nativeWorktreeProbeCount
        nativeWorktreeProbeLastReason = snapshot.nativeWorktreeProbeLastReason
        nativeWorktreeProbeLastReceiverReason = snapshot.nativeWorktreeProbeLastReceiverReason
        nativeWorktreeProbeLastFrameKind = snapshot.nativeWorktreeProbeLastFrameKind
        nativeWorktreeProbeLastGeneration = snapshot.nativeWorktreeProbeLastGeneration
        nativeWorktreeProbeLastReceiverGeneration = snapshot.nativeWorktreeProbeLastReceiverGeneration
        nativeWorktreeProbeLastSequence = snapshot.nativeWorktreeProbeLastSequence
        nativeWorktreeProbeLastStreamIdMatches = snapshot.nativeWorktreeProbeLastStreamIdMatches
        nativeWorktreeProbeFrameEvidenceCount = snapshot.nativeWorktreeProbeFrameEvidenceCount
        nativeWorktreeProbeFinalGeneration = snapshot.nativeWorktreeProbeFinalGeneration
        nativeWorktreeProbeFinalGenerationFrameEvidenceCount =
            snapshot.nativeWorktreeProbeFinalGenerationFrameEvidenceCount
        nativeWorktreeProbeBenignReceiverGenerationBucketDropCount =
            snapshot.nativeWorktreeProbeBenignReceiverGenerationBucketDropCount
        nativeWorktreeProbeFailureDropCount = snapshot.nativeWorktreeProbeFailureDropCount
        nativeWorktreeProbeFinalGenerationFailureDropCount =
            snapshot.nativeWorktreeProbeFinalGenerationFailureDropCount
    }

    var succeeded: Bool {
        expectedVisiblePaneCount == 1
            && hasFileShell
            && hasTree
            && hasCodeViewPanel
            && bootstrapProtocol == expectedBootstrapProtocol
            && bootstrapSourceSpecState == "parseable"
            && bootstrapSourceSpecLength > 0
            && descriptorCount > 0
            && totalDescriptorCount >= descriptorCount
            && metadataTreeRowCount > 0
            && metadataFileRowCount > 0
            && hasSatisfiedDemandedTreeCoverageRequirement
            && !selectedDisplayPath.isEmpty
            && sourceState == "live"
            && openFileState == "ready"
            && openFilePath == selectedDisplayPath
            && renderedFilePath == selectedDisplayPath
            && bodyPreviewLength > 0
            && hasSatisfiedClickContentRequirement
            && hasSatisfiedSecondClickContentRequirement
            && hasSatisfiedOffscreenClickContentRequirement
            && hasSatisfiedModeSwitchStressRequirement
            && hasSatisfiedTreeScrollStressRequirement
            && treeHeight > 0
            && codeViewPanelWidth > 0
            && codeViewPanelHeight > 0
            && codeTextLength > 0
            && workerPoolState == "ready"
            && workerPoolManagerState == "initialized"
            && !workerPoolWorkersFailed
            && workerDiagnosticFileSuccessCount > 0
            && workerDiagnosticErrorCount == 0
            && hasOnlyAllowedPageIssues
            && hasNativePathEvidence
            && !hasNativeWorktreeProbeFailure
    }

    private var hasSatisfiedClickContentRequirement: Bool {
        guard let clickTargetPath, !clickTargetPath.isEmpty,
            let clickSelectedPath,
            let clickOpenFilePath,
            let clickRenderedFilePath,
            let clickBodyPreviewLength
        else {
            return false
        }
        return clickSelectedPath == clickTargetPath
            && clickOpenFilePath == clickTargetPath
            && clickRenderedFilePath == clickTargetPath
            && clickBodyPreviewLength > 0
    }

    private var hasSatisfiedSecondClickContentRequirement: Bool {
        guard let secondClickTargetPath, !secondClickTargetPath.isEmpty,
            let secondClickSelectedPath,
            let secondClickOpenFilePath,
            let secondClickRenderedFilePath,
            let secondClickBodyPreviewLength
        else {
            return false
        }
        return secondClickSelectedPath == secondClickTargetPath
            && secondClickOpenFilePath == secondClickTargetPath
            && secondClickRenderedFilePath == secondClickTargetPath
            && secondClickBodyPreviewLength > 0
    }

    private var hasSatisfiedOffscreenClickContentRequirement: Bool {
        guard let offscreenClickTargetPath, !offscreenClickTargetPath.isEmpty,
            let offscreenClickSelectedPath,
            let offscreenClickOpenFilePath,
            let offscreenClickRenderedFilePath,
            let offscreenClickBodyPreviewLength
        else {
            return false
        }
        return offscreenClickSelectedPath == offscreenClickTargetPath
            && offscreenClickOpenFilePath == offscreenClickTargetPath
            && offscreenClickRenderedFilePath == offscreenClickTargetPath
            && offscreenClickBodyPreviewLength > 0
    }

    private var hasSatisfiedModeSwitchStressRequirement: Bool {
        expectedBootstrapProtocol != "review" || (modeSwitchCount >= 4 && finalFileContextSelected)
    }

    private var hasSatisfiedTreeScrollStressRequirement: Bool {
        treeScrollStressCount >= 4 && treeScrollStressReachedBottom
    }

    private var hasSatisfiedDemandedTreeCoverageRequirement: Bool {
        guard treeExtentKind == "exactPathCount", treePathCount > 0 else {
            return false
        }
        if treePathCount <= Self.startupTreeWindowRowLimit {
            return metadataTreeRowCount >= treePathCount
        }
        guard
            metadataTreeRowCount >= Self.startupTreeWindowRowLimit,
            treeScrollStressReachedBottom,
            hasSatisfiedOffscreenClickContentRequirement
        else {
            return false
        }
        return metadataTreeRowCount > Self.startupTreeWindowRowLimit
    }

    private var hasNativeWorktreeProbeFailure: Bool {
        nativeWorktreeProbeFinalGenerationFailureDropCount > 0
    }

    private var hasOnlyAllowedPageIssues: Bool {
        pageIssueDisallowedCount == 0
    }

    private var hasNativePathEvidence: Bool {
        nativeWorktreeProbeCount > 0
            && nativeWorktreeProbeFinalGeneration > 0
            && nativeWorktreeProbeFinalGenerationFrameEvidenceCount > 0
            && nativeWorktreeProbeLastStreamIdMatches
    }

    var attributes: [String: AgentStudioTraceValue] {
        [
            "agentstudio.startup_diagnostic.expected_visible_pane.count": .int(expectedVisiblePaneCount),
            "agentstudio.startup_diagnostic.bridge.file_view.expected_bootstrap.protocol": .string(
                expectedBootstrapProtocol),
            "agentstudio.startup_diagnostic.bridge.file_view.shell.visible": .bool(hasFileShell),
            "agentstudio.startup_diagnostic.bridge.file_view.tree.visible": .bool(hasTree),
            "agentstudio.startup_diagnostic.bridge.file_view.code_view.visible": .bool(hasCodeViewPanel),
            "agentstudio.startup_diagnostic.bridge.file_view.bootstrap.protocol": .string(bootstrapProtocol),
            "agentstudio.startup_diagnostic.bridge.file_view.bootstrap.source_spec.state": .string(
                bootstrapSourceSpecState),
            "agentstudio.startup_diagnostic.bridge.file_view.bootstrap.source_spec.length": .int(
                bootstrapSourceSpecLength),
            "agentstudio.startup_diagnostic.bridge.file_view.descriptor.count": .int(descriptorCount),
            "agentstudio.startup_diagnostic.bridge.file_view.total_descriptor.count": .int(totalDescriptorCount),
            "agentstudio.startup_diagnostic.bridge.file_view.selected_path": .string(selectedDisplayPath),
            "agentstudio.startup_diagnostic.bridge.file_view.tree_extent.kind": .string(treeExtentKind),
            "agentstudio.startup_diagnostic.bridge.file_view.tree_path.count": .int(treePathCount),
            "agentstudio.startup_diagnostic.bridge.file_view.metadata_tree_row.count": .int(metadataTreeRowCount),
            "agentstudio.startup_diagnostic.bridge.file_view.metadata_file_row.count": .int(metadataFileRowCount),
            "agentstudio.startup_diagnostic.bridge.file_view.tree_full_stream.satisfied": .bool(
                hasSatisfiedDemandedTreeCoverageRequirement),
            "agentstudio.startup_diagnostic.bridge.file_view.source.state": .string(sourceState),
            "agentstudio.startup_diagnostic.bridge.file_view.open_file.state": .string(openFileState),
            "agentstudio.startup_diagnostic.bridge.file_view.open_file.path": .string(openFilePath),
            "agentstudio.startup_diagnostic.bridge.file_view.rendered_file.path": .string(renderedFilePath),
            "agentstudio.startup_diagnostic.bridge.file_view.body_preview.length": .int(bodyPreviewLength),
            "agentstudio.startup_diagnostic.bridge.file_view.click.target_found": .bool(
                clickTargetPath?.isEmpty == false),
            "agentstudio.startup_diagnostic.bridge.file_view.click.selected_matches": .bool(
                clickSelectedPath == clickTargetPath && clickTargetPath?.isEmpty == false),
            "agentstudio.startup_diagnostic.bridge.file_view.click.open_file_matches": .bool(
                clickOpenFilePath == clickTargetPath && clickTargetPath?.isEmpty == false),
            "agentstudio.startup_diagnostic.bridge.file_view.click.rendered_file_matches": .bool(
                clickRenderedFilePath == clickTargetPath && clickTargetPath?.isEmpty == false),
            "agentstudio.startup_diagnostic.bridge.file_view.click.body_preview.length": .int(
                clickBodyPreviewLength ?? 0),
            "agentstudio.startup_diagnostic.bridge.file_view.second_click.target_found": .bool(
                secondClickTargetPath?.isEmpty == false),
            "agentstudio.startup_diagnostic.bridge.file_view.second_click.selected_matches": .bool(
                secondClickSelectedPath == secondClickTargetPath && secondClickTargetPath?.isEmpty == false),
            "agentstudio.startup_diagnostic.bridge.file_view.second_click.open_file_matches": .bool(
                secondClickOpenFilePath == secondClickTargetPath && secondClickTargetPath?.isEmpty == false),
            "agentstudio.startup_diagnostic.bridge.file_view.second_click.rendered_file_matches": .bool(
                secondClickRenderedFilePath == secondClickTargetPath && secondClickTargetPath?.isEmpty == false),
            "agentstudio.startup_diagnostic.bridge.file_view.second_click.body_preview.length": .int(
                secondClickBodyPreviewLength ?? 0),
            "agentstudio.startup_diagnostic.bridge.file_view.offscreen_click.target_found": .bool(
                offscreenClickTargetPath?.isEmpty == false),
            "agentstudio.startup_diagnostic.bridge.file_view.offscreen_click.selected_matches": .bool(
                offscreenClickSelectedPath == offscreenClickTargetPath && offscreenClickTargetPath?.isEmpty == false),
            "agentstudio.startup_diagnostic.bridge.file_view.offscreen_click.open_file_matches": .bool(
                offscreenClickOpenFilePath == offscreenClickTargetPath && offscreenClickTargetPath?.isEmpty == false),
            "agentstudio.startup_diagnostic.bridge.file_view.offscreen_click.rendered_file_matches": .bool(
                offscreenClickRenderedFilePath == offscreenClickTargetPath
                    && offscreenClickTargetPath?.isEmpty == false),
            "agentstudio.startup_diagnostic.bridge.file_view.offscreen_click.body_preview.length": .int(
                offscreenClickBodyPreviewLength ?? 0),
            "agentstudio.startup_diagnostic.bridge.file_view.mode_switch.count": .int(modeSwitchCount),
            "agentstudio.startup_diagnostic.bridge.file_view.mode_switch.final_file_selected": .bool(
                finalFileContextSelected),
            "agentstudio.startup_diagnostic.bridge.file_view.tree_scroll_stress.count": .int(
                treeScrollStressCount),
            "agentstudio.startup_diagnostic.bridge.file_view.tree_scroll_stress.reached_bottom": .bool(
                treeScrollStressReachedBottom),
            "agentstudio.startup_diagnostic.bridge.file_view.tree.height_px": .int(treeHeight),
            "agentstudio.startup_diagnostic.bridge.file_view.code_view.width_px": .int(codeViewPanelWidth),
            "agentstudio.startup_diagnostic.bridge.file_view.code_view.height_px": .int(codeViewPanelHeight),
            "agentstudio.startup_diagnostic.bridge.file_view.code_text.length": .int(codeTextLength),
            "agentstudio.startup_diagnostic.bridge.worker_pool.state": .string(workerPoolState),
            "agentstudio.startup_diagnostic.bridge.worker_pool.manager_state": .string(workerPoolManagerState),
            "agentstudio.startup_diagnostic.bridge.worker_pool.workers_failed": .bool(workerPoolWorkersFailed),
            "agentstudio.startup_diagnostic.bridge.worker_diagnostic.file_success_count": .int(
                workerDiagnosticFileSuccessCount),
            "agentstudio.startup_diagnostic.bridge.worker_diagnostic.failure_count": .int(
                workerDiagnosticErrorCount),
            "agentstudio.startup_diagnostic.bridge.frame_liveness.raf_alive": .string(
                frameLivenessRafAlive),
            "agentstudio.startup_diagnostic.bridge.frame_liveness.raf_fired_latency.bucket": .string(
                frameLivenessRafFiredLatencyBucket),
            "agentstudio.startup_diagnostic.bridge.page_issue.count": .int(pageErrorCount),
            "agentstudio.startup_diagnostic.bridge.page_issue.last_kind": .string(pageIssueLastKind),
            "agentstudio.startup_diagnostic.bridge.page_issue.last_class": .string(pageIssueLastClass),
            "agentstudio.startup_diagnostic.bridge.page_issue.disallowed.count": .int(pageIssueDisallowedCount),
            "agentstudio.startup_diagnostic.bridge.file_view.bridge_command.count": .int(bridgeCommandCount),
            "agentstudio.startup_diagnostic.bridge.file_view.open_source_command.count": .int(
                worktreeOpenSourceCommandCount),
            "agentstudio.startup_diagnostic.bridge.file_view.intake_ready_command.count": .int(
                intakeReadyCommandCount),
            "agentstudio.startup_diagnostic.bridge.file_view.descriptor_request_command.count": .int(
                worktreeDescriptorRequestCommandCount),
            "agentstudio.startup_diagnostic.bridge.file_view.bridge_response.count": .int(bridgeResponseCount),
            "agentstudio.startup_diagnostic.bridge.file_view.intake_frame.count": .int(intakeFrameCount),
            "agentstudio.startup_diagnostic.bridge.file_view.native_probe.count": .int(nativeWorktreeProbeCount),
            "agentstudio.startup_diagnostic.bridge.file_view.native_probe.last_reason": .string(
                nativeWorktreeProbeLastReason),
            "agentstudio.startup_diagnostic.bridge.file_view.native_probe.last_receiver_reason": .string(
                nativeWorktreeProbeLastReceiverReason),
            "agentstudio.startup_diagnostic.bridge.file_view.native_probe.last_frame_kind": .string(
                nativeWorktreeProbeLastFrameKind),
            "agentstudio.startup_diagnostic.bridge.file_view.native_probe.last_generation": .int(
                nativeWorktreeProbeLastGeneration),
            "agentstudio.startup_diagnostic.bridge.file_view.native_probe.last_receiver_generation": .int(
                nativeWorktreeProbeLastReceiverGeneration),
            "agentstudio.startup_diagnostic.bridge.file_view.native_probe.last_sequence": .int(
                nativeWorktreeProbeLastSequence),
            "agentstudio.startup_diagnostic.bridge.file_view.native_probe.last_stream_id_matches": .bool(
                nativeWorktreeProbeLastStreamIdMatches),
            "agentstudio.startup_diagnostic.bridge.file_view.native_probe.frame_evidence.count": .int(
                nativeWorktreeProbeFrameEvidenceCount),
            "agentstudio.startup_diagnostic.bridge.file_view.native_probe.final_generation": .int(
                nativeWorktreeProbeFinalGeneration),
            "agentstudio.startup_diagnostic.bridge.file_view.native_probe.final_generation_frame_evidence.count": .int(
                nativeWorktreeProbeFinalGenerationFrameEvidenceCount),
            "agentstudio.startup_diagnostic.bridge.file_view.native_probe.benign_receiver_generation_bucket_drop.count":
                .int(nativeWorktreeProbeBenignReceiverGenerationBucketDropCount),
            "agentstudio.startup_diagnostic.bridge.file_view.native_probe.failure_drop.count": .int(
                nativeWorktreeProbeFailureDropCount),
            "agentstudio.startup_diagnostic.bridge.file_view.native_probe.final_generation_failure_drop.count": .int(
                nativeWorktreeProbeFinalGenerationFailureDropCount),
            "agentstudio.startup_diagnostic.render_proof.succeeded": .bool(succeeded),
        ]
    }

}

extension BridgeFileViewObservabilitySmokeRenderProof {
    static func unavailable() -> Self {
        Self(
            snapshot: BridgeFileViewObservabilitySmokeRenderSnapshot(
                hasFileShell: false,
                hasTree: false,
                hasCodeViewPanel: false,
                bootstrapProtocol: "unavailable",
                bootstrapSourceSpecState: "unavailable",
                bootstrapSourceSpecLength: 0,
                descriptorCount: 0,
                totalDescriptorCount: 0,
                selectedDisplayPath: "",
                treeExtentKind: "unavailable",
                treePathCount: 0,
                metadataTreeRowCount: 0,
                metadataFileRowCount: 0,
                sourceState: "unavailable",
                openFileState: "unavailable",
                openFilePath: "",
                renderedFilePath: "",
                bodyPreviewLength: 0,
                clickTargetPath: nil,
                clickSelectedPath: nil,
                clickOpenFilePath: nil,
                clickRenderedFilePath: nil,
                clickBodyPreviewLength: nil,
                secondClickTargetPath: nil,
                secondClickSelectedPath: nil,
                secondClickOpenFilePath: nil,
                secondClickRenderedFilePath: nil,
                secondClickBodyPreviewLength: nil,
                offscreenClickTargetPath: nil,
                offscreenClickSelectedPath: nil,
                offscreenClickOpenFilePath: nil,
                offscreenClickRenderedFilePath: nil,
                offscreenClickBodyPreviewLength: nil,
                modeSwitchCount: 0,
                finalFileContextSelected: false,
                treeScrollStressCount: 0,
                treeScrollStressReachedBottom: false,
                treeHeight: 0,
                codeViewPanelWidth: 0,
                codeViewPanelHeight: 0,
                codeTextLength: 0,
                workerPoolState: "unavailable",
                workerPoolManagerState: "unavailable",
                workerPoolWorkersFailed: false,
                workerDiagnosticFileSuccessCount: 0,
                workerDiagnosticErrorCount: 0,
                pageErrorCount: 0,
                pageIssueLastKind: "none",
                pageIssueLastClass: "none",
                pageIssueDisallowedCount: 0,
                bridgeCommandCount: 0,
                worktreeOpenSourceCommandCount: 0,
                intakeReadyCommandCount: 0,
                worktreeDescriptorRequestCommandCount: 0,
                bridgeResponseCount: 0,
                intakeFrameCount: 0,
                nativeWorktreeProbeCount: 0,
                nativeWorktreeProbeLastReason: "none",
                nativeWorktreeProbeLastReceiverReason: "none",
                nativeWorktreeProbeLastFrameKind: "none",
                nativeWorktreeProbeLastGeneration: 0,
                nativeWorktreeProbeLastReceiverGeneration: 0,
                nativeWorktreeProbeLastSequence: 0,
                nativeWorktreeProbeLastStreamIdMatches: false,
                nativeWorktreeProbeFrameEvidenceCount: 0,
                nativeWorktreeProbeFinalGeneration: 0,
                nativeWorktreeProbeFinalGenerationFrameEvidenceCount: 0,
                nativeWorktreeProbeBenignReceiverGenerationBucketDropCount: 0,
                nativeWorktreeProbeFailureDropCount: 0,
                nativeWorktreeProbeFinalGenerationFailureDropCount: 0
            ),
            expectedVisiblePaneCount: 1
        )
    }
}
