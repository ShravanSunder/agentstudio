import Foundation

@MainActor
extension BridgePaneController {
    func handleCommittedProductActiveViewerModeUpdate(
        sessionId: String,
        sequence: Int,
        mode: BridgeActiveViewerMode,
        activeSource: BridgeActiveViewerSource?
    ) async {
        if activeViewerModeSignalState.sessionId != sessionId {
            if activeViewerModeSignalState.sessionId != nil {
                await recordActiveViewerModeSignalRejected(
                    reason: .sessionReset,
                    mode: mode,
                    activeSource: activeSource
                )
            }
            activeViewerModeSignalState = BridgeActiveViewerModeSignalState(
                sessionId: sessionId,
                lastSequence: nil,
                acceptedSignal: nil
            )
        }
        if let lastSequence = activeViewerModeSignalState.lastSequence,
            sequence <= lastSequence
        {
            await recordActiveViewerModeSignalRejected(
                reason: .staleSequence,
                mode: mode,
                activeSource: activeSource
            )
            return
        }

        activeViewerModeSignalState.lastSequence = sequence
        guard let activeSource else {
            activeViewerModeSignalState.acceptedSignal = nil
            return
        }
        guard isCommittedProductActiveViewerSourceAccepted(mode: mode, source: activeSource) else {
            activeViewerModeSignalState.acceptedSignal = nil
            await recordActiveViewerModeSignalRejected(
                reason: .staleGeneration,
                mode: mode,
                activeSource: activeSource
            )
            return
        }
        activeViewerModeSignalState.acceptedSignal = BridgeActiveViewerModeAcceptedSignal(
            mode: mode,
            activeSource: activeSource,
            sequenceFloor: sequence
        )
    }

    func setActiveViewerModeAcceptedSignalForExplicitReviewRequest(
        streamId: String,
        generation: Int
    ) async {
        await setActiveViewerModeAcceptedSignalForExplicitRequest(
            mode: .review,
            activeSource: BridgeActiveViewerSource(
                protocolId: .review,
                streamId: streamId,
                generation: generation
            )
        )
    }

    func clearActiveViewerModeAcceptedSignalForExplicitReviewRequest() {
        activeViewerModeSignalState.acceptedSignal = nil
    }

    private func setActiveViewerModeAcceptedSignalForExplicitRequest(
        mode: BridgeActiveViewerMode,
        activeSource: BridgeActiveViewerSource
    ) async {
        let sequenceFloor = (activeViewerModeSignalState.lastSequence ?? 0) + 1
        activeViewerModeSignalState.lastSequence = sequenceFloor
        activeViewerModeSignalState.acceptedSignal = BridgeActiveViewerModeAcceptedSignal(
            mode: mode,
            activeSource: activeSource,
            sequenceFloor: sequenceFloor
        )
    }

    private func recordActiveViewerModeSignalRejected(
        reason: BridgeActiveViewerModeSignalRejectionReason,
        mode: BridgeActiveViewerMode,
        activeSource: BridgeActiveViewerSource?
    ) async {
        guard let telemetryRecorder else {
            return
        }
        await telemetryRecorder.record(
            sample: BridgeTelemetrySample(
                scope: .swift,
                name: "performance.bridge.swift.active_viewer_mode_signal_rejected",
                durationMilliseconds: nil,
                traceContext: nil,
                stringAttributes: [
                    "agentstudio.bridge.active_source.protocol": activeSource?.protocolId.rawValue ?? "none",
                    "agentstudio.bridge.active_viewer.mode": mode.rawValue,
                    "agentstudio.bridge.active_viewer.signal_rejection_reason": reason.rawValue,
                    "agentstudio.bridge.phase": "active_viewer_mode_signal_rejected",
                    "agentstudio.bridge.plane": BridgeTelemetryPlane.control.rawValue,
                    "agentstudio.bridge.priority": BridgeTelemetryPriority.warm.rawValue,
                    "agentstudio.bridge.slice": BridgeTelemetrySlice.reviewRPC.rawValue,
                    "agentstudio.bridge.transport": "swift",
                ],
                numericAttributes: [
                    "agentstudio.bridge.active_viewer.signal_rejected.count": 1
                ],
                booleanAttributes: [:]
            ),
            receivedAtUnixNano: UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        )
    }

    private func isCommittedProductActiveViewerSourceAccepted(
        mode: BridgeActiveViewerMode,
        source: BridgeActiveViewerSource
    ) -> Bool {
        if mode == .file {
            return source.protocolId == .worktreeFile
        }
        guard source.protocolId == .review,
            let package = paneState.diff.packageMetadata
        else { return false }
        return source.streamId == reviewProtocolStreamId()
            && source.generation == package.reviewGeneration.rawValue
    }

}

private enum BridgeActiveViewerModeSignalRejectionReason: String {
    case staleGeneration = "stale_generation"
    case staleSequence = "stale_sequence"
    case sessionReset = "session_reset"
}
