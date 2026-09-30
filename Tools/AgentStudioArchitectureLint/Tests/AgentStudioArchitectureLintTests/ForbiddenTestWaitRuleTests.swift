import Testing

@testable import AgentStudioArchitectureLintCore

@Suite("Forbidden test wait rule")
struct ForbiddenTestWaitRuleTests {
    @Test("calls, optional calls, function references and aliases are diagnosed")
    func detectsCallsAndResolvableReferences() {
        let context = LintTestSupport.repositoryContext(
            path: "Tests/AgentStudioTests/ForbiddenWaitExamples.swift",
            source: """
                func scenario() async {
                    waitUntilIdle()
                    owner.waitUntilIdle()
                    owner?.waitUntilIdle()
                    let reference = assertEventuallyAsync
                    let alias = reference
                    alias()
                    await assertEventuallyMain()
                }
                """
        )

        let diagnostics = ForbiddenTestWaitRule().validate(context: context)

        #expect(diagnostics.count == 7)
        #expect(diagnostics.allSatisfy { $0.ruleID == "agentstudio_no_forbidden_test_wait" })
        #expect(diagnostics.contains { $0.line == 7 })
    }

    @Test("comments, strings and declarations do not become test wait sites")
    func ignoresNonExpressionsAndProduction() {
        let testContext = LintTestSupport.repositoryContext(
            path: "Tests/AgentStudioTests/GoodFixture.swift",
            source: """
                // waitUntilIdle()
                let fixture = "assertEventuallyMain()"
                func waitUntilIdle() {}
                """
        )
        let productionContext = LintTestSupport.repositoryContext(
            path: "Sources/AgentStudio/Core/Production.swift",
            source: "func work() { waitUntilIdle() }"
        )

        #expect(ForbiddenTestWaitRule().validate(context: testContext).isEmpty)
        #expect(ForbiddenTestWaitRule().validate(context: productionContext).isEmpty)
    }

    @Test("a local alias does not taint the same name in another function")
    func aliasResolutionStaysInItsScope() {
        let context = LintTestSupport.repositoryContext(
            path: "Tests/AgentStudioTests/AliasScopes.swift",
            source: """
                func first() {
                    let callback = waitUntilIdle
                    callback()
                }
                func second(unrelated: () -> Void) {
                    let callback = unrelated
                    callback()
                }
                """
        )

        let diagnostics = ForbiddenTestWaitRule().validate(context: context)

        #expect(diagnostics.map(\.line) == [2, 3])
    }

    @Test("the existing polling rule still exempts for await streams")
    func streamingLoopRemainsAllowed() {
        let context = LintTestSupport.repositoryContext(
            path: "Tests/AgentStudioTests/StreamFixture.swift",
            source: "func observe() async { for await fact in facts { consume(fact) } }"
        )

        #expect(TestPollingWaitRule().validate(context: context).isEmpty)
        #expect(ForbiddenTestWaitRule().validate(context: context).isEmpty)
    }
}
