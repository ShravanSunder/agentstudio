import Foundation
import Testing

@Suite("AgentStudio IPC Phase A smoke verifier script")
struct AgentStudioIPCPhaseASmokeScriptTests {
    @Test("phase-a verifier is wired through mise and escrow-authenticated pane snapshot calls")
    func phaseAVerifierIsWiredThroughMiseAndEscrowAuthenticatedPaneSnapshotCalls() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let script = try String(
            contentsOf: projectRoot.appendingPathComponent("scripts/verify-agentstudio-ipc-phase-a-smoke.sh"),
            encoding: .utf8
        )
        let mise = try String(contentsOf: projectRoot.appendingPathComponent(".mise.toml"), encoding: .utf8)

        #expect(mise.contains("[tasks.verify-agentstudio-ipc-phase-a-smoke]"))
        #expect(mise.contains("/bin/bash scripts/verify-agentstudio-ipc-phase-a-smoke.sh"))
        #expect(script.contains("tmp/debug-observability/latest-observability.env"))
        #expect(script.contains("AGENTSTUDIO_OBSERVABILITY_IPC_METADATA"))
        #expect(script.contains("AGENTSTUDIO_OBSERVABILITY_IPC_DEBUG_TOKEN"))
        #expect(script.contains("socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)"))
        #expect(script.contains("AGENTSTUDIO_IPC_PHASE_A_SMOKE_RESPONSE_TIMEOUT_SECONDS"))
        #expect(script.contains("self.socket.settimeout(response_timeout_seconds)"))
        #expect(script.contains("IPC response timed out after"))
        #expect(script.contains("\"auth.login\""))
        #expect(script.contains("\"system.capabilities\""))
        #expect(script.contains("\"pane.list\""))
        #expect(script.contains("\"pane.snapshot\""))
        #expect(script.contains("\"handle\": \"pane:1\""))
        #expect(script.contains("\"handle\": canonical_pane_handle"))
        #expect(!script.contains("--token-stdin"))
        #expect(!script.contains("AGENTSTUDIO_IPC_UNSAFE_NO_AUTH"))
    }
}
