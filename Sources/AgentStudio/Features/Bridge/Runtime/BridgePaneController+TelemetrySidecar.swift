import AgentStudioProgrammaticControl
import Foundation
import WebKit

@MainActor
extension BridgePaneController {
    func telemetrySidecarSnapshot() async throws -> BridgeTelemetrySidecarSnapshotEnvelope {
        let data = try await telemetrySidecarControlData(action: .snapshot)
        let envelope = try JSONDecoder().decode(BridgeTelemetrySidecarSnapshotEnvelope.self, from: data)
        return envelope
    }

    func drainTelemetrySidecar(
        closeAfterDrain: Bool
    ) async throws -> BridgeTelemetrySidecarDrainEnvelope {
        let action: BridgeTelemetrySidecarControlAction = closeAfterDrain ? .drainAndClose : .drain
        let data = try await telemetrySidecarControlData(action: action)
        let envelope = try JSONDecoder().decode(BridgeTelemetrySidecarDrainEnvelope.self, from: data)
        return envelope
    }

    func recordTelemetrySidecarProof(
        report: IPCBridgeTelemetryReport,
        phase: BridgeTelemetrySidecarProofPhase,
        expectedSettlementDisposition: IPCBridgeTelemetryDrainSettlementDisposition
    ) async throws {
        guard let telemetryRecorder else { return }
        await telemetryRecorder.record(
            sample: BridgeTelemetryProofReport.proofSample(
                report: report,
                phase: phase,
                expectedSettlementDisposition: expectedSettlementDisposition
            ),
            receivedAtUnixNano: UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        )
        try await telemetryRecorder.drain()
    }

    private func telemetrySidecarControlData(
        action: BridgeTelemetrySidecarControlAction
    ) async throws -> Data {
        let result = try await page.callJavaScript(
            """
            const control = globalThis.__bridgeTelemetrySidecarControl;
            if (!control || typeof control[action] !== 'function') {
                return JSON.stringify({ kind: 'unavailable', reason: 'disabled' });
            }
            return JSON.stringify(await control[action]());
            """,
            arguments: ["action": action.rawValue],
            contentWorld: .page
        )
        guard let json = result as? String, let data = json.data(using: .utf8) else {
            throw BridgeTelemetrySidecarControlError.invalidResponse
        }
        return data
    }
}
