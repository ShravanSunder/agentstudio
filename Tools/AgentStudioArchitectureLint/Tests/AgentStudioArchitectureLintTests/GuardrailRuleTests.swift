import Foundation
import SwiftParser
import SwiftSyntax
import Testing

@testable import AgentStudioArchitectureLintCore

/// The guardrail rules added with the debt ledger: the MainActor shapes, the
/// test-hold and wait-helper freezes, blocking-wait owners, and agent-doc
/// references. Each is proven on Good/Bad fixtures or inline sources.
@Suite
struct GuardrailRuleTests {
    @Test(
        "MainActor shape rules flag every Bad fixture site and no Good fixture site",
        arguments: [
            MainActorShapeFixture(
                ruleID: "agentstudio_observation_rearm_guarded",
                badFixture: "Bad/Sources/AgentStudio/App/BadObservationRearm.swift",
                expectedLines: [9, 20, 32, 47, 56, 67, 81],
                goodFixture: "Good/Sources/AgentStudio/App/GoodObservationRearm.swift"
            ),
            MainActorShapeFixture(
                ruleID: "agentstudio_swiftui_body_derivation",
                badFixture: "Bad/Sources/AgentStudio/App/BadSwiftUIBodyDerivation.swift",
                expectedLines: [10, 12, 13, 16, 17, 29],
                goodFixture: "Good/Sources/AgentStudio/App/GoodSwiftUIBodyDerivation.swift"
            ),
            MainActorShapeFixture(
                ruleID: "agentstudio_atom_assign_only",
                badFixture: "Bad/Sources/AgentStudio/Core/State/MainActor/Atoms/BadAtomSideEffects.swift",
                expectedLines: [8, 9, 10, 11, 12, 13, 14, 15, 16, 17],
                goodFixture: "Good/Sources/AgentStudio/Core/State/MainActor/Atoms/GoodAtomAssignOnly.swift"
            ),
            MainActorShapeFixture(
                ruleID: "agentstudio_mainactor_hop_per_element",
                badFixture: "Bad/Sources/AgentStudio/App/BadMainActorHopPerElement.swift",
                expectedLines: [7, 16, 26, 40, 56, 69],
                goodFixture: "Good/Sources/AgentStudio/App/GoodMainActorHopPerElement.swift"
            ),
            MainActorShapeFixture(
                ruleID: "agentstudio_probe_reports_off_main",
                badFixture: "Bad/Sources/AgentStudio/Infrastructure/Diagnostics/BadProbeRecorder.swift",
                expectedLines: [1, 3, 8, 16],
                goodFixture: "Good/Sources/AgentStudio/Infrastructure/Diagnostics/GoodProbeRecorder.swift"
            ),
        ]
    )
    func mainActorShapeRulesSeparateBadFromGoodFixtures(fixture: MainActorShapeFixture) throws {
        let badDiagnostics = try lintFixtureCorpus("Bad").filter {
            $0.ruleID == fixture.ruleID && $0.path.hasSuffix(fixture.badFixture)
        }
        let goodDiagnostics = try lintFixtureCorpus("Good").filter { $0.ruleID == fixture.ruleID }

        #expect(badDiagnostics.map(\.line) == fixture.expectedLines)
        #expect(goodDiagnostics.isEmpty, Comment(rawValue: goodDiagnostics.map(\.rendered).joined()))
    }

    @Test("MainActor shape rules leave test sources alone")
    func mainActorShapeRulesLeaveTestSourcesAlone() {
        let source = """
            @MainActor
            final class ObservingTestHelper {
                var value = 0
                func observe() {
                    withObservationTracking { _ = value } onChange: { self.observe() }
                }
                func drain(stream: AsyncStream<Int>) async {
                    for await element in stream { value = element }
                }
            }
            """
        let testContext = context(path: "Tests/AgentStudioTests/ObservingTestHelper.swift", source: source)
        let sourceContext = context(path: "Sources/AgentStudio/App/ObservingHelper.swift", source: source)

        #expect(ObservationRearmGuardedRule().validate(context: testContext).isEmpty)
        #expect(MainActorHopPerElementRule().validate(context: testContext).isEmpty)
        #expect(ObservationRearmGuardedRule().validate(context: sourceContext).map(\.line) == [5])
        #expect(MainActorHopPerElementRule().validate(context: sourceContext).map(\.line) == [8])
    }

