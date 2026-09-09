import Foundation
import Testing

@testable import AgentStudioInfrastructure
@testable import AgentStudioRepoExplorer

@MainActor
@Suite(.serialized)
struct RepoExplorerPerformanceAccumulatorTelemetryTests {
    @Test("ordinary performance inputs aggregate without per-input trace records")
    func ordinaryPerformanceInputsAggregateWithoutPerInputTraceRecords() async throws {
        let traceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo-explorer-aggregate-telemetry-\(UUID().uuidString)", isDirectory: true)
        let runtime = makeRuntime(traceDirectory: traceDirectory, traceName: "repo-explorer-aggregate-telemetry")
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)
        RepoExplorerPerformanceTelemetry.shared.configure(
            traceRuntime: runtime,
            performanceTraceRecorder: recorder
        )
        defer {
            RepoExplorerPerformanceTelemetry.shared.resetForTests()
            try? FileManager.default.removeItem(at: traceDirectory)
        }

        for _ in 0..<1000 {
            RepoExplorerPerformanceTelemetry.shared.record(stage: "capture_rebuild", outcome: "admitted")
        }

        let snapshot = RepoExplorerPerformanceTelemetry.shared.snapshotAndReset()
        try await RepoExplorerPerformanceTelemetry.shared.drainForTests()

        #expect(snapshot.totalRecordedOutcomeCount == 1000)
        #expect(snapshot.count(stage: .captureRebuild, outcome: .admitted) == 1000)
        #expect(snapshot.exactAttributionAdmittedRecordCount == 0)
        #expect(snapshot.exactAttributionCapacityLimitedCount == 0)
        #expect(RepoExplorerPerformanceTelemetry.shared.sequence(for: "capture_rebuild") == 1000)
        #expect(traceContents(runtime: runtime).contains("performance.repo_explorer.keyed_wake") == false)

