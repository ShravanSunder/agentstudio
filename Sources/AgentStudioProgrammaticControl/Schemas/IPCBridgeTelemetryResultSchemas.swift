import Foundation

extension IPCBridgeTelemetryUnavailableReason: IPCSchemaProviding {}
extension IPCBridgeTelemetryResultKind: IPCSchemaProviding {}
extension IPCBridgeTelemetryDrainSettlementDisposition: IPCSchemaProviding {}
extension IPCBridgeTelemetryWorkerState: IPCSchemaProviding {}
extension IPCBridgeTelemetryProducerId: IPCSchemaProviding {}
extension IPCBridgeTelemetryLossOrigin: IPCSchemaProviding {}
extension IPCBridgeTelemetryLossReason: IPCSchemaProviding {}
extension IPCBridgeTelemetryTransportFailureStage: IPCSchemaProviding {}
extension IPCBridgeTelemetryNativeRejectionReason: IPCSchemaProviding {}
extension IPCBridgeTelemetryResponseMismatchField: IPCSchemaProviding {}

extension IPCBridgeTelemetryProducerDiagnostics: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            telemetryInteger("generation", "Producer generation", minimum: 0),
            telemetryInteger("nextSampleSequence", "Next sample sequence", minimum: 0),
            telemetryInteger("nextControlSequence", "Next control sequence", minimum: 0),
            telemetryInteger("sampleCredits", "Remaining sample credits", minimum: 0),
            telemetryInteger("controlCredits", "Remaining control credits", minimum: 0),
        ])
    }
}

extension IPCBridgeTelemetryHeadOutboxDiagnostics: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            telemetryInteger("batchSequence", "Head outbox batch sequence", minimum: 1),
            telemetryInteger("retryAttemptCount", "Delivery attempts already made", minimum: 0),
            .init(
                name: "retryScheduled", description: "Whether another delivery attempt is scheduled", schema: .boolean),
        ])
    }
}

extension IPCBridgeTelemetryTransportFailureDiagnostics: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        let retryAttempts = telemetryInteger("retryAttempts", "Positive transport retry attempt count", minimum: 1)
        return .oneOf([
            .object(fields: [
                .init(name: "stage", description: "Transport failure stage", schema: .string(allowedValues: ["fetch"])),
                .init(name: "httpStatus", description: "No HTTP response was received", schema: .null),
                retryAttempts,
            ]),
            telemetryHTTPFailure(stage: "http_status", retryAttempts: retryAttempts),
            telemetryHTTPFailure(stage: "response_body", retryAttempts: retryAttempts),
            telemetryHTTPFailure(stage: "response_schema", retryAttempts: retryAttempts),
        ])
    }
}

extension IPCBridgeTelemetryBatchDeliveryFailureDiagnostics: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .oneOf([
            .object(fields: [
                telemetryKind("transport"),
                .init(
                    name: "transport", description: "Transport-layer delivery failure",
                    schema: try IPCBridgeTelemetryTransportFailureDiagnostics.ipcSchema()),
            ]),
            .object(fields: [
                telemetryKind("native_rejection"),
                telemetryInteger("batchSequence", "Rejected batch sequence", minimum: 1),
                telemetryInteger("retryAttempts", "Delivery attempts already made", minimum: 0),
                .init(
                    name: "reason", description: "Native ingestion rejection reason",
                    schema: try IPCBridgeTelemetryNativeRejectionReason.ipcSchema()),
                .init(name: "retryable", description: "Whether native ingestion permits retry", schema: .boolean),
            ]),
            .object(fields: [
                telemetryKind("response_mismatch"),
                telemetryInteger("batchSequence", "Batch sequence whose response was inconsistent", minimum: 1),
                telemetryInteger("retryAttempts", "Delivery attempts already made", minimum: 0),
                .init(
                    name: "mismatchField", description: "Response field that failed identity validation",
                    schema: try IPCBridgeTelemetryResponseMismatchField.ipcSchema()),
            ]),
        ])
    }
}

extension IPCBridgeTelemetryLossDiagnostic: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(
                name: "origin", description: "Layer that recorded the loss",
                schema: try IPCBridgeTelemetryLossOrigin.ipcSchema()),
            .init(
                name: "producerId", description: "Producer whose sequence was lost",
                schema: try IPCBridgeTelemetryProducerId.ipcSchema()),
            telemetryInteger("lostSequenceStart", "First lost producer sequence", minimum: 0),
            telemetryInteger("lostSequenceEnd", "Last lost producer sequence", minimum: 0),
            telemetryInteger("requiredCount", "Required telemetry records lost", minimum: 0),
            telemetryInteger("optionalCount", "Optional telemetry records lost", minimum: 0),
            .init(
                name: "reason", description: "Resource or delivery cause of loss",
                schema: try IPCBridgeTelemetryLossReason.ipcSchema()),
        ])
    }
}

