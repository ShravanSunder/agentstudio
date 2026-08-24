import Foundation
import Testing

@testable import AgentStudioInfrastructure

@Suite
struct SidebarPerformanceWorkloadSettlementScriptTests {
    @Test("strict quiescence accepts bounded future Git eligibility")
    func strictQuiescenceAcceptsBoundedFutureGitEligibility() async throws {
        let result = try await runQuiescenceContract(
            sequence: reasonedGitSettlementSequence(
                gitLogicalDebt: 86,
                futureAutomaticCount: 86,
                nextDeadlineMilliseconds: 120_000
            )
        )

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        #expect(result.stdout.contains("positive_quiescence=test_contract_passed"))
    }

    @Test("strict quiescence rejects overdue Git deadlines")
    func strictQuiescenceRejectsOverdueGitDeadlines() async throws {
        let result = try await runQuiescenceContract(
            sequence: reasonedGitSettlementSequence(overdueDeadlineCount: 1)
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("quiescence Git deadline is overdue"))
    }

    @Test("strict quiescence rejects Git physical capacity overflow")
    func strictQuiescenceRejectsGitPhysicalCapacityOverflow() async throws {
        let result = try await runQuiescenceContract(
            sequence: reasonedGitSettlementSequence(
                runningCount: 5,
                physicalLimit: 4
            )
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("quiescence Git running count exceeds physical limit"))
    }

    @Test("strict quiescence accepts classified future remote eligibility")
    func strictQuiescenceAcceptsFutureRemoteEligibility() async throws {
        let sequence = reasonedGitSettlementSequence()
            .replacingOccurrences(of: "\"remote_pending_total\":0", with: "\"remote_pending_total\":1")
            .replacingOccurrences(of: "\"remote_pending_future\":0", with: "\"remote_pending_future\":1")
            .replacingOccurrences(of: "\"remote_next_deadline_ms\":0", with: "\"remote_next_deadline_ms\":180000")
        let result = try await runQuiescenceContract(sequence: sequence)

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
    }

    @Test("strict quiescence rejects ready Forge work and broken source classification")
    func strictQuiescenceRejectsReadyForgeAndBrokenClassification() async throws {
        let readySequence = reasonedGitSettlementSequence()
            .replacingOccurrences(of: "\"forge_pending_total\":0", with: "\"forge_pending_total\":1")
            .replacingOccurrences(of: "\"forge_pending_ready\":0", with: "\"forge_pending_ready\":1")
        let ready = try await runQuiescenceContract(sequence: readySequence)
        #expect(ready.exitCode == 1)
        #expect(ready.stderr.contains("quiescence forge ready work remains pending"))

        let inconsistentSequence = reasonedGitSettlementSequence()
            .replacingOccurrences(of: "\"remote_pending_total\":0", with: "\"remote_pending_total\":2")
        let inconsistent = try await runQuiescenceContract(sequence: inconsistentSequence)
        #expect(inconsistent.exitCode == 1)
        #expect(inconsistent.stderr.contains("quiescence remote pending classification is inconsistent"))
    }

