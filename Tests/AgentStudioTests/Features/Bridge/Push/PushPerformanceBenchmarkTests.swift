import Foundation
import Observation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class PushPerformanceBenchmarkTests {

    private struct SingleFileIncrementalBenchmarkResult {
        let benchmarkMode: PushBenchmarkMode
        let stats: PushBenchmarkStats
        let payloadRatio: Double
    }

    // MARK: - Timestamp-recording transport for latency measurement

    /// Records timestamps and payload sizes for each push,
    /// so tests can measure mutation-to-transport latency and wire payload size.
    @MainActor
    final class TimestampingTransport: PushTransport {
        var pushCount = 0
        var lastPushInstant: ContinuousClock.Instant?
        var lastPayloadBytes: Int = 0
        var allPayloadBytes: [Int] = []

        func pushJSON(
            store: StoreKey, op: PushOp, level: PushLevel,
            revision: Int, epoch: Int, json: Data
        ) async {
            pushCount += 1
            lastPushInstant = ContinuousClock.now
            lastPayloadBytes = json.count
            allPayloadBytes.append(json.count)
        }

        func waitForPushCount(
            atLeast expectedCount: Int,
            timeout: Duration = .seconds(1)
        ) async -> Bool {
            if pushCount >= expectedCount {
                return true
            }

            let deadline = ContinuousClock().now.advanced(by: timeout)
            while pushCount < expectedCount && ContinuousClock().now < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }

            return pushCount >= expectedCount
        }
    }

    // MARK: - Helpers

    /// Generate a dictionary of FileManifest entries keyed by file ID.
    private func generateFiles(count: Int, version: Int = 1) -> [String: FileManifest] {
        var files: [String: FileManifest] = [:]
        for i in 0..<count {
            let fileId = "file-\(i)"
            files[fileId] = FileManifest(
                id: fileId,
                version: version,
                path: "src/components/Component\(i).tsx",
                oldPath: nil,
                changeType: .modified,
                additions: 1 + (i % 50),
                deletions: i % 31,
                size: 100 + (i * 97),
                contextHash: "hash-\(version)-\(i)"
            )
        }
        return files
    }

    /// Create a PushPlan with an EntitySlice for diffFiles at the given level.
    private func makeDiffPlan(
        state: DiffState, transport: PushTransport, clock: RevisionClock, level: PushLevel = .hot
    ) -> PushPlan<DiffState> {
        PushPlan(
            state: state,
            transport: transport,
            revisions: clock,
            epoch: { state.epoch },
            slices: {
                EntitySlice(
                    "diffFiles", store: .diff, level: level,
                    capture: { (state: DiffState) in state.files },
                    version: { file in file.version },
                    keyToString: { $0 }
                )
            }
        )
    }

    private func waitForPushCount(
        _ transport: TimestampingTransport,
        targetCount: Int,
        timeout: Duration = .seconds(1)
    ) async -> Bool {
        await transport.waitForPushCount(atLeast: targetCount, timeout: timeout)
    }

    private func isBenchmarkRunEnabled() -> Bool {
        PushBenchmarkMode.current == .benchmark
    }

    private func runSingleFileIncrementalBenchmark(
        fileCount: Int = 100,
        warmupIterations: Int = 4,
        measuredIterations: Int = 12
    ) async throws -> SingleFileIncrementalBenchmarkResult {
        let diffState = DiffState()
        let transport = TimestampingTransport()
        let plan = makeDiffPlan(state: diffState, transport: transport, clock: RevisionClock())
        defer { plan.stop() }
        let state = diffState

        plan.start()

        state.replaceFiles(generateFiles(count: fileCount))
        let loaded = await waitForPushCount(
            transport,
            targetCount: 1,
            timeout: .seconds(2)
        )
        #expect(loaded, "Initial file-load push should appear")

        let initialPayloadBytes = transport.lastPayloadBytes

        var durationSamples: [Duration] = []
        var payloadSamples: [Int] = []
        var ratioSamples: [Double] = []

        // warmup runs stabilize the first-pass allocator/caching behavior
        for _ in 0..<warmupIterations {
            let file = "file-42"

            state.mutateFile(id: file) { updatedFile in
                updatedFile.additions += 1
                updatedFile.version += 1
            }

            let observed = await waitForPushCount(
                transport, targetCount: transport.pushCount + 1, timeout: .seconds(1))
            #expect(observed, "Warmup push should appear for single-file mutation")
        }

        for _ in 0..<measuredIterations {
            let file = "file-42"
            let mutationStart = ContinuousClock.now

            state.mutateFile(id: file) { fileToMutate in
                fileToMutate.additions += 1
                fileToMutate.version += 1
            }

            let observed = await waitForPushCount(
                transport, targetCount: transport.pushCount + 1, timeout: .seconds(1))
            #expect(observed, "Single-file mutation should trigger a push")
            let pushTime = try #require(
                transport.lastPushInstant, "Transport should have recorded a push timestamp")

            durationSamples.append(pushTime - mutationStart)
            payloadSamples.append(transport.lastPayloadBytes)
            if initialPayloadBytes > 0 {
                ratioSamples.append(Double(transport.lastPayloadBytes) / Double(initialPayloadBytes))
            }
        }

        let stats = PushBenchmarkStats(
            durations: durationSamples,
            payloadBytes: payloadSamples,
            initialPayloadBytes: initialPayloadBytes
        )

        return SingleFileIncrementalBenchmarkResult(
            benchmarkMode: PushBenchmarkMode.current,
            stats: stats,
            payloadRatio: ratioSamples.max() ?? 0
        )
    }

    // MARK: - 100-file initial push (baseline)

    @Test
    func test_100file_manifest_push_under_32ms() async throws {
        guard isBenchmarkRunEnabled() else {
            return
        }
        let diffState = DiffState()
        let transport = TimestampingTransport()
        let plan = makeDiffPlan(state: diffState, transport: transport, clock: RevisionClock())
        defer { plan.stop() }

        plan.start()

        let files = generateFiles(count: 100)
        let baselinePushCount = transport.pushCount
        let benchmarkMode = PushBenchmarkMode.current

        let mutationInstant = ContinuousClock.now
        diffState.replaceFiles(files)

        let observed = await waitForPushCount(
            transport,
            targetCount: baselinePushCount + 1,
            timeout: .seconds(2)
        )
        #expect(observed, "100-file initial push should be observed")

        let pushInstant = try #require(
            transport.lastPushInstant,
            "Transport should have recorded a push timestamp"
        )

        let latency = pushInstant - mutationInstant
        print("[PushBenchmark] 100-file initial push latency: \(latency)")
        assertPushBenchmarkThreshold(
            mode: benchmarkMode,
            benchmarkName: "100-file initial push latency",
            measured: latency,
            threshold: .milliseconds(150)
        )
    }

    // MARK: - 500-file stress test (large monorepo PR)

    @Test
    func test_500file_manifest_push_under_32ms() async throws {
        guard isBenchmarkRunEnabled() else {
            return
        }
        let diffState = DiffState()
        let transport = TimestampingTransport()
        let plan = makeDiffPlan(state: diffState, transport: transport, clock: RevisionClock())
        defer { plan.stop() }

        plan.start()

        let files = generateFiles(count: 500)
        let baselinePushCount = transport.pushCount
        let benchmarkMode = PushBenchmarkMode.current

        let mutationInstant = ContinuousClock.now
        diffState.replaceFiles(files)

        let observed = await waitForPushCount(
            transport,
            targetCount: baselinePushCount + 1,
            timeout: .seconds(2)
        )
        #expect(observed, "500-file initial push should be observed")

        let pushInstant = try #require(
            transport.lastPushInstant,
            "Transport should have recorded a push timestamp"
        )

        let latency = pushInstant - mutationInstant
        print("[PushBenchmark] 500-file initial push latency: \(latency)")
        print("[PushBenchmark] 500-file payload size: \(transport.lastPayloadBytes) bytes")
        assertPushBenchmarkThreshold(
            mode: benchmarkMode,
            benchmarkName: "500-file initial push latency",
            measured: latency,
            threshold: .milliseconds(300)
        )
    }

    // MARK: - Single-file incremental change (EntitySlice sweet spot)

    /// Measures the actual use case EntitySlice optimizes for:
    /// 100 files already loaded, agent updates 1 file's metadata.
    /// Delta should contain only that 1 file, not all 100.
    @Test
    func test_singleFile_incremental_payload_stays_small() async throws {
        guard isBenchmarkRunEnabled() else {
            return
        }
        let result = try await runSingleFileIncrementalBenchmark(
            warmupIterations: 1,
            measuredIterations: 3
        )

        #expect(!result.stats.durations.isEmpty)
        #expect(result.payloadRatio < 0.2, "Single-file payload delta should stay under 20%")
    }

    /// Benchmark-only latency measurement for single-file incremental updates.
    @Test
    func test_singleFile_incremental_change_under_2ms() async throws {
        guard isBenchmarkRunEnabled() else {
            return
        }
        let result = try await runSingleFileIncrementalBenchmark()

        print(result.stats.summary(for: "single-file incremental"))
        assertPushBenchmarkThreshold(
            mode: result.benchmarkMode,
            benchmarkName: "single-file incremental p95",
            measured: result.stats.p95,
            threshold: .milliseconds(5)
        )
    }

    // MARK: - Rapid sequential mutations (simulates streaming diff results)

    /// Simulates an agent streaming file results: files arrive one at a time
    /// in rapid succession. With .cold debounce (32ms), multiple mutations
    /// should coalesce into fewer pushes.
    @Test
    func test_rapid_mutations_coalesce_with_cold_debounce() async throws {
        let diffState = DiffState()
        let transport = TimestampingTransport()
        // Use .cold level (32ms debounce) matching production configuration
        let plan = makeDiffPlan(
            state: diffState, transport: transport, clock: RevisionClock(), level: .cold)
        defer { plan.stop() }

        plan.start()

        let baselinePushCount = transport.pushCount

        // Act — add 20 files back-to-back to force debounce coalescing.
        for i in 0..<20 {
            let fileId = "rapid-\(i)"
            diffState.setFile(
                FileManifest(
                    id: fileId,
                    version: 1,
                    path: "src/rapid/File\(i).tsx",
                    oldPath: nil,
                    changeType: .added,
                    additions: 10,
                    deletions: 0,
                    size: 500,
                    contextHash: "hash-\(i)"
                )
            )
        }

        let observed = await waitForPushCount(
            transport,
            targetCount: baselinePushCount + 1,
            timeout: .seconds(2)
        )
        #expect(observed, "Rapid mutation burst should trigger at least one debounced push")

        let pushCount = transport.pushCount - baselinePushCount

        print("[PushBenchmark] 20 rapid mutations (burst, 32ms debounce) -> \(pushCount) pushes")

        #expect(
            pushCount < 20,
            "20 rapid mutations should coalesce into fewer than 20 pushes. Got: \(pushCount)"
        )
        #expect(pushCount > 0, "At least one push should have fired after debounce")
        #expect(diffState.files.count == 20)
    }

    // MARK: - Epoch reset worst case (new PR loaded)

    /// Simulates the worst-case scenario: a new PR is loaded (epoch reset),
    /// wiping all files and loading 200 new ones. Measures the full
    /// reset-and-reload cycle latency.
    @Test
    func test_epoch_reset_and_reload_under_32ms() async throws {
        guard isBenchmarkRunEnabled() else {
            return
        }
        let diffState = DiffState()
        let transport = TimestampingTransport()
        let plan = makeDiffPlan(state: diffState, transport: transport, clock: RevisionClock())
        defer { plan.stop() }

        plan.start()

        // Pre-load 100 files from "old PR"
        diffState.replaceFiles(generateFiles(count: 100))
        let preloaded = await waitForPushCount(
            transport,
            targetCount: 1,
            timeout: .seconds(2)
        )
        #expect(preloaded, "Preload push should be observed before epoch reset")

        let baselinePushCount = transport.pushCount
        let benchmarkMode = PushBenchmarkMode.current

        // Act — epoch reset: clear files and load 200 new ones (new PR)
        let mutationInstant = ContinuousClock.now
        diffState.advanceEpoch()
        diffState.replaceFiles(generateFiles(count: 200, version: 1))

        let observed = await waitForPushCount(
            transport,
            targetCount: baselinePushCount + 1,
            timeout: .seconds(2)
        )
        #expect(observed, "Epoch reset + reload should trigger a push")

        let pushInstant = try #require(
            transport.lastPushInstant,
            "Transport should have recorded a push timestamp"
        )

        let latency = pushInstant - mutationInstant
        print("[PushBenchmark] epoch reset + 200-file reload latency: \(latency)")
        print("[PushBenchmark] epoch reset payload: \(transport.lastPayloadBytes) bytes")
        #expect(diffState.files.count == 200)

        assertPushBenchmarkThreshold(
            mode: benchmarkMode,
            benchmarkName: "epoch reset + 200-file reload latency",
            measured: latency,
            threshold: .milliseconds(32)
        )
    }
}
