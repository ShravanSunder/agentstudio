import Foundation

/// Viewer-perceived interaction contracts (time-to-first-interaction) split
/// from the main wire schema to keep it under the file-length cap.
extension BridgeTelemetryWireSchema {
    static func timeToFirstInteractionContractMatches(_ contract: EventContract) -> Bool {
        contract.matches(
            .init(
                phase: "time_to_first_interaction",
                plane: .data,
                priority: .hot,
                slice: .contentFetch,
                transport: "content",
                attributeKeys: .init(
                    additionalStringKeys: [
                        "agentstudio.bridge.result",
                        "agentstudio.bridge.viewer",
                        "agentstudio.bridge.viewer.ttfi_variant",
                    ],
                    numericKeys: [
                        "agentstudio.bridge.visible_item.count"
                    ]
                )
            )
        )
    }
}
