import Foundation

/// Viewer-perceived interaction contracts (time-to-first-interaction) split
/// from the main validator to keep it under the file-length cap.
extension BridgeTelemetryEventValidator {
    static func timeToFirstInteractionContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
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
