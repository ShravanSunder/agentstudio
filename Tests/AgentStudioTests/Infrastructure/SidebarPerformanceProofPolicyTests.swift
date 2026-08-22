import Testing

@testable import AgentStudioInfrastructure

@Suite("Sidebar performance proof policy")
struct SidebarPerformanceProofPolicyTests {
    @Test("native table pilot policy is immutable and centrally owned")
    func nativeTablePilotPolicyIsImmutableAndCentrallyOwned() {
        #expect(AppPolicies.SidebarPerformanceProof.repositoryCount == 150)
        #expect(AppPolicies.SidebarPerformanceProof.worktreeCount == 180)
        #expect(AppPolicies.SidebarPerformanceProof.tabCount == 12)
        #expect(AppPolicies.SidebarPerformanceProof.paneCount == 36)
        #expect(AppPolicies.SidebarPerformanceProof.doubledWorktreeCount == 360)
        #expect(AppPolicies.SidebarPerformanceProof.representedRowCount == 24)
        #expect(AppPolicies.SidebarPerformanceProof.warmupTransactionCountPerScale == 20)
        #expect(AppPolicies.SidebarPerformanceProof.measuredTransactionCountPerScale == 200)
        #expect(AppPolicies.SidebarPerformanceProof.maximumMembershipP95Milliseconds == 4.0)
        #expect(AppPolicies.SidebarPerformanceProof.maximumDoubledOffscreenGrowthPercent == 20.0)
        #expect(AppPolicies.SidebarPerformanceProof.nativeTablePilotCompletionTimeout == .seconds(30))
        #expect(
            AppPolicies.SidebarPerformanceProof.scaleWorktreeCounts == [180, 360]
        )
        #expect(AppPolicies.SidebarPerformanceProof.invalidatesWholePopulationOnFailure)
        #expect(AppPolicies.SidebarPerformanceProof.nativeTablePilotPolicyID == "sidebar-native-table-pilot")
        #expect(AppPolicies.SidebarPerformanceProof.nativeTablePilotPolicyVersion == 1)
    }
}
