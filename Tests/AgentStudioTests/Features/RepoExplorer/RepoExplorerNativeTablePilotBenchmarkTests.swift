// This suite lives in its own file, not alongside `RepoExplorerNativeTablePilotTests`: `swift
// test --filter`/`--skip` also match a test's declaring file's basename, so a suite sharing
// `RepoExplorerNativeTablePilotTests.swift` would be swept back into the PR-gated fast lane.
import Dispatch
import Foundation
import Testing

@testable import AgentStudioRepoExplorer
@testable import AgentStudioTestSupport

@MainActor
@Suite("Repo Explorer native table pilot benchmark", .serialized)
struct RepoExplorerNativeTablePilotBenchmarkTests {
    @Test("fixed production pilot passes p95 and growth policy")
    func fixedProductionPilotPassesTimingPolicy() async {
        let result = await RepoExplorerNativeTablePilot.run(performanceTraceRecorder: nil)
        print(
            "REPO_EXPLORER_NATIVE_TABLE_PILOT_RESULT "
                + "baseline_p95_ms=\(result.baselineMembershipP95Milliseconds) "
                + "doubled_p95_ms=\(result.doubledMembershipP95Milliseconds) "
                + "growth_percent=\(result.doubledOffscreenGrowthPercent)"
        )
        #expect(result.passed)
        #expect(result.failureReason == nil)
        #expect(result.baselineMembershipP95Milliseconds <= 4)
        #expect(result.doubledMembershipP95Milliseconds <= 4)
        #expect(result.doubledOffscreenGrowthPercent <= 20)
    }
}
