import Foundation
import Testing

@Suite(.serialized)
struct ArchitectureSwiftLintRulesTests {
    @Test("architecture lint wiring uses stock SwiftLint and local SwiftPM tool")
    func architectureLintWiringUsesStockSwiftLintAndLocalTool() throws {
        let miseConfig = try String(contentsOfFile: ".mise.toml", encoding: .utf8)
        let lintScript = try String(contentsOfFile: "scripts/lint-swift.sh", encoding: .utf8)
        let ciWorkflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)
        let swiftLintConfig = try String(contentsOfFile: ".swiftlint.yml", encoding: .utf8)

        #expect(miseConfig.contains("run = \"/bin/bash scripts/lint-swift.sh\""))
        #expect(lintScript.contains("swiftlint lint --strict"))
        #expect(
            lintScript.contains(
                "swift run --package-path Tools/AgentStudioArchitectureLint"
            ))
        #expect(lintScript.contains("agentstudio-architecture-lint Sources Tests"))
        #expect(!miseConfig.contains(legacyRunnerScriptPath))
        #expect(!miseConfig.contains("scripts/check-core-boundary-imports.sh"))
        #expect(!miseConfig.contains("scripts/check-atomlib-boundaries.sh"))
        #expect(lintScript.contains("if [[ $# -eq 0 ]]"))
        #expect(!lintScript.contains("run_admission_contract"))
        #expect(lintScript.contains("run_release_contract=0"))

        #expect(ciWorkflow.contains("brew install swift-format swiftlint"))
        #expect(ciWorkflow.contains("swift test --package-path Tools/AgentStudioArchitectureLint"))
        #expect(!ciWorkflow.contains(legacyBuildToolName))
        #expect(!ciWorkflow.contains("ripgrep"))

        #expect(swiftLintConfig.contains("Tools/AgentStudioArchitectureLint/Sources"))
        #expect(swiftLintConfig.contains("Tools/AgentStudioArchitectureLint/Tests"))
        #expect(
            swiftLintConfig.contains(
                "Tools/AgentStudioArchitectureLint/Tests/AgentStudioArchitectureLintTests/Fixtures"))
    }

    @Test("deleted external runner files are not present")
    func deletedExternalRunnerFilesAreNotPresent() {
        #expect(!FileManager.default.fileExists(atPath: legacyRunnerScriptPath))
        #expect(!FileManager.default.fileExists(atPath: legacyRunnerEnvironmentPath))
    }

    @Test("local architecture tool package is pinned")
    func localArchitectureToolPackageIsPinned() throws {
        let packageManifest = try String(
            contentsOfFile: "Tools/AgentStudioArchitectureLint/Package.swift",
            encoding: .utf8
        )

        #expect(FileManager.default.fileExists(atPath: "Tools/AgentStudioArchitectureLint/Package.resolved"))
        #expect(packageManifest.contains("name: \"agentstudio-architecture-lint\""))
        #expect(packageManifest.contains("exact: \"602.0.0\""))
        #expect(!packageManifest.contains("swift-argument-parser"))
    }

    @Test("stock SwiftLint honors repo regex custom rules")
    func stockSwiftLintHonorsRepoRegexCustomRules() throws {
        let fixturePath = "Tests/AgentStudioTests/Fixtures/SwiftLintLegacyCustomRules/CombineImportViolation.fixture"
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-stock-swiftlint-\(UUID().uuidString)")
        let temporaryFile = temporaryDirectory.appendingPathComponent("CombineImportViolation.swift")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try FileManager.default.copyItem(atPath: fixturePath, toPath: temporaryFile.path)

        let result = try runProcess(arguments: [
            "swiftlint", "lint", "--strict", "--config", ".swiftlint.yml", temporaryFile.path,
        ])

        #expect(result.exitCode != 0)
        #expect(result.stdout.contains("no_combine_import") || result.stderr.contains("no_combine_import"))
    }

    @Test("local architecture tool exposes expected rule inventory")
    func localArchitectureToolExposesExpectedRuleInventory() throws {
        let result = try runProcess(arguments: [
            "swift", "run",
            "--package-path", "Tools/AgentStudioArchitectureLint",
            "agentstudio-architecture-lint",
            "--print-rules",
        ])

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        #expect(result.stdout.contains("agentstudio_import_direction error"))
        #expect(result.stdout.contains("agentstudio_state_actor_path warning"))
        #expect(result.stdout.contains("agentstudio_ipc_programmatic_control_boundary error"))
        #expect(result.stdout.contains("agentstudio_appipc_port_boundary error"))
        #expect(result.stdout.contains("agentstudio_ipc_composition_location error"))
        #expect(result.stdout.contains("agentstudio_ipc_public_surface_sanitization error"))
        #expect(result.stdout.contains("agentstudio_ipc_no_direct_atom_access error"))
    }

    private func runProcess(arguments: [String]) throws -> ScriptRunResult {
        let stdoutURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-architecture-lint-stdout-\(UUID().uuidString).log")
        let stderrURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-architecture-lint-stderr-\(UUID().uuidString).log")
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
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
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

    private var legacyRunnerScriptPath: String {
        [
            "scripts",
            "run-" + "agentstudio-" + "architecture-" + "swiftlint.sh",
        ].joined(separator: "/")
    }

    private var legacyRunnerEnvironmentPath: String {
        [
            "scripts",
            "agentstudio-" + "architecture-" + "swiftlint.env",
        ].joined(separator: "/")
    }

    private var legacyBuildToolName: String {
        "baz" + "el" + "isk"
    }
}
