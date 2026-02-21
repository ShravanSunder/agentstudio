import Testing
import Foundation

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct StateMachineTests {

    // MARK: - Basic Transitions

    @Test
    func test_machine_initialState() {
        // Arrange & Act
        let machine = Machine<SessionStatus>(initialState: .unknown)

        // Assert
        #expect(machine.state == .unknown)
    }

    @Test
    func test_machine_transitionsState() async {
        // Arrange
        let machine = Machine<SessionStatus>(initialState: .unknown)

        // Act
        await machine.send(.verify)

        // Assert
        #expect(machine.state == .verifying)
    }

    @Test
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
        #expect(machine.state == .verifying)
        #expect(executedEffects.count == 1)
        if case .checkSocket = executedEffects.first {
        } else {
            Issue.record("Expected .checkSocket effect")
        }
    }

    @Test
    func test_machine_unhandledEventStaysInState() async {
        // Arrange
        let machine = Machine<SessionStatus>(initialState: .unknown)

        // Act — .healthCheckPassed is not valid from .unknown
        await machine.send(.healthCheckPassed)

        // Assert
        #expect(machine.state == .unknown)
    }

    // MARK: - Event Queue (Reentrancy Safety)

    @Test
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
        #expect(machine.state == .verifying)
    }

    @Test
    func test_machine_sendAlwaysReturnsTrue() async {
        // Arrange
        let machine = Machine<SessionStatus>(initialState: .unknown)

        // Act
        let result = await machine.send(.verify)

        // Assert — events are never dropped
        #expect(result)
    }

    // MARK: - Queue Depth Guard

    @Test
    func test_machine_capsQueueDepthOnRunaway() async {
        // Arrange — use a handler that always re-sends an event, creating a cycle
        let machine = Machine<SessionStatus>(initialState: .alive)
        var effectCount = 0
        machine.setEffectHandler { [weak machine] effect in
            effectCount += 1
            // Every effect re-sends .healthCheckPassed which triggers .scheduleHealthCheck
            // which calls this handler again — a runaway cycle
            if case .scheduleHealthCheck = effect {
                await machine?.send(.healthCheckPassed)
            }
        }

        // Act — .healthCheckPassed from .alive produces .scheduleHealthCheck effect
        // which triggers the handler, which sends .healthCheckPassed again → cycle
        await machine.send(.healthCheckPassed)

        // Assert — machine should have capped at maxQueueDepth instead of looping forever.
        // Each healthCheckPassed → scheduleHealthCheck → handler sends healthCheckPassed,
        // so effectCount tracks how many cycles occurred.
        #expect(
            effectCount <= Machine<SessionStatus>.maxQueueDepth + 1,
            "Queue depth guard should cap runaway cycles"
        )
        // Machine should still be in a valid state (alive, since healthCheckPassed→alive)
        #expect(machine.state == .alive)
    }

    // MARK: - Force State

    @Test
    func test_machine_forceState_overridesCurrentState() {
        // Arrange
        let machine = Machine<SessionStatus>(initialState: .unknown)

        // Act
        machine.forceState(.alive)

        // Assert
        #expect(machine.state == .alive)
    }

    // MARK: - SessionStatus Transitions

    @Test
    func test_sessionStatus_fullVerificationPath() async {
        // Arrange
        let machine = Machine<SessionStatus>(initialState: .unknown)

        // Act — simulate full verification: unknown -> verifying -> alive
        await machine.send(.verify)
        #expect(machine.state == .verifying)

        await machine.send(.socketFound)
        #expect(machine.state == .verifying)

        await machine.send(.sessionDetected)

        // Assert
        #expect(machine.state == .alive)
    }

    @Test
    func test_sessionStatus_healthCheckCycle() async {
        // Arrange
        let machine = Machine<SessionStatus>(initialState: .alive)

        // Act
        await machine.send(.healthCheckPassed)
        #expect(machine.state == .alive)

        await machine.send(.healthCheckFailed)

        // Assert
        #expect(machine.state == .dead)
    }

    @Test
    func test_sessionStatus_recoveryPath() async {
        // Arrange
        let machine = Machine<SessionStatus>(initialState: .dead)

        // Act
        await machine.send(.attemptRecovery)
        #expect(machine.state == .recovering)

        await machine.send(.recoverySucceeded)

        // Assert
        #expect(machine.state == .alive)
    }

    @Test
    func test_sessionStatus_recoveryFailure() async {
        // Arrange
        let machine = Machine<SessionStatus>(initialState: .dead)

        // Act
        await machine.send(.attemptRecovery)
        await machine.send(.recoveryFailed(reason: "gone"))

        // Assert
        #expect(machine.state == .failed(reason: "gone"))
    }

}
