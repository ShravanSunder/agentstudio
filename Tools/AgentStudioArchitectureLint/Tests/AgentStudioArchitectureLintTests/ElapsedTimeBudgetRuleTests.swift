import Foundation
import Testing

@testable import AgentStudioArchitectureLintCore

/// `agentstudio_no_test_elapsed_time_budget`: every budget shape is flagged in
/// the Bad fixture and none in the Good fixture, production sources are out of
/// scope, and named owners are exempt only by their exact file and fail when
/// stale.
@Suite
struct ElapsedTimeBudgetRuleTests {
    private static let ruleID = "agentstudio_no_test_elapsed_time_budget"

    @Test("flags every executor, Dispatch deadline wait, asyncAfter, and file-wait budget in the Bad fixture")
    func flagsEveryBudgetShapeInTheBadFixture() throws {
        let badDiagnostics = try LintTestSupport.lintFixtureCorpus("Bad").filter {
            $0.ruleID == Self.ruleID && $0.path.hasSuffix("BadTestElapsedTimeBudgetTest.swift")
        }

        #expect(badDiagnostics.map(\.line) == [5, 9, 13, 19, 23, 30, 34, 39])
    }

    @Test("leaves run-to-exit, untimed waits, product timeouts, and unrelated wait(timeout:) alone")
    func leavesPermittedFormsAlone() throws {
        let goodDiagnostics = try LintTestSupport.lintFixtureCorpus("Good").filter { $0.ruleID == Self.ruleID }

        #expect(goodDiagnostics.isEmpty, Comment(rawValue: goodDiagnostics.map(\.rendered).joined()))
    }

    @Test("scopes to test sources and exempts a named owner only by its exact file")
    func scopesToTestSourcesAndExemptsOwnersByFile() {
        let source = """
            func runsScript() async throws {
                _ = try await DefaultProcessExecutor(timeout: 10).execute(
                    command: "bash", args: [], cwd: nil, environment: nil)
            }
            """
        let rule = TestElapsedTimeBudgetRule(
            owners: [ElapsedTimeBudgetOwner(path: "Tests/Support/Owner.swift", owner: "fixture", reason: "fixture")]
        )

        #expect(
            rule.validate(context: LintTestSupport.repositoryContext(path: "Tests/Support/Owner.swift", source: source))
                .isEmpty)
        #expect(
            rule.validate(
                context: LintTestSupport.repositoryContext(path: "Tests/Support/NotOwner.swift", source: source)
            ).count == 1)
        #expect(
            rule.validate(
                context: LintTestSupport.repositoryContext(path: "Sources/AgentStudio/App/Runner.swift", source: source)
            ).isEmpty)
    }

    @Test("an owner that still carries a budget passes; a stale or missing owner fails")
    func ownersFailWhenStaleOrMissing() {
        let rule = TestElapsedTimeBudgetRule(
            owners: [
                ElapsedTimeBudgetOwner(path: "Tests/Support/Current.swift", owner: "current", reason: "fixture"),
                ElapsedTimeBudgetOwner(path: "Tests/Support/Stale.swift", owner: "stale", reason: "fixture"),
                ElapsedTimeBudgetOwner(path: "Tests/Support/Missing.swift", owner: "missing", reason: "fixture"),
            ]
        )
        let current = LintTestSupport.repositoryContext(
            path: "Tests/Support/Current.swift",
            source: "let executor = DefaultProcessExecutor(timeout: 0.5)"
        )
        let stale = LintTestSupport.repositoryContext(
            path: "Tests/Support/Stale.swift",
            source: "func runsToExit() {}"
        )

        let problems = rule.ownerProblems(for: [current, stale])

        #expect(problems.count == 2)
        #expect(problems.contains { $0.message.contains("(stale) no longer carries a budget") })
        #expect(problems.contains { $0.message.contains("Tests/Support/Missing.swift (missing) no longer exists") })
    }
}
