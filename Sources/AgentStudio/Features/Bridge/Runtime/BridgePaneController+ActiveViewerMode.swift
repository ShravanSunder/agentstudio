import Foundation

@MainActor
extension BridgePaneController {
    func handleBridgeActiveViewerModeUpdate(_ params: BridgeActiveViewerModeUpdateMethod.Params) {
        if activeViewerModeSignalState.sessionId != params.sessionId {
            activeViewerModeSignalState = BridgeActiveViewerModeSignalState(
                sessionId: params.sessionId,
                lastSequence: nil,
                acceptedSignal: nil
            )
        }
        if let lastSequence = activeViewerModeSignalState.lastSequence,
            params.sequence <= lastSequence
        {
            return
        }

        activeViewerModeSignalState.lastSequence = params.sequence
        guard let activeSource = params.activeSource,
            isActiveViewerSourceCurrent(activeSource)
        else {
            activeViewerModeSignalState.acceptedSignal = nil
            return
        }
        activeViewerModeSignalState.acceptedSignal = BridgeActiveViewerModeAcceptedSignal(
            mode: params.mode,
            activeSource: activeSource
        )
    }

    func shouldSuppressReviewProtocolProduction(generation _: Int) -> Bool {
        guard let acceptedSignal = activeViewerModeSignalState.acceptedSignal,
            acceptedSignal.mode == .file,
            acceptedSignal.activeSource.protocolId == .worktreeFile
        else {
            return false
        }
        return isActiveViewerSourceCurrent(acceptedSignal.activeSource)
    }

    func shouldSuppressWorktreeFileProduction(generation _: Int) -> Bool {
        guard let acceptedSignal = activeViewerModeSignalState.acceptedSignal,
            acceptedSignal.mode == .review,
            acceptedSignal.activeSource.protocolId == .review
        else {
            return false
        }
        return isActiveViewerSourceCurrent(acceptedSignal.activeSource)
    }

    func recordActiveViewerModeSuppression(
        suppressedProtocolId: String,
        generation: Int,
        phase: String
    ) async {
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

    private func isActiveViewerSourceCurrent(_ source: BridgeActiveViewerSource) -> Bool {
        switch source.protocolId {
        case .review:
            guard let package = paneState.diff.packageMetadata else {
                return false
            }
            return source.streamId == reviewProtocolStreamId()
                && source.generation == package.reviewGeneration.rawValue
        case .worktreeFile:
            guard let activeSource = activeWorktreeFileSurfaceSource else {
                return false
            }
            return source.streamId == activeSource.streamId
                && source.generation == activeSource.source.subscriptionGeneration
                && source.generation == nextWorktreeFileSurfaceGeneration
        }
    }

    private func telemetrySliceForSuppressedProtocol(_ protocolId: String) -> BridgeTelemetrySlice {
        switch protocolId {
        case "review":
            return .reviewMetadata
        case "worktree-file":
            return .treePrepareInput
        default:
            return .unknown
        }
    }
}
