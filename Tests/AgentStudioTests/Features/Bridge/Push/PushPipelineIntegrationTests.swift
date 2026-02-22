import Foundation
import Observation
import Testing

@testable import AgentStudio

/// Integration tests for Phase 2 push pipeline.
/// Validates the full push path: mutate @Observable -> PushPlan -> transport.
/// Design doc section 13 Phase 2 tests (line 2643-2656).
@MainActor
@Suite(.serialized)
final class PushPipelineIntegrationTests {

    // MARK: - Mutate @Observable -> PushPlan -> MockTransport

    /// Verifies that mutating an @Observable property triggers the full push pipeline:
    /// observation fires -> Slice captures snapshot -> transport receives pushJSON call.
    @Test
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
        let didReceiveInitialPush = await transport.waitForPushCount(
            atLeast: 1,
            timeout: .seconds(2)
        )
        #expect(didReceiveInitialPush, "Plan should emit initial snapshot")

        // Initial observation fires (nil -> initial snapshot), record baseline
        let baselineCount = transport.pushCount

        // Act — mutate observable
        diffState.setStatus(.loading)
        let didReceiveMutationPush = await transport.waitForPushCount(
            atLeast: baselineCount + 1,
            timeout: .seconds(2)
        )
        #expect(didReceiveMutationPush, "State mutation should emit push through plan")

        // Assert — mutation triggered push through the full pipeline
        #expect(transport.pushCount > baselineCount, "Observable mutation should trigger push via PushPlan")
        #expect(transport.lastStore == .diff)
        #expect(transport.lastLevel == .hot)

        plan.stop()
    }

    // MARK: - Rapid mutations coalesce with debounce

    /// Verifies that cold-level slices debounce rapid mutations, coalescing
    /// multiple state changes into fewer pushes.
    @Test
    func test_cold_slice_coalesces_rapid_mutations() async throws {
        // Arrange
        let diffState = DiffState()
        let transport = MockPushTransport()
        let clock = RevisionClock()
        let debounceClock = TestPushClock()

        let plan = PushPlan(
            state: diffState,
            transport: transport,
            revisions: clock,
            epoch: { diffState.epoch },
            slices: {
                Slice("diffEpoch", store: .diff, level: .cold, op: .replace) { state in
                    state.epoch
                }
                .erased(debounceClock: debounceClock)
            }
        )

        plan.start()
        let didReceiveInitialPush = await transport.waitForPushCount(
            atLeast: 1,
            maxTicks: 40,
            advanceClock: { debounceClock.advance(by: .milliseconds(5)) }
        )
        #expect(didReceiveInitialPush, "Plan should emit initial snapshot")

        // Record baseline after initial observation emission
        let baselineCount = transport.pushCount

        // Act — rapid mutations within debounce window (cold = 32ms)
        for epochValue in 1...5 {
            diffState.setEpoch(epochValue)
        }
        let didReceiveCoalescedPush = await transport.waitForPushCount(
            atLeast: baselineCount + 1,
            maxTicks: 40,
            advanceClock: { debounceClock.advance(by: .milliseconds(5)) }
        )
        #expect(didReceiveCoalescedPush, "Rapid cold-level mutations should coalesce into a push")

        // Assert — debounce coalesced rapid mutations into fewer pushes than mutations
        let pushesAfterMutations = transport.pushCount - baselineCount
        #expect(
            pushesAfterMutations < 5,
            "Cold debounce should coalesce rapid mutations into fewer pushes (got \(pushesAfterMutations))")
        #expect(pushesAfterMutations >= 1, "At least one push should have fired after the mutations settled")

        plan.stop()
    }

    // MARK: - Hot slice pushes without debounce

    /// Verifies that hot-level slices push immediately on each mutation
    /// without coalescing via debounce.
    @Test
    func test_hot_slice_pushes_on_mutation() async throws {
        // Arrange
        let paneState = PaneDomainState()
        let transport = MockPushTransport()
        let clock = RevisionClock()

        let plan = PushPlan(
            state: paneState,
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
        let didReceiveInitialPush = await transport.waitForPushCount(
            atLeast: 1,
            timeout: .seconds(2)
        )
        #expect(didReceiveInitialPush, "Plan should emit initial snapshot")

        // Record baseline after initial observation emission
        let baselineCount = transport.pushCount

        // Act — mutate connection health
        paneState.connection.setHealth(.error)
        let didReceiveMutationPush = await transport.waitForPushCount(
            atLeast: baselineCount + 1,
            timeout: .seconds(2)
        )
        #expect(didReceiveMutationPush, "Hot mutation should emit immediately")

        // Assert — hot slice pushed immediately
        #expect(transport.pushCount == baselineCount + 1, "Hot slice should push immediately on mutation")
        #expect(transport.lastStore == .connection)
        #expect(transport.lastLevel == .hot)

        plan.stop()
    }

    // MARK: - Revision stamping across plan lifecycle

    /// Verifies that pushes through the plan are stamped with monotonically
    /// increasing revision numbers from the shared RevisionClock.
    @Test
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
        let didReceiveInitialPush = await transport.waitForPushCount(
            atLeast: 1,
            timeout: .seconds(2)
        )
        #expect(didReceiveInitialPush, "Plan should emit initial revision")

        // Initial emission should stamp revision 1
        #expect(transport.lastRevision == 1, "Initial observation should stamp revision 1")

        // Act — two sequential mutations
        diffState.setStatus(.loading)
        let didReceiveFirstMutation = await transport.waitForPushCount(
            atLeast: 2,
            timeout: .seconds(2)
        )
        #expect(didReceiveFirstMutation, "Mutation to loading should emit revision 2")
        let revisionAfterFirstMutation = transport.lastRevision

        diffState.setStatus(.ready)
        let didReceiveSecondMutation = await transport.waitForPushCount(
            atLeast: 3,
            timeout: .seconds(2)
        )
        #expect(didReceiveSecondMutation, "Mutation to ready should emit revision 3")
        let revisionAfterSecondMutation = transport.lastRevision

        // Assert — revisions increase monotonically
        #expect(revisionAfterFirstMutation == 2)
        #expect(revisionAfterSecondMutation == 3)

        plan.stop()
    }

    // MARK: - Epoch propagation

    /// Verifies that the epoch value from the EpochProvider is correctly
    /// propagated through pushJSON calls.
    @Test
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
        let didReceiveInitialPush = await transport.waitForPushCount(
            atLeast: 1,
            timeout: .seconds(2)
        )
        #expect(didReceiveInitialPush, "Plan should emit initial epoch")

        // Initial emission with epoch 0
        #expect(transport.lastEpoch == 0, "Initial push should carry epoch 0")

        // Act — update epoch and trigger mutation
        diffState.setEpoch(42)
        diffState.setStatus(.loading)
        let didReceiveMutationPush = await transport.waitForPushCount(
            atLeast: 2,
            timeout: .seconds(2)
        )
        #expect(didReceiveMutationPush, "Mutation should emit updated epoch")

        // Assert — epoch propagated
        #expect(transport.lastEpoch == 42, "Push should carry the epoch value from the provider at push time")

        plan.stop()
    }
}
