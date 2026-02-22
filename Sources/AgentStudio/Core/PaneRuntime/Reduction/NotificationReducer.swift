import Foundation

@MainActor
final class NotificationReducer {
    private let clock: any Clock<Duration>
    private let tierResolver: (any VisibilityTierResolver)?

    private let criticalContinuation: AsyncStream<PaneEventEnvelope>.Continuation
    let criticalEvents: AsyncStream<PaneEventEnvelope>

    private let batchContinuation: AsyncStream<[PaneEventEnvelope]>.Continuation
    let batchedEvents: AsyncStream<[PaneEventEnvelope]>

    private var lossyBuffer: [String: PaneEventEnvelope] = [:]
    private var frameTimer: Task<Void, Never>?

    init(
        clock: any Clock<Duration> = ContinuousClock(),
        tierResolver: (any VisibilityTierResolver)? = nil
    ) {
        self.clock = clock
        self.tierResolver = tierResolver

        var criticalCont: AsyncStream<PaneEventEnvelope>.Continuation?
        self.criticalEvents = AsyncStream<PaneEventEnvelope> { continuation in
            criticalCont = continuation
        }
        self.criticalContinuation = criticalCont!

        var batchCont: AsyncStream<[PaneEventEnvelope]>.Continuation?
        self.batchedEvents = AsyncStream<[PaneEventEnvelope]> { continuation in
            batchCont = continuation
        }
        self.batchContinuation = batchCont!
    }

    isolated deinit {
        frameTimer?.cancel()
        criticalContinuation.finish()
        batchContinuation.finish()
    }

    func submit(_ envelope: PaneEventEnvelope) {
        switch envelope.event.actionPolicy {
        case .critical:
            criticalContinuation.yield(envelope)
        case .lossy(let consolidationKey):
            let key = "\(envelope.source):\(consolidationKey)"
            lossyBuffer[key] = envelope
            if lossyBuffer.count > 1000,
                let oldest = lossyBuffer.min(by: { $0.value.timestamp < $1.value.timestamp })
            {
                lossyBuffer.removeValue(forKey: oldest.key)
            }
            ensureFrameTimer()
        }
    }

    private func ensureFrameTimer() {
        guard frameTimer == nil else { return }
        frameTimer = Task { [weak self] in
            while let self, !self.lossyBuffer.isEmpty {
                try? await self.clock.sleep(for: .milliseconds(16))
                self.flushLossyBuffer()
            }
            self?.frameTimer = nil
        }
    }

    private func flushLossyBuffer() {
        guard !lossyBuffer.isEmpty else { return }
        var batch = Array(lossyBuffer.values)
        batch.sort(by: compareEnvelopes)
        lossyBuffer.removeAll(keepingCapacity: true)
        batchContinuation.yield(batch)
    }

    private func compareEnvelopes(_ lhs: PaneEventEnvelope, _ rhs: PaneEventEnvelope) -> Bool {
        let lhsTier = tier(for: lhs)
        let rhsTier = tier(for: rhs)
        if lhsTier != rhsTier {
            return lhsTier < rhsTier
        }
        if lhs.source == rhs.source {
            return lhs.seq < rhs.seq
        }
        return lhs.timestamp < rhs.timestamp
    }

    private func tier(for envelope: PaneEventEnvelope) -> VisibilityTier {
        guard
            let resolver = tierResolver,
            case .pane(let paneId) = envelope.source
        else {
            return .p3Background
        }
        return resolver.tier(for: paneId)
    }
}
