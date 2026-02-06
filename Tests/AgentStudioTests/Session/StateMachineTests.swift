import XCTest
@testable import AgentStudio

@MainActor
final class StateMachineTests: XCTestCase {

    // MARK: - Basic Transitions

    func test_machine_initialState() {
        // Arrange & Act
        let machine = Machine<SessionStatus>(initialState: .unknown)

        // Assert
        XCTAssertEqual(machine.state, .unknown)
    }

    func test_machine_transitionsState() async {
        // Arrange
        let machine = Machine<SessionStatus>(initialState: .unknown)

        // Act
        await machine.send(.verify)

        // Assert
        XCTAssertEqual(machine.state, .verifying)
    }

    func test_machine_executesEffects() async {
        // Arrange
        let machine = Machine<SessionStatus>(initialState: .unknown)
        var executedEffects: [SessionStatus.Effect] = []
        machine.setEffectHandler { effect in
            executedEffects.append(effect)
        }

        // Act
        await machine.send(.verify)

        // Assert
        XCTAssertEqual(machine.state, .verifying)
        XCTAssertEqual(executedEffects.count, 1)
        if case .checkSocket = executedEffects.first {} else {
            XCTFail("Expected .checkSocket effect")
        }
    }

    func test_machine_unhandledEventStaysInState() async {
        // Arrange
        let machine = Machine<SessionStatus>(initialState: .unknown)

        // Act — .healthCheckPassed is not valid from .unknown
        await machine.send(.healthCheckPassed)

        // Assert
        XCTAssertEqual(machine.state, .unknown)
    }

    // MARK: - Event Queue (Reentrancy Safety)

    func test_machine_queuesEventsFromEffectHandler() async {
        // Arrange
        let machine = Machine<SessionStatus>(initialState: .alive)
        var effectCount = 0
        machine.setEffectHandler { [weak machine] effect in
            effectCount += 1
            // During effect execution, send another event (simulates reentrancy)
            if case .cancelHealthCheck = effect {
                await machine?.send(.create)
            }
        }

        // Act — .sessionDied from .alive triggers .cancelHealthCheck + .notifyDead effects
        await machine.send(.sessionDied)

        // Assert — the reentrant .create event should have been queued and processed
        // .alive -> .dead -> (effects: cancelHealthCheck, notifyDead)
        // During cancelHealthCheck effect, .create is queued
        // After all effects, .create is processed: .dead -> .verifying
        XCTAssertEqual(machine.state, .verifying)
    }

    func test_machine_sendAlwaysReturnsTrue() async {
        // Arrange
        let machine = Machine<SessionStatus>(initialState: .unknown)

        // Act
        let result = await machine.send(.verify)

        // Assert — events are never dropped
        XCTAssertTrue(result)
    }

    // MARK: - Force State

    func test_machine_forceState_overridesCurrentState() {
        // Arrange
        let machine = Machine<SessionStatus>(initialState: .unknown)

        // Act
        machine.forceState(.alive)

        // Assert
        XCTAssertEqual(machine.state, .alive)
    }

    // MARK: - SessionStatus Transitions

    func test_sessionStatus_fullVerificationPath() async {
        // Arrange
        let machine = Machine<SessionStatus>(initialState: .unknown)

        // Act — simulate full verification: unknown -> verifying -> alive
        await machine.send(.verify)
        XCTAssertEqual(machine.state, .verifying)

        await machine.send(.socketFound)
        XCTAssertEqual(machine.state, .verifying)

        await machine.send(.sessionDetected)

        // Assert
        XCTAssertEqual(machine.state, .alive)
    }

    func test_sessionStatus_healthCheckCycle() async {
        // Arrange
        let machine = Machine<SessionStatus>(initialState: .alive)

        // Act
        await machine.send(.healthCheckPassed)
        XCTAssertEqual(machine.state, .alive)

        await machine.send(.healthCheckFailed)

        // Assert
        XCTAssertEqual(machine.state, .dead)
    }

    func test_sessionStatus_recoveryPath() async {
        // Arrange
        let machine = Machine<SessionStatus>(initialState: .dead)

        // Act
        await machine.send(.attemptRecovery)
        XCTAssertEqual(machine.state, .recovering)

        await machine.send(.recoverySucceeded)

        // Assert
        XCTAssertEqual(machine.state, .alive)
    }

    func test_sessionStatus_recoveryFailure() async {
        // Arrange
        let machine = Machine<SessionStatus>(initialState: .dead)

        // Act
        await machine.send(.attemptRecovery)
        await machine.send(.recoveryFailed(reason: "gone"))

        // Assert
        XCTAssertEqual(machine.state, .failed(reason: "gone"))
    }

}
