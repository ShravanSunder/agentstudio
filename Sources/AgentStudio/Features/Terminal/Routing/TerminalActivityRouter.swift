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

    private var busTask: Task<Void, Never>?

    init(
        bus: EventBus<RuntimeEnvelope>,
        activityAtom: TerminalActivityAtom
    ) {
        self.bus = bus
        self.activityAtom = activityAtom
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
    }
}
