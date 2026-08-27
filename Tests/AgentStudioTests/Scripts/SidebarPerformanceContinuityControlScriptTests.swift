import AgentStudioInfrastructure
import Foundation
import Testing

@Suite("Sidebar performance continuity control script")
struct SidebarPerformanceContinuityControlScriptTests {
    @Test("zero PTY idle injects one ignored mutation immediately before sampling")
    func zeroPTYIdleInjectsOneIgnoredMutationImmediatelyBeforeSampling() throws {
        let source = try String(contentsOfFile: scriptPath, encoding: .utf8)
        let idleStart = try #require(source.range(of: "sample_strict_idle_population() {"))
        let idleEnd = try #require(
            source.range(
                of: "drive_strict_action_population() {",
                range: idleStart.upperBound..<source.endIndex
            )
        )
        let idleSource = source[idleStart.lowerBound..<idleEnd.lowerBound]
        let authorityBaseline = try #require(
            idleSource.range(of: "capture_strict_git_continuity_baseline")
        )
        let mutation = try #require(
            idleSource.range(of: "inject_strict_git_continuity_uncertainty")
        )
        let firstSample = try #require(idleSource.range(of: "record_strict_cpu_sample"))

        #expect(authorityBaseline.lowerBound < mutation.lowerBound)
        #expect(mutation.lowerBound < firstSample.lowerBound)
        let injectionToSample = idleSource[mutation.lowerBound..<firstSample.lowerBound]
        #expect(!injectionToSample.contains("wait_for_positive_quiescence"))
        #expect(!injectionToSample.contains("wait_for_strict_git_physical_settlement"))
        #expect(idleSource.contains("validate_strict_git_continuity_recovery"))
        #expect(source.contains("AGENTSTUDIO_STARTUP_WATCH_FOLDER=\"$STRICT_CONTROL_ROOT\""))
        #expect(source.contains("control_root_present"))
    }

    @Test("continuity control helper commits a clean baseline and injects one ignored file")
    func continuityControlHelperCommitsCleanBaselineAndInjectsOneIgnoredFile() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "agentstudio-sidebar-script-control-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        let controlRoot = fixtureRoot.appending(path: "control", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let result = try await runSidebarScript(
            arguments: [scriptPath, "--prepare-only"],
            environment: [
                "AGENTSTUDIO_SIDEBAR_ALLOW_TEST_RESPONSES": "1",
                "AGENTSTUDIO_SIDEBAR_TEST_CONTROL_ROOT": controlRoot.path,
            ]
        )

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        #expect(result.stdout.contains("continuity_control_clean=true"))
        #expect(FileManager.default.fileExists(atPath: controlRoot.appending(path: ".git/HEAD").path))
        #expect(
            FileManager.default.fileExists(
                atPath: controlRoot.appending(path: ".continuity-proof-ignored").path
            )
        )
    }

    @Test("continuity delta contract rejects missing recovery outcomes")
    func continuityDeltaContractRejectsMissingRecoveryOutcomes() async throws {
        let accepted = try await runContinuityDeltaContract(
            "1,2,0,1,0,1,0,1,0,0,2,3,2,3,2,3,1"
        )
        #expect(accepted.exitCode == 0, Comment(rawValue: accepted.stderr))

        let missingFallback = try await runContinuityDeltaContract(
            "1,2,0,1,0,1,0,0,0,0,2,3,2,3,2,3,1"
        )
        #expect(missingFallback.exitCode == 1)
        #expect(missingFallback.stderr.contains("exactly one bounded fallback outcome"))

        let missingRenewal = try await runContinuityDeltaContract(
            "1,2,0,1,0,1,0,1,0,0,2,2,2,3,2,3,1"
        )
        #expect(missingRenewal.exitCode == 1)
        #expect(missingRenewal.stderr.contains("positive continuity renewal"))
    }

    private func runContinuityDeltaContract(_ values: String) async throws -> ProcessResult {
        try await runSidebarScript(
            arguments: [scriptPath, "--prepare-only"],
            environment: [
                "AGENTSTUDIO_SIDEBAR_ALLOW_TEST_RESPONSES": "1",
                "AGENTSTUDIO_SIDEBAR_TEST_CONTINUITY_DELTAS": values,
            ]
        )
    }

    private let scriptPath = "scripts/verify-sidebar-performance-workload.sh"
}
