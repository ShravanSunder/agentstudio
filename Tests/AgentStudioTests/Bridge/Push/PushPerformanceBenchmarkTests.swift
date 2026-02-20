import Observation
import XCTest

@testable import AgentStudio

@MainActor
final class PushPerformanceBenchmarkTests: XCTestCase {

    // MARK: - Timestamp-recording transport for latency measurement

    /// Records timestamps and payload sizes for each push,
    /// so tests can measure mutation-to-transport latency and wire payload size.
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
                additions: Int.random(in: 1...50),
                deletions: Int.random(in: 1...30),
                size: Int.random(in: 100...10_000),
                contextHash: UUID().uuidString
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

    // MARK: - 100-file initial push (baseline)

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

        XCTAssertGreaterThan(transport.pushCount, baselinePushCount)
        guard let pushInstant = transport.lastPushInstant else {
            XCTFail("Transport should have recorded a push timestamp")
            plan.stop()
            return
        }

        let latency = pushInstant - mutationInstant
        print("[PushBenchmark] 100-file initial push latency: \(latency)")
        XCTAssertLessThan(
            latency, .milliseconds(32),
            "100-file initial push should complete within 32ms. Measured: \(latency)")

        plan.stop()
    }

    // MARK: - 500-file stress test (large monorepo PR)

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

        XCTAssertGreaterThan(transport.pushCount, baselinePushCount)
        guard let pushInstant = transport.lastPushInstant else {
            XCTFail("Transport should have recorded a push timestamp")
            plan.stop()
            return
        }

        let latency = pushInstant - mutationInstant
        print("[PushBenchmark] 500-file initial push latency: \(latency)")
        print("[PushBenchmark] 500-file payload size: \(transport.lastPayloadBytes) bytes")
        XCTAssertLessThan(
            latency, .milliseconds(32),
            "500-file initial push should complete within 32ms. Measured: \(latency)")

        plan.stop()
    }

    // MARK: - Single-file incremental change (EntitySlice sweet spot)

    /// Measures the actual use case EntitySlice optimizes for:
    /// 100 files already loaded, agent updates 1 file's metadata.
    /// Delta should contain only that 1 file, not all 100.
    func test_singleFile_incremental_change_under_2ms() async throws {
        let diffState = DiffState()
        let transport = TimestampingTransport()
        let plan = makeDiffPlan(state: diffState, transport: transport, clock: RevisionClock())

        plan.start()
        try await Task.sleep(for: .milliseconds(50))

        // Load 100 files and wait for initial push to settle
        diffState.files = generateFiles(count: 100)
        try await Task.sleep(for: .milliseconds(200))

        let baselinePushCount = transport.pushCount
        let initialPayloadBytes = transport.lastPayloadBytes

        // Act — change a single file (bump version + mutate field)
        let mutationInstant = ContinuousClock.now
        diffState.files["file-42"]?.additions = 999
        diffState.files["file-42"]?.version += 1
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertGreaterThan(
            transport.pushCount, baselinePushCount,
            "Single-file version bump should trigger a push")
        guard let pushInstant = transport.lastPushInstant else {
            XCTFail("Transport should have recorded a push timestamp")
            plan.stop()
            return
        }

        let latency = pushInstant - mutationInstant
        let deltaPayloadBytes = transport.lastPayloadBytes

        print("[PushBenchmark] single-file incremental latency: \(latency)")
        print("[PushBenchmark] delta payload: \(deltaPayloadBytes) bytes vs initial: \(initialPayloadBytes) bytes")

        // Delta payload should be much smaller than full 100-file payload
        XCTAssertLessThan(
            deltaPayloadBytes, initialPayloadBytes / 5,
            "Single-file delta (\(deltaPayloadBytes)B) should be <20% of full payload (\(initialPayloadBytes)B)")

        // Latency should be sub-2ms for a single entity encode
        XCTAssertLessThan(
            latency, .milliseconds(2),
            "Single-file incremental push should complete within 2ms. Measured: \(latency)")

        plan.stop()
    }

    // MARK: - Rapid sequential mutations (simulates streaming diff results)

    /// Simulates an agent streaming file results: files arrive one at a time
    /// in rapid succession. With .cold debounce (32ms), multiple mutations
    /// should coalesce into fewer pushes.
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
        XCTAssertLessThan(
            pushCount, 10,
            "20 rapid mutations should coalesce to fewer than 10 pushes with cold debounce. Got: \(pushCount)")
        XCTAssertGreaterThan(
            pushCount, 0,
            "At least one push should have fired after debounce")

        // Verify all 20 files arrived (final state is complete regardless of coalescing)
        XCTAssertEqual(diffState.files.count, 20)

        plan.stop()
    }

    // MARK: - Epoch reset worst case (new PR loaded)

    /// Simulates the worst-case scenario: a new PR is loaded (epoch reset),
    /// wiping all files and loading 200 new ones. Measures the full
    /// reset-and-reload cycle latency.
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

        XCTAssertGreaterThan(transport.pushCount, baselinePushCount)
        guard let pushInstant = transport.lastPushInstant else {
            XCTFail("Transport should have recorded a push timestamp")
            plan.stop()
            return
        }

        let latency = pushInstant - mutationInstant
        print("[PushBenchmark] epoch reset + 200-file reload latency: \(latency)")
        print("[PushBenchmark] epoch reset payload: \(transport.lastPayloadBytes) bytes")

        // This is the worst case: EntitySlice sees 100 removed + 200 new = full re-encode
        XCTAssertLessThan(
            latency, .milliseconds(32),
            "Epoch reset + 200-file reload should complete within 32ms. Measured: \(latency)")

        plan.stop()
    }
}
