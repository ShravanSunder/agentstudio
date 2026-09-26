import Foundation

@testable import AgentStudioBridge

extension BridgeProductWebKitCarrierTraceRecorder {
    func recordRealGitFileQueryDiagnosticPhase(_ sample: BridgeTelemetrySample) {
        guard sample.name == "performance.bridge.worker.task",
            let phase = sample.stringAttributes["agentstudio.bridge.worker.file_query.phase"]
        else { return }

        let chunkIndex = sample.numericAttributes["agentstudio.bridge.worker.file_query.chunk.index"]
            .map(Int.init)
        switch phase {
        case "command_received":
            recordRealGitLiveProofStage("worker-query-command-received")
        case "chunk_started":
            guard let chunkIndex else { return }
            recordRealGitLiveProofStage("worker-query-chunk-\(chunkIndex)-start")
        case "chunk_completed":
            guard let chunkIndex,
                let evaluatedRowCount = sample.numericAttributes[
                    "agentstudio.bridge.worker.file_query.evaluated_row.count"
                ]?.rounded(.towardZero)
            else { return }
            recordRealGitLiveProofStage(
                "worker-query-chunk-\(chunkIndex)-end rows=\(Int(evaluatedRowCount))"
            )
        case "projection_published":
            recordRealGitLiveProofStage("worker-query-projection-published")
        case "outcome_published":
            recordRealGitLiveProofStage("worker-query-outcome-published")
        default:
            return
        }
    }

    func recordRealGitFileQueryPageDiagnosticPhase(_ sample: BridgeTelemetrySample) {
        guard sample.name == "performance.bridge.web.file_query_diagnostic",
            let phase = sample.stringAttributes["agentstudio.bridge.file_query.diagnostic.phase"]
        else { return }

        let pageVisibility =
            sample.booleanAttributes[
                "agentstudio.bridge.file_query.diagnostic.page_hidden"
            ] == true ? "hidden" : "visible"
        let batchIndex = sample.numericAttributes[
            "agentstudio.bridge.file_query.diagnostic.batch.index"
        ]?.rounded(.towardZero)
        let batchCount = sample.numericAttributes[
            "agentstudio.bridge.file_query.diagnostic.batch.count"
        ]?.rounded(.towardZero)
        let batchSuffix =
            if let batchIndex, let batchCount {
                " batch=\(Int(batchIndex) + 1)/\(Int(batchCount))"
            } else {
                ""
            }

        switch phase {
        case "patch_received":
            recordRealGitLiveProofStage(
                "page-file-query-patch-received\(batchSuffix),visibility=\(pageVisibility)"
            )
        case "applier_batch_accepted":
            recordRealGitLiveProofStage("page-file-query-applier-accepted\(batchSuffix)")
        case "applier_batch_rejected_stale":
            recordRealGitLiveProofStage("page-file-query-applier-rejected reason=stale\(batchSuffix)")
        case "applier_batch_rejected_protocol":
            recordRealGitLiveProofStage(
                "page-file-query-applier-rejected reason=protocol\(batchSuffix)"
            )
        case "applier_batch_buffered_after_commit":
            recordRealGitLiveProofStage(
                "page-file-query-applier-buffered-after-commit\(batchSuffix)"
            )
        case "transaction_committed":
            recordRealGitLiveProofStage("page-file-query-transaction-committed\(batchSuffix)")
        case "render_consumer_committed":
            let treeRowCount = sample.numericAttributes[
                "agentstudio.bridge.file_query.diagnostic.tree_row.count"
            ]?.rounded(.towardZero)
            let displayItemCount = sample.numericAttributes[
                "agentstudio.bridge.file_query.diagnostic.display_item.count"
            ]?.rounded(.towardZero)
            guard let treeRowCount,
                let displayItemCount,
                let queryKeyMatchesInput = sample.booleanAttributes[
                    "agentstudio.bridge.file_query.diagnostic.query_key_matches_input"
                ]
            else { return }
            recordRealGitLiveProofStage(
                "page-file-query-render-consumer-committed source=useSyncExternalStore,treeRowCount=\(Int(treeRowCount)),displayItemCount=\(Int(displayItemCount)),queryKeyMatchesInput=\(queryKeyMatchesInput),visibility=\(pageVisibility)"
            )
        case "snapshot_published":
            let treeRowCount = sample.numericAttributes[
                "agentstudio.bridge.file_query.diagnostic.tree_row.count"
            ]?.rounded(.towardZero)
            let displayItemCount = sample.numericAttributes[
                "agentstudio.bridge.file_query.diagnostic.display_item.count"
            ]?.rounded(.towardZero)
            guard let treeRowCount, let displayItemCount else { return }
            recordRealGitLiveProofStage(
                "page-file-query-snapshot-published treeRowCount=\(Int(treeRowCount)),displayItemCount=\(Int(displayItemCount))"
            )
        case "tree_stream_received":
            recordRealGitLiveProofStage(
                "page-file-query-tree-stream-received visibility=\(pageVisibility)"
            )
        case "tree_task_started":
            recordRealGitLiveProofStage(
                "page-file-query-tree-task-started visibility=\(pageVisibility)"
            )
        case "tree_turn_completed":
            recordRealGitLiveProofStage(
                "page-file-query-tree-turn-completed visibility=\(pageVisibility)"
            )
        case "tree_dom_commit":
            let mountedPathRowCount = sample.numericAttributes[
                "agentstudio.bridge.file_query.diagnostic.mounted_path_row.count"
            ]?.rounded(.towardZero)
            guard let mountedPathRowCount,
                let viewportMeasured = sample.booleanAttributes[
                    "agentstudio.bridge.file_query.diagnostic.viewport_measured"
                ]
            else { return }
            recordRealGitLiveProofStage(
                "page-file-query-tree-dom-commit mountedPathRowCount=\(Int(mountedPathRowCount)),viewportMeasured=\(viewportMeasured),visibility=\(pageVisibility)"
            )
        default:
            return
        }
    }
}
