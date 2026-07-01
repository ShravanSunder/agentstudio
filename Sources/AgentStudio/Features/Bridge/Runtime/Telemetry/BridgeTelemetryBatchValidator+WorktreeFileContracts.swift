import Foundation

extension BridgeTelemetryBatchValidator {
    static func fileOpenReadyContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        let requiredStringKeys = requiredStringAttributeKeys.union([
            "agentstudio.bridge.content.role",
            "agentstudio.bridge.demand.disposition",
            "agentstudio.bridge.demand.lane",
            "agentstudio.bridge.result",
            "agentstudio.bridge.result_reason",
            "agentstudio.bridge.viewer",
        ])
        let requiredNumericKeys: Set<String> = [
            "agentstudio.bridge.demand.request.sequence"
        ]
        let optionalNumericKeys: Set<String> = Self.worktreeFileDemandTimingNumericKeys.union([
            "agentstudio.bridge.content.body_registry_commit_ms",
            "agentstudio.bridge.content.estimated_bytes",
            "agentstudio.bridge.source.generation",
        ])
        return contract.phase == "file_open_ready"
            && contract.plane == .data
            && contract.priority == .hot
            && contract.slice == .contentFetch
            && contract.transport == "content"
            && contract.stringKeys == requiredStringKeys
            && requiredNumericKeys.isSubset(of: contract.numericKeys)
            && contract.numericKeys.isSubset(of: requiredNumericKeys.union(optionalNumericKeys))
            && contract.booleanKeys.isEmpty
    }

    static func worktreeFileContentFetchContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        let requiredStringKeys = requiredStringAttributeKeys.union([
            "agentstudio.bridge.content.correlation_mode",
            "agentstudio.bridge.content.role",
            "agentstudio.bridge.demand.lane",
            "agentstudio.bridge.file_size_bucket",
            "agentstudio.bridge.generation_relation",
            "agentstudio.bridge.protocol",
            "agentstudio.bridge.result",
            "agentstudio.bridge.result_reason",
            "agentstudio.bridge.viewer",
        ])
        let requiredNumericKeys: Set<String> = [
            "agentstudio.bridge.content.byte_length"
        ]
        let optionalNumericKeys: Set<String> = [
            "agentstudio.bridge.content.estimated_bytes",
            "agentstudio.bridge.content.first_chunk_wait_ms",
            "agentstudio.bridge.content.response_wait_ms",
            "agentstudio.bridge.content.stream_read_ms",
        ]
        return contract.phase == "fetch"
            && contract.plane == .data
            && contract.priority == .hot
            && contract.slice == .contentFetch
            && contract.transport == "content"
            && contract.stringKeys == requiredStringKeys
            && requiredNumericKeys.isSubset(of: contract.numericKeys)
            && contract.numericKeys.isSubset(of: requiredNumericKeys.union(optionalNumericKeys))
            && contract.booleanKeys == [
                "agentstudio.bridge.header_missing",
                "agentstudio.bridge.header_supported",
            ]
    }

    static func scrollVisibleDemandContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            .init(
                phase: "scroll_visible_demand",
                plane: .data,
                priority: .hot,
                slice: .treePrepareInput,
                transport: "worker",
                attributeKeys: .init(
                    additionalStringKeys: [
                        "agentstudio.bridge.demand.disposition",
                        "agentstudio.bridge.demand.lane",
                        "agentstudio.bridge.result",
                        "agentstudio.bridge.result_reason",
                        "agentstudio.bridge.viewer",
                    ],
                    numericKeys: ["agentstudio.bridge.visible_item.count"]
                )
            )
        )
    }

    static func visibleDemandSettledContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        let requiredStringKeys = requiredStringAttributeKeys.union([
            "agentstudio.bridge.content.role",
            "agentstudio.bridge.demand.lane",
            "agentstudio.bridge.result",
            "agentstudio.bridge.result_reason",
            "agentstudio.bridge.viewer",
        ])
        let requiredNumericKeys: Set<String> = [
            "agentstudio.bridge.demand.enqueue_accepted.count",
            "agentstudio.bridge.demand.enqueue_rejected.count",
            "agentstudio.bridge.demand.failed.count",
            "agentstudio.bridge.demand.intent.count",
            "agentstudio.bridge.demand.loaded.count",
            "agentstudio.bridge.demand.request.sequence",
            "agentstudio.bridge.visible_item.count",
        ]
        let optionalNumericKeys = Self.worktreeFileDemandTimingNumericKeys
        return contract.phase == "visible_demand_settled"
            && contract.plane == .data
            && contract.priority == .hot
            && contract.slice == .contentFetch
            && contract.transport == "content"
            && contract.stringKeys == requiredStringKeys
            && requiredNumericKeys.isSubset(of: contract.numericKeys)
            && contract.numericKeys.isSubset(of: requiredNumericKeys.union(optionalNumericKeys))
            && contract.booleanKeys.isEmpty
    }

    private static let worktreeFileDemandTimingNumericKeys: Set<String> = [
        "agentstudio.bridge.content.first_chunk_wait_ms",
        "agentstudio.bridge.content.response_wait_ms",
        "agentstudio.bridge.content.stream_read_ms",
        "agentstudio.bridge.demand.executor_in_flight_ms",
        "agentstudio.bridge.demand.executor_pending_wait_ms",
        "agentstudio.bridge.demand.scheduler_queue_wait_ms",
    ]
}
