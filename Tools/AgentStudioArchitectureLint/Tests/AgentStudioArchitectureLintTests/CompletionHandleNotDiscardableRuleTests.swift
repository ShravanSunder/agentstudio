import Foundation
import SwiftParser
import Testing

@testable import AgentStudioArchitectureLintCore

@Suite
struct CompletionHandleNotDiscardableRuleTests {
    private let ruleID = "agentstudio_completion_handle_not_discardable"

    @Test("bad fixture reports the discardable declaration and the reasonless discard only")
    func badFixtureReportsDiscardableDeclarationAndReasonlessDiscard() throws {
        // Arrange
        let fixture = fixtureRoot().appendingPathComponent(
            "Bad/Sources/AgentStudio/App/BadCompletionHandleDiscard.swift"
        )

        // Act
        let diagnostics = try lint(files: [fixture.path])

        // Assert
        #expect(diagnostics.map(\.line) == [3, 9])
        #expect(
            diagnostics.map(\.message) == [
                CompletionHandleNotDiscardableRule.discardableDeclarationMessage,
                CompletionHandleNotDiscardableRule.reasonlessDiscardMessage,
            ])
        #expect(diagnostics.allSatisfy { $0.severity == .error })
    }

    @Test("good fixture accepts awaited, stored, reasoned, optional-chained, and ambiguous discards")
    func goodFixtureAcceptsResolvedCallSites() throws {
        // Arrange
        let fixture = fixtureRoot().appendingPathComponent(
            "Good/Sources/AgentStudio/App/GoodCompletionHandleDiscard.swift"
        )

        // Act
        let diagnostics = try lint(files: [fixture.path])

        // Assert
        #expect(diagnostics.isEmpty)
    }

    @Test("the reason must be on the discard line or the line directly above it, and must say something")
    func reasonPlacementAndContent() {
        // Arrange
        let source = """
            func makeHandle() -> Task<Void, Never> { Task {} }
            func discards() {
                _ = makeHandle()  // fire-and-forget: trailing reason
                // fire-and-forget: reason directly above
                _ = makeHandle()
                // fire-and-forget: reason separated by a blank line

                _ = makeHandle()
                _ = makeHandle()  // fire-and-forget:
                _ = makeHandle()  // some other comment
                _ = Swift.max(1, 2)
                defer { _ = makeHandle() }  // fire-and-forget: defer cannot await
            }
            """

        // Act
        let diagnostics = lint(source: source)

        // Assert
        #expect(diagnostics.map(\.line) == [8, 9, 10])
    }

    @Test("the index covers module-qualified and optional task results but not stored-handle properties")
    func taskResultTypeShapes() {
        // Arrange
        let source = """
            enum ScanState {
                case running(Task<Void, Never>)
                var task: Task<Void, Never>? {
                    if case .running(let task) = self { return task }
                    return nil
                }
            }
            func qualifiedHandle() -> Swift.Task<Int, Never> { Task { 1 } }
            func optionalHandle() -> Task<Int, Never>? { nil }
            func takeHandleForStop() -> Task<Void, Never>? { nil }
            func discards(state: ScanState) {
                _ = qualifiedHandle()
                _ = optionalHandle()
                _ = state.task
                let handle = takeHandleForStop()
                handle?.cancel()
            }
            """

        // Act
        let diagnostics = lint(source: source)

        // Assert
        #expect(diagnostics.map(\.line) == [12, 13])
    }

    private func lint(source: String) -> [ArchitectureDiagnostic] {
        let context = ArchitectureLintContext(
            path: "Sources/AgentStudio/App/InlineCompletionHandleFixture.swift",
            source: source,
            sourceFile: Parser.parse(source: source)
        )
        return CompletionHandleNotDiscardableRule()
            .prepared(for: [context])
            .validate(context: context)
    }

    private func lint(files: [String]) throws -> [ArchitectureDiagnostic] {
        let contexts = try files.map { file in
            let source = try String(contentsOfFile: file, encoding: .utf8)
            return ArchitectureLintContext(path: file, source: source, sourceFile: Parser.parse(source: source))
        }
        let rule = CompletionHandleNotDiscardableRule().prepared(for: contexts)
        return contexts.flatMap { rule.validate(context: $0) }.filter { $0.ruleID == ruleID }.sorted()
    }

    private func fixtureRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
    }
}
