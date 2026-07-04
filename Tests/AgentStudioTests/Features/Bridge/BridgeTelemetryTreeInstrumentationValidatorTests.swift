import Foundation
import Testing

@testable import AgentStudio

@Suite
struct BridgeTelemetryTreeInstrumentationValidatorTests {
    @Test
    func validatorAcceptsBridgeTreeInstrumentationSamples() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                treeSample(
                    name: "performance.bridge.trees.click_to_row_highlight",
                    phase: "click_to_row_highlight",
                    strings: [
                        "agentstudio.bridge.input.source": "mouse",
                        "agentstudio.bridge.result": "success",
                        "agentstudio.bridge.viewer": "review",
                    ],
                    numbers: ["agentstudio.bridge.visible_item.count": 12],
                    booleans: [
                        "agentstudio.bridge.already_selected": false,
                        "agentstudio.bridge.scroll.active": true,
                    ]
                ),
                treeSample(
                    name: "performance.bridge.trees.hover_to_render",
                    phase: "hover_to_render",
                    strings: [
                        "agentstudio.bridge.result": "success",
                        "agentstudio.bridge.viewer": "review",
                    ],
                    numbers: ["agentstudio.bridge.visible_item.count": 12],
                    booleans: ["agentstudio.bridge.row_mounted": true]
                ),
                treeSample(
                    name: "performance.bridge.trees.scroll_frame_gap",
                    phase: "scroll_frame_gap",
                    strings: [
                        "agentstudio.bridge.result": "success",
                        "agentstudio.bridge.viewer": "review",
                    ],
                    numbers: [
                        "agentstudio.bridge.scroll.frame_gap.max_ms": 41,
                        "agentstudio.bridge.scroll.frame_gap.over_16ms.count": 3,
                        "agentstudio.bridge.scroll.frame_gap.over_33ms.count": 1,
                        "agentstudio.bridge.scroll.frame_gap.over_50ms.count": 0,
                        "agentstudio.bridge.scroll.frame_gap.p95_ms": 33,
                        "agentstudio.bridge.visible_publisher.skipped.count": 2,
                        "agentstudio.bridge.visible_row.count": 22,
                    ]
                ),
                treeSample(
                    name: "performance.bridge.trees.anchor_restore",
                    phase: "anchor_restore",
                    strings: [
                        "agentstudio.bridge.anchor_restore.phase": "direct_restore",
                        "agentstudio.bridge.result": "success",
                        "agentstudio.bridge.viewer": "file",
                    ],
                    numbers: [
                        "agentstudio.bridge.anchor_restore.call.count": 1,
                        "agentstudio.bridge.anchor_restore.direct_scroll_top_write.count": 1,
                        "agentstudio.bridge.anchor_restore.synthetic_scroll.count": 1,
                    ]
                ),
                treeSample(
                    name: "performance.bridge.trees.scroll_to_path",
                    phase: "scroll_to_path",
                    strings: [
                        "agentstudio.bridge.result": "success",
                        "agentstudio.bridge.scroll.offset": "nearest",
                        "agentstudio.bridge.scroll.reason": "selected_path_effect",
                        "agentstudio.bridge.viewer": "file",
                    ],
                    booleans: ["agentstudio.bridge.focus": true]
                ),
                treeSample(
                    name: "performance.bridge.trees.visible_ids_capture",
                    phase: "visible_ids_capture",
                    strings: [
                        "agentstudio.bridge.result": "success",
                        "agentstudio.bridge.viewer": "review",
                    ],
                    numbers: [
                        "agentstudio.bridge.visible_descriptor.count": 4,
                        "agentstudio.bridge.visible_item.count": 6,
                        "agentstudio.bridge.visible_row.count": 9,
                    ]
                ),
            ]
        )

        #expect(validator.validate(batch) == .accepted(batch))
    }
}

private func treeSample(
    name: String,
    phase: String,
    strings: [String: String],
    numbers: [String: Double] = [:],
    booleans: [String: Bool] = [:]
) -> BridgeTelemetrySample {
    BridgeTelemetrySample(
        scope: .web,
        name: name,
        durationMilliseconds: 1,
        traceContext: nil,
        stringAttributes: [
            "agentstudio.bridge.phase": phase,
            "agentstudio.bridge.plane": "data",
            "agentstudio.bridge.priority": "hot",
            "agentstudio.bridge.slice": "tree_prepare_input",
            "agentstudio.bridge.transport": "worker",
        ].merging(strings, uniquingKeysWith: { _, next in next }),
        numericAttributes: numbers,
        booleanAttributes: booleans
    )
}
