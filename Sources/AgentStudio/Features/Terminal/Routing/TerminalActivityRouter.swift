import Foundation
import os.log

private let terminalActivityRouterLogger = Logger(
    subsystem: "com.agentstudio",
    category: "TerminalActivityRouter"
)

@MainActor
/// Leaf runtime-bus subscriber that projects high-churn terminal facts into
/// `TerminalActivityAtom`; inbox-worthy promotion stays in the notification router.
final class TerminalActivityRouter {
    private let bus: EventBus<RuntimeEnvelope>
    private let activityAtom: TerminalActivityAtom
    private let traceRuntime: AgentStudioTraceRuntime?

    private var busTask: Task<Void, Never>?

    init(
        bus: EventBus<RuntimeEnvelope>,
        activityAtom: TerminalActivityAtom,
        traceRuntime: AgentStudioTraceRuntime? = .fromEnvironment()
    ) {
        self.bus = bus
        self.activityAtom = activityAtom
        self.traceRuntime = traceRuntime
    }

    func start() async {
        guard busTask == nil else { return }

        let stream = await bus.subscribe()
        busTask = Task { @MainActor [weak self] in
            for await envelope in stream {
                guard !Task.isCancelled else { return }
                guard let self, !Task.isCancelled else { return }
                self.consume(envelope)
            }
            if !Task.isCancelled {
                terminalActivityRouterLogger.warning(
                    "Runtime event stream ended while terminal activity router was active")
            }
        }
    }

    func stop() {
        busTask?.cancel()
        busTask = nil
    }

    private func consume(_ envelope: RuntimeEnvelope) {
        guard case .pane(let paneEnvelope) = envelope else { return }
        activityAtom.consume(paneEnvelope)
        traceTerminalActivity(paneEnvelope)
    }

    private func traceTerminalActivity(_ envelope: PaneEnvelope) {
        guard case .terminal(let event) = envelope.event else { return }
        let attributes = terminalTraceAttributes(for: envelope, event: event)
        Task {
            await traceRuntime?.record(
                tag: .runtime,
                body: "terminal.activity.observed",
                traceID: envelope.correlationId?.uuidString,
                parentSpanID: envelope.causationId?.uuidString,
                attributes: attributes
            )
        }
    }

    private func terminalTraceAttributes(
        for envelope: PaneEnvelope,
        event: GhosttyEvent
    ) -> [String: AgentStudioTraceValue] {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.envelope.event_id": .string(envelope.eventId.uuidString),
            "agentstudio.envelope.seq": .int(Int(envelope.seq)),
            "agentstudio.pane.id": .string(envelope.paneId.uuidString),
            "agentstudio.pane.kind": .string(String(describing: envelope.paneKind)),
            "agentstudio.runtime.event": .string(event.eventName.rawValue),
        ]
        if let commandId = envelope.commandId {
            attributes["agentstudio.command.id"] = .string(commandId.uuidString)
        }
        if let correlationId = envelope.correlationId {
            attributes["agentstudio.envelope.correlation_id"] = .string(correlationId.uuidString)
        }
        if let causationId = envelope.causationId {
            attributes["agentstudio.envelope.causation_id"] = .string(causationId.uuidString)
        }
        return attributes
    }
}
