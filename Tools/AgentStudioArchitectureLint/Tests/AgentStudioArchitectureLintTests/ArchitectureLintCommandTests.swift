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
        #expect(result.output.contains("error: [agentstudio_retired_worktrunk_cli]"))
        #expect(result.output.contains("error: [agentstudio_product_atom_boundary]"))
        #expect(result.output.contains("error: [agentstudio_canonical_atom_mutation]"))
        #expect(result.output.contains("warning: [agentstudio_state_actor_path]"))
        #expect(result.output.contains("error: [agentstudio_no_forbidden_architecture_marker]"))
        #expect(result.output.contains("error: [agentstudio_no_generic_clock_sleep]"))
        #expect(result.output.contains("error: [agentstudio_no_task_sleep_in_tests]"))
        #expect(result.output.contains("error: [agentstudio_eventbus_subscriber_policy_required]"))
        #expect(result.output.contains("error: [agentstudio_shared_components_are_stateless]"))
        #expect(result.output.contains("error: [agentstudio_hot_pane_snapshot_reads]"))
    }

    @Test("shared components reject Core-owned static presentation reads")
    func sharedComponentsRejectCoreOwnedStaticPresentationReads() throws {
        let result = runCommand(
            arguments: [
                fixturePath("Bad/Sources/AgentStudio/SharedComponents/BadSharedComponentStaticRead.swift")
            ]
        )

        #expect(result.exitCode == 1)
        #expect(result.output.contains("error: [agentstudio_shared_components_are_stateless]"))
        #expect(result.output.contains("Core-owned presentation types"))
    }

    @Test("blocking wait rule recognizes Process receivers without matching unrelated names")
    func blockingWaitRuleRecognizesProcessReceiversWithoutMatchingUnrelatedNames() throws {
        let badResult = runCommand(
            arguments: [
                fixturePath("Bad/Tests/AgentStudioTests/BadProcessWaitUntilExitTest.swift")
            ]
        )
        let goodResult = runCommand(
            arguments: [
                fixturePath("Good/Tests/AgentStudioTests/GoodProcessWaitUntilExitTest.swift")
            ]
        )

        #expect(badResult.exitCode == 1)
        #expect(badResult.output.contains("Wrap this Process.waitUntilExit call"))
        #expect(
            badResult.output.components(separatedBy: "Wrap this Process.waitUntilExit call").count - 1 == 4,
            Comment(rawValue: badResult.output)
        )
        #expect(goodResult.exitCode == 0, Comment(rawValue: goodResult.output))
        #expect(goodResult.output.isEmpty)
    }

    @Test("blocking wait rule accepts a wait inside valueFromDedicatedThread and rejects the same wait outside it")
    func blockingWaitRuleRecognizesTheHarnessDedicatedThreadHop() throws {
        let badResult = runCommand(
            arguments: [
                fixturePath("Bad/Tests/AgentStudioTests/BadDedicatedThreadBlockingWaitTest.swift")
            ]
        )
        let goodResult = runCommand(
            arguments: [
                fixturePath("Good/Tests/AgentStudioTests/GoodDedicatedThreadBlockingWaitTest.swift")
            ]
        )

        #expect(badResult.exitCode == 1)
        #expect(
            badResult.output.components(separatedBy: "Wrap this semaphore wait").count - 1 == 1,
            Comment(rawValue: badResult.output)
        )
        #expect(goodResult.exitCode == 0, Comment(rawValue: goodResult.output))
        #expect(goodResult.output.isEmpty)
    }

    @Test("PaneTab command presentation rejects bulk pane snapshots and wrappers")
    func paneTabCommandPresentationRejectsBulkPaneSnapshotsAndWrappers() throws {
        let result = runCommand(
            arguments: [
                fixturePath("Bad/Sources/AgentStudio/App/Panes/PaneTabViewController.swift")
            ]
        )

        #expect(result.exitCode == 1)
        #expect(result.output.contains("error: [agentstudio_hot_pane_snapshot_reads]"))
        #expect(
            result.output.components(separatedBy: "[agentstudio_hot_pane_snapshot_reads]").count - 1 == 4
        )
    }

    @Test("scoped run reports exactly the full run's diagnostics for the scoped files")
    func scopedRunReportsFullRunDiagnosticsForScopedFiles() throws {
        // Arrange: files whose verdict depends on cross-file prepared indexes
        // (the atom owner index) as well as single-file rules.
        let fixture = fixturePath("Bad")
        let scopedRelativePaths = [
            "Sources/AgentStudio/Core/State/MainActor/Atoms/BadFeatureAtomReference.swift",
            "Sources/AgentStudio/Features/RepoExplorer/State/MainActor/Atoms/BadSiblingFeatureAtomReference.swift",
            "Tests/AgentStudioTests/BadPollingWaitTest.swift",
        ]
        let scopedAbsolutePaths = scopedRelativePaths.map { "\(fixture)/\($0)" }

        // Act
        let fullResult = runCommand(arguments: [fixture], workspaceRootPath: fixture)
        let scopedResult = runCommand(
            arguments: [fixture] + scopedRelativePaths.flatMap { ["--only", $0] },
            workspaceRootPath: fixture
        )

        // Assert
        let fullLinesForScopedFiles = fullResult.output
            .split(separator: "\n")
            .filter { line in scopedAbsolutePaths.contains { line.hasPrefix("\($0):") } }
        let scopedLines = scopedResult.output.split(separator: "\n")
        #expect(!fullLinesForScopedFiles.isEmpty)
        #expect(scopedLines == fullLinesForScopedFiles, Comment(rawValue: scopedResult.output))
        #expect(scopedResult.exitCode == 1)
    }

    @Test("timings print per stage and per rule without changing the exit code")
    func timingsPrintPerStageAndPerRuleWithoutChangingExitCode() throws {
        let fixture = fixturePath("Good")
        let result = runCommand(arguments: ["--timings", fixture], workspaceRootPath: fixture)

        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        #expect(result.output.contains("architecture-lint timing stage=parse"))
        #expect(result.output.contains("architecture-lint timing stage=validate"))
        for expectedRule in ExpectedRuleInventory.rules {
            #expect(result.output.contains("architecture-lint timing rule=\(expectedRule.id) ms="))
        }
    }

    @Test("unknown options fail instead of being ignored")
    func unknownOptionsFailInsteadOfBeingIgnored() throws {
        let result = runCommand(arguments: ["--ledgr", "x"])

        #expect(result.exitCode == 2)
        #expect(result.output.contains("unknown option --ledgr"))
    }

    @Test("ledger rows at the found count silence a file's sites; one site over reports them all")
    func ledgerRowsSilenceExactCountAndReportOverCount() throws {
        let fixture = fixturePath("Bad")
        let pollingFixture = "Tests/AgentStudioTests/BadPollingWaitTest.swift"
        let pollingRule = "agentstudio_no_polling_wait_in_tests"

        let exactLedger = try writeLedger(rows: ["\(pollingRule)\t\(pollingFixture)\t5"])
        let underLedger = try writeLedger(rows: ["\(pollingRule)\t\(pollingFixture)\t4"])
        let exact = runCommand(
            arguments: [pollingFixture, "--ledger", exactLedger.path],
            workspaceRootPath: fixture
        )
        let over = runCommand(
            arguments: [pollingFixture, "--ledger", underLedger.path],
            workspaceRootPath: fixture
        )

        #expect(!exact.output.contains("[\(pollingRule)]"), Comment(rawValue: exact.output))
        #expect(over.exitCode == 1)
        #expect(over.output.components(separatedBy: "count 5 exceeds 4 permitted").count - 1 == 5)
    }

    @Test("lowering rewrites the ledger to the found count and then passes")
    func loweringRewritesLedgerToFoundCount() throws {
        let fixture = fixturePath("Bad")
        let pollingFixture = "Tests/AgentStudioTests/BadPollingWaitTest.swift"
        let pollingRule = "agentstudio_no_polling_wait_in_tests"
        let ledger = try writeLedger(rows: ["\(pollingRule)\t\(pollingFixture)\t7"])

        let before = runCommand(arguments: [pollingFixture, "--ledger", ledger.path], workspaceRootPath: fixture)
        let lowering = runCommand(
            arguments: [pollingFixture, "--ledger", ledger.path, "--lower-ledger-counts"],
            workspaceRootPath: fixture
        )

        #expect(before.output.contains("lower the row to 5"))
        #expect(!lowering.output.contains("[\(pollingRule)]"), Comment(rawValue: lowering.output))
        #expect(
            try String(contentsOf: ledger, encoding: .utf8)
                == "rule_id\tpath\tcount\n\(pollingRule)\t\(pollingFixture)\t5\n")
    }

    @Test("a missing or malformed ledger fails closed")
    func missingOrMalformedLedgerFailsClosed() throws {
        let fixture = fixturePath("Good")
        let malformed = try writeLedger(rows: ["not a row"])

        let missingResult = runCommand(
            arguments: [fixture, "--ledger", "/nonexistent/ledger.tsv"],
            workspaceRootPath: fixture
        )
        let malformedResult = runCommand(arguments: [fixture, "--ledger", malformed.path], workspaceRootPath: fixture)

        #expect(missingResult.exitCode == 2)
        #expect(missingResult.output.contains("cannot read debt ledger"))
        #expect(malformedResult.exitCode == 2)
        #expect(malformedResult.output.contains("\(malformed.path):2: malformed debt ledger"))
    }

    @Test("ratchet fails a raised row and passes when the merge base has no ledger")
    func ratchetFailsRaisedRowAndPassesWithoutBaseLedger() throws {
        let base = try writeLedger(rows: ["a_rule\tTests/A.swift\t1"])
        let raised = try writeLedger(rows: ["a_rule\tTests/A.swift\t2"])

        let raisedResult = runCommand(arguments: ["--ledger", raised.path, "--check-ledger-ratchet", base.path])
        let noBaseResult = runCommand(
            arguments: ["--ledger", raised.path, "--check-ledger-ratchet", "/nonexistent/base.tsv"]
        )

        #expect(raisedResult.exitCode == 1)
        #expect(raisedResult.output.contains("[agentstudio_debt_ledger_ratchet]"))
        #expect(raisedResult.output.contains("from 1 to 2"))
        #expect(noBaseResult.exitCode == 0, Comment(rawValue: noBaseResult.output))
        #expect(noBaseResult.output.contains("no debt ledger at the merge base"))
    }

    @Test("configuration diagnostics are reported by full runs only")
    func configurationDiagnosticsAreReportedByFullRunsOnly() throws {
        let fixture = fixturePath("Good")
        let scopedFile = "Sources/AgentStudio/AtomRegistry.swift"

        let full = runCommand(arguments: [fixture], workspaceRootPath: fixture, rules: [StaleOwnerRule()])
        let scoped = runCommand(
            arguments: [fixture, "--only", scopedFile],
            workspaceRootPath: fixture,
            rules: [StaleOwnerRule()]
        )

        #expect(full.exitCode == 1)
        #expect(full.output.contains("[agentstudio_test_stale_owner] stale owner"))
        #expect(scoped.exitCode == 0, Comment(rawValue: scoped.output))
        #expect(!scoped.output.contains("stale owner"))
    }

    @Test("relative single-file paths receive the same architecture classification")
    func relativeSingleFilePathsReceiveArchitectureClassification() throws {
        let badFixtureRoot = fixturePath("Bad")
        let relativeFixture =
            "Sources/AgentStudio/SharedComponents/BadRealizedModuleImport.swift"

        let result = runCommand(
            arguments: [relativeFixture],
            workspaceRootPath: badFixtureRoot
        )

        #expect(result.exitCode == 1)
        #expect(result.output.contains("error: [agentstudio_import_direction]"))
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

    @Test("every registered rule fails the command when it reports a site")
    func everyRegisteredRuleFailsTheCommand() throws {
        let fixture = fixturePath("Bad")
        let result = runCommand(arguments: [fixture], workspaceRootPath: fixture)

        #expect(result.exitCode == 1)
        for expectedRule in ExpectedRuleInventory.rules {
            #expect(
                result.output.contains(": \(expectedRule.severity.rawValue): [\(expectedRule.id)]"),
                Comment(rawValue: expectedRule.id)
            )
        }
        #expect(!result.output.contains(": report: "))
    }

    @Test("warning diagnostics continue to fail the command")
    func warningDiagnosticsContinueToFailCommand() throws {
        let fixture = fixturePath("Good")
        let result = runCommand(
            arguments: [fixture],
            workspaceRootPath: fixture,
            rules: [AlwaysWarningArchitectureRule()]
        )

        #expect(result.exitCode == 1)
        #expect(result.output.contains("warning: [agentstudio_test_warning]"))
    }

    private func fixturePath(_ name: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
            .path
    }

    /// A ledger file in a fresh temporary directory; the directory is left
    /// for the system to clean, like the command runs' own output files.
    private func writeLedger(rows: [String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-architecture-ledger-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ledger = directory.appendingPathComponent("architecture-debt-ledger.tsv")
        try (([ArchitectureDebtLedger.header] + rows).joined(separator: "\n") + "\n")
            .write(to: ledger, atomically: true, encoding: .utf8)
        return ledger
    }

    private func runCommand(
        arguments: [String],
        workspaceRootPath: String = FileManager.default.currentDirectoryPath,
        rules: [any ArchitectureRule] = ArchitectureRuleRegistry.rules
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
            rules: rules,
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

private struct StaleOwnerRule: ArchitectureRule {
    let id = "agentstudio_test_stale_owner"
    let severity = ArchitectureSeverity.error
    let message = "stale owner"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        []
    }

    func configurationDiagnostics() -> [ArchitectureDiagnostic] {
        [
            ArchitectureDiagnostic(
                path: "Owner.swift", line: 1, column: 1, severity: severity, ruleID: id, message: message)
        ]
    }
}

private struct AlwaysWarningArchitectureRule: ArchitectureRule {
    let id = "agentstudio_test_warning"
    let severity = ArchitectureSeverity.warning
    let message = "test warning diagnostic"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        [
            diagnostic(
                context: context,
                position: context.sourceFile.positionAfterSkippingLeadingTrivia
            )
        ]
    }
}

private struct CommandRunResult {
    let exitCode: Int32
    let output: String
}
