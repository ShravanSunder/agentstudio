import Foundation
import SwiftParser
import Testing

@testable import AgentStudioArchitectureLintCore

@Suite
struct RuleParityTests {
    @Test("bad fixture corpus exercises every migrated rule")
    func badFixtureCorpusExercisesEveryMigratedRule() throws {
        let diagnostics = try lintFixtureCorpus("Bad")
        let actualIDs = Set(diagnostics.map(\.ruleID))
        let expectedIDs = Set(ExpectedRuleInventory.rules.map(\.id))

        #expect(actualIDs.isSuperset(of: expectedIDs))
    }

    @Test("good fixture corpus stays clean")
    func goodFixtureCorpusStaysClean() throws {
        let diagnostics = try lintFixtureCorpus("Good")

        #expect(diagnostics.isEmpty)
    }

    @Test("forbidden architecture marker has dedicated fixture coverage")
    func forbiddenArchitectureMarkerHasDedicatedFixtureCoverage() throws {
        let markerFixture = fixtureRoot()
            .appendingPathComponent("Bad")
            .appendingPathComponent("Sources")
            .appendingPathComponent("AgentStudio")
            .appendingPathComponent("App")
            .appendingPathComponent("BadForbiddenArchitectureMarker.swift")
            .path

        let diagnostics = try lint(files: [markerFixture])

        #expect(diagnostics.map(\.ruleID) == ["agentstudio_no_forbidden_architecture_marker"])
    }

    private func lintFixtureCorpus(_ corpus: String) throws -> [ArchitectureDiagnostic] {
        let files = try SourceFileDiscovery(fileManager: .default)
            .swiftFiles(under: [fixtureRoot().appendingPathComponent(corpus).path])
        return try lint(files: files)
    }

    private func lint(files: [String]) throws -> [ArchitectureDiagnostic] {
        var diagnostics: [ArchitectureDiagnostic] = []
        for file in files {
            let source = try String(contentsOfFile: file, encoding: .utf8)
            let context = ArchitectureLintContext(
                path: file,
                source: source,
                sourceFile: Parser.parse(source: source)
            )
            for rule in ArchitectureRuleRegistry.rules {
                diagnostics.append(contentsOf: rule.validate(context: context))
            }
        }
        return diagnostics.sorted()
    }

    private func fixtureRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
    }
}
