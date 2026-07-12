import Foundation
import Testing

@testable import AgentStudioArchitectureLintCore

@Suite(.serialized)
struct ArchitectureLintCommandTests {
    @Test("good fixtures pass")
    func goodFixturesPass() throws {
        let fixture = fixturePath("Good")
        let result = runCommand(arguments: [fixture], workspaceRootPath: fixture)

        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        #expect(result.output.isEmpty)
    }

    @Test("bad fixtures fail with architecture rule diagnostics")
    func badFixturesFail() throws {
        let fixture = fixturePath("Bad")
        let result = runCommand(arguments: [fixture], workspaceRootPath: fixture)

        #expect(result.exitCode == 1)
        #expect(result.output.contains("error: [agentstudio_import_direction]"))
        #expect(result.output.contains("warning: [agentstudio_state_actor_path]"))
        #expect(result.output.contains("error: [agentstudio_no_forbidden_architecture_marker]"))
        #expect(result.output.contains("error: [agentstudio_no_generic_clock_sleep]"))
        #expect(result.output.contains("error: [agentstudio_no_task_sleep_in_tests]"))
        #expect(result.output.contains("error: [agentstudio_eventbus_subscriber_policy_required]"))
        #expect(result.output.contains("error: [agentstudio_runtime_signal_plane]"))
    }

