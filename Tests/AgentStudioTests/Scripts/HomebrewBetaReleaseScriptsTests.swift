import Foundation
import Testing

@Suite(.serialized)
struct HomebrewBetaReleaseScriptsTests {
    @Test("release tag metadata classifies stable and beta tags")
    func releaseTagMetadataClassifiesStableAndBetaTags() throws {
        let stable = try runScript("scripts/release-tag-metadata.sh", ["v0.0.54"])
        let beta = try runScript("scripts/release-tag-metadata.sh", ["v0.0.54-beta.1"])

        #expect(stable.exitCode == 0)
        #expect(stable.stdout.contains("channel=stable"))
        #expect(stable.stdout.contains("cask_token=agent-studio"))
        #expect(stable.stdout.contains("data_dir_name=.agentstudio"))

        #expect(beta.exitCode == 0)
        #expect(beta.stdout.contains("channel=beta"))
        #expect(beta.stdout.contains("cask_token=agent-studio@beta"))
        #expect(beta.stdout.contains("data_dir_name=.agent-studio-b"))
    }

    @Test("release tag metadata rejects malformed beta tags")
    func releaseTagMetadataRejectsMalformedBetaTags() throws {
        let result = try runScript("scripts/release-tag-metadata.sh", ["v0.0.54-beta"])

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("unsupported release tag"))
    }

    @Test("cask renderer emits stable and beta casks")
    func caskRendererEmitsStableAndBetaCasks() throws {
        let stable = try runScript(
            "scripts/render-homebrew-cask.sh",
            ["stable", "0.0.54", validSHA]
        )
        let beta = try runScript(
            "scripts/render-homebrew-cask.sh",
            ["beta", "0.0.54-beta.1", validSHA]
        )

        #expect(stable.exitCode == 0)
        #expect(stable.stdout.contains("cask \"agent-studio\" do"))
        #expect(stable.stdout.contains("version \"0.0.54\""))
        #expect(stable.stdout.contains("conflicts_with cask: \"agent-studio@beta\""))
        #expect(stable.stdout.contains("\"~/.agentstudio\""))

        #expect(beta.exitCode == 0)
        #expect(beta.stdout.contains("cask \"agent-studio@beta\" do"))
        #expect(beta.stdout.contains("version \"0.0.54-beta.1\""))
        #expect(beta.stdout.contains("conflicts_with cask: \"agent-studio\""))
        #expect(beta.stdout.contains("\"~/.agent-studio-b\""))
    }

    @Test("tap updater dry run writes only the selected cask")
    func tapUpdaterDryRunWritesOnlySelectedCask() throws {
        let tapRoot = try makeFakeTap()

        let result = try runScript(
            "scripts/update-homebrew-tap.sh",
            ["beta", "v0.0.54-beta.1", validSHA],
            environment: [
                "HOMEBREW_TAP_LOCAL_PATH": tapRoot.path,
                "DRY_RUN": "1",
                "SKIP_BREW_STYLE": "1",
            ]
        )

        #expect(result.exitCode == 0)
        #expect(
            FileManager.default.fileExists(
                atPath: tapRoot.appending(path: "Casks/agent-studio@beta.rb").path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: tapRoot.appending(path: "Casks/agent-studio.rb").path
            )
        )
    }

    private let validSHA = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

    private func makeFakeTap() throws -> URL {
        let tapRoot = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-homebrew-tap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tapRoot.appending(path: "Casks"),
            withIntermediateDirectories: true
        )
        return tapRoot
    }

    private func runScript(
        _ scriptPath: String,
        _ arguments: [String],
        environment: [String: String] = [:]
    ) throws -> ScriptResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bash", scriptPath] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, newValue in newValue }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return ScriptResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
}

private struct ScriptResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
