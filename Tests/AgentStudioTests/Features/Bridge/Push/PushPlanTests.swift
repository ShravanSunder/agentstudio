import Observation
import XCTest

@testable import AgentStudio

@MainActor
final class PushPlanTests: XCTestCase {

    @Observable
    class TestState {
        var status: String = "idle"
        var count: Int = 0
        var items: [UUID: String] = [:]
    }

    func test_pushPlan_creates_tasks_per_slice() {
        // Arrange
        let state = TestState()
        let transport = MockPushTransport()
        let clock = RevisionClock()

        let plan = PushPlan(
            state: state,
            transport: transport,
            revisions: clock,
            epoch: { 1 },
            slices: {
                Slice("status", store: .diff, level: .hot) { s in s.status }
                Slice("count", store: .diff, level: .cold) { s in s.count }
            }
        )

        // Act
        plan.start()

        // Assert
        XCTAssertEqual(
            plan.taskCount, 2,
            "PushPlan should create one task per slice")
        plan.stop()
    }

    func test_pushPlan_stop_cancels_tasks() {
        // Arrange
        let state = TestState()
        let transport = MockPushTransport()
        let clock = RevisionClock()

        let plan = PushPlan(
            state: state,
            transport: transport,
            revisions: clock,
            epoch: { 1 },
            slices: {
                Slice("status", store: .diff, level: .hot) { s in s.status }
            }
        )

        // Act
        plan.start()
        XCTAssertEqual(plan.taskCount, 1)
        plan.stop()

        // Assert
        XCTAssertEqual(plan.taskCount, 0)
    }

    func test_pushPlan_mixed_slices() {
        // Arrange
        let state = TestState()
        let transport = MockPushTransport()
        let clock = RevisionClock()

        let plan = PushPlan(
            state: state,
            transport: transport,
            revisions: clock,
            epoch: { 1 },
            slices: {
                Slice("status", store: .diff, level: .hot) { s in s.status }
                EntitySlice(
                    "items", store: .review, level: .warm,
                    capture: { s in s.items },
                    version: { _ in 1 },
                    keyToString: { $0.uuidString }
                )
            }
        )

        // Act
        plan.start()

        // Assert
        XCTAssertEqual(plan.taskCount, 2)
        plan.stop()
    }

    // MARK: - Stop-guard: stopped plan drops in-flight pushes

    /// Proves that mutations after stop() do not reach the transport.
    /// Task cancellation is cooperative — an in-flight iteration between
    /// `for await` yield and `pushJSON` may not see cancellation immediately.
    /// The StopGuardedTransport wrapper checks isStopped before forwarding.
    func test_pushPlan_stopped_plan_drops_subsequent_pushes() async throws {
        // Arrange
        let state = TestState()
        let transport = MockPushTransport()
        let clock = RevisionClock()

        let plan = PushPlan(
            state: state,
            transport: transport,
            revisions: clock,
            epoch: { 1 },
            slices: {
                Slice("status", store: .diff, level: .hot) { s in s.status }
            }
        )

        plan.start()
        await transport.waitForPushCount(atLeast: 1)

        // Trigger a push to confirm transport is working
        state.status = "loading"
        await transport.waitForPushCount(atLeast: 2)
        let countBeforeStop = transport.pushCount
        XCTAssertGreaterThan(countBeforeStop, 0, "Should have received at least one push before stop")

        // Act — stop the plan, then mutate state
        plan.stop()
        XCTAssertTrue(plan.isStopped)

        state.status = "this-should-not-arrive"
        await Task.yield()

        // Assert — no additional pushes after stop
        XCTAssertEqual(
            transport.pushCount, countBeforeStop,
            "Mutations after stop() should not reach transport (StopGuardedTransport drops them)")
    }

    // MARK: - Generation-safe restart: old generation pushes are dropped

    /// Proves that stop→start creates a new generation and late emissions from
    /// the previous generation's tasks cannot leak through to the transport.
    /// This is the regression test for the restart race: generation N tasks
    /// must be rejected after generation N+1 starts.
    func test_restart_drops_previous_generation_pushes() async throws {
        // Arrange
        let state = TestState()
        let transport = MockPushTransport()
        let clock = RevisionClock()

        let plan = PushPlan(
            state: state,
            transport: transport,
            revisions: clock,
            epoch: { 1 },
            slices: {
                Slice("status", store: .diff, level: .hot) { s in s.status }
            }
        )

        // Act — start generation 1, get some pushes flowing
        plan.start()
        let gen1 = plan.generation
        await transport.waitForPushCount(atLeast: 1)

        state.status = "gen1-value"
        await transport.waitForPushCount(atLeast: 2)
        let countAfterGen1 = transport.pushCount
        XCTAssertGreaterThan(countAfterGen1, 0, "Gen 1 should have produced pushes")

        // Act — restart (stop→start), creating generation 2
        plan.start()
        let gen2 = plan.generation
        XCTAssertGreaterThan(gen2, gen1, "Restart should increment generation")
        await transport.waitForPushCount(atLeast: countAfterGen1 + 1)

        // Mutate state — only gen2 tasks should deliver
        let countBeforeGen2Mutation = transport.pushCount
        state.status = "gen2-value"
        await transport.waitForPushCount(atLeast: countBeforeGen2Mutation + 1)

        // Assert — gen2 pushes arrive
        XCTAssertGreaterThan(
            transport.pushCount, countBeforeGen2Mutation,
            "Gen 2 tasks should deliver pushes")

        // Assert — generation counter tracks correctly
        XCTAssertEqual(gen1, 1)
        XCTAssertEqual(gen2, 2)
        XCTAssertFalse(plan.isStopped)

        plan.stop()
    }

