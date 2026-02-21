import Foundation
import os

private let machineLogger = Logger(subsystem: "com.agentstudio", category: "StateMachine")

// MARK: - MachineState Protocol

/// Protocol for state types that can be used with the generic state machine.
/// Each conforming type defines its own Event and Effect types.
protocol MachineState: Equatable, Sendable {
    associatedtype Event: Sendable
    associatedtype Effect: Sendable

    /// Pure state transition: given current state + event, produce new state + optional effects.
    static func transition(from state: Self, on event: Event) -> Transition<Self, Effect>
}

// MARK: - Transition

/// Result of a state transition: the new state and any side effects to execute.
struct Transition<State: Equatable, Effect> {
    let state: State
    let effects: [Effect]

    init(_ state: State, effects: [Effect] = []) {
        self.state = state
        self.effects = effects
    }
}

// MARK: - Machine

/// Generic state machine with event queue to prevent event loss during effect execution.
///
/// PR #1's machine used `guard !isProcessing else { return false }` which silently
/// dropped events sent during effect execution. This version queues them and drains
/// after the current event finishes processing.
@MainActor
final class Machine<State: MachineState> {
    typealias EffectHandler = (State.Effect) async -> Void

    /// Maximum events drained per send() call. Protects against infinite loops
    /// from pathological effect handlers that re-send events cyclically.
    static var maxQueueDepth: Int { 50 }

    private(set) var state: State
    private var effectHandler: EffectHandler?
    private var isProcessing = false
    private var eventQueue: [State.Event] = []

    init(initialState: State) {
        self.state = initialState
    }

    /// Register a handler that executes side effects produced by transitions.
    func setEffectHandler(_ handler: @escaping EffectHandler) {
        self.effectHandler = handler
    }

    /// Send an event to the machine. If already processing, the event is queued
    /// and will be drained after the current processing completes.
    /// Returns `true` if the event was accepted (always true — events are never dropped).
    @discardableResult
    func send(_ event: State.Event) async -> Bool {
        if isProcessing {
            eventQueue.append(event)
            return true
        }

        isProcessing = true
        defer { isProcessing = false }

        await processEvent(event)

        // Drain queued events that arrived during effect execution.
        // Cap iterations to catch runaway effect→event cycles.
        var drained = 0
        while !eventQueue.isEmpty {
            guard drained < Self.maxQueueDepth else {
                machineLogger.error(
                    "StateMachine queue depth exceeded \(Self.maxQueueDepth) — possible cycle. Dropping \(self.eventQueue.count) queued events."
                )
                eventQueue.removeAll()
                break
            }
            drained += 1
            let next = eventQueue.removeFirst()
            await processEvent(next)
        }

        return true
    }

    /// Force-set state without going through a transition. Use sparingly —
    /// primarily for initialization or test setup.
    func forceState(_ newState: State) {
        self.state = newState
        self.eventQueue.removeAll()
    }

    // MARK: - Private

    private func processEvent(_ event: State.Event) async {
        let transition = State.transition(from: state, on: event)
        state = transition.state

        guard let handler = effectHandler else { return }
        for effect in transition.effects {
            await handler(effect)
        }
    }
}
