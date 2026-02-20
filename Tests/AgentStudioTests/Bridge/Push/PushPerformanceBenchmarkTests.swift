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

    // MARK: - 100-file entity slice push latency (§6.10 line 1042)

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
                EntitySlice(
                    "diffFiles", store: .diff, level: .hot,
                    capture: { (state: DiffState) in state.files },
                    version: { file in file.version },
                    keyToString: { $0 }
                )
            }
        )

        plan.start()
        try await Task.sleep(for: .milliseconds(50))

        // Generate 100-file dictionary (metadata only, no file contents)
        var files: [String: FileManifest] = [:]
        for i in 0..<100 {
            let fileId = "file-\(i)"
            files[fileId] = FileManifest(
                id: fileId,
                version: 1,
                path: "src/components/Component\(i).tsx",
                oldPath: nil,
                changeType: .modified,
                additions: Int.random(in: 1...50),
                deletions: Int.random(in: 1...30),
                size: Int.random(in: 100...10_000),
                contextHash: UUID().uuidString
            )
        }

        // Record the baseline push count (initial observation fires once)
        let baselinePushCount = transport.pushCount

        // Act — mutate the observable state with a 100-file dictionary
        let mutationInstant = ContinuousClock.now
        diffState.files = files

        // Wait for push to arrive at transport
        try await Task.sleep(for: .milliseconds(200))

        // Assert — push was triggered
        XCTAssertGreaterThan(
            transport.pushCount, baselinePushCount,
            "100-file entity slice mutation should trigger at least one push beyond baseline")

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
        print("[PushBenchmark] 100-file entity slice push latency: \(latency)")
        XCTAssertLessThan(
            latency, .milliseconds(32),
            "100-file entity slice push should complete within 32ms (Swift-side observation + encode + transport call). "
                + "Measured: \(latency)")

        plan.stop()
    }
}
