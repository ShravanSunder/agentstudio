import Foundation

extension BridgeTelemetryBatchValidator {
    static func auxiliaryContractMatches(name: String, contract: BridgeTelemetryEventContract) -> Bool? {
        switch name {
        case "performance.bridge.viewer.content_queue":
            contentQueueContractMatches(contract)
        case "performance.bridge.viewer.content_cache":
            contentCacheContractMatches(contract)
        case "performance.bridge.viewer.time_to_first_interaction":
            timeToFirstInteractionContractMatches(contract)
        case "performance.bridge.pierre.item_update":
            itemUpdateContractMatches(contract)
        case "performance.bridge.pierre.scroll_target":
            scrollTargetContractMatches(contract)
        case "performance.bridge.pierre.virtualized_range":
            virtualizedRangeContractMatches(contract)
        case "performance.bridge.shiki.highlight":
            shikiHighlightContractMatches(contract)
        case "performance.bridge.worker.task":
            workerTaskContractMatches(contract)
        default:
            nil
        }
    }

    private static func contentQueueContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            .init(
                phase: "content_queue",
                plane: .data,
                priority: .hot,
                slice: .contentFetch,
                transport: "content",
                additionalStringKeys: [
                    "agentstudio.bridge.content.interest",
                    "agentstudio.bridge.content.priority",
                    "agentstudio.bridge.content.role",
                    "agentstudio.bridge.queue.depth_bucket",
                    "agentstudio.bridge.result",
                ]
            )
        )
    }

    private static func contentCacheContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            .init(
                phase: "content_cache",
                plane: .data,
                priority: .hot,
                slice: .contentFetch,
                transport: "content",
                additionalStringKeys: [
                    "agentstudio.bridge.cache.result",
                    "agentstudio.bridge.content.role",
                    "agentstudio.bridge.content_bytes_bucket",
                    "agentstudio.bridge.result",
                ]
            )
        )
    }

    private static func itemUpdateContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            .init(
                phase: "item_update",
                plane: .data,
                priority: .hot,
                slice: .codeViewItem,
                transport: "swift",
                additionalStringKeys: [
                    "agentstudio.bridge.item_count_bucket",
                    "agentstudio.bridge.item_update.kind",
                    "agentstudio.bridge.result",
                ]
            )
        )
    }

    private static func scrollTargetContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            .init(
                phase: "scroll_target",
                plane: .control,
                priority: .hot,
                slice: .codeViewScroll,
                transport: "swift",
                additionalStringKeys: [
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.scroll_target.kind",
                ]
            )
        )
    }

    private static func virtualizedRangeContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            .init(
                phase: "virtualized_range",
                plane: .data,
                priority: .hot,
                slice: .codeViewVirtualRange,
                transport: "swift",
                additionalStringKeys: [
                    "agentstudio.bridge.diff_row_count_bucket",
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.visible_row_bucket",
                ]
            )
        )
    }

    private static func shikiHighlightContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            .init(
                phase: "highlight",
                plane: .data,
                priority: .hot,
                slice: .shikiHighlight,
                transport: "worker",
                additionalStringKeys: [
                    "agentstudio.bridge.content_bytes_bucket",
                    "agentstudio.bridge.language_class",
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.worker.lane",
                ]
            )
        )
    }

    private static func workerTaskContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            .init(
                phase: "worker_task",
                plane: .data,
                priority: .warm,
                slice: .workerTask,
                transport: "worker",
                additionalStringKeys: [
                    "agentstudio.bridge.item_count_bucket",
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.worker.lane",
                    "agentstudio.bridge.worker.task_kind",
                ]
            )
        )
    }
}
