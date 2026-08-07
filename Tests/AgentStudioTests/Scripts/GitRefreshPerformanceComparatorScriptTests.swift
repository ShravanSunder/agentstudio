import Foundation
import Testing

@Suite(.serialized)
struct GitRefreshPerformanceComparatorScriptTests {
    @Test("performance comparator passes matched evidence without a universal improvement win")
    func performanceComparatorPassesMatchedEvidenceWithoutUniversalImprovementWin() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let baselineWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10)
        )
        let afterWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10)
        )
        let baselineInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-interaction.txt"),
            values: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1)
        )
        let afterInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-interaction.txt"),
            values: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1)
        )
        let output = fixtureRoot.appendingPathComponent("comparison.txt")

        let result = try runScript(arguments: [
            comparisonScriptPath,
            "--baseline-workload", baselineWorkload.path,
            "--after-workload", afterWorkload.path,
            "--baseline-interaction", baselineInteraction.path,
            "--after-interaction", afterInteraction.path,
            "--output", output.path,
        ])

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        let comparison = try String(contentsOf: output, encoding: .utf8)
        #expect(comparison.contains("ready"))
        #expect(comparison.contains("frozen regression boundary: 10%"))
        #expect(!comparison.contains("threshold met"))
    }

    @Test("performance comparator fails when coordinator write regresses")
    func performanceComparatorFailsWhenCoordinatorWriteRegresses() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let baselineWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10)
                .merging(coordinatorSummaryValues(count: 10, p95: 10, max: 10)) { _, newValue in newValue }
        )
        let afterWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 4, fanoutP95: 10, fanoutMax: 9)
                .merging(coordinatorSummaryValues(count: 12, p95: 10, max: 10)) { _, newValue in newValue }
        )
        let baselineInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-interaction.txt"),
            values: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1)
        )
        let afterInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-interaction.txt"),
            values: commandBarSummaryValues(itemsCount: 4, itemsP95: 10, itemsMax: 1)
        )
        let output = fixtureRoot.appendingPathComponent("comparison.txt")

        let result = try runScript(arguments: [
            comparisonScriptPath,
            "--baseline-workload", baselineWorkload.path,
            "--after-workload", afterWorkload.path,
            "--baseline-interaction", baselineInteraction.path,
            "--after-interaction", afterInteraction.path,
            "--output", output.path,
        ])

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("performance.coordinator.write.victoria_metrics_count regressed"))
        let comparison = try String(contentsOf: output, encoding: .utf8)
        #expect(comparison.contains("not_ready"))
    }

    @Test("performance comparator passes improvements within the frozen regression boundary")
    func performanceComparatorPassesImprovementsWithinFrozenRegressionBoundary() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let baselineWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10)
        )
        let afterWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 4, fanoutP95: 10, fanoutMax: 9)
        )
        let baselineInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-interaction.txt"),
            values: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1)
        )
        let afterInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-interaction.txt"),
            values: commandBarSummaryValues(itemsCount: 4, itemsP95: 10, itemsMax: 1)
                .merging([
                    "performance.commandbar.filter.elapsed_ms.max": "100"
                ]) { _, newValue in newValue }
        )
        let output = fixtureRoot.appendingPathComponent("comparison.txt")

        let result = try runScript(arguments: [
            comparisonScriptPath,
            "--baseline-workload", baselineWorkload.path,
            "--after-workload", afterWorkload.path,
            "--baseline-interaction", baselineInteraction.path,
            "--after-interaction", afterInteraction.path,
            "--output", output.path,
        ])

        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        let comparison = try String(contentsOf: output, encoding: .utf8)
        #expect(comparison.contains("ready"))
        #expect(comparison.contains("frozen regression boundary: 10%"))
        #expect(comparison.contains("performance.commandbar.filter.elapsed_ms.max is informational"))
    }

    @Test("performance comparator rejects missing provenance before distributions")
    func performanceComparatorRejectsMissingProvenanceBeforeDistributions() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        var baselineWorkloadValues = workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10)
        baselineWorkloadValues.removeValue(forKey: "source_digest")
        baselineWorkloadValues.removeValue(forKey: "executable_digest")
        baselineWorkloadValues.removeValue(forKey: "launch_method")
        baselineWorkloadValues.removeValue(forKey: "issued_interaction_count")

        let result = try runComparator(
            fixtureRoot: fixtureRoot,
            baselineWorkloadValues: baselineWorkloadValues,
            afterWorkloadValues: workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10),
            baselineInteractionValues: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1),
            afterInteractionValues: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1)
        )

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("missing required provenance source_digest in baseline workload"))
        #expect(result.stderr.contains("missing required provenance executable_digest in baseline workload"))
        #expect(result.stderr.contains("requires launch_method=launchservices in baseline workload"))
        #expect(result.stderr.contains("missing required metric issued_interaction_count in baseline workload"))
    }

    @Test("performance comparator rejects mismatched same-side digests and lane fingerprints")
    func performanceComparatorRejectsMismatchedSameSideDigestsAndLaneFingerprints() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        var afterWorkloadValues = workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10)
        afterWorkloadValues["workload_fingerprint"] = "different-workload"
        var afterInteractionValues = commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1)
        afterInteractionValues["source_digest"] = "different-source"

        let result = try runComparator(
            fixtureRoot: fixtureRoot,
            baselineWorkloadValues: workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10),
            afterWorkloadValues: afterWorkloadValues,
            baselineInteractionValues: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1),
            afterInteractionValues: afterInteractionValues
        )

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("candidate source_digest differs between workload and interaction"))
        #expect(result.stderr.contains("workload workload_fingerprint changed"))
    }

    @Test("performance comparator rejects incomplete tab bar lifecycle continuity")
    func performanceComparatorRejectsIncompleteTabBarLifecycleContinuity() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        var afterWorkloadValues = workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10)
        afterWorkloadValues["performance.tabbar.terminal_count"] = "9"

        let result = try runComparator(
            fixtureRoot: fixtureRoot,
            baselineWorkloadValues: workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10),
            afterWorkloadValues: afterWorkloadValues,
            baselineInteractionValues: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1),
            afterInteractionValues: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1)
        )

        #expect(result.exitCode != 0)
        #expect(
            result.stderr.contains("tab bar lifecycle continuity failed in candidate workload: capture=10 terminal=9"))
    }

    @Test("performance comparator rejects duplicate and missing tab bar lifecycle sequences")
    func performanceComparatorRejectsNonExactTabBarLifecycle() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        var afterWorkloadValues = workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10)
        afterWorkloadValues["performance.tabbar.lifecycle_exact"] = "false"
        afterWorkloadValues["performance.tabbar.duplicate_capture_sequence_count"] = "1"
        afterWorkloadValues["performance.tabbar.missing_terminal_sequence_count"] = "1"

        let result = try runComparator(
            fixtureRoot: fixtureRoot,
            baselineWorkloadValues: workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10),
            afterWorkloadValues: afterWorkloadValues,
            baselineInteractionValues: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1),
            afterInteractionValues: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1)
        )

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("performance.tabbar.lifecycle_exact must be true"))
        #expect(result.stderr.contains("duplicate capture sequences"))
        #expect(result.stderr.contains("missing terminal sequences"))
    }

    @Test("performance comparator rejects trace queue loss")
    func performanceComparatorRejectsTraceQueueLoss() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        var afterWorkloadValues = workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10)
        afterWorkloadValues["agentstudio.performance.trace_queue.dropped_record.count"] = "1"

        let result = try runComparator(
            fixtureRoot: fixtureRoot,
            baselineWorkloadValues: workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10),
            afterWorkloadValues: afterWorkloadValues,
            baselineInteractionValues: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1),
            afterInteractionValues: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1)
        )

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("trace queue dropped 1 records in candidate workload"))
    }

    @Test("performance comparator rejects a false final-state oracle")
    func performanceComparatorRejectsFalseFinalStateOracle() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        var afterWorkloadValues = workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10)
        afterWorkloadValues["final_active_tab_equivalent"] = "false"

        let result = try runComparator(
            fixtureRoot: fixtureRoot,
            baselineWorkloadValues: workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10),
            afterWorkloadValues: afterWorkloadValues,
            baselineInteractionValues: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1),
            afterInteractionValues: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1)
        )

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("final_active_tab_equivalent must be true in candidate workload"))
    }

    @Test("performance comparator fails when required metrics are missing")
    func performanceComparatorFailsWhenRequiredMetricsAreMissing() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let baselineWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10)
        )
        let afterWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 4, fanoutP95: 10, fanoutMax: 9)
        )
        let baselineInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-interaction.txt"),
            values: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1)
        )
        var afterInteractionValues = commandBarSummaryValues(itemsCount: 4, itemsP95: 10, itemsMax: 1)
        afterInteractionValues.removeValue(forKey: "performance.commandbar.items.victoria_metrics_count")
        let afterInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-interaction.txt"),
            values: afterInteractionValues
        )
        let output = fixtureRoot.appendingPathComponent("comparison.txt")

        let result = try runScript(arguments: [
            comparisonScriptPath,
            "--baseline-workload", baselineWorkload.path,
            "--after-workload", afterWorkload.path,
            "--baseline-interaction", baselineInteraction.path,
            "--after-interaction", afterInteraction.path,
            "--output", output.path,
        ])

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("missing required metric"))
        let comparison = try String(contentsOf: output, encoding: .utf8)
        #expect(comparison.contains("not_ready"))
    }

    @Test("performance comparator fails when metrics disappear but logs remain")
    func performanceComparatorFailsWhenMetricsDisappearButLogsRemain() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let baselineWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10)
        )
        let afterWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 4, fanoutP95: 10, fanoutMax: 9)
        )
        let baselineInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-interaction.txt"),
            values: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1)
        )
        var afterInteractionValues = commandBarSummaryValues(itemsCount: 0, itemsP95: 10, itemsMax: 1)
        afterInteractionValues["performance.commandbar.items.victoria_logs_count"] = "10"
        let afterInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-interaction.txt"),
            values: afterInteractionValues
        )
        let output = fixtureRoot.appendingPathComponent("comparison.txt")

        let result = try runScript(arguments: [
            comparisonScriptPath,
            "--baseline-workload", baselineWorkload.path,
            "--after-workload", afterWorkload.path,
            "--baseline-interaction", baselineInteraction.path,
            "--after-interaction", afterInteraction.path,
            "--output", output.path,
        ])

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("instrumentation loss"))
        let comparison = try String(contentsOf: output, encoding: .utf8)
        #expect(comparison.contains("not_ready"))
    }

    @Test("performance comparator fails when command-bar interaction sequence differs")
    func performanceComparatorFailsWhenCommandBarInteractionSequenceDiffers() throws {
        let fixtureRoot = try temporaryFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let baselineWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 10, fanoutP95: 10, fanoutMax: 10)
        )
        let afterWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-workload.txt"),
            values: workloadSummaryValues(fanoutCount: 4, fanoutP95: 10, fanoutMax: 9)
        )
        let baselineInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-interaction.txt"),
            values: commandBarSummaryValues(itemsCount: 10, itemsP95: 10, itemsMax: 1)
        )
        var afterInteractionValues = commandBarSummaryValues(itemsCount: 4, itemsP95: 10, itemsMax: 1)
        afterInteractionValues["performance.commandbar.filter.query_character.max"] = "1"
        let afterInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-interaction.txt"),
            values: afterInteractionValues
        )
        let output = fixtureRoot.appendingPathComponent("comparison.txt")

        let result = try runScript(arguments: [
            comparisonScriptPath,
            "--baseline-workload", baselineWorkload.path,
            "--after-workload", afterWorkload.path,
            "--baseline-interaction", baselineInteraction.path,
            "--after-interaction", afterInteraction.path,
            "--output", output.path,
        ])

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("command-bar interaction fingerprint changed"))
        let comparison = try String(contentsOf: output, encoding: .utf8)
        #expect(comparison.contains("not_ready"))
    }

    private let comparisonScriptPath = "scripts/compare-atomlib-v2-performance.sh"
    private func runScript(
        arguments: [String],
        environment: [String: String] = [:]
    ) throws -> ScriptRunResult {
        let stdoutURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-script-stdout-\(UUID().uuidString).log")
        let stderrURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-script-stderr-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, newValue in newValue }
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        try process.run()
        process.waitUntilExit()
        try stdoutHandle.close()
        try stderrHandle.close()

        return ScriptRunResult(
            exitCode: process.terminationStatus,
            stdout: try String(contentsOf: stdoutURL, encoding: .utf8),
            stderr: try String(contentsOf: stderrURL, encoding: .utf8)
        )
    }

    private func temporaryFixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-performance-comparison-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeSummary(
        at url: URL,
        values: [String: String]
    ) throws -> URL {
        let body =
            values
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
        try (body + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func runComparator(
        fixtureRoot: URL,
        baselineWorkloadValues: [String: String],
        afterWorkloadValues: [String: String],
        baselineInteractionValues: [String: String],
        afterInteractionValues: [String: String]
    ) throws -> ScriptRunResult {
        let baselineWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-workload.txt"),
            values: baselineWorkloadValues
        )
        let afterWorkload = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-workload.txt"),
            values: afterWorkloadValues
        )
        let baselineInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("baseline-interaction.txt"),
            values: baselineInteractionValues
        )
        let afterInteraction = try writeSummary(
            at: fixtureRoot.appendingPathComponent("after-interaction.txt"),
            values: afterInteractionValues
        )
        return try runScript(arguments: [
            comparisonScriptPath,
            "--baseline-workload", baselineWorkload.path,
            "--after-workload", afterWorkload.path,
            "--baseline-interaction", baselineInteraction.path,
            "--after-interaction", afterInteraction.path,
            "--output", fixtureRoot.appendingPathComponent("comparison.txt").path,
        ])
    }

    private func evidenceCompletenessValues(
        workloadFingerprint: String,
        issuedInteractionCount: Int
    ) -> [String: String] {
        [
            "source_digest": "source-digest",
            "executable_digest": "executable-digest",
            "workload_fingerprint": workloadFingerprint,
            "trace_tags": "performance,app.startup",
            "launch_method": "launchservices",
            "activation_mode": "background",
            "issued_interaction_count": "\(issuedInteractionCount)",
            "regression_boundary_percent": "10",
            "performance.tabbar.capture_count": "10",
            "performance.tabbar.terminal_count": "10",
            "performance.tabbar.lifecycle_exact": "true",
            "performance.tabbar.duplicate_capture_sequence_count": "0",
            "performance.tabbar.duplicate_terminal_sequence_count": "0",
            "performance.tabbar.missing_terminal_sequence_count": "0",
            "performance.tabbar.unexpected_terminal_sequence_count": "0",
            "performance.tabbar.invalid_terminal_outcome_count": "0",
            "agentstudio.performance.trace_queue.dropped_record.count": "0",
            "agentstudio.performance.trace_queue.high_watermark": "7",
            "final_tab_count_equivalent": "true",
            "final_active_tab_equivalent": "true",
            "final_membership_equivalent": "true",
        ]
    }

    private func commandBarSummaryValues(
        itemsCount: Int,
        itemsP95: Int,
        itemsMax: Int
    ) -> [String: String] {
        [
            "performance.commandbar.items.victoria_metrics_count": "\(itemsCount)",
            "performance.commandbar.items.victoria_logs_count": "\(itemsCount)",
            "performance.commandbar.items.jsonl_count": "0",
            "performance.commandbar.items.elapsed_ms.p95": "\(itemsP95)",
            "performance.commandbar.items.elapsed_ms.p95_unavailable": "false",
            "performance.commandbar.items.elapsed_ms.max": "\(itemsMax)",
            "performance.commandbar.filter.victoria_metrics_count": "10",
            "performance.commandbar.filter.victoria_logs_count": "10",
            "performance.commandbar.filter.jsonl_count": "0",
            "performance.commandbar.filter.elapsed_ms.p95": "10",
            "performance.commandbar.filter.elapsed_ms.p95_unavailable": "false",
            "performance.commandbar.filter.elapsed_ms.max": "1",
            "performance.commandbar.filter.query_character.max": "10",
        ].merging(
            evidenceCompletenessValues(
                workloadFingerprint: "command-bar-interaction-v1",
                issuedInteractionCount: 1
            )
        ) { _, newValue in newValue }
    }

    private func workloadSummaryValues(
        fanoutCount: Int,
        fanoutP95: Int,
        fanoutMax: Int
    ) -> [String: String] {
        var values: [String: String] = [:]
        for eventName in [
            "performance.tabbar.refresh",
            "performance.sidebar.projection",
            "performance.sidebar.row_index",
            "performance.topology.repo_and_worktree",
            "performance.coordinator.write",
        ] {
            values["\(eventName).victoria_metrics_count"] = "\(fanoutCount)"
            values["\(eventName).victoria_logs_count"] = "\(fanoutCount)"
            values["\(eventName).jsonl_count"] = "0"
            values["\(eventName).elapsed_ms.p95"] = "\(fanoutP95)"
            values["\(eventName).elapsed_ms.p95_unavailable"] = "false"
            values["\(eventName).elapsed_ms.max"] = "\(fanoutMax)"
        }
        return values.merging(
            evidenceCompletenessValues(
                workloadFingerprint: "git-refresh-workload-v1",
                issuedInteractionCount: 25
            )
        ) { _, newValue in newValue }
    }

    private func coordinatorSummaryValues(count: Int, p95: Int, max: Int) -> [String: String] {
        [
            "performance.coordinator.write.victoria_metrics_count": "\(count)",
            "performance.coordinator.write.victoria_logs_count": "\(count)",
            "performance.coordinator.write.jsonl_count": "0",
            "performance.coordinator.write.elapsed_ms.p95": "\(p95)",
            "performance.coordinator.write.elapsed_ms.p95_unavailable": "false",
            "performance.coordinator.write.elapsed_ms.max": "\(max)",
        ]
    }
}
