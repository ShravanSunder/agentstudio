import Foundation
import Testing

@testable import AgentStudioArchitectureLintCore

@Suite(.serialized)
struct ArchitectureLintCommandTests {
    @Test("good fixtures pass")
    func goodFixturesPass() throws {
        let result = runCommand(arguments: [fixturePath("Good")])

        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        #expect(result.output.isEmpty)
    }

    @Test("bad fixtures fail with architecture rule diagnostics")
    func badFixturesFail() throws {
        let result = runCommand(arguments: [fixturePath("Bad")])

        #expect(result.exitCode == 1)
        #expect(result.output.contains("error: [agentstudio_import_direction]"))
        #expect(result.output.contains("warning: [agentstudio_state_actor_path]"))
        #expect(result.output.contains("error: [agentstudio_no_forbidden_architecture_marker]"))
        #expect(result.output.contains("error: [agentstudio_no_generic_clock_sleep]"))
        #expect(result.output.contains("error: [agentstudio_no_task_sleep_in_tests]"))
        #expect(result.output.contains("error: [agentstudio_eventbus_subscriber_policy_required]"))
        #expect(result.output.contains("error: [agentstudio_shared_components_are_stateless]"))
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

    private func runCommand(arguments: [String]) -> CommandRunResult {
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
            standardError: errorHandle
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
