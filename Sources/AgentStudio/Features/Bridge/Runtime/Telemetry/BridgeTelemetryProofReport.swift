import AgentStudioProgrammaticControl
import CryptoKit
import Foundation

enum BridgeTelemetrySidecarProofPhase: String, Sendable {
    case nonterminalReopened = "nonterminal_reopened"
    case terminalClosed = "terminal_closed"
}

private struct BridgeTelemetryWorkerProofSnapshot {
    let proofEligible: Bool
    let lossy: Bool
    let requiredLossCount: Int
    let optionalLossCount: Int
    let sequenceGapCount: Int
    let acceptedBatchSequence: Int
    let mainProducerHighWatermark: Int?
    let commProducerHighWatermark: Int?
    let drainSettlementDisposition: IPCBridgeTelemetryDrainSettlementDisposition?
    let workerDiagnostics: IPCBridgeTelemetryWorkerDiagnostics?
}

enum BridgeTelemetryProofReport {
    static func snapshot(
        telemetrySessionId: String,
        sidecar: BridgeTelemetrySidecarSnapshot,
        native: BridgeTelemetrySessionSnapshot
    ) -> IPCBridgeTelemetryReport {
        make(
            telemetrySessionId: telemetrySessionId,
            worker: BridgeTelemetryWorkerProofSnapshot(
                proofEligible: sidecar.proofEligible,
                lossy: sidecar.lossy,
                requiredLossCount: sidecar.requiredLossCount,
                optionalLossCount: sidecar.optionalLossCount,
                sequenceGapCount: sidecar.sequenceGapCount,
                acceptedBatchSequence: sidecar.acceptedBatchSequence,
                mainProducerHighWatermark:
                    sidecar.producers["main"].flatMap { $0 }?.barrierHighWatermark,
                commProducerHighWatermark:
                    sidecar.producers["comm"].flatMap { $0 }?.barrierHighWatermark,
                drainSettlementDisposition: nil,
                workerDiagnostics: workerDiagnostics(sidecar)
            ),
            native: native
        )
    }

    static func drain(
        telemetrySessionId: String,
        sidecar: BridgeTelemetrySidecarDrainResult,
        expectedSettlementDisposition: BridgeTelemetrySidecarSettlementDisposition,
        native: BridgeTelemetrySessionSnapshot
    ) -> IPCBridgeTelemetryReport {
        let report = make(
            telemetrySessionId: telemetrySessionId,
            worker: BridgeTelemetryWorkerProofSnapshot(
                proofEligible: sidecar.proofEligible,
                lossy: sidecar.requiredLossCount > 0 || sidecar.optionalLossCount > 0,
                requiredLossCount: sidecar.requiredLossCount,
                optionalLossCount: sidecar.optionalLossCount,
                sequenceGapCount: sidecar.sequenceGapCount,
                acceptedBatchSequence: sidecar.acceptedBatchSequence,
                mainProducerHighWatermark: sidecar.producerHighWatermarks["main"],
                commProducerHighWatermark: sidecar.producerHighWatermarks["comm"],
                drainSettlementDisposition: IPCBridgeTelemetryDrainSettlementDisposition(
                    rawValue: sidecar.settlementDisposition.rawValue
                ),
                workerDiagnostics: nil
            ),
            native: native
        )
        guard sidecar.settlementDisposition == expectedSettlementDisposition else {
            return IPCBridgeTelemetryReport(
                telemetrySessionId: report.telemetrySessionId,
                proofEligible: false,
                lossy: report.lossy,
                requiredLossCount: report.requiredLossCount,
                optionalLossCount: report.optionalLossCount,
                workerSequenceGapCount: report.workerSequenceGapCount,
                nativeBatchSequenceGapCount: report.nativeBatchSequenceGapCount,
                acceptedBatchSequence: report.acceptedBatchSequence,
                mainProducerHighWatermark: report.mainProducerHighWatermark,
                commProducerHighWatermark: report.commProducerHighWatermark,
                drainSettlementDisposition: report.drainSettlementDisposition,
                workerDiagnostics: report.workerDiagnostics
            )
        }
        return report
    }

