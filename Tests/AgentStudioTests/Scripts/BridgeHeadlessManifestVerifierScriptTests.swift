import Foundation
import Testing

@Suite("Bridge headless manifest verifier script")
struct BridgeHeadlessManifestVerifierScriptTests {
    @Test("headless manifest verifier has stable task contract and bash syntax")
    func headlessManifestVerifierHasStableTaskContractAndBashSyntax() throws {
        let syntax = try runBash(arguments: ["-n", scriptPath])
        let source = try String(contentsOfFile: scriptPath, encoding: .utf8)
        let miseConfig = try String(contentsOfFile: ".mise.toml", encoding: .utf8)

        #expect(syntax.exitCode == 0, Comment(rawValue: syntax.stderr))
        #expect(miseConfig.contains("[tasks.verify-bridge-headless-manifest]"))
        #expect(miseConfig.contains("/bin/bash scripts/verify-bridge-headless-manifest.sh"))
        #expect(source.contains("AGENTSTUDIO_BRIDGE_HEADLESS_PROOF_DIR"))
        #expect(source.contains("WebKitSerializedTests.BridgeWorktreeFileSurfaceCurrentWorktreeProofTests"))
        #expect(source.contains("source \"$PROJECT_ROOT/scripts/swift-build-slot.sh\" debug"))
        #expect(source.contains("swift build --build-path \"$SWIFT_BUILD_DIR\" --build-tests"))
        #expect(source.contains("swift test --build-path \"$SWIFT_BUILD_DIR\" --skip-build --filter \"$TEST_FILTER\""))
        #expect(source.contains("expectedMetadataFileTotal"))
        #expect(source.contains("emittedMetadataFileTotal"))
        #expect(source.contains("missingExpectedFilePaths"))
        #expect(source.contains("unexpectedPublishedFilePaths"))
        #expect(source.contains("metadataInterestRequestToDeliveredFrame.p95Milliseconds"))
        #expect(source.contains("noStarvationProgress.completed"))
    }

    @Test("headless manifest verifier accepts complete artifact in validate only mode")
    func headlessManifestVerifierAcceptsCompleteArtifactInValidateOnlyMode() throws {
        let fixture = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let artifact = fixture.appendingPathComponent("current-worktree-manifest-proof.json")
        try completeArtifactJSON.write(to: artifact, atomically: true, encoding: .utf8)

        let result = try runScript(
            arguments: ["--validate-only"],
            environment: ["AGENTSTUDIO_BRIDGE_HEADLESS_PROOF_DIR": fixture.path]
        )

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        #expect(result.stdout.contains("expectedMetadataFileTotal=3"))
        #expect(result.stdout.contains("emittedMetadataFileTotal=3"))
    }

    @Test("headless manifest verifier rejects missing expected paths")
    func headlessManifestVerifierRejectsMissingExpectedPaths() throws {
        let fixture = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let artifact = fixture.appendingPathComponent("current-worktree-manifest-proof.json")
        try completeArtifactJSON
            .replacingOccurrences(
                of: #""missingExpectedFilePaths": []"#,
                with: #""missingExpectedFilePaths": ["lost.swift"]"#
            )
            .write(to: artifact, atomically: true, encoding: .utf8)

        let result = try runScript(
            arguments: ["--validate-only"],
            environment: ["AGENTSTUDIO_BRIDGE_HEADLESS_PROOF_DIR": fixture.path]
        )

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("missingExpectedFilePaths must be an empty list"))
    }

    private let scriptPath = "scripts/verify-bridge-headless-manifest.sh"

    private var completeArtifactJSON: String {
        """
        {
          "expectedMetadataFileTotal": 3,
          "emittedMetadataFileTotal": 3,
          "missingExpectedFilePaths": [],
          "unexpectedPublishedFilePaths": [],
          "expectedMetadataRowTotal": 5,
          "emittedMetadataRowTotal": 5,
          "remainingMetadataRowTotal": 0,
          "uniquePathCount": 5,
          "firstWindowRowCount": 5,
          "metadataInterestRequestToDeliveredFrame": {
            "p95Milliseconds": 1.2,
            "p99Milliseconds": 1.4
          },
          "noStarvationProgress": {
            "completed": true
          }
        }
        """
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bridge-headless-manifest-verifier-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func runScript(
        arguments: [String],
        environment: [String: String]
    ) throws -> ScriptResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, newValue in
            newValue
        }
        return try run(process)
    }

    private func runBash(arguments: [String]) throws -> ScriptResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments
        return try run(process)
    }

    private func run(_ process: Process) throws -> ScriptResult {
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        return ScriptResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    private struct ScriptResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }
}