    @Test("ad-hoc gate rule flags gate-named types that store a suspension, outside the harness only")
    func adHocGateRuleFlagsGateNamedSuspensionStorageOutsideHarness() throws {
        let badDiagnostics = try lintFixtureCorpus("Bad").filter {
            $0.ruleID == "agentstudio_test_ad_hoc_gate"
        }
        let goodDiagnostics = try lintFixtureCorpus("Good").filter {
            $0.ruleID == "agentstudio_test_ad_hoc_gate"
                || $0.ruleID == "agentstudio_test_blocking_wait_off_cooperative_pool"
        }

        #expect(badDiagnostics.map(\.line) == [3, 7, 11, 15])
        #expect(badDiagnostics.allSatisfy { $0.path.hasSuffix("Tests/AgentStudioTests/BadAdHocGateTest.swift") })
        #expect(goodDiagnostics.isEmpty, Comment(rawValue: goodDiagnostics.map(\.rendered).joined()))
    }

    @Test("wait helper rule flags async wait helpers that return nothing, outside the harness only")
    func waitHelperRuleFlagsVoidAsyncWaitHelpersOutsideHarness() throws {
        let badDiagnostics = try lintFixtureCorpus("Bad").filter {
            $0.ruleID == "agentstudio_test_wait_helper_returns_observation"
        }
        let goodDiagnostics = try lintFixtureCorpus("Good").filter {
            $0.ruleID == "agentstudio_test_wait_helper_returns_observation"
        }

        #expect(badDiagnostics.map(\.line) == [22, 24, 26])
        #expect(goodDiagnostics.isEmpty, Comment(rawValue: goodDiagnostics.map(\.rendered).joined()))
        #expect(TestWaitHelperReturnsObservationRule.isWaitHelperName("waitUntilIdle"))
        #expect(TestWaitHelperReturnsObservationRule.isWaitHelperName("await"))
        #expect(!TestWaitHelperReturnsObservationRule.isWaitHelperName("waitsForNothing"))
        #expect(!TestWaitHelperReturnsObservationRule.isWaitHelperName("requiredValue"))
    }

    @Test("agent doc references fail for a missing file, anchor, or repository-path token, and nothing else")
    func agentDocReferencesFailForMissingTargetsOnly() throws {
        let badDiagnostics = try lintFixtureCorpus("Bad").filter {
            $0.ruleID == "agentstudio_agent_doc_reference_resolves"
        }
        let goodDiagnostics = try lintFixtureCorpus("Good").filter {
            $0.ruleID == "agentstudio_agent_doc_reference_resolves"
        }

        #expect(badDiagnostics.map(\.line) == [3, 4, 5, 6, 7])
        #expect(badDiagnostics.allSatisfy { $0.path.hasSuffix("/Fixtures/Bad/AGENTS.md") })
        #expect(badDiagnostics[0].message.contains("docs/plans/missing.md does not exist"))
        #expect(badDiagnostics[1].message.contains("#absent-heading"))
        #expect(badDiagnostics[3].message.contains("Sources/AgentStudio/Gone.swift:12 does not exist"))
        #expect(goodDiagnostics.isEmpty, Comment(rawValue: goodDiagnostics.map(\.rendered).joined()))
    }

    @Test("agent doc references cannot resolve outside the repository")
    func agentDocReferencesCannotResolveOutsideRepository() throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentDocReferenceRuleTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let workspaceRoot = fixtureRoot.appendingPathComponent("repository", isDirectory: true)
        let documentDirectory = workspaceRoot.appendingPathComponent("docs/nested", isDirectory: true)
        let externalTarget = fixtureRoot.appendingPathComponent("outside.md")
        let externalSymlink = documentDirectory.appendingPathComponent("external.md")
        let relativeTarget = documentDirectory.appendingPathComponent("related.md")
        let repositoryRootTarget = workspaceRoot.appendingPathComponent("docs/repository-guide.md")
        try FileManager.default.createDirectory(at: documentDirectory, withIntermediateDirectories: true)
        try Data().write(to: externalTarget)
        try Data().write(to: relativeTarget)
        try Data().write(to: repositoryRootTarget)
        try FileManager.default.createSymbolicLink(at: externalSymlink, withDestinationURL: externalTarget)

        let markdown = """
            [absolute external](\(externalTarget.path))
            [parent escape](../../../outside.md)
            [symlink escape](external.md)
            [home path](~/outside.md)
            [document relative](related.md)
            [repository rooted](docs/repository-guide.md)
            """
        let document = AgentDocumentContext(
            path: documentDirectory.appendingPathComponent(AgentDocumentContext.fileName).path,
            contents: markdown,
            workspaceRootPath: workspaceRoot.path
        )

