import XCTest
import Observation
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
            epoch: { 1 }
        ) {
            Slice("status", store: .diff, level: .hot) { s in s.status }
            Slice("count", store: .diff, level: .cold) { s in s.count }
        }

        // Act
        plan.start()

        // Assert
        XCTAssertEqual(plan.taskCount, 2,
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
            epoch: { 1 }
        ) {
            Slice("status", store: .diff, level: .hot) { s in s.status }
        }

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
            epoch: { 1 }
        ) {
            Slice("status", store: .diff, level: .hot) { s in s.status }
            EntitySlice(
                "items", store: .review, level: .warm,
                capture: { s in s.items },
                version: { _ in 1 },
                keyToString: { $0.uuidString }
            )
        }

        // Act
        plan.start()

        // Assert
        XCTAssertEqual(plan.taskCount, 2)
        plan.stop()
    }
}
