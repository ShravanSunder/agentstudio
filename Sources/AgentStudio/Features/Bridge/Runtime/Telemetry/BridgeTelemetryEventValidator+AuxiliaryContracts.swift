import Foundation

extension BridgeTelemetryEventValidator {
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
        legacyWorkerTaskContractMatches(contract)
            || commWorkerMessageHandlerContractMatches(contract)
            || commWorkerContentPreparationContractMatches(contract)
            || commWorkerStoreActionContractMatches(contract)
    }

    private static func legacyWorkerTaskContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        workerTaskContractMatches(
            contract,
            priority: .warm,
            attributeKeys: .init(
                additionalStringKeys: [
                    "agentstudio.bridge.item_count_bucket",
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.worker.lane",
                    "agentstudio.bridge.worker.task_kind",
                ]
            )
        )
    }

    private static func commWorkerMessageHandlerContractMatches(
        _ contract: BridgeTelemetryEventContract
    ) -> Bool {
        let additionalStringKeys: Set<String> = [
            "agentstudio.bridge.result",
            "agentstudio.bridge.worker.command",
            "agentstudio.bridge.worker.lane",
            "agentstudio.bridge.worker.task_kind",
        ]
        let numericKeys: Set<String> = [
            "agentstudio.bridge.worker.handler_duration_ms",
            "agentstudio.bridge.worker.queue_wait_ms",
        ]
        return workerTaskContractMatches(
            contract,
            attributeKeys: .init(
                additionalStringKeys: additionalStringKeys,
                numericKeys: numericKeys
            )
        )
            || workerTaskContractMatches(
                contract,
                attributeKeys: .init(
                    additionalStringKeys: additionalStringKeys,
                    numericKeys: numericKeys,
                    booleanKeys: [
                        "agentstudio.bridge.worker.file_metadata_selected_path_resolved"
                    ]
                )
            )
    }

    private static func commWorkerContentPreparationContractMatches(
        _ contract: BridgeTelemetryEventContract
    ) -> Bool {
        workerTaskContractMatches(
            contract,
            attributeKeys: .init(
                additionalStringKeys: [
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.worker.lane",
                    "agentstudio.bridge.worker.payload_class",
                    "agentstudio.bridge.worker.task_kind",
                    "agentstudio.bridge.worker.work_kind",
                ],
                numericKeys: [
                    "agentstudio.bridge.worker.handler_duration_ms",
                    "agentstudio.bridge.worker.queue_wait_ms",
                    "agentstudio.bridge.worker.source_epoch",
                ]
            )
        )
    }

    private static func commWorkerStoreActionContractMatches(
        _ contract: BridgeTelemetryEventContract
    ) -> Bool {
        workerTaskContractMatches(
            contract,
            attributeKeys: .init(
                additionalStringKeys: [
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.worker.action",
                    "agentstudio.bridge.worker.lane",
                    "agentstudio.bridge.worker.task_kind",
                ],
                numericKeys: [
                    "agentstudio.bridge.worker.handler_duration_ms",
                    "agentstudio.bridge.worker.patch_count",
                    "agentstudio.bridge.worker.touched_key_count",
                ]
            )
        )
            || workerTaskContractMatches(
                contract,
                attributeKeys: .init(
                    additionalStringKeys: [
                        "agentstudio.bridge.result",
                        "agentstudio.bridge.worker.action",
                        "agentstudio.bridge.worker.lane",
                        "agentstudio.bridge.worker.task_kind",
                    ],
                    numericKeys: [
                        "agentstudio.bridge.worker.handler_duration_ms",
                        "agentstudio.bridge.worker.patch_count",
                        "agentstudio.bridge.worker.source_epoch",
                        "agentstudio.bridge.worker.touched_key_count",
                    ]
                )
            )
            || workerTaskContractMatches(
                contract,
                attributeKeys: .init(
                    additionalStringKeys: [
                        "agentstudio.bridge.result",
                        "agentstudio.bridge.result_reason",
                        "agentstudio.bridge.worker.action",
                        "agentstudio.bridge.worker.lane",
                        "agentstudio.bridge.worker.task_kind",
                    ],
                    numericKeys: [
                        "agentstudio.bridge.worker.handler_duration_ms",
                        "agentstudio.bridge.worker.patch_count",
                        "agentstudio.bridge.worker.source_epoch",
                        "agentstudio.bridge.worker.touched_key_count",
                    ]
                )
            )
    }

    private static func workerTaskContractMatches(
        _ contract: BridgeTelemetryEventContract,
        attributeKeys: BridgeTelemetryEventAttributeKeys
    ) -> Bool {
        workerTaskContractMatches(contract, priority: .hot, attributeKeys: attributeKeys)
            || workerTaskContractMatches(contract, priority: .warm, attributeKeys: attributeKeys)
    }

    private static func workerTaskContractMatches(
        _ contract: BridgeTelemetryEventContract,
        priority: BridgeTelemetryPriority,
        attributeKeys: BridgeTelemetryEventAttributeKeys
    ) -> Bool {
        contract.matches(
            .init(
                phase: "worker_task",
                plane: .data,
                priority: priority,
                slice: .workerTask,
                transport: "worker",
                attributeKeys: attributeKeys
            )
        )
    }
}
