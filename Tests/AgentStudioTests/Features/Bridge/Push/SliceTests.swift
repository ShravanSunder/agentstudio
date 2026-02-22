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
        #expect(await transport.waitForPushCount(atLeast: 1))

        // Observations emits the initial value ("idle"), which triggers the first push
        // since prev starts as nil. Record baseline after initial emission settles.
        let baselineCount = transport.pushCount
        #expect(baselineCount == 1, "Initial observation should trigger one push (initial snapshot differs from nil)")

        // Act — set to the same value (no-op mutation)
        state.status = "idle"
        await Task.yield()

        // Assert — no additional push because value did not change (Equatable skip)
        #expect(transport.pushCount == baselineCount, "Setting same value should not trigger push (Equatable skip)")

        // Act — set to a different value
        state.status = "loading"
        #expect(await transport.waitForPushCount(atLeast: baselineCount + 1))

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
        #expect(await transport.waitForPushCount(atLeast: 1))

        // Observations emits initial value first; record baseline
        let baselineCount = transport.pushCount

        // Act
        state.status = "loading"
        #expect(await transport.waitForPushCount(atLeast: baselineCount + 1))

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

        #expect(await transport.waitForPushCount(atLeast: 1))

        // Initial emission gets revision 1
        #expect(transport.lastRevision == 1, "Initial observation emission should stamp revision 1")

        // Act — first mutation
        state.status = "loading"
        #expect(await transport.waitForPushCount(atLeast: 2))

        // Assert — second revision (initial was 1, this mutation is 2)
        #expect(transport.lastRevision == 2)

        // Act — second mutation
        state.status = "ready"
        #expect(await transport.waitForPushCount(atLeast: 3))

        // Assert — third revision
        #expect(transport.lastRevision == 3)

        task.cancel()
    }
}

// MARK: - MockPushTransport

/// Test double for PushTransport — shared across push pipeline tests.
@MainActor
final class MockPushTransport: PushTransport {
    private struct PushWaiter {
        let id: UUID
        let expectedCount: Int
        let continuation: CheckedContinuation<Bool, Never>
    }

    var pushCount = 0
    var lastStore: StoreKey?
    var lastOp: PushOp?
    var lastLevel: PushLevel?
    var lastRevision: Int?
    var lastEpoch: Int?
    var lastJSON: Data?
    private var waiters: [PushWaiter] = []

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

        let ready = waiters.filter { pushCount >= $0.expectedCount }
        waiters.removeAll { pushCount >= $0.expectedCount }
        for waiter in ready {
            waiter.continuation.resume(returning: true)
        }
    }

    func waitForPushCount(
        atLeast expectedCount: Int
    ) async -> Bool {
        await waitForPushCount(atLeast: expectedCount, timeout: .seconds(2))
    }

    func waitForPushCount(
        atLeast expectedCount: Int,
        timeout: Duration
    ) async -> Bool {
        if pushCount >= expectedCount { return true }
        let waiterId = UUID()

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor [weak self] in
                await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    guard let self else {
                        continuation.resume(returning: false)
                        return
                    }
                    if self.pushCount >= expectedCount {
                        continuation.resume(returning: true)
                        return
                    }
                    self.waiters.append(
                        PushWaiter(
                            id: waiterId,
                            expectedCount: expectedCount,
                            continuation: continuation
                        )
                    )
                }
            }

            group.addTask { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self else { return false }
                if let index = self.waiters.firstIndex(where: { $0.id == waiterId }) {
                    let waiter = self.waiters.remove(at: index)
                    waiter.continuation.resume(returning: false)
                }
                return false
            }

            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}
