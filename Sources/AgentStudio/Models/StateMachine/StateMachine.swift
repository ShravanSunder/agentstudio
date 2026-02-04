// StateMachine.swift
// AgentStudio
//
// Generic declarative state machine with effects support.

import Foundation
import OSLog

// MARK: - Protocol

/// Protocol for state machine states.
/// Each state defines how it handles events and what transitions/effects result.
protocol MachineState: Hashable, Sendable {
    associatedtype Event: Sendable
    associatedtype Effect: Sendable

    /// Handle an event and return the resulting transition, or nil if invalid.
    func handle(_ event: Event) -> Transition<Self, Effect>?
}

// MARK: - Transition

/// Result of a state transition, including the new state and any effects to execute.
struct Transition<State, Effect> {
    let newState: State
    let effects: [Effect]

    init(newState: State, effects: [Effect] = []) {
        self.newState = newState
        self.effects = effects
    }

    /// Create a transition to a new state with no effects.
    static func to(_ state: State) -> Transition {
        Transition(newState: state, effects: [])
    }

    /// Add effects to this transition.
    func emitting(_ effects: Effect...) -> Transition {
        Transition(newState: newState, effects: self.effects + effects)
    }

    /// Add an array of effects to this transition.
    func emitting(_ effects: [Effect]) -> Transition {
        Transition(newState: newState, effects: self.effects + effects)
    }
}

// MARK: - Machine

/// Observable state machine that manages state transitions and effect execution.
@MainActor
@Observable
final class Machine<State: MachineState>: @unchecked Sendable {

    // MARK: - Properties

    /// Current state of the machine.
    private(set) var state: State

    /// Whether the machine is currently processing an event.
    private(set) var isProcessing: Bool = false

    /// Handler for executing effects. Set this to process side effects.
    var effectHandler: ((State.Effect) async -> Void)?

    /// Observer for state transitions. Useful for logging/debugging.
    var transitionObserver: ((State, State.Event, State) -> Void)?

    #if DEBUG
    /// History of transitions for debugging (only in debug builds).
    private(set) var history: [TransitionRecord<State>] = []

    struct TransitionRecord<S> {
        let from: S
        let event: S.Event where S: MachineState
        let to: S
        let timestamp: Date
    }
    #endif

    private let logger = Logger(subsystem: "AgentStudio", category: "StateMachine")

    // MARK: - Initialization

    init(initial: State) {
        self.state = initial
    }

    // MARK: - Event Handling

    /// Send an event to the machine.
    /// Returns true if a transition occurred, false if the event was invalid for the current state.
    @discardableResult
    func send(_ event: State.Event) async -> Bool {
        guard !isProcessing else {
            logger.warning("Reentrant state machine event ignored: \(String(describing: event))")
            return false
        }

        guard let transition = state.handle(event) else {
            logger.debug("No transition for event \(String(describing: event)) in state \(String(describing: self.state))")
            return false
        }

        isProcessing = true
        defer { isProcessing = false }

        let oldState = state
        state = transition.newState

        #if DEBUG
        history.append(TransitionRecord(
            from: oldState,
            event: event,
            to: state,
            timestamp: Date()
        ))
        #endif

        logger.debug("Transition: \(String(describing: oldState)) → \(String(describing: self.state))")
        transitionObserver?(oldState, event, state)

        // Execute effects sequentially
        for effect in transition.effects {
            await effectHandler?(effect)
        }

        return true
    }

    /// Send an event synchronously (fire-and-forget).
    /// Use when you don't need to wait for effects to complete.
    func sendSync(_ event: State.Event) {
        Task { @MainActor in
            await send(event)
        }
    }

    /// Check if an event would cause a valid transition from the current state.
    func canSend(_ event: State.Event) -> Bool {
        state.handle(event) != nil
    }

    // MARK: - State Management

    /// Reset the machine to a specific state (for testing or recovery).
    func reset(to newState: State) {
        state = newState
        #if DEBUG
        history.removeAll()
        #endif
        logger.debug("Machine reset to: \(String(describing: newState))")
    }

    /// Get current state (for external observation).
    var currentState: State {
        state
    }
}

// MARK: - Convenience Extensions

extension Machine {
    /// Wait for the machine to reach a specific state (with timeout).
    func waitForState(
        matching predicate: @escaping (State) -> Bool,
        timeout: TimeInterval = 10.0
    ) async -> Bool {
        if predicate(state) { return true }

        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            if predicate(state) { return true }
        }

        return false
    }

    /// Wait for the machine to reach any of the specified states.
    func waitForState(
        in targetStates: Set<State>,
        timeout: TimeInterval = 10.0
    ) async -> Bool where State: Hashable {
        await waitForState(matching: { targetStates.contains($0) }, timeout: timeout)
    }
}
