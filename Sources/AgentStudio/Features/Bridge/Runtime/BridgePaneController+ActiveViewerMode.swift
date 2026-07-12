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
        await runActiveViewerModeSuppressionCatchUpIfNeeded(
            for: activeViewerModeSignalState.acceptedSignal
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
        await runActiveViewerModeSuppressionCatchUpIfNeeded(
            for: activeViewerModeSignalState.acceptedSignal
        )
    }

    func shouldSuppressReviewProtocolProduction(generation _: Int) -> Bool {
        guard let acceptedSignal = activeViewerModeSignalState.acceptedSignal,
            acceptedSignal.mode == .file,
            acceptedSignal.activeSource.protocolId == .worktreeFile
        else {
            return false
        }
        return true
    }

    func recordActiveViewerModeSuppression(
        suppressedProtocolId: String,
        generation: Int,
        phase: String
    ) async {
        markDroppedWhileSuppressed(protocolId: suppressedProtocolId)
        guard let telemetryRecorder,
            let acceptedSignal = activeViewerModeSignalState.acceptedSignal
        else {
            return
        }
        await telemetryRecorder.record(
            sample: BridgeTelemetrySample(
                scope: .swift,
                name: "performance.bridge.swift.active_viewer_mode_gate_suppressed",
                durationMilliseconds: nil,
                traceContext: nil,
                stringAttributes: [
                    "agentstudio.bridge.active_source.protocol": acceptedSignal.activeSource.protocolId.rawValue,
                    "agentstudio.bridge.active_viewer.mode": acceptedSignal.mode.rawValue,
                    "agentstudio.bridge.phase": phase,
                    "agentstudio.bridge.plane": BridgeTelemetryPlane.data.rawValue,
                    "agentstudio.bridge.priority": BridgeTelemetryPriority.cold.rawValue,
                    "agentstudio.bridge.slice": telemetrySliceForSuppressedProtocol(suppressedProtocolId).rawValue,
                    "agentstudio.bridge.suppressed.protocol": suppressedProtocolId,
                    "agentstudio.bridge.transport": "swift",
                ],
                numericAttributes: [
                    "agentstudio.bridge.generation": Double(generation),
                    "agentstudio.bridge.mode_gate.suppressed.count": 1,
                ],
                booleanAttributes: [:]
            ),
            receivedAtUnixNano: UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        )
    }

    private func markDroppedWhileSuppressed(protocolId: String) {
        guard protocolId == "review",
            let generation = paneState.diff.packageMetadata?.reviewGeneration.rawValue
        else { return }
        reviewProtocolSuppressedDrop = BridgeSuppressedProtocolDrop(
            generation: generation,
            nextSequenceAtDrop: nextReviewProtocolSequence
        )
    }

    private func runActiveViewerModeSuppressionCatchUpIfNeeded(
        for acceptedSignal: BridgeActiveViewerModeAcceptedSignal?
    ) async {
        guard let acceptedSignal else { return }
        guard acceptedSignal.mode == .review,
            acceptedSignal.activeSource.protocolId == .review,
            let suppressedDrop = reviewProtocolSuppressedDrop,
            suppressedDrop.generation == acceptedSignal.activeSource.generation,
            suppressedDrop.nextSequenceAtDrop == nextReviewProtocolSequence
        else { return }
        reviewProtocolSuppressedDrop = nil
        await recordActiveViewerModeSuppressionCatchUp(
            protocolId: "review",
            mode: acceptedSignal.mode,
            activeSource: acceptedSignal.activeSource
        )
        await redeliverCurrentReviewPackageForSuppressionCatchUp()
    }

    private func redeliverCurrentReviewPackageForSuppressionCatchUp() async {
        guard let currentPackage = paneState.diff.packageMetadata else {
            return
        }
        await commitReviewPackageLoad(
            BridgeReviewPackageLoadData(
                package: currentPackage,
                delta: paneState.diff.packageDelta
            ),
            traceContext: lastReviewPackageTraceContext
        )
    }

    private func recordActiveViewerModeSuppressionCatchUp(
        protocolId: String,
        mode: BridgeActiveViewerMode,
        activeSource: BridgeActiveViewerSource
    ) async {
        guard let telemetryRecorder else {
            return
        }
        await telemetryRecorder.record(
            sample: BridgeTelemetrySample(
                scope: .swift,
                name: "performance.bridge.swift.active_viewer_mode_suppression_catch_up",
                durationMilliseconds: nil,
                traceContext: nil,
                stringAttributes: [
                    "agentstudio.bridge.active_source.protocol": activeSource.protocolId.rawValue,
                    "agentstudio.bridge.active_viewer.mode": mode.rawValue,
                    "agentstudio.bridge.phase": "active_viewer_mode_suppression_catch_up",
                    "agentstudio.bridge.plane": BridgeTelemetryPlane.data.rawValue,
                    "agentstudio.bridge.priority": BridgeTelemetryPriority.warm.rawValue,
                    "agentstudio.bridge.protocol": protocolId,
                    "agentstudio.bridge.slice": telemetrySliceForSuppressedProtocol(protocolId).rawValue,
                    "agentstudio.bridge.transport": "swift",
                ],
                numericAttributes: [
                    "agentstudio.bridge.generation": Double(activeSource.generation),
                    "agentstudio.bridge.mode_gate.catch_up.count": 1,
                ],
                booleanAttributes: [:]
            ),
            receivedAtUnixNano: UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
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

    private func telemetrySliceForSuppressedProtocol(_ protocolId: String) -> BridgeTelemetrySlice {
        switch protocolId {
        case "review":
            return .reviewMetadata
        default:
            return .unknown
        }
    }
}

private enum BridgeActiveViewerModeSignalRejectionReason: String {
    case staleGeneration = "stale_generation"
    case staleSequence = "stale_sequence"
    case sessionReset = "session_reset"
}
