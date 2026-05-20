import Testing

@testable import AgentStudio

@Suite("TerminalSemanticArtifactExtractor")
struct TerminalSemanticArtifactExtractorTests {
    @Test("extracts absolute and relative file references with line and column")
    func extractsAbsoluteAndRelativeFileReferencesWithLineAndColumn() {
        let extractor = TerminalSemanticArtifactExtractor()

        let artifacts = extractor.artifacts(
            in: """
                Sources/AgentStudio/App/AppDelegate.swift:42:7: warning
                /Users/me/project/Tests/AppTests.swift:18 failed
                """
        )

        #expect(
            artifacts == [
                .fileReference(
                    TerminalFileReference(
                        path: "Sources/AgentStudio/App/AppDelegate.swift",
                        line: 42,
                        column: 7,
                        sourceText: "Sources/AgentStudio/App/AppDelegate.swift:42:7: warning"
                    )
                ),
                .fileReference(
                    TerminalFileReference(
                        path: "/Users/me/project/Tests/AppTests.swift",
                        line: 18,
                        column: nil,
                        sourceText: "/Users/me/project/Tests/AppTests.swift:18 failed"
                    )
                ),
            ]
        )
    }

    @Test("separates URLs from file references")
    func separatesURLsFromFileReferences() {
        let extractor = TerminalSemanticArtifactExtractor()

        let artifacts = extractor.artifacts(
            in: "See https://example.com/docs/path and ./docs/plan.md:9."
        )

        #expect(
            artifacts == [
                .urlReference(
                    TerminalURLReference(
                        url: "https://example.com/docs/path",
                        sourceText: "See https://example.com/docs/path and ./docs/plan.md:9."
                    )
                ),
                .fileReference(
                    TerminalFileReference(
                        path: "./docs/plan.md",
                        line: 9,
                        column: nil,
                        sourceText: "See https://example.com/docs/path and ./docs/plan.md:9."
                    )
                ),
            ]
        )
    }

    @Test("ignores bare words and directory-only paths")
    func ignoresBareWordsAndDirectoryOnlyPaths() {
        let extractor = TerminalSemanticArtifactExtractor()

        let artifacts = extractor.artifacts(
            in: "build failed in Sources/AgentStudio and target AgentStudio"
        )

        #expect(artifacts.isEmpty)
    }
}
