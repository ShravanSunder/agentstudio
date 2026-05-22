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

        #expect(artifacts.count == 2)
        assertFileReference(
            artifacts[0],
            path: "Sources/AgentStudio/App/AppDelegate.swift",
            line: 42,
            column: 7,
            sourceText: "Sources/AgentStudio/App/AppDelegate.swift:42:7: warning"
        )
        assertFileReference(
            artifacts[1],
            path: "/Users/me/project/Tests/AppTests.swift",
            line: 18,
            column: nil,
            sourceText: "/Users/me/project/Tests/AppTests.swift:18 failed"
        )
    }

    @Test("separates URLs from file references")
    func separatesURLsFromFileReferences() {
        let extractor = TerminalSemanticArtifactExtractor()

        let artifacts = extractor.artifacts(
            in: "See https://example.com/docs/path and ./docs/plan.md:9."
        )

        #expect(artifacts.count == 2)
        assertURLReference(
            artifacts[0],
            url: "https://example.com/docs/path",
            sourceText: "See https://example.com/docs/path and ./docs/plan.md:9."
        )
        assertFileReference(
            artifacts[1],
            path: "./docs/plan.md",
            line: 9,
            column: nil,
            sourceText: "See https://example.com/docs/path and ./docs/plan.md:9."
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

    @Test("splits comma-separated file references")
    func splitsCommaSeparatedFileReferences() {
        let artifacts = TerminalSemanticArtifactExtractor()
            .artifacts(in: "src/x.swift,src/y.swift")

        #expect(artifacts.count == 2)
        assertFileReference(artifacts[0], path: "src/x.swift", line: nil, column: nil)
        assertFileReference(artifacts[1], path: "src/y.swift", line: nil, column: nil)
    }

    @Test("does not extract file references inside URL bodies")
    func doesNotExtractFileReferencesInsideURLBodies() {
        let artifacts = TerminalSemanticArtifactExtractor()
            .artifacts(in: "Open https://example.com/foo/bar.html now")

        #expect(artifacts.count == 1)
        assertURLReference(artifacts[0], url: "https://example.com/foo/bar.html")
    }

    @Test("ignores URL-like and extensionless references")
    func ignoresURLLikeAndExtensionlessReferences() {
        let extractor = TerminalSemanticArtifactExtractor()

        #expect(extractor.artifacts(in: "git@github.com:foo/bar").isEmpty)
        #expect(extractor.artifacts(in: "mailto:user@example.com").isEmpty)
        #expect(extractor.artifacts(in: "C:/Users/me/file.txt").isEmpty)
        #expect(extractor.artifacts(in: "Makefile").isEmpty)
    }

    @Test("extracts multiple references on one line")
    func extractsMultipleReferencesOnOneLine() {
        let artifacts = TerminalSemanticArtifactExtractor()
            .artifacts(in: "src/a.swift and src/b.swift compile")

        #expect(artifacts.count == 2)
        assertFileReference(artifacts[0], path: "src/a.swift", line: nil, column: nil)
        assertFileReference(artifacts[1], path: "src/b.swift", line: nil, column: nil)
    }

    @Test("extracts bracketed paths with line numbers")
    func extractsBracketedPathsWithLineNumbers() {
        let artifacts = TerminalSemanticArtifactExtractor()
            .artifacts(in: "[/abs/path/file.go:12]")

        #expect(artifacts.count == 1)
        assertFileReference(artifacts[0], path: "/abs/path/file.go", line: 12, column: nil)
    }

    @Test("trims trailing periods from URLs")
    func trimsTrailingPeriodsFromURLs() {
        let artifacts = TerminalSemanticArtifactExtractor()
            .artifacts(in: "See https://example.com/docs.")

        #expect(artifacts.count == 1)
        assertURLReference(artifacts[0], url: "https://example.com/docs")
    }

    @Test("file reference equality ignores source text")
    func fileReferenceEqualityIgnoresSourceText() throws {
        let sourceText = "src/App.swift:42"
        let firstReference = try #require(
            TerminalFileReference.make(
                path: "src/App.swift",
                line: 42,
                column: nil,
                sourceText: sourceText,
                sourceRange: sourceText.startIndex..<sourceText.endIndex
            ))
        let secondSourceText = "warning in src/App.swift:42"
        let secondReference = try #require(
            TerminalFileReference.make(
                path: "src/App.swift",
                line: 42,
                column: nil,
                sourceText: secondSourceText,
                sourceRange: secondSourceText.startIndex..<secondSourceText.endIndex
            ))

        #expect(firstReference == secondReference)
    }

    @Test("semantic references reject invalid values")
    func semanticReferencesRejectInvalidValues() {
        let emptySourceText = ""

        #expect(
            TerminalFileReference.make(
                path: "",
                line: -5,
                column: 0,
                sourceText: emptySourceText,
                sourceRange: emptySourceText.startIndex..<emptySourceText.endIndex
            ) == nil
        )
        #expect(TerminalURLReference.make(urlString: "not a url", sourceText: "not a url") == nil)
    }
}

private func assertFileReference(
    _ artifact: TerminalSemanticArtifact,
    path: String,
    line: Int?,
    column: Int?,
    sourceText: String? = nil
) {
    guard case .fileReference(let reference) = artifact else {
        Issue.record("Expected file reference, got \(artifact)")
        return
    }
    #expect(reference.path == path)
    #expect(reference.line == line)
    #expect(reference.column == column)
    if let sourceText {
        #expect(reference.sourceText == sourceText)
    }
    #expect(String(reference.sourceText[reference.sourceRange]) == path)
}

private func assertURLReference(
    _ artifact: TerminalSemanticArtifact,
    url: String,
    sourceText: String? = nil
) {
    guard case .urlReference(let reference) = artifact else {
        Issue.record("Expected URL reference, got \(artifact)")
        return
    }
    #expect(reference.url.absoluteString == url)
    if let sourceText {
        #expect(reference.sourceText == sourceText)
    }
    #expect(String(reference.sourceText[reference.sourceRange]) == url)
}
