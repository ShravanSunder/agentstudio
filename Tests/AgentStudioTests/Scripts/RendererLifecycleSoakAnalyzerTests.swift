import Foundation
import Testing

@testable import AgentStudioInfrastructure

@Suite("Renderer lifecycle soak analyzer")
struct RendererLifecycleSoakAnalyzerTests {
    @Test("constant and recovering pressure pass with exact OLS output")
    func constantAndRecoveringPressurePass() async throws {
        let result = try await runAnalyzer(rawFreeMemoryStep: 10, appPhysicalStep: 0)

        #expect(result.execution.exitCode == 0, Comment(rawValue: result.execution.stderr))
        let report = try #require(result.report)
        #expect(report["passed"] as? Bool == true)
        let slopes = try #require(report["slopes"] as? [String: Any])
        let physical = try #require(slopes["app_physical_bytes"] as? [String: Any])
        #expect(physical["slope_per_second"] as? Double == 0)
        let pressure = try #require(slopes["free_memory_pressure_bytes"] as? [String: Any])
        #expect((pressure["upper_95"] as? Double ?? 1) < 0)
    }

    @Test("declining free memory fails through pointwise negative pressure")
    func decliningFreeMemoryFails() async throws {
        let result = try await runAnalyzer(rawFreeMemoryStep: -10, appPhysicalStep: 0)

        #expect(result.execution.exitCode == 1)
        #expect(result.execution.stderr.contains("free_memory_pressure_bytes"))
    }

    @Test("positive physical lower confidence bound fails")
    func positivePhysicalSlopeFails() async throws {
        let result = try await runAnalyzer(rawFreeMemoryStep: 10, appPhysicalStep: 20)

        #expect(result.execution.exitCode == 1)
        #expect(result.execution.stderr.contains("app_physical_bytes"))
    }

    @Test("missing series and invalid lifecycle algebra fail closed")
    func missingSeriesAndInvalidAlgebraFailClosed() async throws {
        let missing = try await runAnalyzer(rawFreeMemoryStep: 10, appPhysicalStep: 0) { samples in
            samples[0].removeValue(forKey: "app_iosurface_bytes")
        }
        let invalidAlgebra = try await runAnalyzer(rawFreeMemoryStep: 10, appPhysicalStep: 0) { samples in
            samples[0]["orphan_current"] = 1
        }

        #expect(missing.execution.exitCode == 2)
        #expect(missing.execution.stderr.contains("app_iosurface_bytes"))
        #expect(invalidAlgebra.execution.exitCode == 2)
        #expect(invalidAlgebra.execution.stderr.contains("orphan algebra invalid"))
    }

    @Test("wrong sample count, cadence, identity, and workload counts fail closed")
    func samplingIdentityAndWorkloadContractsFailClosed() async throws {
        let wrongCount = try await runAnalyzer(rawFreeMemoryStep: 10, appPhysicalStep: 0) { samples in
            samples.removeLast()
        }
        let wrongCadence = try await runAnalyzer(rawFreeMemoryStep: 10, appPhysicalStep: 0) { samples in
            let firstFinalIndex = samples.firstIndex { $0["window"] as? String == "final" } ?? 0
            samples[firstFinalIndex + 1]["timestamp_seconds"] = 9999
        }
        let wrongIdentity = try await runAnalyzer(rawFreeMemoryStep: 10, appPhysicalStep: 0) { samples in
            samples[samples.count - 1]["windowserver_pid"] = 999
        }
        let wrongWorkload = try await runAnalyzer(
            rawFreeMemoryStep: 10,
            appPhysicalStep: 0,
            mutateProgress: { progress in
                let index = progress.firstIndex { $0["scenario"] as? String == "tab_switch" } ?? 0
                progress[index]["completed_count"] = 19
            })

        #expect(wrongCount.execution.exitCode == 2)
        #expect(wrongCadence.execution.exitCode == 2)
        #expect(wrongIdentity.execution.exitCode == 2)
        #expect(wrongWorkload.execution.exitCode == 2)
    }

