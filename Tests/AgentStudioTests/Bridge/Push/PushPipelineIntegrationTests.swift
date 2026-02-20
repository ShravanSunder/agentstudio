import Observation
import XCTest

@testable import AgentStudio

/// Integration tests for Phase 2 push pipeline.
/// Validates the full push path: mutate @Observable -> PushPlan -> transport.
/// Design doc section 13 Phase 2 tests (line 2643-2656).
@MainActor
final class PushPipelineIntegrationTests: XCTestCase {

    // MARK: - Mutate @Observable -> PushPlan -> MockTransport

    /// Verifies that mutating an @Observable property triggers the full push pipeline:
    /// observation fires -> Slice captures snapshot -> transport receives pushJSON call.
    func test_observable_mutation_triggers_push_via_plan() async throws {
        // Arrange
        let diffState = DiffState()
        let transport = MockPushTransport()
        let clock = RevisionClock()

        let plan = PushPlan(
            state: diffState,
            transport: transport,
            revisions: clock,
            epoch: { diffState.epoch },
            slices: {
                Slice("diffStatus", store: .diff, level: .hot) { state in
                    DiffStatusSlice(status: state.status, error: state.error, epoch: state.epoch)
                }
            }
        )

        plan.start()
        try await Task.sleep(for: .milliseconds(50))

        // Initial observation fires (nil -> initial snapshot), record baseline
        let baselineCount = transport.pushCount

        // Act — mutate observable
        diffState.status = .loading
        try await Task.sleep(for: .milliseconds(100))

        // Assert — mutation triggered push through the full pipeline
        XCTAssertGreaterThan(
            transport.pushCount, baselineCount,
            "Observable mutation should trigger push via PushPlan")
        XCTAssertEqual(transport.lastStore, .diff)
        XCTAssertEqual(transport.lastLevel, .hot)

        plan.stop()
    }

    // MARK: - Rapid mutations coalesce with debounce

    /// Verifies that cold-level slices debounce rapid mutations, coalescing
    /// multiple state changes into fewer pushes.
    func test_cold_slice_coalesces_rapid_mutations() async throws {
        // Arrange
        let diffState = DiffState()
        let transport = MockPushTransport()
        let clock = RevisionClock()

        let plan = PushPlan(
            state: diffState,
            transport: transport,
            revisions: clock,
            epoch: { diffState.epoch },
            slices: {
                Slice("diffEpoch", store: .diff, level: .cold, op: .replace) { state in
                    state.epoch
                }
            }
        )

        plan.start()
        try await Task.sleep(for: .milliseconds(50))

        // Record baseline after initial observation emission
        let baselineCount = transport.pushCount

        // Act — rapid mutations within debounce window (cold = 32ms)
        for epochValue in 1...5 {
            diffState.epoch = epochValue
        }
        try await Task.sleep(for: .milliseconds(200))

        // Assert — debounce coalesced rapid mutations into fewer pushes than mutations
        let pushesAfterMutations = transport.pushCount - baselineCount
        XCTAssertLessThan(
            pushesAfterMutations, 5,
            "Cold debounce should coalesce rapid mutations into fewer pushes (got \(pushesAfterMutations))")
        XCTAssertGreaterThanOrEqual(
            pushesAfterMutations, 1,
            "At least one push should have fired after the mutations settled")

        plan.stop()
    }

    // MARK: - Hot slice pushes without debounce

    /// Verifies that hot-level slices push immediately on each mutation
    /// without coalescing via debounce.
    func test_hot_slice_pushes_on_mutation() async throws {
        // Arrange
        let sharedState = SharedBridgeState()
        let transport = MockPushTransport()
        let clock = RevisionClock()

        let plan = PushPlan(
            state: sharedState,
            transport: transport,
            revisions: clock,
            epoch: { 0 },
            slices: {
                Slice("connectionHealth", store: .connection, level: .hot) { state in
                    ConnectionSlice(
                        health: state.connection.health,
                        latencyMs: state.connection.latencyMs
                    )
                }
            }
        )

        plan.start()
        try await Task.sleep(for: .milliseconds(50))

        // Record baseline after initial observation emission
        let baselineCount = transport.pushCount

        // Act — mutate connection health
        sharedState.connection.health = .error
        try await Task.sleep(for: .milliseconds(50))

        // Assert — hot slice pushed immediately
        XCTAssertEqual(
            transport.pushCount, baselineCount + 1,
            "Hot slice should push immediately on mutation")
        XCTAssertEqual(transport.lastStore, .connection)
        XCTAssertEqual(transport.lastLevel, .hot)

        plan.stop()
    }

    // MARK: - Revision stamping across plan lifecycle

    /// Verifies that pushes through the plan are stamped with monotonically
    /// increasing revision numbers from the shared RevisionClock.
    func test_plan_stamps_monotonic_revisions() async throws {
        // Arrange
        let diffState = DiffState()
        let transport = MockPushTransport()
        let clock = RevisionClock()

        let plan = PushPlan(
            state: diffState,
            transport: transport,
            revisions: clock,
            epoch: { diffState.epoch },
            slices: {
                Slice("diffStatus", store: .diff, level: .hot) { state in
                    DiffStatusSlice(status: state.status, error: state.error, epoch: state.epoch)
                }
            }
        )

        plan.start()
        try await Task.sleep(for: .milliseconds(50))

        // Initial emission should stamp revision 1
        XCTAssertEqual(
            transport.lastRevision, 1,
            "Initial observation should stamp revision 1")

        // Act — two sequential mutations
        diffState.status = .loading
        try await Task.sleep(for: .milliseconds(100))
        let revisionAfterFirstMutation = transport.lastRevision

        diffState.status = .ready
        try await Task.sleep(for: .milliseconds(100))
        let revisionAfterSecondMutation = transport.lastRevision

        // Assert — revisions increase monotonically
        XCTAssertEqual(revisionAfterFirstMutation, 2)
        XCTAssertEqual(revisionAfterSecondMutation, 3)

        plan.stop()
    }

    // MARK: - Epoch propagation

    /// Verifies that the epoch value from the EpochProvider is correctly
    /// propagated through pushJSON calls.
    func test_plan_propagates_epoch_from_provider() async throws {
        // Arrange
        let diffState = DiffState()
        let transport = MockPushTransport()
        let clock = RevisionClock()

        let plan = PushPlan(
            state: diffState,
            transport: transport,
            revisions: clock,
            epoch: { diffState.epoch },
            slices: {
                Slice("diffStatus", store: .diff, level: .hot) { state in
                    DiffStatusSlice(status: state.status, error: state.error, epoch: state.epoch)
                }
            }
        )

        plan.start()
        try await Task.sleep(for: .milliseconds(50))

        // Initial emission with epoch 0
        XCTAssertEqual(
            transport.lastEpoch, 0,
            "Initial push should carry epoch 0")

        // Act — update epoch and trigger mutation
        diffState.epoch = 42
        diffState.status = .loading
        try await Task.sleep(for: .milliseconds(100))

        // Assert — epoch propagated
        XCTAssertEqual(
            transport.lastEpoch, 42,
            "Push should carry the epoch value from the provider at push time")

        plan.stop()
    }
}
