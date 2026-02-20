import Observation
import XCTest

@testable import AgentStudio

@MainActor
final class PushPerformanceBenchmarkTests: XCTestCase {

    // MARK: - Timestamp-recording transport for latency measurement

    /// Records the `ContinuousClock.Instant` when each push arrives,
    /// so the test can measure mutation-to-transport latency without
    /// including the sleep wait in the measurement.
    final class TimestampingTransport: PushTransport {
        var pushCount = 0
        var lastPushInstant: ContinuousClock.Instant?

        func pushJSON(
            store: StoreKey, op: PushOp, level: PushLevel,
            revision: Int, epoch: Int, json: Data
        ) async {
            pushCount += 1
            lastPushInstant = ContinuousClock.now
        }
    }

    // MARK: - 100-file manifest push latency (§6.10 line 1042)

    func test_100file_manifest_push_under_32ms() async throws {
        // Arrange
        let diffState = DiffState()
        let transport = TimestampingTransport()
        let clock = RevisionClock()

        let plan = PushPlan(
            state: diffState,
            transport: transport,
            revisions: clock,
            epoch: { diffState.epoch },
            slices: {
                Slice("diffManifest", store: .diff, level: .hot, op: .replace) { state in
                    state.manifest  // Using .hot to measure raw push time without debounce
                }
            }
        )

        plan.start()
        try await Task.sleep(for: .milliseconds(50))

        // Generate 100-file manifest (metadata only, no file contents)
        let manifest = DiffManifest(
            files: (0..<100).map { i in
                FileManifest(
                    id: UUID().uuidString,
                    path: "src/components/Component\(i).tsx",
                    oldPath: nil,
                    changeType: .modified,
                    additions: Int.random(in: 1...50),
                    deletions: Int.random(in: 1...30),
                    size: Int.random(in: 100...10_000),
                    contextHash: UUID().uuidString
                )
            })

        // Record the baseline push count (initial observation fires once)
        let baselinePushCount = transport.pushCount

        // Act — mutate the observable state with a 100-file manifest
        let mutationInstant = ContinuousClock.now
        diffState.manifest = manifest

        // Wait for push to arrive at transport
        try await Task.sleep(for: .milliseconds(200))

        // Assert — push was triggered
        XCTAssertGreaterThan(
            transport.pushCount, baselinePushCount,
            "100-file manifest mutation should trigger at least one push beyond baseline")

        guard let pushInstant = transport.lastPushInstant else {
            XCTFail("Transport should have recorded a push timestamp")
            plan.stop()
            return
        }

        // Measure actual latency: mutation instant → transport receipt instant
        let latency = pushInstant - mutationInstant

        // Target: < 32ms from mutation to transport.pushJSON call
        // Note: This measures Swift-side only (observation + JSON encode + pushJSON call).
        // Full end-to-end includes JS JSON.parse + store update.
        print("[PushBenchmark] 100-file manifest push latency: \(latency)")
        XCTAssertLessThan(
            latency, .milliseconds(32),
            "100-file manifest push should complete within 32ms (Swift-side observation + encode + transport call). "
                + "Measured: \(latency)")

        plan.stop()
    }
}