    @Test("warmup completion cannot overlap the sixtieth sample")
    func warmupCompletionRequiresCollectionGrace() async throws {
        let result = try await runAnalyzer(
            rawFreeMemoryStep: 10,
            appPhysicalStep: 0,
            mutateProgress: { progress in
                let index = progress.firstIndex { $0["stage"] as? String == "warmup_completed" } ?? 0
                progress[index]["timestamp_seconds"] = 1599
            })

        #expect(result.execution.exitCode == 2)
        #expect(result.execution.stderr.contains("overlapped the final warmup sample"))
    }

    @Test("final lifecycle must be exact, fresh, and quiescent")
    func finalLifecycleMustBeExactFreshAndQuiescent() async throws {
        let wrongTotals = try await runAnalyzer(rawFreeMemoryStep: 10, appPhysicalStep: 0) { samples in
            for index in samples.indices where samples[index]["window"] as? String == "final" {
                samples[index]["created_total"] = 49
                samples[index]["live_current"] = 19
                samples[index]["manager_owned_current"] = 19
                samples[index]["active_current"] = 9
            }
        }
        let regressedSequence = try await runAnalyzer(rawFreeMemoryStep: 10, appPhysicalStep: 0) { samples in
            samples[samples.count - 1]["sample_sequence"] = 0
        }
        let lifecycleChurn = try await runAnalyzer(rawFreeMemoryStep: 10, appPhysicalStep: 0) { samples in
            let finalIndex = samples.firstIndex { $0["window"] as? String == "final" } ?? 0
            samples[finalIndex + 1]["visibility_delivery_total"] = 101
        }

        #expect(wrongTotals.execution.exitCode == 2)
        #expect(wrongTotals.execution.stderr.contains("exact soak workload"))
        #expect(regressedSequence.execution.exitCode == 2)
        #expect(regressedSequence.execution.stderr.contains("sample sequence"))
        #expect(lifecycleChurn.execution.exitCode == 2)
        #expect(lifecycleChurn.execution.stderr.contains("not quiescent"))
    }

    @Test("delivery-cardinality milestones and exact counts are mandatory")
    func deliveryCardinalityProofMustBeComplete() async throws {
        let missingMilestone = try await runAnalyzer(
            rawFreeMemoryStep: 10,
            appPhysicalStep: 0,
            mutateProgress: { progress in
                progress.removeAll { $0["stage"] as? String == "equal_reconciliation_verified" }
            })
        let wrongChangedCount = try await runAnalyzer(
            rawFreeMemoryStep: 10,
            appPhysicalStep: 0,
            mutateProgress: { progress in
                let index = progress.firstIndex { $0["stage"] as? String == "changed_delivery_verified" } ?? 0
                progress[index]["completed_count"] = 39
            })

        #expect(missingMilestone.execution.exitCode == 2)
        #expect(missingMilestone.execution.stderr.contains("equal_reconciliation_verified"))
        #expect(wrongChangedCount.execution.exitCode == 2)
        #expect(wrongChangedCount.execution.stderr.contains("changed_delivery_verified"))
    }

    private func runAnalyzer(
        rawFreeMemoryStep: Double,
        appPhysicalStep: Double,
        mutateSamples: (inout [[String: Any]]) -> Void = { _ in },
        mutateProgress: (inout [[String: Any]]) -> Void = { _ in }
    ) async throws -> (execution: ProcessResult, report: [String: Any]?) {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "renderer-lifecycle-soak-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let samplesURL = root.appending(path: "samples.jsonl")
        let progressURL = root.appending(path: "progress.jsonl")
        let reportURL = root.appending(path: "report.json")
        var samples = fixtureSamples(
            rawFreeMemoryStep: rawFreeMemoryStep,
            appPhysicalStep: appPhysicalStep
        )
        var progress = fixtureProgress()
        mutateSamples(&samples)
        mutateProgress(&progress)
        try writeJSONLines(samples, to: samplesURL)
        try writeJSONLines(progress, to: progressURL)

        let execution = try await DefaultProcessExecutor(timeout: 20).execute(
            command: "/usr/bin/python3",
            args: [
                analyzerPath,
                "--samples", samplesURL.path,
                "--progress", progressURL.path,
                "--report", reportURL.path,
            ],
            cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            environment: ["PYTHONDONTWRITEBYTECODE": "1"]
        )
        let report: [String: Any]?
        if let data = try? Data(contentsOf: reportURL) {
            report = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } else {
            report = nil
        }
        return (execution, report)
    }