        let emptyInterval = RepoExplorerPerformanceTelemetry.shared.snapshotAndReset()
        #expect(emptyInterval.totalRecordedOutcomeCount == 0)
        #expect(RepoExplorerPerformanceTelemetry.shared.sequence(for: "capture_rebuild") == 1000)
    }

    @Test("exact diagnostic attribution has a hard admission limit and accounts for shed inputs")
    func exactDiagnosticAttributionHasHardAdmissionLimit() async throws {
        let traceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo-explorer-exact-telemetry-\(UUID().uuidString)", isDirectory: true)
        let runtime = makeRuntime(traceDirectory: traceDirectory, traceName: "repo-explorer-exact-telemetry")
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)
        RepoExplorerPerformanceTelemetry.shared.configure(
            traceRuntime: runtime,
            performanceTraceRecorder: recorder,
            exactAttributionAdmissionLimit: 2
        )
        defer {
            RepoExplorerPerformanceTelemetry.shared.resetForTests()
            try? FileManager.default.removeItem(at: traceDirectory)
        }
        RepoExplorerPerformanceTelemetry.shared.setContext(
            keyClass: "rendered_repo_favorite",
            rowRelation: "affected_row"
        )

        for _ in 0..<4 {
            RepoExplorerPerformanceTelemetry.shared.record(stage: "affected_row", outcome: "changed")
        }

        let snapshot = RepoExplorerPerformanceTelemetry.shared.snapshotAndReset()
        try await RepoExplorerPerformanceTelemetry.shared.drainForTests()
        let contents = traceContents(runtime: runtime)

        #expect(snapshot.totalRecordedOutcomeCount == 4)
        #expect(snapshot.count(stage: .affectedRow, outcome: .changed) == 4)
        #expect(snapshot.exactAttributionAdmittedRecordCount == 2)
        #expect(snapshot.exactAttributionCapacityLimitedCount == 2)
        #expect(contents.components(separatedBy: "\"body\":\"performance.repo_explorer.keyed_wake\"").count - 1 == 2)
    }

    @Test("unknown stage and outcome values contract into fixed other buckets")
    func unknownValuesContractIntoFixedOtherBuckets() {
        let traceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo-explorer-other-telemetry-\(UUID().uuidString)", isDirectory: true)
        let runtime = makeRuntime(traceDirectory: traceDirectory, traceName: "repo-explorer-other-telemetry")
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)
        RepoExplorerPerformanceTelemetry.shared.configure(
            traceRuntime: runtime,
            performanceTraceRecorder: recorder
        )
        defer {
            RepoExplorerPerformanceTelemetry.shared.resetForTests()
            try? FileManager.default.removeItem(at: traceDirectory)
        }

        RepoExplorerPerformanceTelemetry.shared.record(
            stage: "private-unbounded-stage",
            outcome: "private-unbounded-outcome"
        )

        let snapshot = RepoExplorerPerformanceTelemetry.shared.snapshotAndReset()

        #expect(snapshot.count(stage: .other, outcome: .other) == 1)
        #expect(
            snapshot.stageOutcomeCounts.count <= RepoExplorerPerformanceStage.allCases.count
                * RepoExplorerPerformanceOutcome.allCases.count)
    }

    @Test("projection worker retains its exact bounded stage bucket")
    func projectionWorkerRetainsExactStageBucket() {
        let traceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo-explorer-projection-worker-telemetry-\(UUID().uuidString)", isDirectory: true)
        let runtime = makeRuntime(traceDirectory: traceDirectory, traceName: "repo-explorer-projection-worker")
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)
        RepoExplorerPerformanceTelemetry.shared.configure(
            traceRuntime: runtime,
            performanceTraceRecorder: recorder
        )
        defer {
            RepoExplorerPerformanceTelemetry.shared.resetForTests()
            try? FileManager.default.removeItem(at: traceDirectory)
        }

        RepoExplorerPerformanceTelemetry.shared.record(stage: "projection_worker", outcome: "published")

        let snapshot = RepoExplorerPerformanceTelemetry.shared.snapshotAndReset()

        #expect(snapshot.count(stage: .projectionWorker, outcome: .published) == 1)
        #expect(snapshot.count(stage: .other, outcome: .published) == 0)
    }

    @Test("row body records require exact context and have an independent hard admission limit")
    func rowBodyRecordsRequireExactContextAndHaveIndependentLimit() {
        let traceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo-explorer-row-body-admission-\(UUID().uuidString)", isDirectory: true)
        let runtime = makeRuntime(traceDirectory: traceDirectory, traceName: "repo-explorer-row-body-admission")
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)
        RepoExplorerPerformanceTelemetry.shared.configure(
            traceRuntime: runtime,
            performanceTraceRecorder: recorder,
            exactAttributionAdmissionLimit: 2
        )
        defer {
            RepoExplorerPerformanceTelemetry.shared.resetForTests()
            try? FileManager.default.removeItem(at: traceDirectory)
        }

        #expect(RepoExplorerPerformanceTelemetry.shared.admitExactRowBodyRecord() == false)
        RepoExplorerPerformanceTelemetry.shared.setContext(keyClass: "rendered_repo_favorite")
        #expect(RepoExplorerPerformanceTelemetry.shared.admitExactRowBodyRecord())
        #expect(RepoExplorerPerformanceTelemetry.shared.admitExactRowBodyRecord())
        #expect(RepoExplorerPerformanceTelemetry.shared.admitExactRowBodyRecord() == false)

        RepoExplorerPerformanceTelemetry.shared.record(stage: "affected_row", outcome: "changed")
        let snapshot = RepoExplorerPerformanceTelemetry.shared.snapshotAndReset()
        #expect(snapshot.exactAttributionAdmittedRecordCount == 1)
        #expect(snapshot.exactAttributionCapacityLimitedCount == 1)
    }

    private func makeRuntime(traceDirectory: URL, traceName: String) -> AgentStudioTraceRuntime {
        AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": traceName,
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 940,
            timeUnixNano: { 800 }
        )
    }

    private func traceContents(runtime: AgentStudioTraceRuntime) -> String {
        guard let outputFileURL = runtime.outputFileURL else { return "" }
        return (try? String(contentsOf: outputFileURL, encoding: .utf8)) ?? ""
    }
}