    static func proofSample(
        report: IPCBridgeTelemetryReport,
        phase: BridgeTelemetrySidecarProofPhase,
        expectedSettlementDisposition: IPCBridgeTelemetryDrainSettlementDisposition
    ) -> BridgeTelemetrySample {
        let settlementAcknowledged = report.drainSettlementDisposition == expectedSettlementDisposition
        return BridgeTelemetrySample(
            scope: .swift,
            name: "performance.bridge.swift.telemetry_sidecar_drain",
            durationMilliseconds: nil,
            traceContext: nil,
            stringAttributes: [
                "agentstudio.bridge.phase": phase.rawValue,
                "agentstudio.bridge.plane": BridgeTelemetryPlane.observability.rawValue,
                "agentstudio.bridge.priority": BridgeTelemetryPriority.cold.rawValue,
                "agentstudio.bridge.slice": "telemetry_sidecar",
                "agentstudio.bridge.telemetry.session.digest": telemetrySessionDigest(
                    report.telemetrySessionId
                ),
                "agentstudio.bridge.transport": "telemetry_sidecar",
            ],
            numericAttributes: [
                "agentstudio.bridge.telemetry.accepted_batch.sequence": Double(
                    report.acceptedBatchSequence
                ),
                "agentstudio.bridge.telemetry.main_producer.high_watermark": Double(
                    report.mainProducerHighWatermark ?? -1
                ),
                "agentstudio.bridge.telemetry.comm_producer.high_watermark": Double(
                    report.commProducerHighWatermark ?? -1
                ),
                "agentstudio.bridge.telemetry.required_loss.count": Double(report.requiredLossCount),
                "agentstudio.bridge.telemetry.optional_loss.count": Double(report.optionalLossCount),
                "agentstudio.bridge.telemetry.worker_sequence_gap.count": Double(
                    report.workerSequenceGapCount
                ),
                "agentstudio.bridge.telemetry.native_batch_sequence_gap.count": Double(
                    report.nativeBatchSequenceGapCount
                ),
            ],
            booleanAttributes: [
                "agentstudio.bridge.telemetry.proof_eligible": report.proofEligible,
                "agentstudio.bridge.telemetry.lossy": report.lossy,
                "agentstudio.bridge.telemetry.settlement_acknowledged": settlementAcknowledged,
            ]
        )
    }