        let diagnostics = AgentDocReferenceRule().validate(document: document)

        #expect(diagnostics.map(\.line) == [1, 2, 3, 4])
        #expect(diagnostics.count == 4)
        #expect(diagnostics.allSatisfy { $0.message.contains("points outside the repository") })
        #expect(diagnostics.allSatisfy { !$0.message.contains("does not exist") })
    }

    @Test(
        "heading anchors follow GitHub slug rules",
        arguments: [
            ("Testing Architecture — When a run is red", "testing-architecture--when-a-run-is-red"),
            ("7. Key Files", "7-key-files"),
            ("Use `mise run lint` (fast)", "use-mise-run-lint-fast"),
            ("Need An Atom?", "need-an-atom"),
            ("[Linked](docs/x.md) heading", "linked-heading"),
            ("snake_case stays", "snake_case-stays"),
        ]
    )
    func headingAnchorsFollowGitHubSlugRules(heading: String, slug: String) {
        #expect(MarkdownReferenceScan.gitHubSlug(heading) == slug)
    }

    @Test("blocking-wait owners: a current owner passes, a stale or missing owner fails")
    func blockingWaitOwnersFailWhenStaleOrMissing() throws {
        let owners = [
            BlockingWaitOwner(path: "Tests/Support/Current.swift", owner: "current", reason: "blocks off the pool"),
            BlockingWaitOwner(path: "Tests/Support/Stale.swift", owner: "stale", reason: "used to block"),
            BlockingWaitOwner(path: "Tests/Support/Gone.swift", owner: "gone", reason: "was deleted"),
        ]
        let current = repositoryContext(
            path: "Tests/Support/Current.swift",
            source: """
                import Foundation

                func runOffPool(_ work: @escaping @Sendable () -> Void) {
                    let done = DispatchSemaphore(value: 0)
                    DispatchQueue.global().async {
                        work()
                        done.signal()
                    }
                    done.wait()
                }
                """
        )
        let stale = repositoryContext(
            path: "Tests/Support/Stale.swift",
            source: "func runOffPool(_ work: () -> Void) { work() }"
        )

        let problems = TestBlockingWaitOffCooperativePoolRule(owners: owners)
            .ownerProblems(for: [current, stale])

        #expect(problems.map(\.path) == ["/repo/Tests/Support/Stale.swift", "Tests/Support/Gone.swift"])
        #expect(problems[0].message.contains("no longer contains a blocking wait"))
        #expect(problems[1].message.contains("no longer exists"))
        #expect(problems.allSatisfy { $0.ruleID == "agentstudio_test_blocking_wait_off_cooperative_pool" })
    }

    @Test("blocking-wait owners are exempt only by their exact file")
    func blockingWaitOwnersAreExemptOnlyByTheirFile() {
        let owners = [BlockingWaitOwner(path: "Tests/Support/Owner.swift", owner: "owner", reason: "hops")]
        let source = """
            import Foundation

            func blocks() {
                let done = DispatchSemaphore(value: 0)
                done.wait()
            }
            """
        let rule = TestBlockingWaitOffCooperativePoolRule(owners: owners)

        #expect(rule.validate(context: repositoryContext(path: "Tests/Support/Owner.swift", source: source)).isEmpty)
        #expect(
            rule.validate(context: repositoryContext(path: "Tests/Support/NotOwner.swift", source: source)).count == 1)
        #expect(
            rule.validate(
                context: repositoryContext(path: "Tests/AgentStudioTestHarness/HeldStep.swift", source: source)
            ).count == 1)
    }

    private func lintFixtureCorpus(_ corpus: String) throws -> [ArchitectureDiagnostic] {
        try LintTestSupport.lintFixtureCorpus(corpus)
    }

    private func context(path: String, source: String) -> ArchitectureLintContext {
        LintTestSupport.context(path: path, source: source)
    }

    private func repositoryContext(path: String, source: String) -> ArchitectureLintContext {
        LintTestSupport.repositoryContext(path: path, source: source)
    }
}

struct MainActorShapeFixture: Sendable, CustomTestStringConvertible {
    let ruleID: String
    let badFixture: String
    let expectedLines: [Int]
    let goodFixture: String

    var testDescription: String { ruleID }
}
