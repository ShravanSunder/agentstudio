import Foundation
import os.log

@MainActor
final class NotificationReducer {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "NotificationReducer")

    private let clock: any Clock<Duration>
    private let tierResolver: (any VisibilityTierResolver)?

    private let criticalContinuation: AsyncStream<PaneEventEnvelope>.Continuation
    let criticalEvents: AsyncStream<PaneEventEnvelope>

    private let batchContinuation: AsyncStream<[PaneEventEnvelope]>.Continuation
    let batchedEvents: AsyncStream<[PaneEventEnvelope]>

    private var criticalBufferByTier: [VisibilityTier: [PaneEventEnvelope]] = [:]
    private var criticalFlushTask: Task<Void, Never>?
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
        criticalFlushTask?.cancel()
        frameTimer?.cancel()
        criticalContinuation.finish()
        batchContinuation.finish()
    }

    func submit(_ envelope: PaneEventEnvelope) {
        switch envelope.event.actionPolicy {
        case .critical:
            guard tierResolver != nil else {
                criticalContinuation.yield(envelope)
                return
            }
            let visibilityTier = tier(for: envelope)
            criticalBufferByTier[visibilityTier, default: []].append(envelope)
            ensureCriticalFlushTask()
        case .lossy(let consolidationKey):
            let key = "\(envelope.source):\(consolidationKey)"
            lossyBuffer[key] = envelope
            if lossyBuffer.count > 1000,
                let oldest = lossyBuffer.min(by: { $0.value.timestamp < $1.value.timestamp })
            {
                Self.logger.warning(
                    "Lossy buffer capacity exceeded; evicting oldest event seq=\(oldest.value.seq, privacy: .public) source=\(String(describing: oldest.value.source), privacy: .public)"
                )
                lossyBuffer.removeValue(forKey: oldest.key)
            }
            ensureFrameTimer()
        }
    }

    private func ensureCriticalFlushTask() {
        guard criticalFlushTask == nil else { return }
        criticalFlushTask = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.flushCriticalBuffer()
            self?.criticalFlushTask = nil
        }
    }

    private func ensureFrameTimer() {
        guard frameTimer == nil else { return }
        frameTimer = Task { [weak self] in
            defer { self?.frameTimer = nil }
            while let self, !self.lossyBuffer.isEmpty {
                do {
                    try await self.clock.sleep(for: .milliseconds(16))
                } catch is CancellationError {
                    return
                } catch {
                    Self.logger.error(
                        "Lossy frame timer sleep failed: \(String(describing: error), privacy: .public)"
                    )
                    continue
                }
                guard !Task.isCancelled else { return }
                self.flushLossyBuffer()
            }
        }
    }

    private func flushCriticalBuffer() {
        let orderedTiers: [VisibilityTier] = [.p0ActivePane, .p1ActiveDrawer, .p2VisibleActiveTab, .p3Background]
        for visibilityTier in orderedTiers {
            let queued = (criticalBufferByTier[visibilityTier] ?? []).sorted(by: compareEnvelopes)
            guard !queued.isEmpty else { continue }
            for envelope in queued {
                criticalContinuation.yield(envelope)
            }
        }
        criticalBufferByTier.removeAll(keepingCapacity: true)
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
        if case .system = envelope.source {
            // Contract 12a: system events are always highest visibility priority.
            return .p0ActivePane
        }
        guard
            let resolver = tierResolver,
            case .pane(let paneId) = envelope.source
        else {
            return .p3Background
        }
        return resolver.tier(for: paneId)
    }
}
