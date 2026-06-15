import Foundation
import Testing

@Suite(.serialized)
struct ArchitectureSwiftLintRulesTests {
    @Test("architecture SwiftLint runner is pinned and owns lint wiring")
    func architectureSwiftLintRunnerIsPinnedAndOwnsLintWiring() throws {
        let miseConfig = try String(contentsOfFile: ".mise.toml", encoding: .utf8)
        let ciWorkflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)
        let runner = try String(contentsOfFile: runnerPath, encoding: .utf8)
        let pin = try String(contentsOfFile: pinPath, encoding: .utf8)

        #expect(miseConfig.contains("scripts/run-agentstudio-architecture-swiftlint.sh lint --strict"))
        #expect(!miseConfig.contains("scripts/check-core-boundary-imports.sh"))
        #expect(!miseConfig.contains("scripts/check-atomlib-boundaries.sh"))
        #expect(ciWorkflow.contains("brew install swift-format bazelisk"))
        #expect(!ciWorkflow.contains("ripgrep"))
        #expect(!ciWorkflow.contains("brew install swift-format swiftlint"))

        #expect(runner.contains("AGENTSTUDIO_ARCH_SWIFTLINT_COMMIT"))
        #expect(runner.contains("AGENTSTUDIO_SWIFTLINT_BINARY="))
        #expect(runner.contains("is_tool_subtree_clean"))
        #expect(runner.contains("git -C \"$CACHE_REPO\" fetch --quiet origin \"$AGENTSTUDIO_ARCH_SWIFTLINT_COMMIT\""))
        #expect(runner.contains("if [ -z \"${!var_name-}\" ]; then"))
        #expect(!runner.contains("${!var_name:-}"))
        #expect(runner.contains("quarantining invalid AgentStudio architecture SwiftLint cache"))
        #expect(runner.contains("mv \"$CACHE_REPO\" \"$invalid_cache_repo\""))
        #expect(!runner.contains("rm -rf \"$CACHE_REPO\""))
        #expect(!runner.contains("repoEnrichmentByRepoId"))
        #expect(!runner.contains("WorktreeEnrichment must not use raw equality"))

        #expect(pin.contains("AGENTSTUDIO_ARCH_SWIFTLINT_REPO_URL=https://github.com/ShravanSunder/ai-tools.git"))
        #expect(pin.contains("AGENTSTUDIO_ARCH_SWIFTLINT_REF=agentstudio-swiftlint-architecture-rules-2026-06-14"))
        #expect(pin.contains("AGENTSTUDIO_ARCH_SWIFTLINT_COMMIT=1bc0e474c48cf01c815f83e16abd65be6d27f51b"))
        #expect(pin.contains("AGENTSTUDIO_ARCH_SWIFTLINT_SUBDIR=swiftlint/agentstudio-architecture-rules"))
    }

    @Test("architecture SwiftLint runner exposes pinned identity")
    func architectureSwiftLintRunnerExposesPinnedIdentity() throws {
        let result = try runScript(arguments: [runnerPath, "--print-tool-identity"])

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        #expect(result.stdout.contains("repo_url=https://github.com/ShravanSunder/ai-tools.git"))
        #expect(result.stdout.contains("ref=agentstudio-swiftlint-architecture-rules-2026-06-14"))
        #expect(result.stdout.contains("commit=1bc0e474c48cf01c815f83e16abd65be6d27f51b"))
        #expect(result.stdout.contains("subdir=swiftlint/agentstudio-architecture-rules"))
    }

    @Test("architecture SwiftLint runner verifies native rule fixtures")
    func architectureSwiftLintRunnerVerifiesNativeRuleFixtures() throws {
        let result = try runScript(arguments: [runnerPath, "--verify-fixtures"])

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        #expect(result.stdout.contains("agentstudio custom SwiftLint verification passed"))
        #expect(result.stdout.contains("agentstudio_import_direction"))
        #expect(result.stdout.contains("agentstudio_derived_value_declared_inputs"))
        #expect(result.stdout.contains("agentstudio_repo_cache_keyed_reads"))
        #expect(result.stdout.contains("agentstudio_worktree_enrichment_comparator"))
        #expect(result.stdout.contains("agentstudio_ipc_programmatic_control_boundary"))
        #expect(result.stdout.contains("agentstudio_appipc_port_boundary"))
        #expect(result.stdout.contains("agentstudio_ipc_composition_location"))
        #expect(result.stdout.contains("agentstudio_ipc_public_surface_sanitization"))
        #expect(result.stdout.contains("agentstudio_ipc_no_direct_atom_access"))
    }

    @Test("custom SwiftLint runner still honors repo regex custom rules")
    func customSwiftLintRunnerStillHonorsRepoRegexCustomRules() throws {
        let fixturePath = "Tests/AgentStudioTests/Fixtures/SwiftLintLegacyCustomRules/CombineImportViolation.fixture"
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-legacy-swiftlint-\(UUID().uuidString)")
        let temporaryFile = temporaryDirectory.appendingPathComponent("CombineImportViolation.swift")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try FileManager.default.copyItem(atPath: fixturePath, toPath: temporaryFile.path)

        let result = try runScript(arguments: [
            runnerPath, "lint", "--strict", "--config", ".swiftlint.yml", temporaryFile.path,
        ])

        #expect(result.exitCode != 0)
        #expect(result.stdout.contains("no_combine_import") || result.stderr.contains("no_combine_import"))
    }

    private let runnerPath = "scripts/run-agentstudio-architecture-swiftlint.sh"
    private let pinPath = "scripts/agentstudio-architecture-swiftlint.env"

    private func runScript(arguments: [String]) throws -> ScriptRunResult {
        let stdoutURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-architecture-swiftlint-stdout-\(UUID().uuidString).log")
        let stderrURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-architecture-swiftlint-stderr-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        process.environment = ProcessInfo.processInfo.environment
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        try process.run()
        process.waitUntilExit()

        let stdout = try String(contentsOf: stdoutURL, encoding: .utf8)
        let stderr = try String(contentsOf: stderrURL, encoding: .utf8)
        return ScriptRunResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
