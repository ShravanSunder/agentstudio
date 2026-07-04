import Testing

@testable import AgentStudio

struct AgentStudioFileViewStartupDiagnosticTests {
    @Test("Bridge FileView smoke render proof requires streamed tree and selected file content")
    func smokeRenderProofRequiresStreamedTreeAndSelectedContent() {
        let proof = BridgeFileViewObservabilitySmokeRenderProof(
            snapshot: makeFileViewSmokeSnapshot(),
            expectedVisiblePaneCount: 1
        )

        #expect(proof.succeeded)
        #expect(proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.tree.visible"] == .bool(true))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.bootstrap.protocol"]
                == .string("worktree-file"))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.bootstrap.source_spec.state"]
                == .string("parseable"))
        #expect(proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.descriptor.count"] == .int(24))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.metadata_tree_row.count"] == .int(260))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.tree_extent.kind"]
                == .string("exactPathCount"))
        #expect(proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.tree_path.count"] == .int(260))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.metadata_file_row.count"] == .int(224))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.open_file.state"] == .string("ready"))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.open_source_command.count"] == .int(1))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.intake_ready_command.count"] == .int(1))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.descriptor_request_command.count"]
                == .int(1))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.native_probe.last_reason"]
                == .string("frame_published"))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.native_probe.last_receiver_reason"]
                == .string("none"))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.native_probe.last_sequence"] == .int(7))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.click.target_found"] == .bool(true))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.click.rendered_file_matches"]
                == .bool(true))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.click.body_preview.length"] == .int(64))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.second_click.rendered_file_matches"]
                == .bool(true))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.mode_switch.count"] == .int(4))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.mode_switch.final_file_selected"]
                == .bool(true))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.tree_scroll_stress.count"] == .int(4))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.tree_scroll_stress.reached_bottom"]
                == .bool(true))
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(true))
    }

    @Test("Bridge FileView smoke render proof fails when clicked file content does not render")
    func smokeRenderProofFailsWhenClickedContentDoesNotRender() {
        let proof = BridgeFileViewObservabilitySmokeRenderProof(
            snapshot: makeFileViewSmokeSnapshot(
                clickRenderedFilePath: "Sources/App/View.swift",
                clickBodyPreviewLength: 80
            ),
            expectedVisiblePaneCount: 1
        )

        #expect(!proof.succeeded)
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(false))
    }

    @Test("Bridge FileView smoke render proof requires an offscreen tree click")
    func smokeRenderProofRequiresOffscreenTreeClick() {
        let proof = BridgeFileViewObservabilitySmokeRenderProof(
            snapshot: makeFileViewSmokeSnapshot(
                offscreenClickTargetPath: nil,
                offscreenClickSelectedPath: nil,
                offscreenClickOpenFilePath: nil,
                offscreenClickRenderedFilePath: nil,
                offscreenClickBodyPreviewLength: nil
            ),
            expectedVisiblePaneCount: 1
        )

        #expect(!proof.succeeded)
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(false))
    }

    @Test("Bridge FileView smoke render proof requires native mode-switch and tree-scroll stress")
    func smokeRenderProofRequiresModeSwitchAndTreeScrollStress() {
        let proof = BridgeFileViewObservabilitySmokeRenderProof(
            snapshot: makeFileViewSmokeSnapshot(
                bootstrapProtocol: "review",
                modeSwitchCount: 1,
                finalFileContextSelected: false,
                treeScrollStressCount: 0,
                treeScrollStressReachedBottom: false
            ),
            expectedVisiblePaneCount: 1,
            expectedBootstrapProtocol: "review"
        )

        #expect(!proof.succeeded)
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.mode_switch.count"] == .int(1))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.mode_switch.final_file_selected"]
                == .bool(false))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.tree_scroll_stress.count"] == .int(0))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.tree_scroll_stress.reached_bottom"]
                == .bool(false))
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(false))
    }

    @Test("Bridge FileView smoke render proof fails when native intake reports a dropped frame")
    func smokeRenderProofFailsWhenNativeIntakeReportsDroppedFrame() {
        let proof = BridgeFileViewObservabilitySmokeRenderProof(
            snapshot: makeFileViewSmokeSnapshot(
                nativeWorktreeProbeLastReason: "drop_parse_failed",
                nativeWorktreeProbeLastReceiverReason: "generation_mismatch",
                nativeWorktreeProbeFailureDropCount: 1
            ),
            expectedVisiblePaneCount: 1
        )

        #expect(!proof.succeeded)
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(false))
    }

    @Test("Bridge FileView smoke render proof accepts old-generation cleanup drop after final evidence")
    func smokeRenderProofAcceptsOldGenerationCleanupDropAfterFinalEvidence() {
        let proof = BridgeFileViewObservabilitySmokeRenderProof(
            snapshot: makeFileViewSmokeSnapshot(
                nativeWorktreeProbeLastReason: "drop_identity_mismatch",
                nativeWorktreeProbeLastReceiverReason: "generation_mismatch",
                nativeWorktreeProbeLastGeneration: 2,
                nativeWorktreeProbeLastReceiverGeneration: 3,
                nativeWorktreeProbeFinalGeneration: 3,
                nativeWorktreeProbeFinalGenerationFrameEvidenceCount: 2,
                nativeWorktreeProbeFailureDropCount: 0
            ),
            expectedVisiblePaneCount: 1
        )

        #expect(proof.succeeded)
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.native_probe.final_generation"]
                == .int(3))
        #expect(
            proof.attributes[
                "agentstudio.startup_diagnostic.bridge.file_view.native_probe.final_generation_frame_evidence.count"
            ] == .int(2))
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(true))
    }

    @Test("Bridge FileView smoke render proof fails on same-generation native intake drop")
    func smokeRenderProofFailsOnSameGenerationNativeIntakeDrop() {
        let proof = BridgeFileViewObservabilitySmokeRenderProof(
            snapshot: makeFileViewSmokeSnapshot(
                nativeWorktreeProbeLastReason: "drop_identity_mismatch",
                nativeWorktreeProbeLastReceiverReason: "generation_mismatch",
                nativeWorktreeProbeLastGeneration: 3,
                nativeWorktreeProbeLastReceiverGeneration: 3,
                nativeWorktreeProbeFinalGeneration: 3,
                nativeWorktreeProbeFinalGenerationFrameEvidenceCount: 2,
                nativeWorktreeProbeFailureDropCount: 1
            ),
            expectedVisiblePaneCount: 1
        )

        #expect(!proof.succeeded)
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.native_probe.failure_drop.count"]
                == .int(1))
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(false))
    }

    @Test("Bridge FileView smoke render proof accepts a replay request after native frame evidence")
    func smokeRenderProofAcceptsReplayRequestAfterNativeFrameEvidence() {
        let proof = BridgeFileViewObservabilitySmokeRenderProof(
            snapshot: makeFileViewSmokeSnapshot(
                nativeWorktreeProbeLastReason: "replay_requested",
                nativeWorktreeProbeLastFrameKind: "none",
                nativeWorktreeProbeLastSequence: 0,
                nativeWorktreeProbeFrameEvidenceCount: 5
            ),
            expectedVisiblePaneCount: 1
        )

        #expect(proof.succeeded)
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.native_probe.frame_evidence.count"]
                == .int(5))
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(true))
    }

    @Test("Bridge FileView smoke diagnostic JavaScript exercises a visible file click")
    func smokeDiagnosticJavaScriptExercisesVisibleFileClick() {
        let script = AppDelegate.bridgeFileViewObservabilitySmokeRenderStateJavaScript

        #expect(script.contains("worktreeFileClickTargetPath"))
        #expect(script.contains("data-item-path"))
        #expect(script.contains(".click()"))
        #expect(script.contains("firstSelectedPath"))
        #expect(script.contains("...clickProbeState"))
        #expect(script.contains("firstBodyPreviewLength: worktreeFileClickBodyPreviewLength"))
    }

    @Test("Bridge Review to FileView smoke diagnostic JavaScript switches to Files before sampling")
    func reviewToFileViewSmokeDiagnosticJavaScriptSwitchesToFilesBeforeSampling() {
        let script = AppDelegate.reviewToFileViewSmokeRenderJavaScript

        #expect(script.contains("bridge-viewer-context-file"))
        #expect(script.contains("data-bridge-viewer-context-selected"))
        #expect(script.contains(".click()"))
        #expect(script.contains("bridge-file-viewer-shell"))
    }

    @Test("Bridge FileView smoke render proof can target Review bootstrap protocol")
    func smokeRenderProofCanTargetReviewBootstrapProtocol() {
        let proof = BridgeFileViewObservabilitySmokeRenderProof(
            snapshot: makeFileViewSmokeSnapshot(bootstrapProtocol: "review"),
            expectedVisiblePaneCount: 1,
            expectedBootstrapProtocol: "review"
        )

        #expect(proof.succeeded)
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.expected_bootstrap.protocol"]
                == .string("review"))
    }

    @Test("Bridge FileView smoke render proof fails when a large tree only has the startup window")
    func smokeRenderProofFailsWhenLargeTreeOnlyHasStartupWindow() {
        let proof = BridgeFileViewObservabilitySmokeRenderProof(
            snapshot: makeFileViewSmokeSnapshot(
                metadataTreeRowCount: 200,
                metadataFileRowCount: 164,
                clickTargetPath: nil,
                clickSelectedPath: nil,
                clickOpenFilePath: nil,
                clickRenderedFilePath: nil,
                clickBodyPreviewLength: nil,
                intakeFrameCount: 2,
                nativeWorktreeProbeLastReason: "snapshot_resolved",
                nativeWorktreeProbeLastFrameKind: "worktree.snapshot"
            ),
            expectedVisiblePaneCount: 1
        )

        #expect(!proof.succeeded)
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(false))
    }

    @Test("Bridge FileView smoke render proof fails when a large estimated tree has only partial windows")
    func smokeRenderProofFailsWhenLargeEstimatedTreeHasOnlyPartialWindows() {
        let proof = BridgeFileViewObservabilitySmokeRenderProof(
            snapshot: makeFileViewSmokeSnapshot(
                treeExtentKind: "estimatedTotalHeight",
                treePathCount: 0,
                metadataTreeRowCount: 600,
                metadataFileRowCount: 444,
                descriptorCount: 1600,
                totalDescriptorCount: 1600,
                treeHeight: 240_000,
                intakeFrameCount: 5
            ),
            expectedVisiblePaneCount: 1
        )

        #expect(!proof.succeeded)
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.tree_full_stream.satisfied"]
                == .bool(false))
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(false))
    }

    @Test("Bridge FileView smoke render proof accepts estimated tree after all descriptors stream")
    func smokeRenderProofAcceptsEstimatedTreeAfterAllDescriptorsStream() {
        let proof = BridgeFileViewObservabilitySmokeRenderProof(
            snapshot: makeFileViewSmokeSnapshot(
                bootstrapProtocol: "review",
                treeExtentKind: "estimatedTotalHeight",
                treePathCount: 0,
                metadataTreeRowCount: 1600,
                metadataFileRowCount: 1299,
                descriptorCount: 1600,
                totalDescriptorCount: 1600,
                treeHeight: 240_000,
                intakeFrameCount: 23,
                nativeWorktreeProbeLastSequence: 12,
                pageErrorCount: 9,
                pageIssueLastKind: "fetch_error",
                pageIssueLastClass: "context_switch_fetch_aborted",
                pageIssueDisallowedCount: 0,
                bridgeCommandCount: 40,
                intakeReadyCommandCount: 2,
                worktreeDescriptorRequestCommandCount: 4,
                bridgeResponseCount: 6,
                nativeWorktreeProbeCount: 31
            ),
            expectedVisiblePaneCount: 1,
            expectedBootstrapProtocol: "review"
        )

        #expect(proof.succeeded)
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.tree_full_stream.satisfied"]
                == .bool(true))
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(true))
    }

    @Test("Bridge FileView smoke render proof fails when exact tree count has not converged")
    func smokeRenderProofFailsWhenExactTreeCountHasNotConverged() {
        let proof = BridgeFileViewObservabilitySmokeRenderProof(
            snapshot: makeFileViewSmokeSnapshot(
                treeExtentKind: "exactPathCount",
                treePathCount: 2384,
                metadataTreeRowCount: 1200,
                metadataFileRowCount: 933,
                treeHeight: 57_216,
                intakeFrameCount: 8
            ),
            expectedVisiblePaneCount: 1
        )

        #expect(!proof.succeeded)
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.tree_full_stream.satisfied"]
                == .bool(false))
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(false))
    }

    @Test("Bridge FileView smoke render proof fails before selected file content is ready")
    func smokeRenderProofFailsBeforeSelectedContentIsReady() {
        let proof = BridgeFileViewObservabilitySmokeRenderProof(
            snapshot: makeFileViewSmokeSnapshot(
                treeExtentKind: "estimatedTotalHeight",
                treePathCount: 0,
                metadataTreeRowCount: 200,
                metadataFileRowCount: 164,
                openFileState: "loading",
                renderedFilePath: "",
                bodyPreviewLength: 0,
                clickTargetPath: nil,
                clickSelectedPath: nil,
                clickOpenFilePath: nil,
                clickRenderedFilePath: nil,
                clickBodyPreviewLength: nil,
                treeHeight: 576,
                codeTextLength: 0,
                workerDiagnosticFileSuccessCount: 0,
                intakeFrameCount: 2,
                nativeWorktreeProbeLastReason: "snapshot_resolved",
                nativeWorktreeProbeLastFrameKind: "worktree.snapshot"
            ),
            expectedVisiblePaneCount: 1
        )

        #expect(!proof.succeeded)
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(false))
    }

    @Test("Bridge FileView smoke render proof ignores context switch fetch aborts after FileView content converges")
    func smokeRenderProofIgnoresContextSwitchFetchAbortsAfterFileViewContentConverges() {
        let proof = BridgeFileViewObservabilitySmokeRenderProof(
            snapshot: makeFileViewSmokeSnapshot(
                bootstrapProtocol: "review",
                pageErrorCount: 2,
                pageIssueLastKind: "fetch_error",
                pageIssueLastClass: "context_switch_fetch_aborted",
                pageIssueDisallowedCount: 0
            ),
            expectedVisiblePaneCount: 1,
            expectedBootstrapProtocol: "review"
        )

        #expect(proof.succeeded)
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(true))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.page_issue.last_class"]
                == .string("context_switch_fetch_aborted"))
    }

    @Test("Bridge FileView smoke render proof fails when a real page issue is masked by a later abort")
    func smokeRenderProofFailsWhenRealPageIssueIsMaskedByLaterAbort() {
        let proof = BridgeFileViewObservabilitySmokeRenderProof(
            snapshot: makeFileViewSmokeSnapshot(
                pageErrorCount: 2,
                pageIssueLastKind: "fetch_error",
                pageIssueLastClass: "context_switch_fetch_aborted",
                pageIssueDisallowedCount: 1
            ),
            expectedVisiblePaneCount: 1
        )

        #expect(!proof.succeeded)
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.page_issue.disallowed.count"] == .int(1))
    }

    @Test("Bridge FileView smoke render proof requires native path counters")
    func smokeRenderProofRequiresNativePathCounters() {
        let proof = BridgeFileViewObservabilitySmokeRenderProof(
            snapshot: makeFileViewSmokeSnapshot(
                intakeFrameCount: 0,
                nativeWorktreeProbeLastReason: "none",
                nativeWorktreeProbeLastFrameKind: "none",
                nativeWorktreeProbeLastStreamIdMatches: false,
                bridgeCommandCount: 0,
                worktreeOpenSourceCommandCount: 0,
                intakeReadyCommandCount: 0,
                worktreeDescriptorRequestCommandCount: 0,
                bridgeResponseCount: 0,
                nativeWorktreeProbeCount: 0
            ),
            expectedVisiblePaneCount: 1
        )

        #expect(!proof.succeeded)
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.open_source_command.count"] == .int(0))
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.file_view.native_probe.last_stream_id_matches"]
                == .bool(false))
    }

    @Test("Bridge FileView smoke diagnostic reads worker error count from the shared diagnostic key")
    func smokeDiagnosticJavaScriptReadsWorkerErrorCountFromSharedDiagnosticKey() {
        let script = AppDelegate.bridgeFileViewObservabilitySmokeRenderStateJavaScript

        #expect(script.contains("data-bridge-pierre-worker-diagnostic-error-count"))
        #expect(!script.contains("data-bridge-pierre-worker-diagnostic-failure-count"))
        #expect(script.contains("__bridgeIntakeReadyCommandProbe"))
        #expect(script.contains("__bridgeWorktreeOpenSourceCommandProbe"))
        #expect(script.contains("__bridgeWorktreeDescriptorRequestCommandProbe"))
        #expect(script.contains("worktreeOpenSourceCommandProbe.filter"))
        #expect(script.contains("worktreeDescriptorRequestCommandProbe.filter"))
        #expect(script.contains("nativeWorktreeProbeReceiverGeneration"))
        #expect(script.contains("nativeWorktreeProbeFinalGenerationFrameEvidenceCount"))
        #expect(script.contains("nativeWorktreeProbeFailureDropCount"))
    }

    private func makeFileViewSmokeSnapshot(
        bootstrapProtocol: String = "worktree-file",
        treeExtentKind: String = "exactPathCount",
        treePathCount: Int = 260,
        metadataTreeRowCount: Int = 260,
        metadataFileRowCount: Int = 224,
        descriptorCount: Int = 24,
        totalDescriptorCount: Int = 24,
        openFileState: String = "ready",
        renderedFilePath: String = "Sources/App/View.swift",
        bodyPreviewLength: Int = 80,
        clickTargetPath: String? = "Sources/App/Other.swift",
        clickSelectedPath: String? = "Sources/App/Other.swift",
        clickOpenFilePath: String? = "Sources/App/Other.swift",
        clickRenderedFilePath: String? = "Sources/App/Other.swift",
        clickBodyPreviewLength: Int? = 64,
        secondClickTargetPath: String? = "Sources/App/Third.swift",
        secondClickSelectedPath: String? = "Sources/App/Third.swift",
        secondClickOpenFilePath: String? = "Sources/App/Third.swift",
        secondClickRenderedFilePath: String? = "Sources/App/Third.swift",
        secondClickBodyPreviewLength: Int? = 72,
        offscreenClickTargetPath: String? = "Sources/App/Bottom.swift",
        offscreenClickSelectedPath: String? = "Sources/App/Bottom.swift",
        offscreenClickOpenFilePath: String? = "Sources/App/Bottom.swift",
        offscreenClickRenderedFilePath: String? = "Sources/App/Bottom.swift",
        offscreenClickBodyPreviewLength: Int? = 96,
        modeSwitchCount: Int = 4,
        finalFileContextSelected: Bool = true,
        treeScrollStressCount: Int = 4,
        treeScrollStressReachedBottom: Bool = true,
        treeHeight: Int = 6240,
        codeTextLength: Int = 160,
        workerDiagnosticFileSuccessCount: Int = 1,
        intakeFrameCount: Int = 3,
        nativeWorktreeProbeLastReason: String = "frame_published",
        nativeWorktreeProbeLastReceiverReason: String = "none",
        nativeWorktreeProbeLastFrameKind: String = "worktree.treeWindow",
        nativeWorktreeProbeLastGeneration: Int = 1,
        nativeWorktreeProbeLastReceiverGeneration: Int = 1,
        nativeWorktreeProbeLastSequence: Int = 7,
        nativeWorktreeProbeLastStreamIdMatches: Bool = true,
        nativeWorktreeProbeFrameEvidenceCount: Int = 4,
        nativeWorktreeProbeFinalGeneration: Int = 1,
        nativeWorktreeProbeFinalGenerationFrameEvidenceCount: Int = 4,
        nativeWorktreeProbeFailureDropCount: Int = 0,
        pageErrorCount: Int = 0,
        pageIssueLastKind: String = "none",
        pageIssueLastClass: String = "none",
        pageIssueDisallowedCount: Int = 0,
        bridgeCommandCount: Int = 2,
        worktreeOpenSourceCommandCount: Int = 1,
        intakeReadyCommandCount: Int = 1,
        worktreeDescriptorRequestCommandCount: Int = 1,
        bridgeResponseCount: Int = 1,
        nativeWorktreeProbeCount: Int = 4
    ) -> BridgeFileViewObservabilitySmokeRenderSnapshot {
        BridgeFileViewObservabilitySmokeRenderSnapshot(
            hasFileShell: true,
            hasTree: true,
            hasCodeViewPanel: true,
            bootstrapProtocol: bootstrapProtocol,
            bootstrapSourceSpecState: "parseable",
            bootstrapSourceSpecLength: 512,
            descriptorCount: descriptorCount,
            totalDescriptorCount: totalDescriptorCount,
            selectedDisplayPath: "Sources/App/View.swift",
            treeExtentKind: treeExtentKind,
            treePathCount: treePathCount,
            metadataTreeRowCount: metadataTreeRowCount,
            metadataFileRowCount: metadataFileRowCount,
            sourceState: "live",
            openFileState: openFileState,
            openFilePath: "Sources/App/View.swift",
            renderedFilePath: renderedFilePath,
            bodyPreviewLength: bodyPreviewLength,
            clickTargetPath: clickTargetPath,
            clickSelectedPath: clickSelectedPath,
            clickOpenFilePath: clickOpenFilePath,
            clickRenderedFilePath: clickRenderedFilePath,
            clickBodyPreviewLength: clickBodyPreviewLength,
            secondClickTargetPath: secondClickTargetPath,
            secondClickSelectedPath: secondClickSelectedPath,
            secondClickOpenFilePath: secondClickOpenFilePath,
            secondClickRenderedFilePath: secondClickRenderedFilePath,
            secondClickBodyPreviewLength: secondClickBodyPreviewLength,
            offscreenClickTargetPath: offscreenClickTargetPath,
            offscreenClickSelectedPath: offscreenClickSelectedPath,
            offscreenClickOpenFilePath: offscreenClickOpenFilePath,
            offscreenClickRenderedFilePath: offscreenClickRenderedFilePath,
            offscreenClickBodyPreviewLength: offscreenClickBodyPreviewLength,
            modeSwitchCount: modeSwitchCount,
            finalFileContextSelected: finalFileContextSelected,
            treeScrollStressCount: treeScrollStressCount,
            treeScrollStressReachedBottom: treeScrollStressReachedBottom,
            treeHeight: treeHeight,
            codeViewPanelWidth: 900,
            codeViewPanelHeight: 700,
            codeTextLength: codeTextLength,
            workerPoolState: "ready",
            workerPoolManagerState: "initialized",
            workerPoolWorkersFailed: false,
            workerDiagnosticFileSuccessCount: workerDiagnosticFileSuccessCount,
            workerDiagnosticErrorCount: 0,
            pageErrorCount: pageErrorCount,
            pageIssueLastKind: pageIssueLastKind,
            pageIssueLastClass: pageIssueLastClass,
            pageIssueDisallowedCount: pageIssueDisallowedCount,
            bridgeCommandCount: bridgeCommandCount,
            worktreeOpenSourceCommandCount: worktreeOpenSourceCommandCount,
            intakeReadyCommandCount: intakeReadyCommandCount,
            worktreeDescriptorRequestCommandCount: worktreeDescriptorRequestCommandCount,
            bridgeResponseCount: bridgeResponseCount,
            intakeFrameCount: intakeFrameCount,
            nativeWorktreeProbeCount: nativeWorktreeProbeCount,
            nativeWorktreeProbeLastReason: nativeWorktreeProbeLastReason,
            nativeWorktreeProbeLastReceiverReason: nativeWorktreeProbeLastReceiverReason,
            nativeWorktreeProbeLastFrameKind: nativeWorktreeProbeLastFrameKind,
            nativeWorktreeProbeLastGeneration: nativeWorktreeProbeLastGeneration,
            nativeWorktreeProbeLastReceiverGeneration: nativeWorktreeProbeLastReceiverGeneration,
            nativeWorktreeProbeLastSequence: nativeWorktreeProbeLastSequence,
            nativeWorktreeProbeLastStreamIdMatches: nativeWorktreeProbeLastStreamIdMatches,
            nativeWorktreeProbeFrameEvidenceCount: nativeWorktreeProbeFrameEvidenceCount,
            nativeWorktreeProbeFinalGeneration: nativeWorktreeProbeFinalGeneration,
            nativeWorktreeProbeFinalGenerationFrameEvidenceCount: nativeWorktreeProbeFinalGenerationFrameEvidenceCount,
            nativeWorktreeProbeFailureDropCount: nativeWorktreeProbeFailureDropCount
        )
    }
}