    private static func telemetrySessionDigest(_ telemetrySessionId: String) -> String {
        SHA256.hash(data: Data(telemetrySessionId.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func make(
        telemetrySessionId: String,
        worker: BridgeTelemetryWorkerProofSnapshot,
        native: BridgeTelemetrySessionSnapshot
    ) -> IPCBridgeTelemetryReport {
        let identitiesMatch =
            native.telemetrySessionId == telemetrySessionId
            && native.acceptedBatchSequence == worker.acceptedBatchSequence
        let lossCountsMatch =
            native.requiredLossCount == worker.requiredLossCount
            && native.optionalLossCount == worker.optionalLossCount
        let requiredLossCount = max(native.requiredLossCount, worker.requiredLossCount)
        let optionalLossCount = max(native.optionalLossCount, worker.optionalLossCount)
        let proofEligible =
            identitiesMatch
            && lossCountsMatch
            && native.proofEligible
            && worker.proofEligible
            && requiredLossCount == 0
            && worker.sequenceGapCount == 0
            && native.batchSequenceGapCount == 0
        return IPCBridgeTelemetryReport(
            telemetrySessionId: telemetrySessionId,
            proofEligible: proofEligible,
            lossy: worker.lossy || native.lossy,
            requiredLossCount: requiredLossCount,
            optionalLossCount: optionalLossCount,
            workerSequenceGapCount: worker.sequenceGapCount,
            nativeBatchSequenceGapCount: native.batchSequenceGapCount,
            acceptedBatchSequence: native.acceptedBatchSequence,
            mainProducerHighWatermark: worker.mainProducerHighWatermark,
            commProducerHighWatermark: worker.commProducerHighWatermark,
            drainSettlementDisposition: worker.drainSettlementDisposition,
            workerDiagnostics: worker.workerDiagnostics
        )
    }

    private static func workerDiagnostics(
        _ sidecar: BridgeTelemetrySidecarSnapshot
    ) -> IPCBridgeTelemetryWorkerDiagnostics {
        IPCBridgeTelemetryWorkerDiagnostics(
            state: IPCBridgeTelemetryWorkerState(rawValue: sidecar.state.rawValue) ?? .failed,
            bufferedSampleCount: sidecar.bufferedSampleCount,
            bufferedSampleByteCount: sidecar.bufferedSampleBytes,
            bufferedLossSummaryCount: sidecar.bufferedLossSummaryCount,
            bufferedLossSummaryByteCount: sidecar.bufferedLossSummaryBytes,
            outboxCount: sidecar.outboxCount,
            outboxByteCount: sidecar.outboxBytes,
            nextBatchSequence: sidecar.nextBatchSequence,
            isPostInFlight: sidecar.isPostInFlight,
            mainProducer: producerDiagnostics(sidecar.producers["main"].flatMap { $0 }),
            commProducer: producerDiagnostics(sidecar.producers["comm"].flatMap { $0 }),
            headOutbox: sidecar.headOutbox.map {
                IPCBridgeTelemetryHeadOutboxDiagnostics(
                    batchSequence: $0.batchSequence,
                    retryAttemptCount: $0.retryAttemptCount,
                    retryScheduled: $0.retryScheduled
                )
            },
            lastBatchDeliveryFailure: {
                switch sidecar.lastBatchDeliveryFailure {
                case .noRecordedFailure:
                    nil
                case .transport(let transport):
                    .transport(transportFailureDiagnostics(transport))
                case .nativeRejection(let rejection):
                    .nativeRejection(
                        IPCBridgeTelemetryNativeRejectionDiagnostics(
                            batchSequence: rejection.batchSequence,
                            retryAttemptCount: rejection.retryAttemptCount,
                            reason: nativeRejectionReason(rejection.reason),
                            retryable: rejection.retryable
                        )
                    )
                case .responseMismatch(let mismatch):
                    .responseMismatch(
                        IPCBridgeTelemetryResponseMismatchDiagnostics(
                            batchSequence: mismatch.batchSequence,
                            retryAttemptCount: mismatch.retryAttemptCount,
                            mismatchField: responseMismatchField(mismatch.mismatchField)
                        )
                    )
                }
            }(),
            lossDiagnostics: sidecar.lossDiagnostics.prefix(16).compactMap { diagnostic in
                guard
                    let origin = IPCBridgeTelemetryLossOrigin(rawValue: diagnostic.origin.rawValue),
                    let producerId = IPCBridgeTelemetryProducerId(rawValue: diagnostic.producerId.rawValue),
                    let reason = IPCBridgeTelemetryLossReason(rawValue: diagnostic.reason.rawValue)
                else { return nil }
                return IPCBridgeTelemetryLossDiagnostic(
                    origin: origin,
                    producerId: producerId,
                    lostSequenceStart: diagnostic.lostSequenceStart,
                    lostSequenceEnd: diagnostic.lostSequenceEnd,
                    requiredCount: diagnostic.requiredCount,
                    optionalCount: diagnostic.optionalCount,
                    reason: reason
                )
            }
        )
    }

    private static func transportFailureDiagnostics(
        _ failure: BridgeTelemetrySidecarTransportFailureSnapshot
    ) -> IPCBridgeTelemetryTransportFailureDiagnostics {
        switch failure {
        case .fetch(let retryAttempts):
            .fetch(retryAttemptCount: retryAttempts)
        case .httpStatus(let statusCode, let retryAttempts):
            .httpStatus(statusCode: statusCode, retryAttemptCount: retryAttempts)
        case .responseBody(let statusCode, let retryAttempts):
            .responseBody(statusCode: statusCode, retryAttemptCount: retryAttempts)
        case .responseSchema(let statusCode, let retryAttempts):
            .responseSchema(statusCode: statusCode, retryAttemptCount: retryAttempts)
        }
    }

    private static func nativeRejectionReason(
        _ reason: BridgeTelemetrySidecarNativeRejectionReason
    ) -> IPCBridgeTelemetryNativeRejectionReason {
        switch reason {
        case .conflict: .conflict
        case .invalidBody: .invalidBody
        case .sequenceGap: .sequenceGap
        case .unavailable: .unavailable
        }
    }

    private static func responseMismatchField(
        _ field: BridgeTelemetrySidecarResponseMismatchField
    ) -> IPCBridgeTelemetryResponseMismatchField {
        switch field {
        case .telemetrySessionId: .telemetrySessionId
        case .batchSequence: .batchSequence
        case .nextExpectedBatchSequence: .nextExpectedBatchSequence
        case .acceptedSampleCount: .acceptedSampleCount
        case .acceptedLossCount: .acceptedLossCount
        }
    }

    private static func producerDiagnostics(
        _ producer: BridgeTelemetrySidecarProducerSnapshot?
    ) -> IPCBridgeTelemetryProducerDiagnostics? {
        producer.map {
            IPCBridgeTelemetryProducerDiagnostics(
                generation: $0.generation,
                nextSampleSequence: $0.nextExpectedSequence,
                nextControlSequence: $0.nextExpectedControlSequence,
                sampleCredits: $0.availableSampleCredits,
                controlCredits: $0.availableControlCredits
            )
        }
    }
}
