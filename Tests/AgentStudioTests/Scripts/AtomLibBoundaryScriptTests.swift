import Foundation
import Testing

@Suite(.serialized)
struct AtomLibBoundaryScriptTests {
    @Test("atomlib boundary script has syntax, lint wiring, and named rules")
    func scriptHasSyntaxLintWiringAndNamedRules() throws {
        let syntax = try runScript(arguments: ["-n", scriptPath])
        #expect(syntax.exitCode == 0, Comment(rawValue: syntax.stderr))

        let miseConfig = try String(contentsOfFile: ".mise.toml", encoding: .utf8)
        let source = try String(contentsOfFile: scriptPath, encoding: .utf8)

        #expect(miseConfig.contains("bash scripts/check-atomlib-boundaries.sh"))
        #expect(source.contains("AtomScope"))
        #expect(source.contains("atom\\("))
        #expect(source.contains("WorktreeEnrichment"))
        #expect(source.contains("repoEnrichmentByRepoId"))
        #expect(source.contains("worktreeEnrichmentByWorktreeId"))
        #expect(source.contains("pullRequestCountByWorktreeId"))
        #expect(source.contains("report-only repo-cache dictionary inventory"))
        #expect(source.contains("production code must use repo-cache keyed reads or named snapshots"))
        #expect(source.contains("AGENTSTUDIO_ATOMLIB_BOUNDARY_PROJECT_ROOT"))
        #expect(source.contains("DerivedValue[<(]"))
        #expect(source.contains("mktemp"))
        #expect(source.contains("command -v rg"))
        #expect(!source.contains("/tmp/atomlib-boundary-"))
    }

    @Test("atomlib compile-negative fixtures are recognized as expected failures")
    func compileNegativeFixturesAreRecognizedAsExpectedFailures() throws {
        let result = try runScript(arguments: [scriptPath, "--expect-fixture-failures"])

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        #expect(result.stdout.contains("expected fixture failures: OK"))
    }

    @Test("custom scan path fails on undeclared derived atom access")
    func customScanPathFailsOnUndeclaredDerivedAtomAccess() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let badFixture = fixtureRoot.appendingPathComponent("BadDerivedAccess.swift.fixture")
        try """
        import AgentStudio

        let derived = DerivedValue<Int>(
            inputRevisions: { [0] },
            isContentEqual: ==
        ) {
            atom(\\.repoCache).repoEnrichmentByRepoId.count
        }
        """.write(to: badFixture, atomically: true, encoding: .utf8)

        let result = try runScript(arguments: [scriptPath, "--scan-path", fixtureRoot.path, "--no-inventory"])

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("undeclared atom access"))
    }

    @Test("custom scan path fails on raw repo-cache dictionary reads")
    func customScanPathFailsOnRawRepoCacheDictionaryReads() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let badFixture = fixtureRoot.appendingPathComponent("BadRepoCacheRead.swift.fixture")
        try """
        import AgentStudio

        func readRawRepoCache(repoCache: RepoCacheAtom) -> Int {
            repoCache.worktreeEnrichmentByWorktreeId.count
        }
        """.write(to: badFixture, atomically: true, encoding: .utf8)

        let result = try runScript(arguments: [scriptPath, "--scan-path", fixtureRoot.path, "--no-inventory"])

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("repo-cache keyed reads or named snapshots"))
    }

    @Test("custom scan path fails on aliased raw repo-cache dictionary reads")
    func customScanPathFailsOnAliasedRawRepoCacheDictionaryReads() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let badFixture = fixtureRoot.appendingPathComponent("BadRepoCacheAliasRead.swift.fixture")
        try """
        import AgentStudio

        func readRawRepoCache(cache: RepoCacheAtom) -> Int {
            cache.worktreeEnrichmentByWorktreeId.count
        }
        """.write(to: badFixture, atomically: true, encoding: .utf8)

        let result = try runScript(arguments: [scriptPath, "--scan-path", fixtureRoot.path, "--no-inventory"])

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("repo-cache keyed reads or named snapshots"))
    }

    @Test("custom scan path fails on raw worktree enrichment comparator closures")
    func customScanPathFailsOnRawWorktreeEnrichmentComparatorClosures() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let closureFixture = fixtureRoot.appendingPathComponent("BadWorktreeClosureComparator.swift.fixture")
        try """
        import AgentStudio

        let map = AtomEntityMap<UUID, WorktreeEnrichment>(
            isContentEqual: { lhs, rhs in lhs == rhs }
        )
        """.write(to: closureFixture, atomically: true, encoding: .utf8)

        let multilineFixture = fixtureRoot.appendingPathComponent("BadWorktreeMultilineComparator.swift.fixture")
        try """
        import AgentStudio

        let atom = AtomValue<WorktreeEnrichment>(
            initialValue: WorktreeEnrichment(worktreeId: UUID(), repoId: UUID(), branch: "main"),
            isContentEqual:
                ==
        )
        """.write(to: multilineFixture, atomically: true, encoding: .utf8)

        let result = try runScript(arguments: [scriptPath, "--scan-path", fixtureRoot.path, "--no-inventory"])

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("WorktreeEnrichment must not use raw equality"))
    }

    @Test("default scan finds derived boundary violations in production sources")
    func defaultScanFindsDerivedBoundaryViolationsInProductionSources() throws {
        let projectRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        let sourceRoot =
            projectRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("AgentStudio")
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let badSource = sourceRoot.appendingPathComponent("BadDerivedAccess.swift")
        try """
        import AgentStudio

        let derived = DerivedValue<Int>(
            inputRevisions: { [0] },
            isContentEqual: ==
        ) {
            atom(\\.repoCache).repoEnrichmentByRepoId.count
        }
        """.write(to: badSource, atomically: true, encoding: .utf8)

        let result = try runScript(
            arguments: [scriptPath, "--no-inventory"],
            environment: ["AGENTSTUDIO_ATOMLIB_BOUNDARY_PROJECT_ROOT": projectRoot.path]
        )

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("undeclared atom access"))
    }

    @Test("custom scan path passes for clean derived source")
    func customScanPathPassesForCleanDerivedSource() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let cleanFixture = fixtureRoot.appendingPathComponent("CleanDerivedAccess.swift.fixture")
        try """
        import AgentStudio

        let revision = AtomRevision()
        let derived = DerivedValue<Int>(
            inputRevisions: { [revision.value] },
            isContentEqual: ==
        ) {
            42
        }
        """.write(to: cleanFixture, atomically: true, encoding: .utf8)

        let result = try runScript(arguments: [scriptPath, "--scan-path", fixtureRoot.path, "--no-inventory"])

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
    }

    private let scriptPath = "scripts/check-atomlib-boundaries.sh"

    private func temporaryFixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-atomlib-boundary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func runScript(
        arguments: [String],
        environment: [String: String] = [:]
    ) throws -> ScriptRunResult {
        let stdoutURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-atomlib-boundary-stdout-\(UUID().uuidString).log")
        let stderrURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-atomlib-boundary-stderr-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        try process.run()
        process.waitUntilExit()

        let stdout = try String(contentsOf: stdoutURL, encoding: .utf8)
        let stderr = try String(contentsOf: stderrURL, encoding: .utf8)
        return ScriptRunResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
