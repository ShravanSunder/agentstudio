import Foundation
import Testing

@Suite("Bridge worker fetch product stream feasibility verifier script")
struct BridgeProductStreamFeasibilityScriptTests {
    @Test("product stream feasibility verifier declares the positive carrier proof")
    func verifierDeclaresPositiveCarrierProof() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=debug-marker
        AGENTSTUDIO_OBSERVABILITY_PROOF_TOKEN=dry-run-proof-token
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=testcode
        AGENTSTUDIO_OBSERVABILITY_PID=999999999
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-07-09T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION=bridge-product-stream-webkit-feasibility
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)

        let result = try fixture.runScript(
            "scripts/verify-bridge-product-stream-webkit-feasibility.sh",
            arguments: ["--dry-run"],
            environment: [
                "AGENTSTUDIO_OBSERVABILITY_STATE_FILE": stateFile.path,
                "AGENTSTUDIO_CURL_BIN": try fixture.executable(
                    "curl-product-stream-feasibility-dry-run",
                    """
                    #!/bin/bash
                    exit 0
                    """
                ).path,
            ]
        )

        #expect(result.exitCode == 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        #expect(result.stdout.contains("requires authenticated actual-body admission without Content-Length"))
        #expect(result.stdout.contains("requires receipt-gated incremental frames"))
        #expect(result.stdout.contains("requires abort-causal zero producer residue"))
        #expect(result.stdout.contains("requires exactly one launch-bound completed record"))
        #expect(result.stdout.contains("agent.proof.launch:=\"<redacted>\""))
        #expect(!result.stdout.contains("dry-run-proof-token"))
        #expect(!result.stderr.contains("dry-run-proof-token"))
    }

    @Test("product stream feasibility verifier rejects a missing launch proof token")
    func verifierRejectsMissingLaunchProofToken() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }
        let stateFile = fixture.url("latest.env")
        try """
        AGENTSTUDIO_OBSERVABILITY_STATUS=running
        AGENTSTUDIO_OBSERVABILITY_MARKER=debug-marker
        AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=testcode
        AGENTSTUDIO_OBSERVABILITY_PID=999999999
        AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-07-09T00:00:00Z
        AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION=bridge-product-stream-webkit-feasibility
        """
        .appending("\n").write(to: stateFile, atomically: true, encoding: .utf8)

        let result = try fixture.runScript(
            "scripts/verify-bridge-product-stream-webkit-feasibility.sh",
            arguments: ["--dry-run"],
            environment: [
                "AGENTSTUDIO_OBSERVABILITY_STATE_FILE": stateFile.path
            ]
        )

        #expect(result.exitCode == 1, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        #expect(result.stderr.contains("missing AgentStudio debug observability proof token"))
    }

    @Test("product stream feasibility verifier uses standard live process identity proof")
    func verifierUsesStandardLiveProcessIdentityProof() throws {
        let source = try String(
            contentsOfFile: "scripts/verify-bridge-product-stream-webkit-feasibility.sh",
            encoding: .utf8
        )

        #expect(source.contains("scripts/verify-debug-observability.sh"))
        #expect(!source.contains("AGENTSTUDIO_OBSERVABILITY_ALLOW_COMPLETED_EXIT=1"))
        #expect(source.contains("agent.proof.marker"))
        #expect(source.contains("agent.proof.launch"))
        #expect(source.contains("if len(records) != 1:"))
        #expect(source.contains("dev.runtime.flavor:debug"))
        #expect(source.contains("bridge-product-stream-webkit-feasibility"))
    }
}
