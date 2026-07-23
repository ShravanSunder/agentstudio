import Darwin
import Foundation
import Testing

@Suite("Vendor consumer wiring")
struct VendorConsumerWiringScriptTests {
    @Test("every mise Swift consumer verifies vendor state")
    func everyMiseSwiftConsumerVerifiesVendorState() throws {
        // Arrange
        let source = try String(contentsOfFile: ".mise.toml", encoding: .utf8)
        let directConsumers = [
            "build",
            "build-release",
            "test",
            "test-fast",
            "test-large",
            "test-prebuild",
            "test-webkit",
            "test-coverage",
            "test-e2e",
            "test-zmx-e2e",
        ]

        // Act / Assert
        for taskName in directConsumers {
            let task = try #require(
                taskBlock(named: taskName, in: source),
                "Missing mise task \(taskName)")
            #expect(
                hasVendorVerificationBeforeConsumption(task),
                "mise task \(taskName) must verify vendors before Swift consumption")
        }

        let benchmarkTask = try #require(taskBlock(named: "test-benchmark", in: source))
        #expect(
            benchmarkTask.contains("depends = [\"build\"]")
                || benchmarkTask.contains("depends = [\"verify-vendors\", \"build\"]")
                || benchmarkTask.contains("depends = [\"build\", \"verify-vendors\"]"),
            "test-benchmark must inherit verification through build")
    }

    @Test("direct scripts verify before build test packaging signing or launch")
    func directScriptsVerifyBeforeConsumption() throws {
        // Arrange
        let contracts = [
            DirectVendorConsumerContract(
                path: "scripts/run-swift-test-task.sh",
                requiredConsumers: ["prebuild_swift_tests"]),
            DirectVendorConsumerContract(
                path: "scripts/verify-global-preferences-startup-performance.sh",
                requiredConsumers: ["swift build"]),
            DirectVendorConsumerContract(
                path: "scripts/verify-bridge-headless-manifest.sh",
                requiredConsumers: ["swift build"]),
        ]

        // Act / Assert
        for contract in contracts {
            let source = try String(contentsOfFile: contract.path, encoding: .utf8)
            let verificationOffset = try #require(
                vendorVerificationOffset(in: source),
                "\(contract.path) must invoke vendor verification")
            for consumer in contract.requiredConsumers {
                let consumerOffset = try #require(
                    source.range(of: consumer)?.lowerBound,
                    "\(contract.path) is missing expected consumer \(consumer)")
                #expect(
                    verificationOffset < consumerOffset,
                    "\(contract.path) must verify before \(consumer)")
            }
        }
    }

    @Test("debug identity and idle preflight remain non-consuming but launch verifies first")
    func debugNonConsumingModesAndLaunchOrdering() throws {
        // Arrange
        let source = try String(
            contentsOfFile: "scripts/run-debug-observability.sh",
            encoding: .utf8)

        // Act
        let identityExit = try #require(source.range(of: "if [ \"$print_identity\" = true ]"))
        let idleExit = try #require(source.range(of: "if [ \"$preflight_idle\" = true ]"))
        let verificationOffset = try #require(vendorVerificationOffset(in: source))
        let buildOffset = try #require(source.range(of: "if [ \"$skip_build\" = false ]")?.lowerBound)
        let packageOffset = try #require(source.range(of: "app_path=\"$(publish_debug_bundle")?.lowerBound)
        let packageFunction = try #require(
            shellFunction(named: "copy_debug_bundle", in: source),
            "debug packaging function is missing")

        // Assert
        #expect(identityExit.lowerBound < verificationOffset)
        #expect(idleExit.lowerBound < verificationOffset)
        #expect(verificationOffset < buildOffset)
        #expect(verificationOffset < packageOffset)
        #expect(
            packageFunction.contains("codesign_debug_item"),
            "post-verification debug packaging must sign its artifacts")
        #expect(
            source[verificationOffset...].contains("open_app"),
            "debug verification must precede launch")
    }

    @Test("debug launch stops before every consumer when vendor verification fails")
    func debugLaunchFailsClosedBeforeConsumption() throws {
        // Arrange
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appending(path: "AgentStudio debug vendor gate \(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: temporaryRoot) }
        let scriptsRoot = temporaryRoot.appending(path: "scripts")
        let spyRoot = temporaryRoot.appending(path: "spies")
        let homeRoot = temporaryRoot.appending(path: "home")
        try fileManager.createDirectory(at: scriptsRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: spyRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homeRoot, withIntermediateDirectories: true)
        try fileManager.copyItem(
            at: URL(fileURLWithPath: "scripts/run-debug-observability.sh"),
            to: scriptsRoot.appending(path: "run-debug-observability.sh"))

        let commandLog = temporaryRoot.appending(path: "commands.log")
        let vendorHelper = scriptsRoot.appending(path: "vendor-worktree.sh")
        try writeExecutable(
            at: vendorHelper,
            source: """
                #!/bin/bash
                printf 'vendor %s\\n' "$*" >> "$SPY_LOG"
                exit 73
                """)

        let downstreamNames = [
            "stack-helper",
            "curl",
            "ditto",
            "codesign",
            "open",
            "pgrep",
            "lsof",
            "security",
            "mise",
        ]
        for downstreamName in downstreamNames {
            try writeExecutable(
                at: spyRoot.appending(path: downstreamName),
                source: """
                    #!/bin/bash
                    printf '\(downstreamName) %s\\n' "$*" >> "$SPY_LOG"
                    exit 74
                    """)
        }

        let environment = [
            "HOME": homeRoot.path,
            "SPY_LOG": commandLog.path,
            "PATH": "\(spyRoot.path):/usr/bin:/bin:/usr/sbin:/sbin",
            "AGENTSTUDIO_OBSERVABILITY_ALLOW_TEST_OVERRIDES": "1",
            "AI_TOOLS_OBSERVABILITY_STACK_HELPER": spyRoot.appending(path: "stack-helper").path,
            "AGENTSTUDIO_CURL_BIN": spyRoot.appending(path: "curl").path,
            "AGENTSTUDIO_DITTO_BIN": spyRoot.appending(path: "ditto").path,
            "AGENTSTUDIO_CODESIGN_BIN": spyRoot.appending(path: "codesign").path,
            "AGENTSTUDIO_OPEN_BIN": spyRoot.appending(path: "open").path,
            "AGENTSTUDIO_PGREP_BIN": spyRoot.appending(path: "pgrep").path,
            "AGENTSTUDIO_LSOF_BIN": spyRoot.appending(path: "lsof").path,
            "AGENTSTUDIO_SECURITY_BIN": spyRoot.appending(path: "security").path,
            "AGENTSTUDIO_OBSERVABILITY_STATE_FILE": temporaryRoot.appending(path: "state.env").path,
        ]

        for arguments in [["--detach"], ["--skip-build", "--detach"]] {
            try Data().write(to: commandLog)

            // Act
            let result = try runShellScript(
                scriptsRoot.appending(path: "run-debug-observability.sh"),
                arguments: arguments,
                currentDirectory: temporaryRoot,
                environment: environment)

            // Assert
            #expect(result.exitCode == 73, Comment(rawValue: result.stderr))
            let commands = try String(contentsOf: commandLog, encoding: .utf8)
                .split(separator: "\n")
                .map(String.init)
            #expect(commands == ["vendor verify"])
        }
    }

    @Test("closed direct-consumer inventory does not drift")
    func closedDirectConsumerInventory() throws {
        // Arrange
        let expectedScripts: Set<String> = [
            "scripts/run-swift-test-task.sh",
            "scripts/run-debug-observability.sh",
            "scripts/verify-global-preferences-startup-performance.sh",
            "scripts/verify-bridge-headless-manifest.sh",
        ]
        let sourcedOnlyHelpers: Set<String> = [
            "scripts/swift-test-helpers.sh"
        ]
        let fileManager = FileManager.default
        let scripts = try fileManager.contentsOfDirectory(atPath: "scripts")
            .filter { $0.hasSuffix(".sh") }
            .map { "scripts/\($0)" }

        // Act
        let swiftCommandScripts = try Set(
            scripts.filter { path in
                let source = try String(contentsOfFile: path, encoding: .utf8)
                return source.contains("swift build")
                    || source.contains("swift test")
                    || source.contains("swift package")
            })

        // Assert
        #expect(
            swiftCommandScripts == expectedScripts.union(sourcedOnlyHelpers),
            "Classify every script containing a Swift command as a verified entry point or a sourced-only helper")
        for path in expectedScripts {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            #expect(
                vendorVerificationOffset(in: source) != nil,
                "\(path) must own an internal vendor verifier")
        }
    }

    @Test("setup owns both vendor modes and low-level producers stay guarded")
    func setupAndProducerContracts() throws {
        // Arrange
        let miseSource = try String(contentsOfFile: ".mise.toml", encoding: .utf8)
        let setupTask = try #require(taskBlock(named: "setup", in: miseSource))

        // Act / Assert
        #expect(setupTask.contains("flag \"--use-local-vendors\""))
        #expect(setupTask.contains("depends = [\"bridge-web-install\", \"install-hooks\"]"))
        #expect(!setupTask.contains("depends = [\"copy-xcframework\""))
        #expect(setupTask.contains("vendor-worktree.sh\" setup-local"))
        #expect(setupTask.contains("vendor-worktree.sh\" setup-shared"))

        for taskName in [
            "init-submodules",
            "build-zmx",
            "copy-xcframework",
            "setup-dev-resources",
            "refresh-vendors",
        ] {
            let task = try #require(taskBlock(named: taskName, in: miseSource))
            #expect(
                task.contains("vendor-worktree.sh\" require-producer"),
                "\(taskName) must reject shared and partial producer use")
        }

        let ghosttyBuild = try String(
            contentsOfFile: "scripts/build-ghostty-local.sh",
            encoding: .utf8)
        #expect(ghosttyBuild.contains("vendor-worktree.sh\" require-producer"))

        let refreshTask = try #require(taskBlock(named: "refresh-vendors", in: miseSource))
        #expect(!refreshTask.contains("rm -rf \"${PROJECT_ROOT}/Sources/AgentStudio/Resources/terminfo\""))
        #expect(refreshTask.contains("rm -f \"${PROJECT_ROOT}/Sources/AgentStudio/Resources/terminfo/67/ghostty\""))
    }

    @Test("active instructions keep setup as the only vendor bootstrap")
    func activeInstructionContracts() throws {
        // Arrange
        let activeInstructionPaths = [
            "AGENTS.md",
            "README.md",
            "docs/guides/agent_resources.md",
            "docs/architecture/session_lifecycle.md",
            "docs/debugging/zmx-environment-isolation.md",
        ]
        let forbiddenInstructions = [
            "git submodule update --init",
            "git clone --recurse-submodules",
            "mise run init-submodules",
            "mise run build-ghostty",
            "mise run build-zmx",
        ]

        // Act / Assert
        for path in activeInstructionPaths {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            for forbiddenInstruction in forbiddenInstructions {
                #expect(
                    !source.contains(forbiddenInstruction),
                    "\(path) must not advertise \(forbiddenInstruction)")
            }
        }

        let agentInstructions = try String(contentsOfFile: "AGENTS.md", encoding: .utf8)
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
        #expect(agentInstructions.contains("Agents must use plain `mise run setup` by default."))
        #expect(agentInstructions.contains("`mise run setup --use-local-vendors`"))
        #expect(agentInstructions.contains("normally unhydrated in linked worktrees"))
        #expect(
            readme.contains(
                "git clone https://github.com/ShravanSunder/agentstudio.git agent-studio\ncd agent-studio"))
        #expect(readme.contains("normally unhydrated in linked worktrees"))
        #expect(readme.contains("[zmx](https://github.com/neurosnap/zmx)"))
    }

    @Test("GitHub workflows remain independent vendor producers")
    func githubWorkflowContracts() throws {
        // Arrange
        let workflowPaths = [
            ".github/workflows/ci.yml",
            ".github/workflows/benchmarks.yml",
            ".github/workflows/release.yml",
        ]

        // Act / Assert
        for path in workflowPaths {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            #expect(source.contains("submodules: recursive"))
            #expect(source.contains("Build Ghostty"))
            #expect(source.contains("Build zmx"))
            #expect(!source.contains("vendor-worktree.sh"))
            #expect(!source.contains("primary worktree"))
        }
    }

    @Test("doctor allows primary pre-setup diagnostics while consumers still verify")
    func doctorRoleContract() throws {
        // Arrange
        let source = try String(contentsOfFile: "scripts/doctor-mac.sh", encoding: .utf8)

        // Act / Assert
        #expect(source.contains("if [[ \"$vendor_role\" == \"primary\" ]]"))
        #expect(source.contains("primary vendor inputs are not prepared yet; mise run setup will prepare them"))
        #expect(source.contains("elif [[ -x \"$vendor_worktree_helper\" && -n \"$vendor_role\" ]]"))
        #expect(source.contains("report_error \"$vendor_verify_output\""))
    }

    private func taskBlock(named taskName: String, in source: String) -> String? {
        guard let start = source.range(of: "[tasks.\(taskName)]") else {
            return nil
        }
        let remainder = source[start.lowerBound...]
        guard let nextTask = remainder.dropFirst().range(of: "\n[tasks.") else {
            return String(remainder)
        }
        return String(remainder[..<nextTask.lowerBound])
    }

    private func hasVendorVerificationBeforeConsumption(_ task: String) -> Bool {
        if task.contains("depends = [\"verify-vendors\"")
            || task.contains(", \"verify-vendors\"")
        {
            return true
        }
        guard let verification = vendorVerificationOffset(in: task) else {
            return false
        }
        let consumerOffsets = ["swift build", "swift test", "run-swift-test-task.sh"]
            .compactMap { task.range(of: $0)?.lowerBound }
        guard let firstConsumer = consumerOffsets.min() else {
            return false
        }
        return verification < firstConsumer
    }

    private func vendorVerificationOffset(in source: String) -> String.Index? {
        let acceptedInvocations = [
            "scripts/vendor-worktree.sh\" verify",
            "scripts/vendor-worktree.sh verify",
            "vendor-worktree.sh\" verify",
            "vendor-worktree.sh verify",
            "mise run verify-vendors",
        ]
        return
            acceptedInvocations
            .compactMap { source.range(of: $0)?.lowerBound }
            .min()
    }

    private func shellFunction(named functionName: String, in source: String) -> String? {
        guard let start = source.range(of: "\(functionName)() {") else {
            return nil
        }
        let remainder = source[start.lowerBound...]
        guard let nextFunction = remainder.dropFirst().range(of: "\n}\n\n") else {
            return nil
        }
        return String(remainder[...nextFunction.lowerBound])
    }

    private func writeExecutable(at url: URL, source: String) throws {
        try source.write(to: url, atomically: true, encoding: .utf8)
        chmod(url.path, 0o755)
    }

    private func runShellScript(
        _ script: URL,
        arguments: [String],
        currentDirectory: URL,
        environment: [String: String]
    ) throws -> VendorCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        process.currentDirectoryURL = currentDirectory
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in
            override
        }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return VendorCommandResult(
            exitCode: process.terminationStatus,
            stdout: String(
                data: stdout.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8) ?? "",
            stderr: String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8) ?? "")
    }
}

private struct DirectVendorConsumerContract {
    let path: String
    let requiredConsumers: [String]
}