    @Test("command prepares qualified aliases across the exact fixture workspace")
    func commandPreparesQualifiedAliasesAcrossFiles() throws {
        let workspace = workspaceFixturePath("QualifiedAliases")
        let result = runCommand(arguments: [workspace], workspaceRootPath: workspace)

        #expect(result.exitCode == 1)
        #expect(
            result.output.contains(
                "AliasConsumers.swift:9:6: error: [agentstudio_runtime_signal_plane]"
            )
        )
        #expect(
            result.output.contains(
                "AliasConsumers.swift:36:10: error: [agentstudio_runtime_signal_plane]"
            )
        )
        #expect(result.output.contains("AliasNamespaces.swift") == false)
        #expect(result.output.contains("AliasHops.swift") == false)
    }

    @Test("command rejects a second owner in the production Admission inventory")
    func commandRejectsSecondProductionOwner() throws {
        let workspace = workspaceFixturePath("SecondOwner")
        let result = runCommand(arguments: [workspace], workspaceRootPath: workspace)

        #expect(result.exitCode == 1)
        #expect(
            result.output.contains(
                "SecondOrderedFactJournalOwner.swift:1:13: error: [agentstudio_runtime_signal_plane]"
            )
        )
    }

    @Test("command rejects a production Admission inventory with no owner")
    func commandRejectsMissingProductionOwner() throws {
        let workspace = workspaceFixturePath("ZeroOwner")
        let result = runCommand(arguments: [workspace], workspaceRootPath: workspace)

        #expect(result.exitCode == 1)
        #expect(
            result.output.contains(
                "AdmissionWithoutJournalOwner.swift:1:1: error: [agentstudio_runtime_signal_plane]"
            )
        )
    }

    @Test("command permits a lexical alias shadowing the canonical journal name")
    func commandPermitsCanonicalJournalNameShadow() throws {
        let workspace = workspaceFixturePath("CanonicalShadow")
        let result = runCommand(arguments: [workspace], workspaceRootPath: workspace)

        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        #expect(result.output.isEmpty)
    }

    @Test("command excludes nested test Sources from production Admission scope")
    func commandExcludesNestedTestAdmissionSources() throws {
        let workspace = workspaceFixturePath("MixedScope")
        let result = runCommand(arguments: [workspace], workspaceRootPath: workspace)

        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        #expect(result.output.isEmpty)
    }

    @Test("relative and absolute command paths enforce identical owner cardinality")
    func commandOwnerCardinalityIsPathFormInvariant() throws {
        for workspaceName in ["ZeroOwner", "SingleOwner", "SecondOwner"] {
            let workspace = workspaceFixturePath(workspaceName)
            let absoluteFiles = try SourceFileDiscovery(fileManager: .default)
                .swiftFiles(under: [workspace])
            let relativeFiles = absoluteFiles.map(workspaceRelativeToCurrentDirectory)
            let absoluteResult = runCommand(
                arguments: absoluteFiles,
                workspaceRootPath: workspace
            )
            let relativeResult = runCommand(
                arguments: relativeFiles,
                workspaceRootPath: workspace
            )

            #expect(relativeResult.exitCode == absoluteResult.exitCode)
            #expect(
                relativeResult.output.split(separator: "\n").count
                    == absoluteResult.output.split(separator: "\n").count
            )
        }
    }

    @Test("command deduplicates canonical source identities before preparation and validation")
    func commandDeduplicatesCanonicalSourceIdentities() throws {
        for workspaceName in ["ZeroOwner", "SingleOwner", "SecondOwner"] {
            let workspace = workspaceFixturePath(workspaceName)
            let absoluteFiles = try SourceFileDiscovery(fileManager: .default)
                .swiftFiles(under: [workspace])
            let duplicatedFiles =
                absoluteFiles + absoluteFiles
                + absoluteFiles.map(
                    workspaceRelativeToCurrentDirectory
                )
            let baseline = runCommand(arguments: absoluteFiles, workspaceRootPath: workspace)
            let duplicated = runCommand(arguments: duplicatedFiles, workspaceRootPath: workspace)

            #expect(duplicated.exitCode == baseline.exitCode)
            #expect(duplicated.output == baseline.output)
        }

        let aliasWorkspace = workspaceFixturePath("QualifiedAliases")
        let aliasFiles = try SourceFileDiscovery(fileManager: .default)
            .swiftFiles(under: [aliasWorkspace])
        let duplicatedAliasFiles = aliasFiles + aliasFiles.map(workspaceRelativeToCurrentDirectory)
        let baselineAliasResult = runCommand(
            arguments: aliasFiles,
            workspaceRootPath: aliasWorkspace
        )
        let duplicatedAliasResult = runCommand(
            arguments: duplicatedAliasFiles,
            workspaceRootPath: aliasWorkspace
        )

        #expect(duplicatedAliasResult.exitCode == baselineAliasResult.exitCode)
        #expect(duplicatedAliasResult.output == baselineAliasResult.output)
    }

    @Test("print rules exposes stable id and severity inventory")
    func printRulesExposesStableInventory() throws {
        let result = runCommand(arguments: ["--print-rules"])

        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        #expect(result.output.split(separator: "\n").count == ExpectedRuleInventory.rules.count)
        for expectedRule in ExpectedRuleInventory.rules {
            #expect(result.output.contains("\(expectedRule.id) \(expectedRule.severity.rawValue)"))
        }
    }

    private func fixturePath(_ name: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
            .path
    }

    private func workspaceFixturePath(_ name: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Workspace")
            .appendingPathComponent(name)
            .path
    }

    private func workspaceRelativeToCurrentDirectory(_ path: String) -> String {
        let prefix = FileManager.default.currentDirectoryPath + "/"
        precondition(path.hasPrefix(prefix))
        return String(path.dropFirst(prefix.count))
    }

    private func runCommand(
        arguments: [String],
        workspaceRootPath: String = FileManager.default.currentDirectoryPath
    ) -> CommandRunResult {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-architecture-lint-\(UUID().uuidString)")
        let outputURL = temporaryDirectory.appendingPathComponent("stdout.log")
        let errorURL = temporaryDirectory.appendingPathComponent("stderr.log")
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let outputHandle = try! FileHandle(forWritingTo: outputURL)
        let errorHandle = try! FileHandle(forWritingTo: errorURL)
        let command = ArchitectureLintCommand(
            fileManager: .default,
            standardOutput: outputHandle,
            standardError: errorHandle,
            rules: ArchitectureRuleRegistry.rules,
            workspaceRootPath: workspaceRootPath
        )

        let exitCode = command.run(arguments: arguments)
        try? outputHandle.close()
        try? errorHandle.close()

        let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
        let error = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
        return CommandRunResult(exitCode: exitCode, output: output + error)
    }
}

private struct CommandRunResult {
    let exitCode: Int32
    let output: String
}
