import Foundation

@MainActor
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
