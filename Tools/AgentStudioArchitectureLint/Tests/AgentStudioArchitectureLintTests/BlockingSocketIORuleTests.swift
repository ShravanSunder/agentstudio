import Foundation
import Testing

@testable import AgentStudioArchitectureLintCore

@Suite("Blocking socket I/O rule")
struct BlockingSocketIORuleTests {
    private static let ruleID = "agentstudio_no_blocking_socket_io_in_tests"

    @Test("raw connect send receive and synchronous request and frame wrappers are diagnosed")
    func rejectsBlockingSocketShapes() throws {
        let fixture = LintTestSupport.fixtureRoot().appendingPathComponent(
            "Bad/Tests/AgentStudioTests/BadBlockingSocketIO.swift")
        let context = LintTestSupport.repositoryContext(
            path: "Tests/AgentStudioTests/BadBlockingSocketIO.swift",
            source: try String(contentsOf: fixture, encoding: .utf8))
        let diagnostics = lint([context])
        #expect(diagnostics.map(\.line) == [4, 5, 6, 7, 8, 9, 10, 11, 15, 16])
        #expect(diagnostics.allSatisfy { $0.ruleID == Self.ruleID && $0.severity == .error })
    }

    @Test("canonical hops and typed dispatch thread and listener contexts stay clean")
    func permitsTypedOffPoolContexts() throws {
        let fixture = LintTestSupport.fixtureRoot().appendingPathComponent(
            "Good/Tests/AgentStudioTests/GoodBlockingSocketIO.swift")
        let context = LintTestSupport.repositoryContext(
            path: "Tests/AgentStudioTests/GoodBlockingSocketIO.swift",
            source: try String(contentsOf: fixture, encoding: .utf8))
        #expect(lint([context]).isEmpty)
    }

    @Test("the error rule is registered")
    func registersTheSocketGuardrail() {
        #expect(ArchitectureRuleRegistry.rules.contains { $0.id == Self.ruleID && $0.severity == .error })
    }

    private func lint(_ contexts: [ArchitectureLintContext]) -> [ArchitectureDiagnostic] {
        let rule = ArchitectureRuleRegistry.rules.first { $0.id == Self.ruleID }?.prepared(for: contexts)
        return contexts.flatMap { rule?.validate(context: $0) ?? [] }
    }
}
