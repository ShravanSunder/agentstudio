import Foundation

/// State machine definition for a session's lifecycle.
/// Pure value types — no backend-specific code. The registry wires effects to backend calls.
enum SessionStatus: Equatable, Sendable, MachineState {
    case unknown
    case verifying
    case alive
    case dead
    case missing
    case recovering
    case failed(reason: String)

    // MARK: - Events

    enum Event: Sendable {
        // Verification
        case verify
        case socketFound
        case socketMissing
        case sessionDetected
        case sessionNotDetected

        // Runtime
        case healthCheckPassed
        case healthCheckFailed
        case sessionDied

        // Recovery
        case attemptRecovery
        case recoverySucceeded
        case recoveryFailed(reason: String)

        // Creation
        case create
        case created
        case createFailed(reason: String)
    }

    // MARK: - Effects

    enum Effect: Sendable {
        case checkSocket
        case checkSessionExists
        case createSession
        case destroySession
        case scheduleHealthCheck
        case cancelHealthCheck
        case attemptRecovery
        case notifyAlive
        case notifyDead
        case notifyFailed(reason: String)
    }

    // MARK: - Transitions

    static func transition(from state: SessionStatus, on event: Event) -> Transition<SessionStatus, Effect> {
        switch (state, event) {

        // --- Unknown ---
        case (.unknown, .verify):
            return Transition(.verifying, effects: [.checkSocket])
        case (.unknown, .create):
            return Transition(.verifying, effects: [.createSession])

        // --- Verifying ---
        case (.verifying, .socketFound):
            return Transition(.verifying, effects: [.checkSessionExists])
        case (.verifying, .socketMissing):
            return Transition(.missing)
        case (.verifying, .sessionDetected):
            return Transition(.alive, effects: [.scheduleHealthCheck, .notifyAlive])
        case (.verifying, .sessionNotDetected):
            return Transition(.missing)
        case (.verifying, .created):
            return Transition(.alive, effects: [.scheduleHealthCheck, .notifyAlive])
        case (.verifying, .createFailed(let reason)):
            return Transition(.failed(reason: reason), effects: [.notifyFailed(reason: reason)])

        // --- Alive ---
        case (.alive, .healthCheckPassed):
            return Transition(.alive, effects: [.scheduleHealthCheck])
        case (.alive, .healthCheckFailed):
            return Transition(.dead, effects: [.cancelHealthCheck, .notifyDead])
        case (.alive, .sessionDied):
            return Transition(.dead, effects: [.cancelHealthCheck, .notifyDead])
        case (.alive, .verify):
            return Transition(.verifying, effects: [.checkSocket])

        // --- Dead ---
        case (.dead, .attemptRecovery):
            return Transition(.recovering, effects: [.attemptRecovery])
        case (.dead, .create):
            return Transition(.verifying, effects: [.createSession])

        // --- Missing ---
        case (.missing, .create):
            return Transition(.verifying, effects: [.createSession])
        case (.missing, .attemptRecovery):
            return Transition(.recovering, effects: [.attemptRecovery])

        // --- Recovering ---
        case (.recovering, .recoverySucceeded):
            return Transition(.alive, effects: [.scheduleHealthCheck, .notifyAlive])
        case (.recovering, .recoveryFailed(let reason)):
            return Transition(.failed(reason: reason), effects: [.notifyFailed(reason: reason)])

        // --- Failed ---
        case (.failed, .create):
            return Transition(.verifying, effects: [.createSession])
        case (.failed, .verify):
            return Transition(.verifying, effects: [.checkSocket])

        // Any unhandled combination stays in current state
        default:
            return Transition(state)
        }
    }
}
