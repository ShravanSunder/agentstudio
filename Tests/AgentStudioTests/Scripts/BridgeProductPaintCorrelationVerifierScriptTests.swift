import Foundation
import Testing

@Suite("Bridge product paint correlation verifier script")
struct BridgeProductPaintCorrelationVerifierScriptTests {
    @Test("paint correlation verifier dry-run states the complete launch-bound proof contract")
    func verifierDryRunStatesCompleteProofContract() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=debug-marker
        AGENTSTUDIO_OBSERVABILITY_PROOF_TOKEN=dry-run-proof-token
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-07-15T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION=bridge-product-paint-correlation
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)

        let result = try fixture.runScript(
            "scripts/verify-bridge-product-paint-correlation.sh",
            arguments: ["--dry-run"],
            environment: [
                "AGENTSTUDIO_OBSERVABILITY_STATE_FILE": stateFile.path
            ]
        )

        #expect(result.exitCode == 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        #expect(result.stdout.contains("requires exactly one launch-bound completed event"))
        #expect(result.stdout.contains("rejects any launch-bound blocked event"))
        #expect(result.stdout.contains("requires all paint-correlation booleans true"))
        #expect(result.stdout.contains("requires review and file source match counts greater than zero"))
        #expect(result.stdout.contains("agent.proof.launch:=\"<redacted>\""))
        #expect(result.stdout.contains("bridge-product-paint-correlation"))
        #expect(!result.stdout.contains("dry-run-proof-token"))
        #expect(!result.stderr.contains("dry-run-proof-token"))
    }

    @Test("paint correlation verifier rejects a missing launch proof token")
    func verifierRejectsMissingLaunchProofToken() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=debug-marker
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-07-15T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION=bridge-product-paint-correlation
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)

        let result = try fixture.runScript(
            "scripts/verify-bridge-product-paint-correlation.sh",
            arguments: ["--dry-run"],
            environment: [
                "AGENTSTUDIO_OBSERVABILITY_STATE_FILE": stateFile.path
            ]
        )

        #expect(result.exitCode == 1, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        #expect(result.stderr.contains("missing AgentStudio debug observability proof token"))
    }

    @Test("paint correlation verifier structurally requires exact-one scoped proof and live identity")
    func verifierRequiresExactOneScopedProofAndLiveIdentity() throws {
        let source = try String(
            contentsOfFile: "scripts/verify-bridge-product-paint-correlation.sh",
            encoding: .utf8
        )

        #expect(source.contains("scripts/verify-debug-observability.sh"))
        #expect(!source.contains("AGENTSTUDIO_OBSERVABILITY_ALLOW_COMPLETED_EXIT=1"))
        #expect(source.contains("agent.proof.marker"))
        #expect(source.contains("agent.proof.launch"))
        #expect(source.contains("agentstudio.startup_diagnostic.action"))
        #expect(source.contains("app.startup_diagnostic_action.completed"))
        #expect(source.contains("app.startup_diagnostic_action.blocked"))
        #expect(source.contains("if len(records) != 1:"))
        #expect(source.contains("if [ \"$proof_record_count\" -ne 1 ]"))
        #expect(source.contains("bridge-product-paint-correlation"))
        #expect(source.contains("VERIFY_ATTEMPTS"))
    }
}
