import Foundation
import SwiftParser
import Testing

@testable import AgentStudioArchitectureLintCore

@Suite
struct CompletionHandleNotDiscardableRuleTests {
    private let ruleID = "agentstudio_completion_handle_not_discardable"

    @Test("bad fixture reports the discardable declaration, every reasonless discard, and the non-task twin")
    func badFixtureReportsEveryPredicate() throws {
        // Arrange
        let fixture = fixtureRoot().appendingPathComponent(
            "Bad/Sources/AgentStudio/App/BadCompletionHandleDiscard.swift"
        )
        let discard = CompletionHandleNotDiscardableRule.reasonlessDiscardMessage

        // Act
        let diagnostics = try lint(files: [fixture.path])

        // Assert
        #expect(diagnostics.map(\.line) == [3, 13, 14, 15, 21, 22, 27, 34])
        #expect(
            diagnostics.map(\.message) == [
                CompletionHandleNotDiscardableRule.discardableDeclarationMessage,
                discard,
                discard,
                discard,
                discard,
                discard,
                CompletionHandleNotDiscardableRule.nonTaskTwinMessage(name: "submit"),
                discard,
            ])
        #expect(diagnostics.allSatisfy { $0.severity == .error })
    }

    @Test("good fixture accepts awaited outcomes, stored handles, and reasoned direct, optional, and wrapped discards")
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

    @Test("the twin predicate spans files, so the index is built over the whole linted tree")
    func twinPredicateSpansFiles() {
        // Arrange
        let taskOwner = """
            final class HandleOwner {
                func teardown() -> Task<Bool, Never> { Task { true } }
            }
            """
        let twinOwner = """
            final class StreamLifecycle {
                private func teardown() {}
                func stop() { teardown() }
            }
            """

        // Act
        let diagnostics = lint(sources: [taskOwner, twinOwner])

        // Assert
        #expect(diagnostics.map(\.path) == ["Sources/AgentStudio/App/Inline1.swift"])
        #expect(diagnostics.map(\.line) == [2])
        #expect(diagnostics.map(\.message) == [CompletionHandleNotDiscardableRule.nonTaskTwinMessage(name: "teardown")])
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
        lint(sources: [source])
    }

    private func lint(sources: [String]) -> [ArchitectureDiagnostic] {
        let contexts = sources.enumerated().map { index, source in
            ArchitectureLintContext(
                path: "Sources/AgentStudio/App/Inline\(index).swift",
                source: source,
                sourceFile: Parser.parse(source: source)
            )
        }
        let rule = CompletionHandleNotDiscardableRule().prepared(for: contexts)
        return contexts.flatMap { rule.validate(context: $0) }.sorted()
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
