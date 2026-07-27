import Foundation
import Testing

@testable import AgentStudio

@Suite
struct BridgeTelemetryWireSchemaTests {
    @Test
    func primitiveWireFieldsReturnNoDropReasonForValidEvent() {
        let dropReason = BridgeTelemetryWireSchema.dropReason(
            eventName: "performance.bridge.web.first_render",
            durationMilliseconds: 1,
            stringAttributes: [
                "agentstudio.bridge.phase": "render",
                "agentstudio.bridge.plane": "data",
                "agentstudio.bridge.priority": "hot",
                "agentstudio.bridge.slice": "diff_status",
                "agentstudio.bridge.transport": "push",
            ],
            numericAttributes: [:],
            booleanAttributes: [:]
        )

        #expect(dropReason == nil)
    }

    @Test(
        arguments: [
            (
                "unknown.event",
                1 as Double?,
                BridgeTelemetryDropReason.unsafeEventName
            ),
            (
                "performance.bridge.web.first_render",
                -1 as Double?,
                BridgeTelemetryDropReason.invalidDuration
            ),
        ]
    )
    func primitiveWireFieldsReturnSpecificDropReason(
        eventName: String,
        durationMilliseconds: Double?,
        expectedDropReason: BridgeTelemetryDropReason
    ) {
        let dropReason = BridgeTelemetryWireSchema.dropReason(
            eventName: eventName,
            durationMilliseconds: durationMilliseconds,
            stringAttributes: [
                "agentstudio.bridge.phase": "render",
                "agentstudio.bridge.plane": "data",
                "agentstudio.bridge.priority": "hot",
                "agentstudio.bridge.slice": "diff_status",
                "agentstudio.bridge.transport": "push",
            ],
            numericAttributes: [:],
            booleanAttributes: [:]
        )

        #expect(dropReason == expectedDropReason)
    }

    @Test
    func primitiveWireFieldsRejectUnexpectedAttributeKey() {
        let dropReason = BridgeTelemetryWireSchema.dropReason(
            eventName: "performance.bridge.web.first_render",
            durationMilliseconds: 1,
            stringAttributes: [
                "agentstudio.bridge.phase": "render",
                "agentstudio.bridge.plane": "data",
                "agentstudio.bridge.priority": "hot",
                "agentstudio.bridge.slice": "diff_status",
                "agentstudio.bridge.transport": "push",
                "agentstudio.bridge.unexpected": "unsafe",
            ],
            numericAttributes: [:],
            booleanAttributes: [:]
        )

        #expect(dropReason == .unsafeAttribute)
    }
}
