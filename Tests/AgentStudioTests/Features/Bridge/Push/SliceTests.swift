import Foundation
import Observation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class SliceTests {

    @Observable
    class TestState {
        var status: String = "idle"
        var count: Int = 0
    }

    @Test
    func test_slice_filters_noOp_mutations() async throws {
        // Arrange
        let state = TestState()
        let transport = MockPushTransport()
        let clock = RevisionClock()

        let slice = Slice<TestState, String>(
            "testStatus", store: .diff, level: .hot
        ) { state in
            state.status
        }

        let task = slice.erased().makeTask(state, transport, clock) { 1 }
        try await Task.sleep(for: .milliseconds(50))

        // Observations emits the initial value ("idle"), which triggers the first push
        // since prev starts as nil. Record baseline after initial emission settles.
        let baselineCount = transport.pushCount
        #expect(baselineCount == 1, "Initial observation should trigger one push (initial snapshot differs from nil)")

        // Act — set to the same value (no-op mutation)
        state.status = "idle"
        try await Task.sleep(for: .milliseconds(100))

        // Assert — no additional push because value did not change (Equatable skip)
        #expect(transport.pushCount == baselineCount, "Setting same value should not trigger push (Equatable skip)")

        // Act — set to a different value
        state.status = "loading"
        try await Task.sleep(for: .milliseconds(100))

        // Assert — push triggered for actual change
        #expect(transport.pushCount == baselineCount + 1, "Setting different value should trigger one additional push")

        task.cancel()
    }

    @Test
    func test_hot_slice_pushes_immediately() async throws {
        // Arrange
        let state = TestState()
        let transport = MockPushTransport()
        let clock = RevisionClock()

        let slice = Slice<TestState, String>(
            "testStatus", store: .diff, level: .hot
        ) { state in
            state.status
        }

        let task = slice.erased().makeTask(state, transport, clock) { 1 }
        try await Task.sleep(for: .milliseconds(50))

        // Observations emits initial value first; record baseline
        let baselineCount = transport.pushCount

        // Act
        state.status = "loading"
        try await Task.sleep(for: .milliseconds(50))

        // Assert — one additional push for the mutation
        #expect(transport.pushCount == baselineCount + 1)
        #expect(transport.lastStore == .diff)
        #expect(transport.lastLevel == .hot)
        #expect(transport.lastOp == .replace)

        task.cancel()
    }

    @Test
    func test_slice_stamps_revision() async throws {
        // Arrange
        let state = TestState()
        let transport = MockPushTransport()
        let clock = RevisionClock()

        let task = Slice<TestState, String>(
            "testStatus", store: .diff, level: .hot
        ) { state in state.status }
        .erased().makeTask(state, transport, clock) { 1 }

        try await Task.sleep(for: .milliseconds(50))

        // Initial emission gets revision 1
        #expect(transport.lastRevision == 1, "Initial observation emission should stamp revision 1")

        // Act — first mutation
        state.status = "loading"
        try await Task.sleep(for: .milliseconds(100))

        // Assert — second revision (initial was 1, this mutation is 2)
        #expect(transport.lastRevision == 2)

        // Act — second mutation
        state.status = "ready"
        try await Task.sleep(for: .milliseconds(100))

        // Assert — third revision
        #expect(transport.lastRevision == 3)

        task.cancel()
    }
}

// MARK: - MockPushTransport

/// Test double for PushTransport — shared across push pipeline tests.
@MainActor
final class MockPushTransport: PushTransport {
    var pushCount = 0
    var lastStore: StoreKey?
    var lastOp: PushOp?
    var lastLevel: PushLevel?
    var lastRevision: Int?
    var lastEpoch: Int?
    var lastJSON: Data?

    func pushJSON(
        store: StoreKey, op: PushOp, level: PushLevel,
        revision: Int, epoch: Int, json: Data
    ) async {
        pushCount += 1
        lastStore = store
        lastOp = op
        lastLevel = level
        lastRevision = revision
        lastEpoch = epoch
        lastJSON = json
    }

    func waitForPushCount(
        atLeast expectedCount: Int,
        timeout: Duration = .seconds(5)
    ) async -> Bool {
        if pushCount >= expectedCount { return true }

        let deadline = ContinuousClock().now.advanced(by: timeout)
        while pushCount < expectedCount && ContinuousClock().now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        return pushCount >= expectedCount
    }

    /// Timer-agnostic wait helper used by tests that advance a mock clock.
    /// Provide a closure that moves mocked time forward and this helper polls
    /// `pushCount` with cooperative yields between ticks.
    func waitForPushCount(
        atLeast expectedCount: Int,
        maxTicks: Int,
        advanceClock: @MainActor () -> Void
    ) async -> Bool {
        if pushCount >= expectedCount { return true }
        guard maxTicks > 0 else { return false }

        for _ in 0..<maxTicks {
            if pushCount >= expectedCount { return true }
            advanceClock()
            await Task.yield()
        }
        return pushCount >= expectedCount
    }
}
