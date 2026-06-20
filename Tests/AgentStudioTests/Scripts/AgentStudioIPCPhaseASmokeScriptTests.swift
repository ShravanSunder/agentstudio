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
        #expect(script.contains("\"command.list\""))
        #expect(script.contains("\"showCommandBarCommands\""))
        #expect(script.contains("\"Command Palette\""))
        #expect(script.contains("\"command.execute\""))
        #expect(script.contains("\"requires presentation\""))
        #expect(script.contains("\"ui.commandBar.open\""))
        #expect(script.contains("\"scope\": \"commands\""))
        #expect(script.contains("\"workspaceWindowId\""))
        #expect(script.contains("allowed_command_keys"))
        #expect(script.contains("command.list leaked non-IPC command metadata keys"))
        #expect(script.contains("AgentStudio IPC debug token was not consumed"))
        #expect(script.contains("\"auth.login replay\""))
        #expect(script.contains("\"unauthenticated\""))
        #expect(!script.contains("--token-stdin"))
        #expect(!script.contains("AGENTSTUDIO_IPC_UNSAFE_NO_AUTH"))
    }
}
