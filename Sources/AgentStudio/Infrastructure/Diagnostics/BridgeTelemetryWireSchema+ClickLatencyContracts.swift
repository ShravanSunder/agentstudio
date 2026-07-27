import Foundation

extension BridgeTelemetryEventValidator {
    static func reviewContentDemandContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            .init(
                phase: "review_content_demand",
                plane: .data,
                priority: .hot,
                slice: .contentFetch,
                transport: "content",
                attributeKeys: .init(
                    additionalStringKeys: [
                        "agentstudio.bridge.content.interest",
                        "agentstudio.bridge.result",
                        "agentstudio.bridge.result_reason",
                        "agentstudio.bridge.viewer",
                    ],
                    numericKeys: [
                        "agentstudio.bridge.demand.active.count",
                        "agentstudio.bridge.demand.deferred.count",
                        "agentstudio.bridge.demand.duration_ms",
                        "agentstudio.bridge.demand.failed.count",
                        "agentstudio.bridge.demand.foreground.count",
                        "agentstudio.bridge.demand.idle.count",
                        "agentstudio.bridge.demand.intent.count",
                        "agentstudio.bridge.demand.loaded.count",
                        "agentstudio.bridge.demand.nearby.count",
                        "agentstudio.bridge.demand.speculative.count",
                        "agentstudio.bridge.demand.visible.count",
                    ]
                )
            )
        )
    }

    static func codeViewItemMaterializeContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        ["swift", "worker"].contains { transport in
            contract.matches(
                .init(
                    phase: "code_view_item_materialize",
                    plane: .data,
                    priority: .hot,
                    slice: .codeViewItem,
                    transport: transport,
                    attributeKeys: .init(
                        additionalStringKeys: [
                            "agentstudio.bridge.content_bytes_bucket",
                            "agentstudio.bridge.item_count_bucket",
                            "agentstudio.bridge.language_class",
                            "agentstudio.bridge.result",
                            "agentstudio.bridge.viewer",
                        ],
                        booleanKeys: ["agentstudio.bridge.selected"]
                    )
                )
            )
        }
    }

    static func selectedContentPaintedContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        ["swift", "worker"].contains { transport in
            contract.matches(
                .init(
                    phase: "selected_content_painted",
                    plane: .data,
                    priority: .hot,
                    slice: .codeViewItem,
                    transport: transport,
                    attributeKeys: .init(
                        additionalStringKeys: ["agentstudio.bridge.viewer"],
                        numericKeys: [
                            "agentstudio.bridge.selected_content.click_to_paint_ms",
                            "agentstudio.bridge.selected_content.frame_wait_ms",
                            "agentstudio.bridge.selected_content.materialize_ms",
                        ]
                    )
                )
            )
        }
    }

    static func selectedContentDroppedContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            .init(
                phase: "selected_content_dropped",
                plane: .data,
                priority: .hot,
                slice: .contentFetch,
                transport: "content",
                attributeKeys: .init(
                    additionalStringKeys: [
                        "agentstudio.bridge.drop_reason",
                        "agentstudio.bridge.result",
                        "agentstudio.bridge.viewer",
                    ]
                )
            )
        )
    }
}
