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

    @Test("strict quiescence rejects any cold automatic deadline or source start")
    func strictQuiescenceRejectsColdAutomaticWork() async throws {
        let deadlineSequence = reasonedGitSettlementSequence().replacingOccurrences(
            of: "\"cold_automatic_deadline_count\":0",
            with: "\"cold_automatic_deadline_count\":1"
        )
        let deadlineResult = try await runQuiescenceContract(sequence: deadlineSequence)
        #expect(deadlineResult.exitCode == 1)
        #expect(deadlineResult.stderr.contains("cold automatic deadline"))

        let startSequence = reasonedGitSettlementSequence().replacingOccurrences(
            of: "\"cold_automatic_source_start_count\":0",
            with: "\"cold_automatic_source_start_count\":1"
        )
        let startResult = try await runQuiescenceContract(sequence: startSequence)
        #expect(startResult.exitCode == 1)
        #expect(startResult.stderr.contains("cold automatic source start"))
    }

    @Test("strict quiescence rejects unknown demand or cadence misprojection")
    func strictQuiescenceRejectsUnknownMisprojection() async throws {
        let zeroUnknownSequence = reasonedGitSettlementSequence()
            .replacingOccurrences(of: "\"unknown_worktree_count\":1", with: "\"unknown_worktree_count\":0")
            .replacingOccurrences(
                of: "\"unknown_background_only_count\":1", with: "\"unknown_background_only_count\":0"
            )
            .replacingOccurrences(
                of: "\"git_background_only_automatic_count\":1", with: "\"git_background_only_automatic_count\":0"
            )
            .replacingOccurrences(
                of: "\"git_background_only_deadline_count\":1", with: "\"git_background_only_deadline_count\":0")
        let zeroUnknown = try await runQuiescenceContract(sequence: zeroUnknownSequence)
        #expect(zeroUnknown.exitCode == 1)
        #expect(zeroUnknown.stderr.contains("positive unknown membership"))

        let remoteSequence = try mutateSettlementSequence(
            reasonedGitSettlementSequence()
        ) { _, observation in
            observation["unknown_worktree_count"] = 1
            observation["unknown_background_only_count"] = 1
            observation["unknown_remote_demand_count"] = 1
            observation["unknown_forge_demand_count"] = 0
            observation["git_background_only_automatic_count"] = 1
            observation["git_background_only_deadline_count"] = 1
            observation["git_background_only_visible_tier_count"] = 0
        }
        let remote = try await runQuiescenceContract(sequence: remoteSequence)
        #expect(remote.exitCode == 1)
        #expect(remote.stderr.contains("unknown remote demand"))

        let visibleSequence = try mutateSettlementSequence(
            reasonedGitSettlementSequence()
        ) { _, observation in
            observation["unknown_worktree_count"] = 1
            observation["unknown_background_only_count"] = 1
            observation["unknown_remote_demand_count"] = 0
            observation["unknown_forge_demand_count"] = 0
            observation["git_background_only_automatic_count"] = 1
            observation["git_background_only_deadline_count"] = 1
            observation["git_background_only_visible_tier_count"] = 1
        }
        let visible = try await runQuiescenceContract(sequence: visibleSequence)
        #expect(visible.exitCode == 1)
        #expect(visible.stderr.contains("unknown visible tier"))

        let missingBackgroundSequence = try mutateSettlementSequence(
            reasonedGitSettlementSequence()
        ) { _, observation in
            observation["unknown_worktree_count"] = 1
            observation["unknown_background_only_count"] = 0
            observation["unknown_remote_demand_count"] = 0
            observation["unknown_forge_demand_count"] = 0
            observation["git_background_only_automatic_count"] = 0
            observation["git_background_only_deadline_count"] = 0
            observation["git_background_only_visible_tier_count"] = 0
        }
        let missingBackground = try await runQuiescenceContract(
            sequence: missingBackgroundSequence
        )
        #expect(missingBackground.exitCode == 1)
        #expect(missingBackground.stderr.contains("unknown background classification"))

        let missingSelfHealSequence = try mutateSettlementSequence(
            reasonedGitSettlementSequence()
        ) { _, observation in
            observation["git_background_only_deadline_count"] = 0
            observation["git_background_only_owned_count"] = 0
        }
        let missingSelfHeal = try await runQuiescenceContract(sequence: missingSelfHealSequence)
        #expect(missingSelfHeal.exitCode == 1)
        #expect(missingSelfHeal.stderr.contains("unknown background self-heal ownership"))
    }

    @Test("strict quiescence rejects overdue Git deadlines")
    func strictQuiescenceRejectsOverdueGitDeadlines() async throws {
        let result = try await runQuiescenceContract(
            sequence: reasonedGitSettlementSequence(overdueDeadlineCount: 1)
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("quiescence Git deadline is overdue"))
    }

    @Test("strict quiescence rejects a terminal native proof failure")
    func strictQuiescenceRejectsTerminalProofFailure() async throws {
        let result = try await runQuiescenceContract(
            sequence: reasonedGitSettlementSequence(proofFailureCount: 1)
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("quiescence native proof has failed"))
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
        let baseSequence = reasonedGitSettlementSequence()
        let sequence = try mutateSettlementSequence(baseSequence) { timestamp, observation in
            observation["remote_pending_total"] = 1
            observation["remote_pending_future"] = 1
            observation["remote_next_deadline_ms"] = 180_000 - (timestamp * 1000)
            observation["forge_pending_total"] = 1
            observation["forge_pending_future"] = 1
            observation["forge_next_deadline_ms"] = 180_000 - (timestamp * 1000)
        }
        let result = try await runQuiescenceContract(sequence: sequence)

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
    }

    @Test("strict quiescence accepts bounded running custody with advancing preparation age")
    func strictQuiescenceAcceptsBoundedRunningCustody() async throws {
        let sequence = try mutateSettlementSequence(
            reasonedGitSettlementSequence(
                gitLogicalDebt: 1,
                activeFollowUpCount: 1,
                runningCount: 1
            )
        ) { timestamp, observation in
            observation["git_oldest_preparation_ms"] = timestamp * 1000
        }
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

    @Test("strict quiescence accepts unchanged change-only source settlement samples")
    func strictQuiescenceAcceptsUnchangedSourceSettlementSamples() async throws {
        let sequence = reasonedGitSettlementSequence().replacingOccurrences(
            of: "\"export_sample_time\":",
            with: "\"remote_sample_time\":0,\"forge_sample_time\":0,\"export_sample_time\":"
        )
        let result = try await runQuiescenceContract(sequence: sequence)

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
    }

    @Test("strict quiescence rejects source settlement samples from the future")
    func strictQuiescenceRejectsFutureSourceSettlementSamples() async throws {
        let sequence = reasonedGitSettlementSequence().replacingOccurrences(
            of: "\"export_sample_time\":",
            with: "\"remote_sample_time\":10,\"forge_sample_time\":10,\"export_sample_time\":"
        )
        let result = try await runQuiescenceContract(sequence: sequence)

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("remote settlement sample is from the future"))
    }

    @Test("strict CPU proof rejects any exact-debug descendant even at zero CPU")
    func strictCPUProofRejectsExactDebugDescendants() async throws {
        let rejected = try await runDebugProcessContract(
            records: """
                [
                  {"pid":700,"ppid":1,"cpu":1.0,"command":"AgentStudio Debug"},
                  {"pid":701,"ppid":700,"cpu":0.0,"command":"git fetch origin"},
                  {"pid":702,"ppid":701,"cpu":0.0,"command":"git-remote-https origin"}
                ]
                """
        )
        #expect(rejected.exitCode == 1)
        #expect(rejected.stderr.contains("debug-owned helper remains active"))

        let accepted = try await runDebugProcessContract(
            records: """
                [
                  {"pid":700,"ppid":1,"cpu":1.0,"command":"AgentStudio Debug"},
                  {"pid":801,"ppid":1,"cpu":4.0,"command":"unrelated browser"}
                ]
                """
        )
        #expect(accepted.exitCode == 0, Comment(rawValue: accepted.stderr))
        #expect(accepted.stdout.contains("debug_owned_helper_contract=passed"))
    }

    @Test("continuous sampler rejects a transient descendant between interval endpoints")
    func continuousSamplerRejectsTransientDescendant() async throws {
        let result = try await runSidebarScript(
            arguments: [scriptPath, "--prepare-only"],
            environment: [
                "AGENTSTUDIO_SIDEBAR_ALLOW_TEST_RESPONSES": "1",
                "AGENTSTUDIO_SIDEBAR_TEST_DESCENDANT_POLL_SEQUENCE":
                    "[{\"offset_ms\":0,\"descendant_count\":0},{\"offset_ms\":50,\"descendant_count\":1},{\"offset_ms\":1000,\"descendant_count\":0}]",
            ]
        )
        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("transient debug-owned descendant"))
    }

    @Test("continuous sampler preserves one absolute phase across multiple intervals")
    func continuousSamplerRejectsMultiIntervalDrift() async throws {
        let accepted = try await runSamplerSequenceContract(
            "20000000 1020000000 1.0\n1020000000 2020000000 1.0\n2020000000 3020000000 1.0"
        )
        #expect(accepted.exitCode == 0, Comment(rawValue: accepted.stderr))

        let drifted = try await runSamplerSequenceContract(
            "20000000 1020000000 1.0\n1040000000 2040000000 1.0\n2080000000 3080000000 1.0"
        )
        #expect(drifted.exitCode == 1)
        #expect(drifted.stderr.contains("absolute phase envelope"))
    }

    @Test("strict quiescence rejects missing reasoned Git settlement fields")
    func strictQuiescenceRejectsMissingReasonedGitSettlementFields() async throws {
        let observations = (0...5).map { timestamp in
            """
            {"capture":1,"execution":1,"publication":1,"binding":1,"visible_update":1,"cold_automatic_deadline_count":0,"cold_automatic_source_start_count":0,"git_logical_debt":0,"export_backlog":0,"observation_time":\(timestamp),"export_sample_time":\(timestamp)}
            """
        }
        let result = try await runQuiescenceContract(
            sequence: "[" + observations.joined(separator: ",") + "]"
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("quiescence vector missing unknown_worktree_count"))
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
        proofFailureCount: Int = 0,
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
            let observedNextDeadlineMilliseconds =
                nextDeadlineMilliseconds > 0
                ? nextDeadlineMilliseconds - (timestamp * 1000)
                : 0
            return """
                {"capture":1,"execution":1,"publication":1,"binding":1,"visible_update":1,"cold_automatic_deadline_count":0,"cold_automatic_source_start_count":0,"unknown_worktree_count":1,"unknown_background_only_count":1,"unknown_remote_demand_count":0,"unknown_forge_demand_count":0,"git_logical_debt":\(gitLogicalDebt),"git_future_automatic_count":\(futureAutomaticCount),"git_future_failure_count":\(futureFailureCount),"git_ready_pending_count":\(readyPendingCount),"git_capacity_pending_count":\(capacityPendingCount),"git_active_follow_up_count":\(activeFollowUpCount),"git_unclassified_pending_count":\(unclassifiedPendingCount),"git_overdue_deadline_count":\(overdueDeadlineCount),"git_running_count":\(runningCount),"git_physical_limit":\(physicalLimit),"git_oldest_preparation_ms":\(oldestPreparationMilliseconds),"git_next_deadline_ms":\(observedNextDeadlineMilliseconds),"git_background_only_automatic_count":1,"git_background_only_deadline_count":1,"git_background_only_owned_count":1,"git_background_only_visible_tier_count":0,"remote_physical_active":0,"remote_pending_total":0,"remote_pending_future":0,"remote_pending_ready":0,"remote_pending_capacity":0,"remote_pending_active_follow_up":0,"remote_pending_unclassified":0,"remote_overdue_deadline":0,"remote_next_deadline_ms":0,"remote_physical_limit":1,"forge_physical_active":0,"forge_pending_total":0,"forge_pending_future":0,"forge_pending_ready":0,"forge_pending_capacity":0,"forge_pending_active_follow_up":0,"forge_pending_unclassified":0,"forge_overdue_deadline":0,"forge_next_deadline_ms":0,"forge_physical_limit":2,"git_maximum_settlement_ms":\(maximumSettlementMilliseconds),"export_backlog":0,"proof_failure_count":\(proofFailureCount),"observation_time":\(timestamp),"export_sample_time":\(timestamp)}
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
                "STRICT_POLICY_METRICS_EXPORT_INTERVAL_MS": "60000",
                "STRICT_POLICY_MAXIMUM_SAMPLER_GAP_MS": "1250",
                "STRICT_POLICY_SAMPLE_INTERVAL_MS": "1000",
                "STRICT_FIXTURE_UNKNOWN_WORKTREE_COUNT": "1",
            ]
        )
    }

    private func mutateSettlementSequence(
        _ sequence: String,
        mutation: (Int, inout [String: Any]) -> Void
    ) throws -> String {
        let data = try #require(sequence.data(using: .utf8))
        var observations = try #require(
            JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        )
        for index in observations.indices {
            mutation(index, &observations[index])
        }
        let mutatedData = try JSONSerialization.data(withJSONObject: observations)
        return try #require(String(data: mutatedData, encoding: .utf8))
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

    private func runDebugProcessContract(records: String) async throws -> ProcessResult {
        try await runSidebarScript(
            arguments: [scriptPath, "--prepare-only"],
            environment: [
                "AGENTSTUDIO_SIDEBAR_ALLOW_TEST_RESPONSES": "1",
                "AGENTSTUDIO_SIDEBAR_TEST_DEBUG_PROCESS_RECORDS": records,
                "AGENTSTUDIO_SIDEBAR_TEST_DEBUG_APP_PID": "700",
            ]
        )
    }

    private func runSamplerSequenceContract(_ sequence: String) async throws -> ProcessResult {
        try await runSidebarScript(
            arguments: [scriptPath, "--prepare-only"],
            environment: [
                "AGENTSTUDIO_SIDEBAR_ALLOW_TEST_RESPONSES": "1",
                "AGENTSTUDIO_SIDEBAR_TEST_SAMPLER_SEQUENCE": sequence,
                "STRICT_POLICY_MAXIMUM_SAMPLER_GAP_MS": "1250",
                "STRICT_POLICY_SAMPLE_INTERVAL_MS": "1000",
                "STRICT_POLICY_ACTION_SAMPLE_BOUNDARY_OFFSET_MS": "50",
            ]
        )
    }
}
