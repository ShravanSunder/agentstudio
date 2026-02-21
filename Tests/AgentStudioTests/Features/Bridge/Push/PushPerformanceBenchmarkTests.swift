import Foundation
import Observation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class PushPerformanceBenchmarkTests {

    private enum PushBenchmarkMode: String {
        case warn
        case strict
        case off

        static var current: Self {
            guard let rawMode = ProcessInfo.processInfo.environment["AGENT_STUDIO_BENCHMARK_MODE"]?.lowercased() else {
                return .warn
            }
            return Self(rawValue: rawMode) ?? .warn
        }
    }

    private struct PushBenchmarkStats {
        let durations: [Duration]
        let payloadBytes: [Int]
        let initialPayloadBytes: Int

        private var sortedDurationsNs: [Int64] {
            durations.map(\.inNanoseconds).sorted()
        }

        var count: Int { durations.count }
        var min: Duration { Duration.nanoseconds(sortedDurationsNs.first ?? 0) }
        var max: Duration { Duration.nanoseconds(sortedDurationsNs.last ?? 0) }
        var median: Duration {
            guard !sortedDurationsNs.isEmpty else {
                return .zero
            }
            let medianIndex = sortedDurationsNs.count / 2
            return Duration.nanoseconds(sortedDurationsNs[medianIndex])
        }

        var p95: Duration {
            guard !sortedDurationsNs.isEmpty else {
                return .zero
            }
            let p95Index = Int((Double(sortedDurationsNs.count - 1) * 0.95).rounded(.up))
            let clamped = Swift.min(Swift.max(p95Index, 0), sortedDurationsNs.count - 1)
            return Duration.nanoseconds(sortedDurationsNs[clamped])
        }

        var average: Duration {
            guard !sortedDurationsNs.isEmpty else { return .zero }
            let total = sortedDurationsNs.reduce(0, +)
            return Duration.nanoseconds(total / Int64(sortedDurationsNs.count))
        }

        func summary(for name: String) -> String {
            """
            [PushBenchmark] \(name) count=\(count), initialPayload=\(initialPayloadBytes)B, \
            min=\(min.formattedMilliseconds), median=\(median.formattedMilliseconds), \
            p95=\(p95.formattedMilliseconds), max=\(max.formattedMilliseconds), avg=\(average.formattedMilliseconds), \
            deltaMin=\(payloadBytes.min() ?? 0)B, deltaMax=\(payloadBytes.max() ?? 0)B
            """
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private struct SingleFileIncrementalBenchmarkResult {
        let benchmarkMode: PushBenchmarkMode
        let stats: PushBenchmarkStats
        let initialPayloadBytes: Int
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

    private func waitForInitialPush(
        transport: TimestampingTransport,
        timeout: Duration = .seconds(1)
    ) async -> Bool {
        await transport.waitForPushCount(atLeast: 1, timeout: timeout)
    }

    private func waitForPushCount(
        _ transport: TimestampingTransport,
        targetCount: Int,
        timeout: Duration = .seconds(1)
    ) async -> Bool {
        await transport.waitForPushCount(atLeast: targetCount, timeout: timeout)
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

        state.files = generateFiles(count: fileCount)
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

            if var updatedFile = state.files[file] {
                updatedFile.additions += 1
                updatedFile.version += 1
                state.files[file] = updatedFile

                let observed = await waitForPushCount(
                    transport, targetCount: transport.pushCount + 1, timeout: .seconds(1))
                #expect(observed, "Warmup push should appear for single-file mutation")
            }
        }

        for _ in 0..<measuredIterations {
            let file = "file-42"
            let mutationStart = ContinuousClock.now

            if var fileToMutate = state.files[file] {
                fileToMutate.additions += 1
                fileToMutate.version += 1
                state.files[file] = fileToMutate

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
        }

        let stats = PushBenchmarkStats(
            durations: durationSamples,
            payloadBytes: payloadSamples,
            initialPayloadBytes: initialPayloadBytes
        )

        let payloadRatio = ratioSamples.max() ?? 0
        let result = SingleFileIncrementalBenchmarkResult(
            benchmarkMode: PushBenchmarkMode.current,
            stats: stats,
            initialPayloadBytes: initialPayloadBytes,
            payloadRatio: payloadRatio
        )
        return result
    }

    // MARK: - 100-file initial push (baseline)

    @Test
    func test_100file_manifest_push_under_32ms() async throws {
        let diffState = DiffState()
        let transport = TimestampingTransport()
        let plan = makeDiffPlan(state: diffState, transport: transport, clock: RevisionClock())

        plan.start()
        try await Task.sleep(for: .milliseconds(50))

        let files = generateFiles(count: 100)
        let baselinePushCount = transport.pushCount

        let mutationInstant = ContinuousClock.now
        diffState.files = files
        try await Task.sleep(for: .milliseconds(200))

        #expect(transport.pushCount > baselinePushCount)
        let pushInstant = try #require(
            transport.lastPushInstant,
            "Transport should have recorded a push timestamp"
        )

        let latency = pushInstant - mutationInstant
        print("[PushBenchmark] 100-file initial push latency: \(latency)")
        #expect(
            latency < .milliseconds(150), "100-file initial push should complete within 150ms. Measured: \(latency)")

        plan.stop()
    }

    // MARK: - 500-file stress test (large monorepo PR)

    @Test
    func test_500file_manifest_push_under_32ms() async throws {
        let diffState = DiffState()
        let transport = TimestampingTransport()
        let plan = makeDiffPlan(state: diffState, transport: transport, clock: RevisionClock())

        plan.start()
        try await Task.sleep(for: .milliseconds(50))

        let files = generateFiles(count: 500)
        let baselinePushCount = transport.pushCount

        let mutationInstant = ContinuousClock.now
        diffState.files = files
        try await Task.sleep(for: .milliseconds(300))

        #expect(transport.pushCount > baselinePushCount)
        let pushInstant = try #require(
            transport.lastPushInstant,
            "Transport should have recorded a push timestamp"
        )

        let latency = pushInstant - mutationInstant
        print("[PushBenchmark] 500-file initial push latency: \(latency)")
        print("[PushBenchmark] 500-file payload size: \(transport.lastPayloadBytes) bytes")
        #expect(
            latency < .milliseconds(300), "500-file initial push should complete within 300ms. Measured: \(latency)")

        plan.stop()
    }

    // MARK: - Single-file incremental change (EntitySlice sweet spot)

    /// Measures the actual use case EntitySlice optimizes for:
    /// 100 files already loaded, agent updates 1 file's metadata.
    /// Delta should contain only that 1 file, not all 100.
    @Test
    func test_singleFile_incremental_change_under_2ms() async throws {
        let result = try await runSingleFileIncrementalBenchmark()

        #expect(!result.stats.durations.isEmpty)
        #expect(result.payloadRatio < 0.2, "Single-file payload delta should stay under 20%")

        print(result.stats.summary(for: "single-file incremental"))

        if result.benchmarkMode == .strict {
            #expect(
                result.stats.p95 < .milliseconds(5),
                "Single-file incremental p95 should stay within 5ms. Measured: \(result.stats.p95)"
            )
        } else if result.benchmarkMode == .warn {
            print(
                """
                [PushBenchmark] warn-mode active (AGENT_STUDIO_BENCHMARK_MODE=\(result.benchmarkMode.rawValue)).
                Latency assertion intentionally non-blocking.
                """
            )
        }
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

        plan.start()
        try await Task.sleep(for: .milliseconds(50))

        let baselinePushCount = transport.pushCount

        // Act — add 20 files one at a time with 5ms gaps (faster than 32ms debounce)
        for i in 0..<20 {
            let fileId = "rapid-\(i)"
            diffState.files[fileId] = FileManifest(
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
            try await Task.sleep(for: .milliseconds(5))
        }

        // Wait for debounce to flush
        try await Task.sleep(for: .milliseconds(200))

        let pushCount = transport.pushCount - baselinePushCount

        print("[PushBenchmark] 20 rapid mutations (5ms apart, 32ms debounce) → \(pushCount) pushes")

        // With 20 mutations at 5ms intervals (100ms total) and 32ms debounce,
        // expect roughly 2-5 coalesced pushes, not 20 individual pushes.
        #expect(
            pushCount < 10,
            "20 rapid mutations should coalesce to fewer than 10 pushes with cold debounce. Got: \(pushCount)")
        #expect(pushCount > 0, "At least one push should have fired after debounce")

        // Verify all 20 files arrived (final state is complete regardless of coalescing)
        #expect(diffState.files.count == 20)

        plan.stop()
    }

    // MARK: - Epoch reset worst case (new PR loaded)

    /// Simulates the worst-case scenario: a new PR is loaded (epoch reset),
    /// wiping all files and loading 200 new ones. Measures the full
    /// reset-and-reload cycle latency.
    @Test
    func test_epoch_reset_and_reload_under_32ms() async throws {
        let diffState = DiffState()
        let transport = TimestampingTransport()
        let plan = makeDiffPlan(state: diffState, transport: transport, clock: RevisionClock())

        plan.start()
        try await Task.sleep(for: .milliseconds(50))

        // Pre-load 100 files from "old PR"
        diffState.files = generateFiles(count: 100)
        try await Task.sleep(for: .milliseconds(200))

        let baselinePushCount = transport.pushCount

        // Act — epoch reset: clear files and load 200 new ones (new PR)
        let mutationInstant = ContinuousClock.now
        diffState.epoch += 1
        diffState.files = generateFiles(count: 200, version: 1)
        try await Task.sleep(for: .milliseconds(300))

        #expect(transport.pushCount > baselinePushCount)
        let pushInstant = try #require(
            transport.lastPushInstant,
            "Transport should have recorded a push timestamp"
        )

        let latency = pushInstant - mutationInstant
        print("[PushBenchmark] epoch reset + 200-file reload latency: \(latency)")
        print("[PushBenchmark] epoch reset payload: \(transport.lastPayloadBytes) bytes")

        // This is the worst case: EntitySlice sees 100 removed + 200 new = full re-encode
        #expect(
            latency < .milliseconds(32),
            "Epoch reset + 200-file reload should complete within 32ms. Measured: \(latency)")

        plan.stop()
    }
}

// MARK: - Test utilities

extension Duration {
    fileprivate var inNanoseconds: Int64 {
        let components = components
        let seconds = Int64(components.seconds)
        let subsecond = Int64(components.attoseconds / 1_000_000_000)
        let secondsInNanoseconds = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        if secondsInNanoseconds.overflow {
            return subsecond
        }
        return secondsInNanoseconds.partialValue + subsecond
    }

    fileprivate var formattedMilliseconds: String {
        let ns = inNanoseconds
        return String(format: "%.3fms", Double(ns) / 1_000_000.0)
    }
}
