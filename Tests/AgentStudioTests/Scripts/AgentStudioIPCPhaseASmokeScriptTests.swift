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
        #expect(script.contains("AGENTSTUDIO_OBSERVABILITY_ACTIVATION_MODE"))
        #expect(script.contains("AGENTSTUDIO_OBSERVABILITY_IPC_AUTH_MODE"))
        #expect(script.contains("requires authenticated IPC auth mode"))
        #expect(script.contains("requires background activation mode"))
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
        #expect(script.contains("\"argumentSchema\""))
        #expect(script.contains("\"setRepoSidebarVisibilityMode\""))
        #expect(script.contains("\"favoritesOnly\""))
        #expect(script.contains("\"setRepoSidebarSortOrder\""))
        #expect(script.contains("\"order\": \"descending\""))
        #expect(script.contains("\"order\": \"ascending\""))
        #expect(script.contains("\"currentRepoOrder\""))
        #expect(script.contains("\"command.execute\""))
        #expect(script.contains("\"requires presentation\""))
        #expect(script.contains("\"ui.commandBar.open\""))
        #expect(script.contains("\"scope\": \"commands\""))
        #expect(script.contains("\"workspaceWindowId\""))
        #expect(script.contains("\"sidebar.surface.set\""))
        #expect(script.contains("\"sidebar.surface.get\""))
        #expect(script.contains("\"sidebar.grouping.set\""))
        #expect(script.contains("\"sidebar.grouping.get\""))
        #expect(script.contains("\"surface\": \"repo\""))
        #expect(script.contains("\"surface\": \"inbox\""))
        #expect(script.contains("\"mode\": \"none\""))
        #expect(script.contains("\"validation rejected\""))
        #expect(script.contains("allowed_command_keys"))
        #expect(script.contains("command.list leaked non-IPC command metadata keys"))
        #expect(script.contains("AgentStudio IPC debug token was not consumed"))
        #expect(script.contains("\"auth.login replay\""))
        #expect(script.contains("\"unauthenticated\""))
        #expect(!script.contains("--token-stdin"))
        #expect(!script.contains("AGENTSTUDIO_IPC_UNSAFE_NO_AUTH"))
    }

    @Test("phase-a verifier rejects unsafe auth and foreground activation state")
    func phaseAVerifierRejectsUnsafeAuthAndForegroundActivationState() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let scriptURL = projectRoot.appendingPathComponent("scripts/verify-agentstudio-ipc-phase-a-smoke.sh")
        let dataRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-phase-a-state-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: dataRoot)
        }
        try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)

        let unsafeState = try writePhaseAState(
            root: dataRoot,
            name: "unsafe.env",
            authMode: "unsafe_no_auth",
            activationMode: "background"
        )
        let unsafeResult = try runPhaseASmokeScript(scriptURL: scriptURL, stateFile: unsafeState)
        #expect(unsafeResult.exitCode == 1)
        #expect(unsafeResult.stderr.contains("requires authenticated IPC auth mode"))

        let foregroundState = try writePhaseAState(
            root: dataRoot,
            name: "foreground.env",
            authMode: "authenticated",
            activationMode: "foreground"
        )
        let foregroundResult = try runPhaseASmokeScript(scriptURL: scriptURL, stateFile: foregroundState)
        #expect(foregroundResult.exitCode == 1)
        #expect(foregroundResult.stderr.contains("requires background activation mode"))
    }

    private func writePhaseAState(
        root: URL,
        name: String,
        authMode: String,
        activationMode: String
    ) throws -> URL {
        let dataDir = root.appendingPathComponent("data-\(name)")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let state = [
            "AGENTSTUDIO_OBSERVABILITY_STATUS=running",
            "AGENTSTUDIO_OBSERVABILITY_PID=\(ProcessInfo.processInfo.processIdentifier)",
            "AGENTSTUDIO_OBSERVABILITY_DATA_DIR=\(dataDir.path)",
            "AGENTSTUDIO_OBSERVABILITY_IPC_AUTH_MODE=\(authMode)",
            "AGENTSTUDIO_OBSERVABILITY_ACTIVATION_MODE=\(activationMode)",
            "",
        ].joined(separator: "\n")
        let stateURL = root.appendingPathComponent(name)
        try state.write(to: stateURL, atomically: true, encoding: .utf8)
        return stateURL
    }

    private func runPhaseASmokeScript(scriptURL: URL, stateFile: URL) throws -> ScriptRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["AGENTSTUDIO_OBSERVABILITY_STATE_FILE": stateFile.path],
            uniquingKeysWith: { _, new in new }
        )
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return ScriptRunResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
}