    private func fixtureSamples(rawFreeMemoryStep: Double, appPhysicalStep: Double) -> [[String: Any]] {
        let warmup = (1...60).map { index in
            sample(window: "warmup", index: index, baseTimestamp: 1000, rawFreeMemoryStep: 0, appPhysicalStep: 0)
        }
        let final = (1...180).map { index in
            sample(
                window: "final",
                index: index,
                baseTimestamp: 2000,
                rawFreeMemoryStep: rawFreeMemoryStep,
                appPhysicalStep: appPhysicalStep
            )
        }
        return warmup + final
    }

    private func sample(
        window: String,
        index: Int,
        baseTimestamp: Double,
        rawFreeMemoryStep: Double,
        appPhysicalStep: Double
    ) -> [String: Any] {
        [
            "marker": "renderer-soak-test",
            "app_pid": 101,
            "windowserver_pid": 202,
            "window": window,
            "window_elapsed_seconds": Double(index * 10),
            "timestamp_seconds": baseTimestamp + Double(index * 10),
            "created_total": 50,
            "active_current": 10,
            "hidden_current": 10,
            "close_undo_current": 0,
            "release_total": 30,
            "free_total": 30,
            "live_current": 20,
            "manager_owned_current": 20,
            "orphan_current": 0,
            "visibility_delivery_total": 100,
            "visibility_equal_suppressed_total": 50,
            "projection_evaluation_total": 100,
            "projection_changed_surface_total": 100,
            "projection_equal_surface_total": 50,
            "lifecycle_valid": 1,
            "sample_sequence": 100,
            "app_physical_bytes": 1000 + Double(index) * appPhysicalStep,
            "app_iosurface_bytes": 1000,
            "app_ioaccelerator_bytes": 1000,
            "windowserver_footprint_bytes": 1000,
            "compressor_bytes": 1000,
            "swap_used_bytes": 1000,
            "raw_free_memory_bytes": 100_000 + Double(index) * rawFreeMemoryStep,
        ]
    }

    private func fixtureProgress() -> [[String: Any]] {
        var rows = [
            progress(stage: "fixture_ready", timestamp: 990),
            progress(
                stage: "equal_reconciliation_verified",
                completed: 20,
                expected: 20,
                timestamp: 995
            ),
            progress(
                stage: "changed_delivery_verified",
                completed: 40,
                expected: 40,
                timestamp: 998
            ),
            progress(stage: "warmup_started", timestamp: 1000),
            progress(stage: "warmup_completed", timestamp: 1610),
        ]
        let counts = [
            "tab_switch": 20, "drawer_toggle": 20, "arrangement_switch": 20,
            "background_reactivate": 20, "zoom_retarget": 20, "parent_minimize": 20,
            "drawer_minimize": 20, "window_minimize": 20, "window_occlusion": 20,
            "repair_recreate": 20, "close_immediate_undo": 10, "close_expiry": 10,
        ]
        rows += counts.sorted(by: { $0.key < $1.key }).map { scenario, count in
            progress(
                stage: "scenario_completed",
                scenario: scenario,
                completed: count,
                expected: count,
                timestamp: 1800
            )
        }
        rows.append(progress(stage: "final_window_started", timestamp: 2000))
        rows.append(progress(stage: "final_window_completed", timestamp: 3815))
        return rows
    }

    private func progress(
        stage: String,
        scenario: String = "none",
        completed: Int = 0,
        expected: Int = 0,
        timestamp: Double
    ) -> [String: Any] {
        [
            "marker": "renderer-soak-test",
            "app_pid": 101,
            "windowserver_pid": 202,
            "stage": stage,
            "scenario": scenario,
            "completed_count": completed,
            "expected_count": expected,
            "timestamp_seconds": timestamp,
        ]
    }

    private func writeJSONLines(_ rows: [[String: Any]], to url: URL) throws {
        let data = try rows.map { row in
            try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        }
        let contents = data.map { String(bytes: $0, encoding: .utf8) ?? "" }.joined(separator: "\n") + "\n"
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private var analyzerPath: String { "scripts/analyze-renderer-lifecycle-soak.py" }
}
