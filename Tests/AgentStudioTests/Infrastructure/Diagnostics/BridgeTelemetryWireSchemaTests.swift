import Foundation
import Testing

@testable import AgentStudioInfrastructure

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

    @Test
    func workerMessageHandlerAcceptsOnlyClosedSemanticClass() {
        let commonStringAttributes = [
            "agentstudio.bridge.phase": "worker_task",
            "agentstudio.bridge.plane": "data",
            "agentstudio.bridge.priority": "hot",
            "agentstudio.bridge.result": "success",
            "agentstudio.bridge.slice": "worker_task",
            "agentstudio.bridge.transport": "worker",
            "agentstudio.bridge.worker.command": "annotationCommand",
            "agentstudio.bridge.worker.lane": "selected",
            "agentstudio.bridge.worker.task_kind": "message_handler",
        ]
        let numericAttributes = [
            "agentstudio.bridge.worker.handler_duration_ms": 1.0,
            "agentstudio.bridge.worker.queue_wait_ms": 2.0,
        ]

        let accepted = BridgeTelemetryWireSchema.dropReason(
            eventName: "performance.bridge.worker.task",
            durationMilliseconds: 1,
            stringAttributes: commonStringAttributes.merging([
                "agentstudio.bridge.worker.semantic_class": "urgent_action"
            ]) { _, newValue in newValue },
            numericAttributes: numericAttributes,
            booleanAttributes: [:]
        )
        let rejected = BridgeTelemetryWireSchema.dropReason(
            eventName: "performance.bridge.worker.task",
            durationMilliseconds: 1,
            stringAttributes: commonStringAttributes.merging([
                "agentstudio.bridge.worker.semantic_class": "comment-body"
            ]) { _, newValue in newValue },
            numericAttributes: numericAttributes,
            booleanAttributes: [:]
        )

        #expect(accepted == nil)
        #expect(rejected == .unsafeAttribute)
    }

    @Test
    func renderDispositionAdmissionAcceptsExactTerminalContract() {
        let stringAttributes = [
            "agentstudio.bridge.phase": "render_disposition_batch_terminal",
            "agentstudio.bridge.plane": "control",
            "agentstudio.bridge.priority": "warm",
            "agentstudio.bridge.render_disposition.outcome": "acked",
            "agentstudio.bridge.result": "success",
            "agentstudio.bridge.slice": "command_acks",
            "agentstudio.bridge.transport": "worker",
            "agentstudio.bridge.viewer": "review",
        ]
        let numericAttributes = [
            "agentstudio.bridge.render_disposition.batch_receipt_count": 64.0,
            "agentstudio.bridge.render_disposition.duplicate_count": 1.0,
            "agentstudio.bridge.render_disposition.oldest_pending_age_ms": 2.0,
            "agentstudio.bridge.render_disposition.pending_count": 3.0,
            "agentstudio.bridge.render_disposition.pending_high_water_mark": 65.0,
            "agentstudio.bridge.render_disposition.produced_count": 66.0,
        ]

        let accepted = BridgeTelemetryWireSchema.dropReason(
            eventName: "performance.bridge.web.render_disposition_admission",
            durationMilliseconds: 4,
            stringAttributes: stringAttributes,
            numericAttributes: numericAttributes,
            booleanAttributes: [:]
        )
        let rejectedOutcome = BridgeTelemetryWireSchema.dropReason(
            eventName: "performance.bridge.web.render_disposition_admission",
            durationMilliseconds: 4,
            stringAttributes: stringAttributes.merging([
                "agentstudio.bridge.render_disposition.outcome": "private-request-id"
            ]) { _, newValue in newValue },
            numericAttributes: numericAttributes,
            booleanAttributes: [:]
        )

        #expect(accepted == nil)
        #expect(rejectedOutcome == .unsafeAttribute)
    }

    @Test
    func workerRenderDispositionBatchAcceptsOnlyAggregateCounts() {
        let commonStringAttributes = [
            "agentstudio.bridge.phase": "render_disposition_batch_applied",
            "agentstudio.bridge.plane": "data",
            "agentstudio.bridge.priority": "warm",
            "agentstudio.bridge.render_disposition.outcome": "degraded",
            "agentstudio.bridge.result": "failed",
            "agentstudio.bridge.slice": "command_acks",
            "agentstudio.bridge.transport": "worker",
            "agentstudio.bridge.viewer": "file",
        ]
        let commonNumericAttributes = [
            "agentstudio.bridge.render_disposition.accepted_count": 1.0,
            "agentstudio.bridge.render_disposition.batch_receipt_count": 3.0,
            "agentstudio.bridge.render_disposition.duplicate_count": 1.0,
            "agentstudio.bridge.render_disposition.rejected_count": 1.0,
        ]

        let accepted = BridgeTelemetryWireSchema.dropReason(
            eventName: "performance.bridge.worker.render_disposition_batch",
            durationMilliseconds: nil,
            stringAttributes: commonStringAttributes,
            numericAttributes: commonNumericAttributes,
            booleanAttributes: [:]
        )
        let rejectedIdentity = BridgeTelemetryWireSchema.dropReason(
            eventName: "performance.bridge.worker.render_disposition_batch",
            durationMilliseconds: nil,
            stringAttributes: commonStringAttributes.merging([
                "agentstudio.bridge.render_disposition.request_id": "private-request-id"
            ]) { _, newValue in newValue },
            numericAttributes: commonNumericAttributes,
            booleanAttributes: [:]
        )

        #expect(accepted == nil)
        #expect(rejectedIdentity == .unsafeAttribute)
    }
}
