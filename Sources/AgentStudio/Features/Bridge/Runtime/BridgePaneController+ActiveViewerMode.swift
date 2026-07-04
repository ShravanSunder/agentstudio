import Foundation

@MainActor
extension BridgePaneController {
    func handleBridgeActiveViewerModeUpdate(_ params: BridgeActiveViewerModeUpdateMethod.Params) async {
        if activeViewerModeSignalState.sessionId != params.sessionId {
            if activeViewerModeSignalState.sessionId != nil {
                await recordActiveViewerModeSignalRejected(
                    reason: .sessionReset,
                    mode: params.mode,
                    activeSource: params.activeSource
                )
            }
            activeViewerModeSignalState = BridgeActiveViewerModeSignalState(
                sessionId: params.sessionId,
                lastSequence: nil,
                acceptedSignal: nil
            )
        }
        if let lastSequence = activeViewerModeSignalState.lastSequence,
            params.sequence <= lastSequence
        {
            await recordActiveViewerModeSignalRejected(
                reason: .staleSequence,
                mode: params.mode,
                activeSource: params.activeSource
            )
            return
        }

        activeViewerModeSignalState.lastSequence = params.sequence
        guard let activeSource = params.activeSource else {
            activeViewerModeSignalState.acceptedSignal = nil
            return
        }
        guard isActiveViewerSourceCurrent(activeSource) else {
            activeViewerModeSignalState.acceptedSignal = nil
            await recordActiveViewerModeSignalRejected(
                reason: .staleGeneration,
                mode: params.mode,
                activeSource: activeSource
            )
            return
        }
        activeViewerModeSignalState.acceptedSignal = BridgeActiveViewerModeAcceptedSignal(
            mode: params.mode,
            activeSource: activeSource,
            sequenceFloor: params.sequence
        )
        await runActiveViewerModeSuppressionCatchUpIfNeeded(
            for: activeViewerModeSignalState.acceptedSignal
        )
    }

    func setActiveViewerModeAcceptedSignalForExplicitFileSurfaceRequest(
        streamId: String,
        generation: Int
    ) async {
        await setActiveViewerModeAcceptedSignalForExplicitRequest(
            mode: .file,
            activeSource: BridgeActiveViewerSource(
                protocolId: .worktreeFile,
                streamId: streamId,
                generation: generation
            )
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
        switch protocolId {
        case "review":
            reviewProtocolDroppedWhileSuppressed = true
        case "worktree-file":
            worktreeFileDroppedWhileSuppressed = true
        default:
            return
        }
    }

    private func runActiveViewerModeSuppressionCatchUpIfNeeded(
        for acceptedSignal: BridgeActiveViewerModeAcceptedSignal?
    ) async {
        guard let acceptedSignal else { return }
        switch (acceptedSignal.mode, acceptedSignal.activeSource.protocolId) {
        case (.review, .review):
            guard reviewProtocolDroppedWhileSuppressed else { return }
            reviewProtocolDroppedWhileSuppressed = false
            await recordActiveViewerModeSuppressionCatchUp(
                protocolId: "review",
                mode: acceptedSignal.mode,
                activeSource: acceptedSignal.activeSource
            )
            scheduleReviewPackageReloadForIntakeAnnounce()
        case (.file, .worktreeFile):
            guard worktreeFileDroppedWhileSuppressed else { return }
            worktreeFileDroppedWhileSuppressed = false
            await recordActiveViewerModeSuppressionCatchUp(
                protocolId: "worktree-file",
                mode: acceptedSignal.mode,
                activeSource: acceptedSignal.activeSource
            )
            scheduleWorktreeFileSurfaceSuppressionCatchUp()
        default:
            return
        }
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

private enum BridgeActiveViewerModeSignalRejectionReason: String {
    case staleGeneration = "stale_generation"
    case staleSequence = "stale_sequence"
    case sessionReset = "session_reset"
}
