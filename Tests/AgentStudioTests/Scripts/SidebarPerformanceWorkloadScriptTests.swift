import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioInfrastructure

@Suite
struct SidebarPerformanceWorkloadScriptTests {
    @Test("strict sidebar driver consumes projected policy and rejects false green populations")
    func strictSidebarDriverConsumesProjectedPolicyAndRejectsFalseGreenPopulations() throws {
        let source = try String(contentsOfFile: scriptPath, encoding: .utf8)

        #expect(source.contains("strict_sidebar_policy_query"))
        #expect(source.contains("load_strict_sidebar_policy"))
        #expect(source.contains("zero_pty_idle"))
        #expect(source.contains("quiescent_pty_idle"))
        #expect(source.contains("search_clear"))
        #expect(source.contains("grouping"))
        #expect(source.contains("hide_show"))
        #expect(source.contains("tab_switch"))
        #expect(source.contains("positive_quiescence"))
        #expect(source.contains("agentstudio_performance_trace_queue_pending_request_count"))
        #expect(source.contains("stage=\\\"materialize\\\",outcome=\\\"materialized\\\""))
        #expect(source.contains("--data-urlencode \"time=$evaluation_time\""))
        #expect(source.contains("semantic_generation"))
        #expect(source.contains("acknowledged_revision"))
        #expect(source.contains("visible_generation"))
        #expect(source.contains("focus_disposition"))
        #expect(source.contains("accessibility_disposition"))
        #expect(source.contains("population_invalidated"))
        #expect(source.contains("sampler_gap"))
        #expect(source.contains("diagnostic_cpu_p95_delta_percentage_points"))
        #expect(source.contains("diagnostic_interaction_p95_growth_percent"))
        #expect(!source.contains("MAXIMUM_PROCESS_CPU_PERCENT=30"))
        #expect(!source.contains("AGENTSTUDIO_SIDEBAR_IDLE_P99"))
        #expect(!source.contains("AGENTSTUDIO_SIDEBAR_ACTION_P95"))
    }

