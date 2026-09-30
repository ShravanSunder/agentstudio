import Foundation
import SwiftParser

@testable import AgentStudioArchitectureLintCore

/// Fixture corpora and inline contexts shared by the rule test suites.
enum LintTestSupport {
    @MainActor
    private static var fixtureCorpusResults: [String: Result<[ArchitectureDiagnostic], any Error>] = [:]

    static func fixtureRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
    }

    /// Every site the registry's rules report in one fixture corpus, linted
    /// with the corpus as the workspace root.
    @MainActor
    static func lintFixtureCorpus(_ corpus: String) throws -> [ArchitectureDiagnostic] {
        if let result = fixtureCorpusResults[corpus] {
            return try result.get()
        }

        let result = Result { try lintFixtureCorpusUncached(corpus) }
        fixtureCorpusResults[corpus] = result
        return try result.get()
    }

    private static func lintFixtureCorpusUncached(_ corpus: String) throws -> [ArchitectureDiagnostic] {
        let corpusRoot = fixtureRoot().appendingPathComponent(corpus)
        let files = try SourceFileDiscovery(fileManager: .default)
            .lintedFiles(under: [corpusRoot.path])
        return try lint(files: files, workspaceRootPath: corpusRoot.path)
    }

    static func lint(
        files: [String],
        workspaceRootPath: String = FileManager.default.currentDirectoryPath
    ) throws -> [ArchitectureDiagnostic] {
        try ArchitectureLintEngine(
            rules: ArchitectureRuleRegistry.rules,
            documentRules: ArchitectureRuleRegistry.documentRules,
            workspaceRootPath: workspaceRootPath
        )
        .lint(files: files)
        .siteDiagnostics
    }

    static func context(path: String, source: String) -> ArchitectureLintContext {
        ArchitectureLintContext(
            path: path,
            source: source,
            sourceFile: Parser.parse(source: source)
        )
    }

    /// A context inside a repository rooted at `/repo`, so repository-relative
    /// paths resolve.
    static func repositoryContext(path: String, source: String) -> ArchitectureLintContext {
        ArchitectureLintContext(
            path: "/repo/\(path)",
            source: source,
            sourceFile: Parser.parse(source: source),
            workspaceRootPath: "/repo"
        )
    }
}
