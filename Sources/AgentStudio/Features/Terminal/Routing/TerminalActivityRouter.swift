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
    private struct TraceRequest: Sendable {
        let body: String
        let traceID: String?
        let parentSpanID: String?
        let attributes: [String: AgentStudioTraceValue]
    }

    private let bus: EventBus<RuntimeEnvelope>
    private let activityAtom: TerminalActivityAtom
    private let traceRuntime: AgentStudioTraceRuntime?

    private var busTask: Task<Void, Never>?
    private var traceContinuation: AsyncStream<TraceRequest>.Continuation?
    private var traceWorkerTask: Task<Void, Never>?

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

    func stop() async {
        let task = busTask
        task?.cancel()
        busTask = nil
        await task?.value
        await drainTraceRecords()
    }

    private func consume(_ envelope: RuntimeEnvelope) {
        guard case .pane(let paneEnvelope) = envelope else { return }
        activityAtom.consume(paneEnvelope)
        traceTerminalActivity(paneEnvelope)
    }

    private func traceTerminalActivity(_ envelope: PaneEnvelope) {
        guard case .terminal(let event) = envelope.event else { return }
        guard traceRuntime != nil else { return }
        ensureTraceWorkerStarted()
        let attributes = terminalTraceAttributes(for: envelope, event: event)
        traceContinuation?.yield(
            .init(
                body: "terminal.activity.observed",
                traceID: envelope.correlationId?.uuidString,
                parentSpanID: envelope.causationId?.uuidString,
                attributes: attributes
            )
        )
    }

    private func ensureTraceWorkerStarted() {
        guard traceWorkerTask == nil, let traceRuntime else { return }
        let (stream, continuation) = AsyncStream.makeStream(of: TraceRequest.self)
        traceContinuation = continuation
        traceWorkerTask = Task(priority: .utility) {
            for await request in stream {
                await traceRuntime.record(
                    tag: .runtime,
                    body: request.body,
                    traceID: request.traceID,
                    parentSpanID: request.parentSpanID,
                    attributes: request.attributes
                )
            }
        }
    }

    private func drainTraceRecords() async {
        traceContinuation?.finish()
        traceContinuation = nil
        let workerTask = traceWorkerTask
        traceWorkerTask = nil
        await workerTask?.value
        do {
            try await traceRuntime?.flush()
        } catch {
            terminalActivityRouterLogger.warning(
                "Terminal activity trace flush failed: \(error.localizedDescription)")
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