    @Test("strict sidebar populations are isolated and descriptor driven")
    func strictSidebarPopulationsAreIsolatedAndDescriptorDriven() throws {
        let source = try String(contentsOfFile: scriptPath, encoding: .utf8)
        for owner in [
            "parse_strict_sidebar_policy", "run_strict_sidebar_cpu_populations",
            "begin_strict_population", "validate_strict_host_envelope",
            "wait_for_positive_quiescence", "sample_strict_idle_population",
            "drive_strict_action_population", "validate_strict_population",
            "validate_strict_perturbation_pair", "validate_strict_zero_loss",
            "nearest_rank_percentile",
        ] { #expect(source.contains(owner)) }
        #expect(source.contains("STRICT_POLICY_MAXIMUM_SAMPLER_GAP_MS"))
        #expect(source.contains("validate_strict_sampler_gaps"))
        #expect(source.contains("record_strict_cpu_sample"))
        #expect(source.contains("cpu.raw.samples"))
        #expect(source.contains("classify_strict_action_samples"))
        #expect(source.contains("query_strict_action_records"))
        #expect(source.contains("duplicate action record"))
        #expect(source.contains("overlaps or is non-monotonic"))
        #expect(source.contains("strict_required_record_loss"))
        #expect(source.contains("kern.memorystatus_vm_pressure_level"))
        #expect(source.contains("/usr/bin/vm_stat"))
        #expect(!source.contains("vm.compressor_mode"))
        #expect(source.contains("forbidden concurrent process"))
        #expect(source.contains("population_invalidated"))
        #expect(source.contains("no sample replacement or trimming"))
        #expect(source.contains("action population terminal did not satisfy both floors"))
        #expect(!source.contains("STRICT_IDLE_P99=10"))
        #expect(!source.contains("STRICT_ACTION_P95=20"))
        #expect(!source.contains("STRICT_IDLE_SAMPLE_COUNT=1000"))
        #expect(!source.contains("STRICT_ACTION_SAMPLE_COUNT=200"))
        let strictLossCaptureStart = try #require(
            source.range(of: "capture_strict_population_loss() {")
        )
        let strictLossCaptureEnd = try #require(
            source.range(
                of: "wait_for_positive_quiescence() {",
                range: strictLossCaptureStart.upperBound..<source.endIndex
            )
        )
        let strictLossCapture = source[
            strictLossCaptureStart.lowerBound..<strictLossCaptureEnd.lowerBound
        ]
        #expect(!strictLossCapture.contains("collector_loss_count=0"))
        #expect(!strictLossCapture.contains("trace_loss:-0"))
        let populationStart = try #require(source.range(of: "begin_strict_population() {"))
        let populationEnd = try #require(
            source.range(
                of: "sample_strict_idle_population() {",
                range: populationStart.upperBound..<source.endIndex
            )
        )
        let populationSource = source[
            populationStart.lowerBound..<populationEnd.lowerBound
        ]
        let samplerArm = try #require(populationSource.range(of: "start_strict_action_sampler"))
        let quiescence = try #require(populationSource.range(of: "wait_for_positive_quiescence"))
        let hostValidation = try #require(populationSource.range(of: "validate_strict_host_envelope"))
        let hostMonitorStart = try #require(
            populationSource.range(of: "start_strict_host_envelope_monitor")
        )
        #expect(hostValidation.lowerBound < hostMonitorStart.lowerBound)
        #expect(hostMonitorStart.lowerBound < samplerArm.lowerBound)
        #expect(samplerArm.lowerBound < quiescence.lowerBound)
        #expect(source.contains("start_strict_host_envelope_monitor"))
        #expect(source.contains("stop_strict_host_envelope_monitor"))
        #expect(source.contains("HOST_ENVELOPE_MONITOR_PID"))
        #expect(source.contains("population_invalidated=host_envelope"))
    }

    @Test("strict quiescence rejects missing and empty stage vectors")
    func strictQuiescenceRejectsMissingAndEmptyStageVectors() async throws {
        let missingObservations = (0...5).map { timestamp in
            """
            {"capture":1,"execution":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":\(timestamp),"export_sample_time":\(timestamp)}
            """
        }
        let missing = try await runQuiescenceContract(
            sequence: "[" + missingObservations.joined(separator: ",") + "]"
        )
        #expect(missing.exitCode == 1)
        #expect(missing.stderr.contains("quiescence vector missing publication"))

        let emptyObservations = (0...5).map { timestamp in
            """
            {"capture":1,"execution":"","publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":\(timestamp),"export_sample_time":\(timestamp)}
            """
        }
        let empty = try await runQuiescenceContract(
            sequence: "[" + emptyObservations.joined(separator: ",") + "]"
        )
        #expect(empty.exitCode == 1)
        #expect(empty.stderr.contains("quiescence vector empty execution"))
    }

    @Test("strict metric observation parser binds values to one requested timestamp")
    func strictMetricObservationParserBindsValuesToRequestedTimestamp() async throws {
        let accepted = try await runMetricObservationContract(
            response: #"{"status":"success","data":{"result":[{"value":[123.5,"7"]}]}}"#,
            observationTime: "123.5"
        )
        #expect(accepted.exitCode == 0, Comment(rawValue: accepted.stderr))
        #expect(accepted.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "7")

        let stale = try await runMetricObservationContract(
            response: #"{"status":"success","data":{"result":[{"value":[122.5,"7"]}]}}"#,
            observationTime: "123.5"
        )
        #expect(stale.exitCode == 1)
        #expect(stale.stderr.contains("not bound to the requested observation time"))

        let empty = try await runMetricObservationContract(
            response: #"{"status":"success","data":{"result":[]}}"#,
            observationTime: "123.5"
        )
        #expect(empty.exitCode == 1)
        #expect(empty.stderr.contains("expected one result, got 0"))
    }

    @Test("strict quiescence rejects a stale export backlog sample")
    func strictQuiescenceRejectsStaleExportBacklogSample() async throws {
        let observations = (0...5).map { timestamp in
            """
            {"capture":1,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":\(timestamp),"export_sample_time":0}
            """
        }
        let result = try await runQuiescenceContract(
            sequence: "[" + observations.joined(separator: ",") + "]"
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("export backlog sample is stale"))
    }

    @Test("strict quiescence rejects changing stages and export backlog")
    func strictQuiescenceRejectsChangingStagesAndExportBacklog() async throws {
        let readyGitDebt = try await runQuiescenceContract(
            sequence: """
                [
                  {"capture":1,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":1,"git_future_automatic_count":0,"git_future_failure_count":0,"git_ready_pending_count":1,"git_capacity_pending_count":0,"git_active_follow_up_count":0,"git_unclassified_pending_count":0,"git_overdue_deadline_count":0,"git_running_count":0,"git_physical_limit":4,"git_oldest_preparation_ms":0,"git_next_deadline_ms":0,"git_maximum_settlement_ms":960000,"export_backlog":0,"observation_time":0,"export_sample_time":0},
                  {"capture":1,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":1,"export_sample_time":1},
                  {"capture":1,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":2,"export_sample_time":2},
                  {"capture":1,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":3,"export_sample_time":3},
                  {"capture":1,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":4,"export_sample_time":4},
                  {"capture":1,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":5,"export_sample_time":5}
                ]
                """
        )
        #expect(readyGitDebt.exitCode == 1)
        #expect(readyGitDebt.stderr.contains("quiescence Git ready work remains pending"))

        let changingStage = try await runQuiescenceContract(
            sequence: """
                [
                  {"capture":1,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":0,"export_sample_time":0},
                  {"capture":1,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":1,"export_sample_time":1},
                  {"capture":2,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":2,"export_sample_time":2},
                  {"capture":2,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":3,"export_sample_time":3},
                  {"capture":2,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":4,"export_sample_time":4},
                  {"capture":2,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":5,"export_sample_time":5},
                  {"capture":2,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":6,"export_sample_time":6}
                ]
                """
        )
        #expect(changingStage.exitCode == 1)
        #expect(changingStage.stderr.contains("quiescence vector changed during required interval"))

        let changingBacklog = try await runQuiescenceContract(
            sequence: """
                [
                  {"capture":1,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":0,"export_sample_time":0},
                  {"capture":1,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":1,"export_sample_time":1},
                  {"capture":1,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":1,"observation_time":2,"export_sample_time":2},
                  {"capture":1,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":3,"export_sample_time":3},
                  {"capture":1,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":4,"export_sample_time":4},
                  {"capture":1,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":5,"export_sample_time":5}
                ]
                """
        )
        #expect(changingBacklog.exitCode == 1)
        #expect(changingBacklog.stderr.contains("quiescence export backlog must remain zero"))
    }

    @Test("strict quiescence accepts a complete unchanged five-second span")
    func strictQuiescenceAcceptsCompleteUnchangedFiveSecondSpan() async throws {
        let observations = (0...5).map { timestamp in
            """
            {"capture":1,"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":\(timestamp),"export_sample_time":\(timestamp)}
            """
        }
        let result = try await runQuiescenceContract(
            sequence: "[" + observations.joined(separator: ",") + "]"
        )

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        #expect(result.stdout.contains("positive_quiescence=test_contract_passed"))
    }

    @Test("strict quiescence restarts the full interval after a changed stage")
    func strictQuiescenceRestartsFullIntervalAfterChangedStage() async throws {
        let observations = (0...6).map { timestamp in
            let capture = timestamp == 0 ? 1 : 2
            return """
                {"capture":\(capture),"execution":1,"publication":1,"binding":1,"visible_update":1,"git_logical_debt":0,\(settledGitVectorFields),"export_backlog":0,"observation_time":\(timestamp),"export_sample_time":\(timestamp)}
                """
        }
        let result = try await runQuiescenceContract(
            sequence: "[" + observations.joined(separator: ",") + "]"
        )

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        #expect(result.stdout.contains("positive_quiescence=test_contract_passed"))
    }

    @Test("strict population rejects a retained mid-population host breach")
    func strictPopulationRejectsRetainedMidPopulationHostBreach() async throws {
        let result = try await runHostReceiptContract(
            receipts: """
                [
                  {"observation":"initial","observed_at":1,"valid":true},
                  {"observation":"during-1","observed_at":2,"valid":false},
                  {"observation":"during-2","observed_at":3,"valid":true},
                  {"observation":"final","observed_at":4,"valid":true}
                ]
                """
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("host envelope breached at observation 2"))
    }

    @Test("strict population accepts complete valid host receipts")
    func strictPopulationAcceptsCompleteValidHostReceipts() async throws {
        let result = try await runHostReceiptContract(
            receipts: """
                [
                  {"observation":"initial","observed_at":1,"valid":true},
                  {"observation":"during-1","observed_at":2,"valid":true},
                  {"observation":"during-2","observed_at":3,"valid":true},
                  {"observation":"final","observed_at":4,"valid":true}
                ]
                """
        )

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        #expect(result.stdout.contains("host_envelope_receipt_count=4"))
    }

    @Test("resident agent hosts are allowed when the normalized CPU envelope is valid")
    func residentAgentHostsAreAllowedInsideValidCPUEnvelope() async throws {
        let result = try await runHostProcessContract(
            records: """
                [
                  {"pid":101,"ppid":1,"cpu":4.0,"command":"/Applications/Codex.app/Contents/MacOS/Codex"},
                  {"pid":102,"ppid":1,"cpu":3.0,"command":"claude --resume"},
                  {"pid":103,"ppid":1,"cpu":2.0,"command":"gemini --model pro"}
                ]
                """
        )

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        #expect(result.stdout.contains("host_process_contract=passed"))
    }

    @Test("resident zero CPU profiler daemons are allowed")
    func residentZeroCPUProfilerDaemonsAreAllowed() async throws {
        let result = try await runHostProcessContract(
            records: """
                [
                  {"pid":201,"ppid":1,"cpu":0.0,"command":"/usr/sbin/spindump"}
                ]
                """
        )

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        #expect(result.stdout.contains("host_process_contract=passed"))
    }

    @Test("build test compiler and profiler contamination is rejected")
    func activeBuildTestCompilerAndProfilerContaminationIsRejected() async throws {
        for command in [
            "swift-frontend -frontend -c Sources/App.swift",
            "xcodebuild -scheme AgentStudio test",
            "mise run test:swift",
            "Instruments -t Time Profiler AgentStudio",
        ] {
            let result = try await runHostProcessContract(
                records: """
                    [{"pid":201,"ppid":1,"cpu":1.0,"command":"\(command)"}]
                    """
            )

            #expect(result.exitCode == 1, Comment(rawValue: "command: \(command)\n\(result.stdout)"))
            #expect(result.stderr.contains("forbidden concurrent process"))
        }
    }

    @Test("strict zmx reducer accepts only the declared zero and one session lifecycles")
    func strictZmxReducerAcceptsOnlyDeclaredZeroAndOneSessionLifecycles() async throws {
        for sequence in [
            """
            [{"phase":"ready","count":0},{"phase":"quiescent","count":0},{"phase":"complete","count":0},{"phase":"retired","count":0}]
            """,
            """
            [{"phase":"ready","count":0},{"phase":"quiescent","count":1,"clients":1},{"phase":"complete","count":1,"clients":1},{"phase":"retired","count":0}]
            """,
        ] {
            let result = try await runZmxStateContract(sequence: sequence)
            #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
            #expect(result.stdout.contains("zmx_state_contract=passed"))
        }
    }

    @Test("strict zmx reducer fails closed on listing transition count and client breaches")
    func strictZmxReducerRejectsEveryLifecycleBreach() async throws {
        let invalidSequences = [
            """
            [{"phase":"ready","list_error":true},{"phase":"quiescent","count":0},{"phase":"complete","count":0},{"phase":"retired","count":0}]
            """,
            """
            [{"phase":"ready","count":0},{"phase":"quiescent","count":2,"clients":1},{"phase":"complete","count":1,"clients":1},{"phase":"retired","count":0}]
            """,
            """
            [{"phase":"ready","count":1,"clients":1},{"phase":"quiescent","count":0},{"phase":"complete","count":0},{"phase":"retired","count":0}]
            """,
            """
            [{"phase":"ready","count":0},{"phase":"quiescent","count":1,"clients":2},{"phase":"complete","count":1,"clients":1},{"phase":"retired","count":0}]
            """,
        ]

        for sequence in invalidSequences {
            let result = try await runZmxStateContract(sequence: sequence)
            #expect(result.exitCode == 1, Comment(rawValue: result.stdout))
            #expect(result.stderr.contains("zmx state contract failed"))
        }
    }

    @Test("strict workload receipt requires a complete zero delta")
    func strictWorkloadReceiptRequiresCompleteZeroDelta() async throws {
        let result = try await runWorkloadReceiptContract(
            receipt: """
                {
                  "baseline":{"terminal_input":7,"terminal_output":11,"ordered_command":13},
                  "completion":{"terminal_input":7,"terminal_output":11,"ordered_command":13}
                }
                """
        )

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        #expect(result.stdout.contains("workload_receipt_contract=passed"))
    }

    @Test("strict workload receipt rejects missing reset dropped and nonzero evidence")
    func strictWorkloadReceiptRejectsInvalidEvidence() async throws {
        let invalidReceipts = [
            #"{"completion":{"terminal_input":1,"terminal_output":1,"ordered_command":1}}"#,
            #"{"baseline":{"terminal_input":2,"terminal_output":2,"ordered_command":2},"completion":{"terminal_input":1,"terminal_output":2,"ordered_command":2}}"#,
            #"{"baseline":{"terminal_input":2,"terminal_output":2,"ordered_command":2},"completion":{"terminal_input":2,"terminal_output":2,"ordered_command":2,"dropped":1}}"#,
            #"{"baseline":{"terminal_input":2,"terminal_output":2,"ordered_command":2},"completion":{"terminal_input":2,"terminal_output":3,"ordered_command":2}}"#,
        ]

        for receipt in invalidReceipts {
            let result = try await runWorkloadReceiptContract(receipt: receipt)
            #expect(result.exitCode == 1, Comment(rawValue: result.stdout))
            #expect(result.stderr.contains("workload receipt contract failed"))
        }
    }

    @Test("native table pilot verifier consumes projected policy without overrides")
    func nativeTablePilotVerifierConsumesProjectedPolicyWithoutOverrides() async throws {
        let pilotScriptPath = "scripts/verify-sidebar-native-table-pilot.sh"
        let syntax = try await runSidebarScript(arguments: ["-n", pilotScriptPath])
        #expect(syntax.exitCode == 0, Comment(rawValue: syntax.stderr))

        let source = try String(contentsOfFile: pilotScriptPath, encoding: .utf8)
        let miseConfig = try String(contentsOfFile: ".mise.toml", encoding: .utf8)

        #expect(source.contains("sidebar-performance-proof"))
        #expect(source.contains("performance.repo_explorer.native_table_pilot"))
        #expect(source.contains("agent.proof.marker"))
        #expect(source.contains("AGENTSTUDIO_OBSERVABILITY_PID"))
        #expect(source.contains("git rev-parse HEAD"))
        #expect(source.contains("policy_id"))
        #expect(source.contains("policy_version"))
        #expect(source.contains("warmup_transaction_count"))
        #expect(source.contains("measured_transaction_count"))
        #expect(source.contains("baseline_p95_ms"))
        #expect(source.contains("doubled_p95_ms"))
        #expect(source.contains("growth_percent"))
        #expect(source.contains("exactness"))
        #expect(source.contains("trace_loss_count"))
        let markerReadinessWait = try #require(source.range(of: "wait_for_marker_record"))
        #expect(source.contains("agentstudio.performance.trace_queue.dropped_record.count"))
        let genericVerifier = try #require(
            source.range(of: "scripts/verify-debug-observability.sh")
        )
        #expect(markerReadinessWait.lowerBound < genericVerifier.lowerBound)
        #expect(!source.contains("REPOSITORY_COUNT="))
        #expect(!source.contains("WORKTREE_COUNT="))
        #expect(!source.contains("MAXIMUM_P95="))
        #expect(!source.contains("MAXIMUM_GROWTH="))
        #expect(!source.contains("AGENTSTUDIO_NATIVE_TABLE_PILOT_"))
        #expect(miseConfig.contains("[tasks.verify-sidebar-native-table-pilot]"))
        #expect(miseConfig.contains("scripts/verify-sidebar-native-table-pilot.sh"))
    }

    @Test("sidebar workload proof script has stable safety contract and bash syntax")
    // swiftlint:disable:next function_body_length
    func sidebarWorkloadProofScriptHasStableSafetyContractAndBashSyntax() async throws {
        let syntax = try await runSidebarScript(arguments: ["-n", scriptPath])
        #expect(syntax.exitCode == 0, Comment(rawValue: syntax.stderr))

        let source = try String(contentsOfFile: scriptPath, encoding: .utf8)
        let miseConfig = try String(contentsOfFile: ".mise.toml", encoding: .utf8)

        #expect(source.contains("sidebar-performance-proof"))
        #expect(source.contains("repo-explorer-key-mutation-proof"))
        #expect(source.contains("repo-explorer-interaction-proof"))
        #expect(source.contains("TRACE_MARKER_W"))
        #expect(source.contains("TRACE_MARKER_K"))
        #expect(source.contains("TRACE_MARKER_I"))
        #expect(source.contains("marker_w="))
        #expect(source.contains("marker_k="))
        #expect(source.contains("marker_i="))
        #expect(source.contains("performance.repo_explorer.keyed_wake"))
        #expect(source.contains("keyed-wake-values.env"))
        #expect(source.contains("repo_explorer_key_mutation_phase"))
        #expect(source.contains("rendered_repo_favorite"))
        #expect(source.contains("rendered_worktree_fact"))
        #expect(source.contains("relevant_key"))
        #expect(source.contains("unrelated_tab_arrangement_pane"))
        #expect(source.contains("observed_tab_title_informational"))
        #expect(source.contains("unrendered_attendance"))
        #expect(source.contains("unread_facet_change"))
        #expect(source.contains("missing_key_insertion"))
        #expect(source.contains("command_bar_open"))
        #expect(source.contains("command_bar_close"))
        #expect(source.contains("divider_frame=program_instrument_gap"))
        #expect(source.contains("TRACE_NONCE=\"$(/usr/bin/uuidgen)\""))
        #expect(source.contains("opaque_trace_marker \"${TRACE_NAME}-w\" \"$TRACE_NONCE\""))
        #expect(source.contains("AGENTSTUDIO_IPC_UNSAFE_NO_AUTH"))
        #expect(source.contains("AGENTSTUDIO_OBSERVABILITY_ACTIVATION_MODE"))
        #expect(source.contains("AGENTSTUDIO_OBSERVABILITY_IPC_AUTH_MODE"))
        #expect(source.contains("performance.sidebar.projection"))
        #expect(source.contains("eager_family_admission_count"))
        #expect(source.contains("assert_keyed_wake_contract"))
        #expect(source.contains("keyed_wake_outcome_count final_projection reference_different"))
        #expect(source.contains("final_projection reference_different expected 0"))
        #expect(source.contains("rendered_repo_favorite affected_row"))
        #expect(source.contains("rendered_repo_favorite capture_rebuild \"$WORKLOAD_CYCLES\""))
        #expect(source.contains("rendered_worktree_fact affected_row"))
        #expect(source.contains("rendered_worktree_fact capture_rebuild \"$WORKLOAD_CYCLES\""))
        #expect(source.contains("unrelated_tab_arrangement_pane capture_rebuild 0"))
        #expect(!source.contains("observed_tab_title capture_rebuild 0"))
        #expect(source.contains("unrendered_attendance capture_rebuild 0"))
        #expect(source.contains("relevant capture_rebuild \"$WORKLOAD_CYCLES\""))
        #expect(source.contains("missing_declared_key membership_path"))
        #expect(source.contains("surface=\"repo\""))
        #expect(
            source.contains(
                "phase=~\"startup_diagnostic|request_build_mainactor|mainactor_apply|projection_worker|row_index\""
            )
        )
        #expect(source.contains("agentstudio_performance_event_elapsed_ms_max"))
        #expect(source.contains("agentstudio_performance_event_elapsed_ms_bucket"))
        #expect(source.contains("histogram_quantile(0.95"))
        #expect(source.contains("trigger=\"%s\""))
        #expect(source.contains("grouping_switch"))
        #expect(!source.contains("\"sidebar.grouping.set\""))
        #expect(!source.contains("\"sidebar.surface.set\""))
        #expect(source.contains("\"setRepoSidebarGroupingRepo\""))
        #expect(source.contains("\"setRepoSidebarGroupingPane\""))
        #expect(source.contains("\"setRepoSidebarGroupingTab\""))
        #expect(!source.contains("\"showWorktreeSidebar\""))
        #expect(!source.contains("setRepoSidebarVisibilityMode"))
        #expect(!source.contains("favoritesOnly"))
        #expect(!source.contains("visibility_mode"))
        #expect(source.contains("\"setRepoSidebarSortOrder\""))
        #expect(source.contains("\"arguments\": {\"order\": order}"))
        #expect(source.contains("sort_order"))
        #expect(source.contains("repo_sort_projection_worker_elapsed_ms_p95"))
        #expect(source.contains("repo_sort_mainactor_apply_elapsed_ms_p95"))
        #expect(source.contains("repo_sort_request_build_mainactor_elapsed_ms_p95"))
        #expect(source.contains("repo_sort_row_index_elapsed_ms_p95"))
        #expect(source.contains("set_grouping(\"repo\", \"pane\")"))
        #expect(source.contains("set_grouping(\"repo\", \"repo\")"))
        #expect(source.contains("\"auth.login replay\""))
        #expect(source.contains("repo_pane_projection_worker_elapsed_ms_p95"))
        #expect(source.contains("repo_pane_projection_worker_elapsed_ms_count"))
        #expect(source.contains("for mode_name in repo pane tab"))
        #expect(source.contains("for phase in request_build_mainactor projection_worker row_index mainactor_apply"))
        #expect(source.contains("\"repo_${mode_name}_${phase}\""))
        #expect(source.contains("repo_pane_request_build_mainactor_elapsed_ms_p95"))
        #expect(source.contains("repo_pane_row_index_elapsed_ms_p95"))
        #expect(source.contains("repo_tab_mainactor_apply_elapsed_ms_max"))
        #expect(!source.contains("surface_switch"))
        #expect(!source.contains(". \"$BASELINE_FILE\""))
        #expect(source.contains("load_baseline_metric_value"))
        #expect(source.contains("record_required_sidebar_metric_matrix"))
        #expect(source.contains("compare_required_metric_matrix"))
        #expect(source.contains("required_metric_keys="))
        #expect(source.contains("wait_for_required_metric_count"))
        #expect(source.contains("REQUIRED_SAMPLE_COUNT=100"))
        #expect(source.contains("REQUIRED_MATERIALIZED_SAMPLE_COUNT=90"))
        #expect(source.contains("WORKLOAD_FIXTURE_VERSION=sidebar-workload-v5-repo-only"))
        #expect(source.contains("REQUIRED_REPOSITORY_COUNT=150"))
        #expect(source.contains("REQUIRED_WORKTREE_COUNT=180"))
        #expect(source.contains("REQUIRED_TAB_COUNT=12"))
        #expect(source.contains("REQUIRED_PANE_COUNT=36"))
        #expect(source.contains("REQUIRED_ACTIVE_PTY_COUNT=1"))
        #expect(!source.contains("MAXIMUM_PROCESS_CPU_PERCENT=30"))
        #expect(source.contains("process_cpu_percent_p50="))
        #expect(source.contains("process_cpu_percent_p95="))
        #expect(source.contains("process_cpu_percent_max="))
        #expect(source.contains("/usr/bin/top -l 0 -s 1 -pid \"$pid\" -stats pid,cpu"))
        #expect(source.contains("discarded_first_process_sample = False"))
        #expect(!source.contains("/bin/ps -p \"$pid\" -o %cpu="))
        #expect(source.contains("trace_queue_dropped_record_count="))
        #expect(source.contains("runtime_delivery_dropped_count="))
        #expect(source.contains("collector_loss_count="))
        #expect(source.contains("input_to_semantic_fact_contraction_ratio="))
        #expect(source.contains("semantic_fact_to_capture_admission_ratio="))
        #expect(source.contains("capture_to_execution_admission_ratio="))
        #expect(source.contains("execution_to_publication_ratio="))
        #expect(source.contains("publication_to_materialization_ratio="))
        #expect(source.contains("fixture_repo_count="))
        #expect(source.contains("fixture_worktree_count="))
        #expect(source.contains("fixture_tab_count="))
        #expect(source.contains("fixture_pane_count="))
        #expect(source.contains("fixture_active_pty_count="))
        #expect(source.contains("minimum_count=\"$REQUIRED_MATERIALIZED_SAMPLE_COUNT\""))
        #expect(source.contains("if [ \"$phase\" = \"request_build_mainactor\" ]"))
        #expect(source.contains("REQUIRED_METRIC_READBACK_ATTEMPTS=45"))
        #expect(source.contains("seq 1 \"$REQUIRED_METRIC_READBACK_ATTEMPTS\""))
        #expect(source.contains("AGENTSTUDIO_SIDEBAR_IPC_CYCLES:-100"))
        #expect(source.contains("performance,app.startup,terminal.startup"))
        #expect(source.contains("STRICT_POLICY_DIAGNOSTIC_TRACE_TAGS"))
        #expect(source.contains("sidebar_proof.diagnostic_trace_tags"))
        #expect(!source.contains("WORKLOAD_TRACE_TAGS=\"performance,atoms,app.startup,terminal.startup\""))
        #expect(source.contains("must be >= {minimum}"))
        #expect(source.contains("def wait_for_readback"))
        #expect(source.contains("time.monotonic() + timeout"))
        #expect(source.contains("AGENTSTUDIO_TRACE_FLUSH=immediate"))
        #expect(source.contains("KEY_MUTATION_TRACE_TAGS=\"performance,app.startup\""))
        #expect(source.contains("AGENTSTUDIO_TRACE_TAGS=\"$KEY_MUTATION_TRACE_TAGS\""))
        #expect(source.contains("run-debug-observability.sh\" --print-identity"))
        #expect(source.contains("refusing to reset debug data root outside $HOME/.agentstudio-db/"))
        #expect(source.contains("--inventory-exact-root \"$zmx_dir\" --zmx-bin \"$zmx_bin\""))
        #expect(source.contains("ZMX_DIR=\"$zmx_dir\" \"$zmx_bin\" kill \"$session_name\""))
        #expect(source.contains("refusing to remove debug data root while exact-root zmx sessions remain"))
        #expect(!source.contains("if data_dir in command:"))
        #expect(source.contains("trap cleanup EXIT INT TERM"))
        #expect(source.contains("readiness timed out"))
        #expect(source.contains("pace_projection_application()"))
        #expect(source.contains("def pace_projection_application():"))
        #expect(!source.contains("sidebar grouping read-back mismatch"))
        #expect(!source.contains("sidebar surface read-back mismatch"))
        #expect(source.contains("workload_fixture_key=$WORKLOAD_FIXTURE_KEY"))
        #expect(source.contains("worktree_fixture_key=$WORKTREE_FIXTURE_KEY"))
        #expect(source.contains("sidebar baseline workload fixture mismatch"))
        #expect(source.contains("sidebar baseline worktree fixture mismatch"))
        #expect(source.contains("validate_compare_baseline_fixture"))
        #expect(source.contains("\"sidebar.grouping.get\""))
        #expect(!source.contains("\"sidebar.surface.get\""))
        #expect(source.contains("repo_only_workload.ipc_sequence=grouping_and_sort"))
        #expect(
            source.contains("repo_sort.ipc_sequence=descending,ascending,descending,ascending,descending,ascending"))
        #expect(source.contains("sidebar-performance-baseline.env"))
        #expect(source.contains("performance_threshold_check"))
        #expect(source.contains("requires authenticated IPC auth mode"))
        #expect(source.contains("requires background LaunchServices activation mode"))
        #expect(!source.contains("notification_text"))
        #expect(!source.lowercased().contains("inbox"))
        #expect(!source.contains("query_text"))
        #expect(!source.contains("osascript"))
        #expect(miseConfig.contains("[tasks.verify-sidebar-performance-workload]"))
        #expect(
            miseConfig.contains(
                "run = \"/bin/bash scripts/verify-sidebar-performance-workload.sh --sidebar-proof\""
            )
        )
    }

    @Test("prepare-only emits comparable sidebar summary without launching app")
    func prepareOnlyEmitsComparableSidebarSummaryWithoutLaunchingApp() async throws {
        let proofRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-sidebar-workload-summary-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: proofRoot)
        }

        let result = try await runSidebarScript(
            arguments: [scriptPath, "--prepare-only"],
            environment: [
                "AGENTSTUDIO_SIDEBAR_PROOF_ROOT": proofRoot.path,
                "AGENTSTUDIO_TRACE_NAME": "sidebar-summary-shape-test",
                "AGENTSTUDIO_SIDEBAR_ALLOW_TEST_RESPONSES": "1",
                "AGENTSTUDIO_SIDEBAR_TEST_METRICS_RESPONSE":
                    #"{"status":"success","data":{"result":[{"value":[0,"1"]}]}}"#,
                "AI_TOOLS_OBSERVABILITY_METRICS_QUERY_URL": "http://127.0.0.1:1/api/v1/query",
            ]
        )

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        let summaryURL =
            proofRoot
            .appendingPathComponent("sidebar-summary-shape-test")
            .appendingPathComponent("summary.txt")
        let summary = try String(contentsOf: summaryURL, encoding: .utf8)
        #expect(summary.contains("mode=prepare-only"))
        #expect(summary.contains("startup_diagnostic=sidebar-performance-proof"))
        #expect(summary.contains("requires_unsafe_no_auth=false"))
        #expect(summary.contains("requires_non_foreground_activation=true"))
        #expect(summary.contains("workload_fixture_key="))
        #expect(summary.contains("worktree_fixture_key="))
        #expect(summary.contains("workload_cycles=100"))
        #expect(summary.contains("sidebar_projection.metric_result_count=1"))
    }

    @Test("each sidebar diagnostic phase starts from the disposable debug root")
    func eachSidebarDiagnosticPhaseStartsFromDisposableDebugRoot() throws {
        let source = try String(contentsOfFile: scriptPath, encoding: .utf8)

        let keyPhase = try #require(
            source.range(of: "run_repo_explorer_key_mutation_phase() {")
        )
        let interactionPhase = try #require(
            source.range(
                of: "run_repo_explorer_interaction_phase() {",
                range: keyPhase.upperBound..<source.endIndex
            )
        )
        let keyPhaseSource = source[keyPhase.lowerBound..<interactionPhase.lowerBound]
        let keyPhaseStop = try #require(keyPhaseSource.range(of: "retire_current_candidate"))
        let keyPhaseReset = try #require(keyPhaseSource.range(of: "reset_disposable_debug_root"))
        let keyPhaseLaunch = try #require(keyPhaseSource.range(of: "repo-explorer-key-mutation-proof"))

        let performanceCheck = try #require(
            source.range(
                of: "performance_threshold_check() {",
                range: interactionPhase.upperBound..<source.endIndex
            )
        )
        let interactionPhaseSource = source[interactionPhase.lowerBound..<performanceCheck.lowerBound]
        #expect(interactionPhaseSource.contains("keyed_wake_key_mutation_completion"))
        #expect(interactionPhaseSource.contains("key_class=\\\"missing_declared_key\\\""))
        #expect(interactionPhaseSource.contains("stage=\\\"membership_path\\\""))
        #expect(interactionPhaseSource.contains("\"$WORKLOAD_CYCLES\" >/dev/null"))
        let interactionPhaseStop = try #require(
            interactionPhaseSource.range(of: "retire_current_candidate")
        )
        let interactionPhaseReset = try #require(
            interactionPhaseSource.range(of: "reset_disposable_debug_root")
        )
        let interactionPhaseLaunch = try #require(
            interactionPhaseSource.range(of: "repo-explorer-interaction-proof")
        )

        #expect(keyPhaseStop.lowerBound < keyPhaseReset.lowerBound)
        #expect(keyPhaseReset.lowerBound < keyPhaseLaunch.lowerBound)
        #expect(interactionPhaseStop.lowerBound < interactionPhaseReset.lowerBound)
        #expect(interactionPhaseReset.lowerBound < interactionPhaseLaunch.lowerBound)
    }

    @Test("workload captures phase W metrics before launching later diagnostic markers")
    func workloadCapturesPhaseWMetricsBeforeLaunchingLaterDiagnosticMarkers() throws {
        let source = try String(contentsOfFile: scriptPath, encoding: .utf8)
        let workloadInvocation = try #require(
            source.range(of: "run_authenticated_sidebar_ipc_workload")
        )
        let phaseWMetricCapture = try #require(
            source.range(
                of: "repo_sort_projection_worker_elapsed_ms_p95=\"$(",
                range: workloadInvocation.upperBound..<source.endIndex
            )
        )
        let keyPhaseInvocation = try #require(
            source.range(
                of: "run_repo_explorer_key_mutation_phase\n",
                range: workloadInvocation.upperBound..<source.endIndex
            )
        )
        let keyedWakeAssertions = try #require(
            source.range(
                of: ": >\"$KEYED_WAKE_VALUES_FILE\"",
                range: keyPhaseInvocation.upperBound..<source.endIndex
            )
        )

        #expect(phaseWMetricCapture.lowerBound < keyPhaseInvocation.lowerBound)
        #expect(keyPhaseInvocation.lowerBound < keyedWakeAssertions.lowerBound)
    }

    @Test("workload rejects fewer than one hundred issued samples per bucket")
    func workloadRejectsFewerThanOneHundredIssuedSamplesPerBucket() async throws {
        let result = try await runSidebarScript(
            arguments: [scriptPath, "--prepare-only"],
            environment: ["AGENTSTUDIO_SIDEBAR_IPC_CYCLES": "99"]
        )

        #expect(result.exitCode == 2)
        #expect(result.stderr.contains("AGENTSTUDIO_SIDEBAR_IPC_CYCLES must be >= 100: 99"))
    }

    @Test("compare rejects mismatched fixture metadata before launch")
    func compareRejectsMismatchedFixtureMetadataBeforeLaunch() async throws {
        let proofRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-sidebar-baseline-mismatch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: proofRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: proofRoot)
        }
        try "workload_fixture_key=stale\nworktree_fixture_key=stale\n".write(
            to: proofRoot.appendingPathComponent("sidebar-performance-baseline.env"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await runSidebarScript(
            arguments: [scriptPath, "--compare"],
            environment: [
                "AGENTSTUDIO_SIDEBAR_PROOF_ROOT": proofRoot.path,
                "AGENTSTUDIO_TRACE_NAME": "sidebar-fixture-mismatch-test",
            ]
        )

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("sidebar baseline workload fixture mismatch"))
    }

    @Test("proof modes reject unsafe no-auth IPC before launching")
    func proofModesRejectUnsafeNoAuthIPCBeforeLaunching() async throws {
        let proofRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-sidebar-unsafe-no-auth-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: proofRoot)
        }

        let result = try await runSidebarScript(
            arguments: [scriptPath, "--sidebar-proof"],
            environment: [
                "AGENTSTUDIO_SIDEBAR_PROOF_ROOT": proofRoot.path,
                "AGENTSTUDIO_TRACE_NAME": "sidebar-unsafe-no-auth-test",
                "AGENTSTUDIO_IPC_UNSAFE_NO_AUTH": "1",
            ]
        )

        #expect(result.exitCode == 2)
        #expect(result.stderr.contains("refuses AGENTSTUDIO_IPC_UNSAFE_NO_AUTH"))
    }

    private let scriptPath = "scripts/verify-sidebar-performance-workload.sh"
    private let settledGitVectorFields =
        """
        "git_future_automatic_count":0,"git_future_failure_count":0,"git_ready_pending_count":0,"git_capacity_pending_count":0,"git_active_follow_up_count":0,"git_unclassified_pending_count":0,"git_overdue_deadline_count":0,"git_running_count":0,"git_physical_limit":4,"git_oldest_preparation_ms":0,"git_next_deadline_ms":0,"git_maximum_settlement_ms":960000
        """

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

    private func runHostReceiptContract(receipts: String) async throws -> ProcessResult {
        try await runSidebarScript(
            arguments: [scriptPath, "--prepare-only"],
            environment: [
                "AGENTSTUDIO_SIDEBAR_ALLOW_TEST_RESPONSES": "1",
                "AGENTSTUDIO_SIDEBAR_TEST_HOST_RECEIPTS": receipts,
            ]
        )
    }

    private func runHostProcessContract(records: String) async throws -> ProcessResult {
        try await runSidebarScript(
            arguments: [scriptPath, "--prepare-only"],
            environment: [
                "AGENTSTUDIO_SIDEBAR_ALLOW_TEST_RESPONSES": "1",
                "AGENTSTUDIO_SIDEBAR_TEST_HOST_PROCESS_RECORDS": records,
                "AGENTSTUDIO_SIDEBAR_TEST_LOGICAL_CPU_COUNT": "8",
                "STRICT_POLICY_HOST_CPU_MAX": "20",
            ]
        )
    }

    private func runZmxStateContract(sequence: String) async throws -> ProcessResult {
        try await runSidebarScript(
            arguments: [scriptPath, "--prepare-only"],
            environment: [
                "AGENTSTUDIO_SIDEBAR_ALLOW_TEST_RESPONSES": "1",
                "AGENTSTUDIO_SIDEBAR_TEST_ZMX_STATE_SEQUENCE": sequence,
            ]
        )
    }

    private func runWorkloadReceiptContract(receipt: String) async throws -> ProcessResult {
        try await runSidebarScript(
            arguments: [scriptPath, "--prepare-only"],
            environment: [
                "AGENTSTUDIO_SIDEBAR_ALLOW_TEST_RESPONSES": "1",
                "AGENTSTUDIO_SIDEBAR_TEST_WORKLOAD_RECEIPT": receipt,
            ]
        )
    }

    private func runMetricObservationContract(
        response: String,
        observationTime: String
    ) async throws -> ProcessResult {
        try await runSidebarScript(
            arguments: [scriptPath, "--prepare-only"],
            environment: [
                "AGENTSTUDIO_SIDEBAR_ALLOW_TEST_RESPONSES": "1",
                "AGENTSTUDIO_SIDEBAR_TEST_METRICS_RESPONSE": response,
                "AGENTSTUDIO_SIDEBAR_TEST_METRIC_OBSERVATION_TIME": observationTime,
            ]
        )
    }

}

func runSidebarScript(
    arguments: [String],
    environment: [String: String] = [:]
) async throws -> ProcessResult {
    var mergedEnvironment = ProcessInfo.processInfo.environment
    mergedEnvironment["AGENTSTUDIO_OBSERVABILITY_ALLOW_TEST_OVERRIDES"] = "1"
    mergedEnvironment["AI_TOOLS_OBSERVABILITY_COLLECTOR_HEALTH_URL"] = "http://127.0.0.1:13133/"
    for (key, value) in environment {
        mergedEnvironment[key] = value
    }
    return try await DefaultProcessExecutor(timeout: 10).execute(
        command: "/bin/bash",
        args: arguments,
        cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        environment: mergedEnvironment
    )
}