    @Test("strict quiescence rejects remote physical capacity overflow")
    func strictQuiescenceRejectsRemotePhysicalCapacityOverflow() async throws {
        let sequence = reasonedGitSettlementSequence()
            .replacingOccurrences(of: "\"remote_physical_active\":0", with: "\"remote_physical_active\":2")
        let result = try await runQuiescenceContract(sequence: sequence)

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("quiescence remote physical count exceeds its limit"))
    }

    @Test("strict quiescence rejects stale remote settlement samples")
    func strictQuiescenceRejectsStaleRemoteSettlementSamples() async throws {
        let sequence = reasonedGitSettlementSequence().replacingOccurrences(
            of: "\"export_sample_time\":",
            with: "\"remote_sample_time\":0,\"forge_sample_time\":0,\"export_sample_time\":"
        )
        let result = try await runQuiescenceContract(sequence: sequence)

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("remote settlement sample is stale"))
    }

    @Test("strict quiescence rejects missing reasoned Git settlement fields")
    func strictQuiescenceRejectsMissingReasonedGitSettlementFields() async throws {
        let observations = (0...5).map { timestamp in
            """
            {"capture":1,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,"export_backlog":0,"observation_time":\(timestamp),"export_sample_time":\(timestamp)}
            """
        }
        let result = try await runQuiescenceContract(
            sequence: "[" + observations.joined(separator: ",") + "]"
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("quiescence vector missing git_future_automatic_count"))
    }

    @Test("strict idle proof requires a periodic Git self-heal completion")
    func strictIdleProofRequiresPeriodicGitSelfHealCompletion() async throws {
        let missingCompletion = try await runPeriodicCompletionContract(baseline: 7, final: 7)
        #expect(missingCompletion.exitCode == 1)
        #expect(
            missingCompletion.stderr.contains(
                "idle population did not observe a periodic Git self-heal completion")
        )

        let completed = try await runPeriodicCompletionContract(baseline: 7, final: 8)
        #expect(completed.exitCode == 0, Comment(rawValue: completed.stderr))
        #expect(completed.stdout.contains("periodic_completion_delta=1"))
    }

    private let scriptPath = "scripts/verify-sidebar-performance-workload.sh"

    private func reasonedGitSettlementSequence(
        gitLogicalDebt: Int = 0,
        futureAutomaticCount: Int = 0,
        futureFailureCount: Int = 0,
        readyPendingCount: Int = 0,
        capacityPendingCount: Int = 0,
        activeFollowUpCount: Int = 0,
        unclassifiedPendingCount: Int = 0,
        overdueDeadlineCount: Int = 0,
        runningCount: Int = 0,
        physicalLimit: Int = 4,
        oldestPreparationMilliseconds: Int = 0,
        nextDeadlineMilliseconds: Int = 0,
        maximumSettlementMilliseconds: Int = 960_000
    ) -> String {
        let observations = (0...5).map { timestamp in
            """
            {"capture":1,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":\(gitLogicalDebt),"git_future_automatic_count":\(futureAutomaticCount),"git_future_failure_count":\(futureFailureCount),"git_ready_pending_count":\(readyPendingCount),"git_capacity_pending_count":\(capacityPendingCount),"git_active_follow_up_count":\(activeFollowUpCount),"git_unclassified_pending_count":\(unclassifiedPendingCount),"git_overdue_deadline_count":\(overdueDeadlineCount),"git_running_count":\(runningCount),"git_physical_limit":\(physicalLimit),"git_oldest_preparation_ms":\(oldestPreparationMilliseconds),"git_next_deadline_ms":\(nextDeadlineMilliseconds),"remote_physical_active":0,"remote_pending_total":0,"remote_pending_future":0,"remote_pending_ready":0,"remote_pending_capacity":0,"remote_pending_active_follow_up":0,"remote_pending_unclassified":0,"remote_overdue_deadline":0,"remote_next_deadline_ms":0,"remote_physical_limit":1,"forge_physical_active":0,"forge_pending_total":0,"forge_pending_future":0,"forge_pending_ready":0,"forge_pending_capacity":0,"forge_pending_active_follow_up":0,"forge_pending_unclassified":0,"forge_overdue_deadline":0,"forge_next_deadline_ms":0,"forge_physical_limit":2,"git_maximum_settlement_ms":\(maximumSettlementMilliseconds),"export_backlog":0,"observation_time":\(timestamp),"export_sample_time":\(timestamp)}
            """
        }
        return "[" + observations.joined(separator: ",") + "]"
    }

    private func runQuiescenceContract(sequence: String) async throws -> ProcessResult {
        try await runSidebarScript(
            arguments: [scriptPath, "--prepare-only"],
            environment: [
                "AGENTSTUDIO_SIDEBAR_ALLOW_TEST_RESPONSES": "1",
                "AGENTSTUDIO_SIDEBAR_TEST_QUIESCENCE_SEQUENCE": sequence,
                "STRICT_POLICY_QUIESCENCE_MS": "5000",
                "STRICT_POLICY_MAXIMUM_SAMPLER_GAP_MS": "1250",
                "STRICT_POLICY_SAMPLE_INTERVAL_MS": "1000",
            ]
        )
    }

    private func runPeriodicCompletionContract(baseline: Int, final: Int) async throws -> ProcessResult {
        try await runSidebarScript(
            arguments: [scriptPath, "--prepare-only"],
            environment: [
                "AGENTSTUDIO_SIDEBAR_ALLOW_TEST_RESPONSES": "1",
                "AGENTSTUDIO_SIDEBAR_TEST_PERIODIC_COMPLETION_BASELINE": String(baseline),
                "AGENTSTUDIO_SIDEBAR_TEST_PERIODIC_COMPLETION_FINAL": String(final),
            ]
        )
    }
}
