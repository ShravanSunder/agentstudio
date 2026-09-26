import Foundation

extension BridgeTelemetryWireSchema {
    static func commWorkerFileQueryDiagnosticContractMatches(
        _ contract: EventContract
    ) -> Bool {
        let phaseKey = "agentstudio.bridge.worker.file_query.phase"
        let chunkIndexKey = "agentstudio.bridge.worker.file_query.chunk.index"
        let evaluatedRowCountKey = "agentstudio.bridge.worker.file_query.evaluated_row.count"
        func matches(numericKeys: Set<String>) -> Bool {
            contract.matches(
                .init(
                    phase: "worker_task",
                    plane: .data,
                    priority: .hot,
                    slice: .workerTask,
                    transport: "worker",
                    attributeKeys: .init(
                        additionalStringKeys: [phaseKey],
                        numericKeys: numericKeys
                    )
                )
            )
        }

        return matches(numericKeys: [])
            || matches(numericKeys: [chunkIndexKey])
            || matches(numericKeys: [chunkIndexKey, evaluatedRowCountKey])
    }

    static func fileQueryDiagnosticContractMatches(_ contract: EventContract) -> Bool {
        let phaseKey = "agentstudio.bridge.file_query.diagnostic.phase"
        let batchCountKey = "agentstudio.bridge.file_query.diagnostic.batch.count"
        let batchIndexKey = "agentstudio.bridge.file_query.diagnostic.batch.index"
        let displayItemCountKey = "agentstudio.bridge.file_query.diagnostic.display_item.count"
        let pageHiddenKey = "agentstudio.bridge.file_query.diagnostic.page_hidden"
        let mountedPathRowCountKey =
            "agentstudio.bridge.file_query.diagnostic.mounted_path_row.count"
        let queryKeyMatchesInputKey =
            "agentstudio.bridge.file_query.diagnostic.query_key_matches_input"
        let treeRowCountKey = "agentstudio.bridge.file_query.diagnostic.tree_row.count"
        let viewportMeasuredKey = "agentstudio.bridge.file_query.diagnostic.viewport_measured"
        func matches(numericKeys: Set<String>, booleanKeys: Set<String>) -> Bool {
            contract.matches(
                .init(
                    phase: "worker_task",
                    plane: .data,
                    priority: .hot,
                    slice: .workerTask,
                    transport: "worker",
                    attributeKeys: .init(
                        additionalStringKeys: [phaseKey],
                        numericKeys: numericKeys,
                        booleanKeys: booleanKeys
                    )
                )
            )
        }

        let pageHiddenKeys: Set<String> = [pageHiddenKey]
        let snapshotCountKeys: Set<String> = [displayItemCountKey, treeRowCountKey]
        return matches(numericKeys: [], booleanKeys: pageHiddenKeys)
            || matches(
                numericKeys: [batchIndexKey, batchCountKey],
                booleanKeys: pageHiddenKeys
            )
            || matches(numericKeys: snapshotCountKeys, booleanKeys: pageHiddenKeys)
            || matches(
                numericKeys: snapshotCountKeys,
                booleanKeys: pageHiddenKeys.union([queryKeyMatchesInputKey])
            )
            || matches(
                numericKeys: [mountedPathRowCountKey],
                booleanKeys: pageHiddenKeys.union([viewportMeasuredKey])
            )
    }
}
