import Foundation
import Testing

@Suite("Bridge packaged product journey scripts")
struct BridgePackagedProductJourneyScriptTests {
    @Test("runner dry-run declares strict LaunchServices fixture and preservation contract")
    func runnerDryRunDeclaresStrictLaunchAndFixtureContract() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }

        let result = try fixture.runScript(
            "scripts/run-bridge-packaged-product-journey.sh",
            arguments: ["--dry-run"],
            environment: [:]
        )

        #expect(result.exitCode == 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        #expect(result.stdout.contains("standard debug observability runner"))
        #expect(result.stdout.contains("strict LaunchServices"))
        #expect(result.stdout.contains("disposable hierarchical Git fixture"))
        #expect(result.stdout.contains("bridge-product-paint-correlation"))
        #expect(result.stdout.contains("preserves the fixture and app for verification"))
    }

    @Test("verifier dry-run declares artifact IPC Victoria and visual proof owners")
    func verifierDryRunDeclaresProofOwners() throws {
        let fixture = try LauncherScriptFixture()
        defer { fixture.cleanup() }

        let result = try fixture.runScript(
            "scripts/verify-bridge-packaged-product-journey.sh",
            arguments: ["--dry-run"],
            environment: [:]
        )

        #expect(result.exitCode == 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        #expect(result.stdout.contains("bundle/executable/assets"))
        #expect(result.stdout.contains("persistent authenticated semantic IPC"))
        #expect(result.stdout.contains("Review early/middle/final traversal"))
        #expect(result.stdout.contains("two independent panes"))
        #expect(result.stdout.contains("Victoria marker and proof token"))
        #expect(result.stdout.contains("PID-targeted Peekaboo"))
        #expect(result.stdout.contains("no frame_not_live skip"))
    }

    @Test("runner reuses standard owners and cannot terminate an existing app")
    func runnerReusesStandardOwnersWithoutProcessTermination() throws {
        let source = try String(
            contentsOfFile: "scripts/run-bridge-packaged-product-journey.sh",
            encoding: .utf8
        )

        #expect(source.contains("scripts/run-debug-observability.sh"))
        #expect(source.contains("AGENTSTUDIO_DEBUG_DIRECT_FALLBACK=0"))
        #expect(source.contains("AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1"))
        #expect(source.contains("AGENTSTUDIO_STARTUP_WATCH_FOLDER"))
        #expect(source.contains("AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION"))
        #expect(!source.contains("kill "))
        #expect(!source.contains("killall"))
        #expect(!source.contains("pkill"))
        #expect(!source.contains("rm -rf"))
    }

    @Test("runner disables commit signing only inside its disposable fixture")
    func runnerDisablesCommitSigningOnlyInsideDisposableFixture() throws {
        let source = try String(
            contentsOfFile: "scripts/run-bridge-packaged-product-journey.sh",
            encoding: .utf8
        )

        #expect(source.contains("config commit.gpgsign false"))
        #expect(!source.contains("--global commit.gpgsign"))
    }

    @Test("runner receipt publishes every verifier-owned journey key")
    func runnerReceiptPublishesEveryVerifierOwnedJourneyKey() throws {
        let runnerSource = try String(
            contentsOfFile: "scripts/run-bridge-packaged-product-journey.sh",
            encoding: .utf8
        )
        let verifierSource = try String(
            contentsOfFile: "scripts/verify-bridge-packaged-product-journey.sh",
            encoding: .utf8
        )
        let verifierOwnedKeys = [
            "AGENTSTUDIO_BRIDGE_JOURNEY_STATUS",
            "AGENTSTUDIO_BRIDGE_JOURNEY_OBSERVABILITY_STATE_FILE",
            "AGENTSTUDIO_BRIDGE_JOURNEY_FIXTURE_ROOT",
            "AGENTSTUDIO_BRIDGE_JOURNEY_EXPECTED_FILE_COUNT",
            "AGENTSTUDIO_BRIDGE_JOURNEY_EARLY_PATH",
            "AGENTSTUDIO_BRIDGE_JOURNEY_MIDDLE_PATH",
            "AGENTSTUDIO_BRIDGE_JOURNEY_FINAL_PATH",
            "AGENTSTUDIO_BRIDGE_JOURNEY_TRACKED_PATH",
        ]

        for key in verifierOwnedKeys {
            #expect(verifierSource.contains(key))
            #expect(runnerSource.contains("write_state_value \(key)"))
        }
    }

    @Test("mise exposes one runner and one verifier task")
    func miseExposesJourneyTasks() throws {
        let source = try String(contentsOfFile: ".mise.toml", encoding: .utf8)

        #expect(source.contains("[tasks.run-bridge-packaged-product-journey]"))
        #expect(source.contains("/bin/bash scripts/run-bridge-packaged-product-journey.sh"))
        #expect(source.contains("[tasks.verify-bridge-packaged-product-journey]"))
        #expect(source.contains("/bin/bash scripts/verify-bridge-packaged-product-journey.sh"))
    }
}