extension IPCBridgeTelemetryWorkerDiagnostics: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(
                name: "state", description: "Telemetry worker lifecycle state",
                schema: try IPCBridgeTelemetryWorkerState.ipcSchema()),
            telemetryInteger("bufferedSampleCount", "Samples buffered in memory", minimum: 0),
            telemetryInteger("bufferedSampleByteCount", "Encoded bytes held by buffered samples", minimum: 0),
            telemetryInteger("bufferedLossSummaryCount", "Loss summaries buffered in memory", minimum: 0),
            telemetryInteger("bufferedLossSummaryByteCount", "Encoded bytes held by loss summaries", minimum: 0),
            telemetryInteger("outboxCount", "Batches awaiting native delivery", minimum: 0),
            telemetryInteger("outboxByteCount", "Encoded bytes held by the outbox", minimum: 0),
            telemetryInteger("nextBatchSequence", "Next batch sequence", minimum: 1),
            .init(name: "isPostInFlight", description: "Whether a native delivery request is active", schema: .boolean),
            .optional(
                "mainProducer", description: "Main-world producer diagnostics",
                schema: try IPCBridgeTelemetryProducerDiagnostics.ipcSchema()),
            .optional(
                "commProducer", description: "Communication-world producer diagnostics",
                schema: try IPCBridgeTelemetryProducerDiagnostics.ipcSchema()),
            .optional(
                "headOutbox", description: "Head outbox batch diagnostics",
                schema: try IPCBridgeTelemetryHeadOutboxDiagnostics.ipcSchema()),
            .optional(
                "lastBatchDeliveryFailure", description: "Most recent batch delivery failure",
                schema: try IPCBridgeTelemetryBatchDeliveryFailureDiagnostics.ipcSchema()),
            .init(
                name: "lossDiagnostics", description: "Up to sixteen recent telemetry loss ranges",
                schema: .array(items: try IPCBridgeTelemetryLossDiagnostic.ipcSchema(), maximumCount: 16)),
        ])
    }
}

extension IPCBridgeTelemetryReport: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "telemetrySessionId", description: "Bridge telemetry session identifier", schema: .string()),
            .init(
                name: "proofEligible", description: "Whether this report satisfies telemetry proof prerequisites",
                schema: .boolean),
            .init(name: "lossy", description: "Whether any required or optional telemetry was lost", schema: .boolean),
            telemetryInteger("requiredLossCount", "Required telemetry records lost", minimum: 0),
            telemetryInteger("optionalLossCount", "Optional telemetry records lost", minimum: 0),
            telemetryInteger("workerSequenceGapCount", "Producer-to-worker sequence gaps", minimum: 0),
            telemetryInteger("nativeBatchSequenceGapCount", "Worker-to-native batch sequence gaps", minimum: 0),
            telemetryInteger("acceptedBatchSequence", "Latest batch accepted by native ingestion", minimum: 0),
            .optional(
                "mainProducerHighWatermark", description: "Highest accepted main-producer sequence",
                schema: .integer(minimum: 0)),
            .optional(
                "commProducerHighWatermark", description: "Highest accepted communication-producer sequence",
                schema: .integer(minimum: 0)),
            .optional(
                "drainSettlementDisposition", description: "Whether drain completion closed or reopened intake",
                schema: try IPCBridgeTelemetryDrainSettlementDisposition.ipcSchema()),
            .optional(
                "workerDiagnostics", description: "Worker and queue diagnostic snapshot",
                schema: try IPCBridgeTelemetryWorkerDiagnostics.ipcSchema()),
        ])
    }
}

extension IPCBridgeTelemetrySnapshotResult: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        try telemetryResultSchema(includeDrained: false)
    }
}

extension IPCBridgeTelemetryFlushResult: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        try telemetryResultSchema(includeDrained: true)
    }
}

private func telemetryResultSchema(includeDrained: Bool) throws -> IPCJSONSchema {
    var unavailableFields: [IPCObjectField] = [
        .init(name: "paneId", description: "Bridge pane UUID", schema: IPCSchemaScalars.uuid),
        .init(name: "kind", description: "Telemetry result kind", schema: .string(allowedValues: ["unavailable"])),
        .init(
            name: "unavailableReason", description: "Reason telemetry is unavailable",
            schema: try IPCBridgeTelemetryUnavailableReason.ipcSchema()),
        .init(
            name: "report", description: "No report is present for unavailable telemetry",
            schema: .null, presence: .optional),
    ]
    var reportFields: [IPCObjectField] = [
        .init(name: "paneId", description: "Bridge pane UUID", schema: IPCSchemaScalars.uuid),
        .init(name: "kind", description: "Telemetry result kind", schema: .string(allowedValues: ["report"])),
        .init(
            name: "unavailableReason",
            description: "No unavailability reason is present for a report", schema: .null,
            presence: .optional),
        .init(name: "report", description: "Bridge telemetry report", schema: try IPCBridgeTelemetryReport.ipcSchema()),
    ]
    if includeDrained {
        unavailableFields.append(
            .init(
                name: "drained",
                description: "No drain state is available when telemetry is unavailable", schema: .null,
                presence: .optional))
        reportFields.append(
            .init(name: "drained", description: "Whether buffered telemetry was fully drained", schema: .boolean))
    }
    return .oneOf([.object(fields: unavailableFields), .object(fields: reportFields)])
}

private func telemetryHTTPFailure(stage: String, retryAttempts: IPCObjectField) -> IPCJSONSchema {
    .object(fields: [
        .init(name: "stage", description: "Transport failure stage", schema: .string(allowedValues: [stage])),
        .init(
            name: "httpStatus", description: "HTTP response status code", schema: .integer(minimum: 100, maximum: 599)),
        retryAttempts,
    ])
}

private func telemetryKind(_ value: String) -> IPCObjectField {
    .init(name: "kind", description: "Batch delivery failure kind", schema: .string(allowedValues: [value]))
}

private func telemetryInteger(_ name: String, _ description: String, minimum: Int64) -> IPCObjectField {
    .init(
        name: name, description: description,
        schema: .integer(minimum: minimum, maximum: IPCSchemaScalars.maximumExactInteger))
}
