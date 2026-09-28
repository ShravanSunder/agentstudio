import AgentStudioInfrastructure
import Foundation

/// Owns transport-only pulses for one open metadata response. Product frames
/// retain their N3 sequence and credit ownership; pulses bypass both.
actor BridgeProductMetadataKeepaliveSender {
    typealias EmitData = @Sendable (Data) throws -> Void

    private let clock: any Clock<Duration> & Sendable
    private let correlation: BridgeProductMetadataStreamCorrelation
    private let emitData: EmitData
    private let interval: Duration
    private var isOpen = true
    private var lastEmittedSequence: Int?

    init(
        correlation: BridgeProductMetadataStreamCorrelation,
        clock: any Clock<Duration> & Sendable = ContinuousClock(),
        interval: Duration = AppPolicies.Bridge.streamKeepaliveInterval,
        emitData: @escaping EmitData
    ) {
        self.correlation = correlation
        self.clock = clock
        self.interval = interval
        self.emitData = emitData
    }

    func send(_ frame: BridgeProductQueuedProducerFrame) throws {
        guard isOpen else { return }
        try emitData(frame.data)
        lastEmittedSequence = frame.sequence
        if frame.terminal {
            isOpen = false
            return
        }
        if frame.batchComplete {
            try emitKeepalive()
        }
    }

    func run() async {
        while isOpen && !Task.isCancelled {
            do {
                try await clock.sleep(for: interval)
                guard isOpen && !Task.isCancelled else { return }
                if lastEmittedSequence != nil {
                    try emitKeepalive()
                }
            } catch {
                // A cancelled route ends the sender. A failed emit means its
                // admission or reply stream has ended and must not be retried.
                isOpen = false
                return
            }
        }
    }

    func stop() {
        isOpen = false
    }

    private func emitKeepalive() throws {
        guard let lastEmittedSequence else { return }
        let frame = BridgeProductMetadataFrame.streamKeepalive(
            .init(
                frameIdentity: .init(
                    correlation: correlation,
                    streamSequence: lastEmittedSequence
                )
            )
        )
        try emitData(BridgeProductMetadataFrameCodec.encode(frame))
    }
}
