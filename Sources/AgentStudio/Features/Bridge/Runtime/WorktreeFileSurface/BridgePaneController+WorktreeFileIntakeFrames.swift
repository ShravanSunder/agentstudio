import Foundation

private struct BridgeWorktreeFileSurfaceFrameIdentity: Decodable {
    let kind: String
    let streamId: String
    let generation: Int
    let sequence: Int
}

/// Emits the scheduler's enqueue-to-dequeue queue-wait and stale-drop facts
/// through the pane's performance trace recorder. Queue wait is scheduler
/// instrumentation only — never a request-to-delivered-frame span.
struct BridgePaneMetadataSchedulerTelemetryAdapter: BridgeMetadataLaneSchedulerTelemetry {
    let recorder: any BridgePerformanceTraceRecording

    func recordQueueWait(
        lane: BridgeDemandLane,
        protocolId: String,
        waitMilliseconds: Double,
        queueDepth: Int
    ) async {
        await recorder.record(
            sample: BridgeTelemetrySample(
                scope: .swift,
                name: "performance.bridge.viewer.demand_queue_wait",
                durationMilliseconds: waitMilliseconds,
                traceContext: nil,
                stringAttributes: [
                    "agentstudio.bridge.phase": "demand_queue_wait",
                    "agentstudio.bridge.plane": BridgeTelemetryPlane.data.rawValue,
                    "agentstudio.bridge.priority": BridgeTelemetryPriority.hot.rawValue,
                    "agentstudio.bridge.slice": BridgeTelemetrySlice.treePrepareInput.rawValue,
                    "agentstudio.bridge.transport": "swift",
                    "agentstudio.bridge.demand.lane": lane.rawValue,
                ],
                numericAttributes: [
                    "agentstudio.bridge.demand.scheduler_queue_wait_ms": waitMilliseconds,
                    "agentstudio.bridge.demand.queue_depth": Double(queueDepth),
                ],
                booleanAttributes: [:]
            ),
            receivedAtUnixNano: UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        )
    }

    func recordStaleDrop(lane: BridgeDemandLane, protocolId: String, droppedCount: Int) async {
        await recorder.record(
            sample: BridgeTelemetrySample(
                scope: .swift,
                name: "performance.bridge.swift.metadata_scheduler_stale_drop",
                durationMilliseconds: nil,
                traceContext: nil,
                stringAttributes: [
                    "agentstudio.bridge.phase": "metadata_scheduler_stale_drop",
                    "agentstudio.bridge.plane": BridgeTelemetryPlane.data.rawValue,
                    "agentstudio.bridge.priority": BridgeTelemetryPriority.cold.rawValue,
                    "agentstudio.bridge.slice": BridgeTelemetrySlice.treePrepareInput.rawValue,
                    "agentstudio.bridge.transport": "swift",
                    "agentstudio.bridge.demand.lane": lane.rawValue,
                ],
                numericAttributes: [
                    "agentstudio.bridge.demand.stale_drop.count": Double(droppedCount)
                ],
                booleanAttributes: [:]
            ),
            receivedAtUnixNano: UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        )
    }

    func recordOverflowDrop(lane: BridgeDemandLane, protocolId: String, droppedCount: Int) async {
        await recorder.record(
            sample: BridgeTelemetrySample(
                scope: .swift,
                name: "performance.bridge.swift.metadata_scheduler_overflow_drop",
                durationMilliseconds: nil,
                traceContext: nil,
                stringAttributes: [
                    "agentstudio.bridge.phase": "metadata_scheduler_overflow_drop",
                    "agentstudio.bridge.plane": BridgeTelemetryPlane.data.rawValue,
                    "agentstudio.bridge.priority": BridgeTelemetryPriority.cold.rawValue,
                    "agentstudio.bridge.slice": BridgeTelemetrySlice.treePrepareInput.rawValue,
                    "agentstudio.bridge.transport": "swift",
                    "agentstudio.bridge.demand.lane": lane.rawValue,
                ],
                numericAttributes: [
                    "agentstudio.bridge.demand.overflow_drop.count": Double(droppedCount)
                ],
                booleanAttributes: [:]
            ),
            receivedAtUnixNano: UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        )
    }
}

@MainActor
extension BridgePaneController {
    /// Encodes and delivers frames immediately. This is the execution body of
    /// scheduler jobs (and the direct path for reset frames): ordering is the
    /// scheduler's responsibility, so no gating or buffering happens here.
    /// Returns false on transport failure after marking connection health.
    func deliverWorktreeFileIntakeFramesNow<Frame: Encodable>(
        _ frames: [Frame]
    ) async -> Bool {
        let encodedFrames: [String]
        do {
            encodedFrames = try frames.map {
                try Self.makeWorktreeFileIntakeFrameString($0)
            }
        } catch {
            paneState.connection.setHealth(.error)
            return false
        }
        for encodedFrame in encodedFrames {
            guard await deliverIntakeFrame(encodedFrame) else {
                paneState.connection.setHealth(.error)
                return false
            }
        }
        return true
    }

    /// Enqueues one worktree-file metadata emission job on the pane's generic
    /// lane scheduler. The scheduler is the single ordering authority:
    /// sequences are reserved inside job execution, so delivery order equals
    /// sequence order by construction.
    func enqueueWorktreeFileMetadataJob(
        lane: BridgeDemandLane,
        generation: Int,
        work: @escaping @MainActor @Sendable () async -> Bool
    ) async {
        await worktreeFileMetadataScheduler.enqueue(
            BridgeMetadataLaneJob(
                protocolId: "worktree-file",
                generation: generation,
                lane: lane,
                work: work
            )
        )
    }

    private nonisolated static func makeWorktreeFileIntakeFrameString<Frame: Encodable>(
        _ frame: Frame
    ) throws -> String {
        let encoder = JSONEncoder()
        let envelopeEncoder = BridgePushEnvelopeEncoder()
        let frameData = try encoder.encode(frame)
        let object = try JSONDecoder().decode(BridgeWorktreeFileSurfaceFrameIdentity.self, from: frameData)
        guard let kind = BridgeIntakeFrameKind(rawValue: object.kind) else {
            throw BridgePushEnvelopeEncodingError.invalidEnvelopeUTF8
        }
        return try envelopeEncoder.encodeIntakeFrame(
            metadata: BridgeIntakeFrameMetadata(
                kind: kind,
                streamId: object.streamId,
                generation: object.generation,
                sequence: object.sequence
            ),
            payload: frameData,
            traceContext: nil
        )
    }

}