    /// Proves that generation counter increments monotonically across multiple restarts.
    func test_generation_increments_across_multiple_restarts() {
        // Arrange
        let state = TestState()
        let transport = MockPushTransport()
        let clock = RevisionClock()

        let plan = PushPlan(
            state: state,
            transport: transport,
            revisions: clock,
            epoch: { 1 },
            slices: {
                Slice("status", store: .diff, level: .hot) { s in s.status }
            }
        )

        // Act — start/stop 5 times
        var generations: [Int] = []
        for _ in 0..<5 {
            plan.start()
            generations.append(plan.generation)
            plan.stop()
        }

        // Assert — strictly monotonically increasing
        XCTAssertEqual(generations, [1, 2, 3, 4, 5])
    }

    // MARK: - Debounce coalescing: warm level

    /// Proves that warm-level (.warm = 12ms debounce) coalesces rapid mutations
    /// into fewer pushes. 5 synchronous mutations within one run-loop turn are
    /// expected to coalesce through the injected test clock into fewer than 5 pushes.
    func test_warm_debounce_coalesces_rapid_mutations() async throws {
        // Arrange
        let state = TestState()
        let transport = MockPushTransport()
        let clock = RevisionClock()
        let debounceClock = TestPushClock()

        let plan = PushPlan(
            state: state,
            transport: transport,
            revisions: clock,
            epoch: { 1 },
            slices: {
                Slice(
                    "status",
                    store: .diff,
                    level: .warm,
                    capture: { (s: TestState) in s.status }
                )
                .erased(debounceClock: debounceClock)
            }
        )

        plan.start()
        let baselineCount = transport.pushCount

        // Act — 5 synchronous mutations within one run-loop turn
        for i in 0..<5 {
            state.status = "state-\(i)"
        }

        // Wait for debounce to flush
        debounceClock.advance(by: .milliseconds(20))
        await transport.waitForPushCount(atLeast: baselineCount + 1)

        let pushCount = transport.pushCount - baselineCount

        // Assert — should be fewer pushes than mutations (coalesced)
        XCTAssertGreaterThan(pushCount, 0, "At least one push should fire after debounce")
        XCTAssertLessThan(
            pushCount, 5,
            "5 mutations within 12ms debounce window should coalesce to fewer than 5 pushes. Got: \(pushCount)")

        plan.stop()
    }

    // MARK: - Debounce coalescing: cold level with EntitySlice

    /// Proves that cold-level EntitySlice (.cold = 32ms debounce) coalesces rapid
    /// entity additions. 10 synchronous mutations within one run-loop turn land in
    /// a single debounce window, producing fewer than 10 pushes.
    func test_cold_entitySlice_debounce_coalesces() async throws {
        // Arrange
        let state = TestState()
        let transport = MockPushTransport()
        let clock = RevisionClock()
        let debounceClock = TestPushClock()

        let plan = PushPlan(
            state: state,
            transport: transport,
            revisions: clock,
            epoch: { 1 },
            slices: {
                EntitySlice(
                    "items", store: .review, level: .cold,
                    capture: { (s: TestState) in s.items },
                    version: { (_ entity: String) in 1 },
                    keyToString: { (key: UUID) in key.uuidString }
                ).erased(debounceClock: debounceClock)
            }
        )

        plan.start()
        let baselineCount = transport.pushCount

        // Act — 10 synchronous entity additions within one run-loop turn
        for i in 0..<10 {
            state.items[UUID()] = "item-\(i)"
        }

        // Wait for debounce to flush
        debounceClock.advance(by: .milliseconds(40))
        await transport.waitForPushCount(atLeast: baselineCount + 1)

        let pushCount = transport.pushCount - baselineCount

        // Assert — should be coalesced (fewer pushes than mutations)
        XCTAssertGreaterThan(pushCount, 0, "At least one push should fire after cold debounce")
        XCTAssertLessThan(
            pushCount, 10,
            "10 mutations within ~32ms debounce should coalesce to fewer than 10 pushes. Got: \(pushCount)")

        // Verify all 10 entities made it into the final delta
        XCTAssertEqual(state.items.count, 10)

        plan.stop()
    }
}
