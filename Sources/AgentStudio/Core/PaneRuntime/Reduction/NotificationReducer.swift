import Foundation
import os.log

/// Event scheduling reducer that splits runtime envelopes into two streams:
/// immediate `criticalEvents` and frame-coalesced `batchedEvents` for lossy traffic.
///
/// Critical events can be tier-ordered (p0...p3) when a resolver is provided.
/// Lossy events are consolidated by `(source, consolidationKey)` and emitted on a frame cadence.
@MainActor
final class NotificationReducer {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "NotificationReducer")

    private let clock: any Clock<Duration>
    private let tierResolver: (any VisibilityTierResolver)?

    private let criticalContinuation: AsyncStream<PaneEventEnvelope>.Continuation
    let criticalEvents: AsyncStream<PaneEventEnvelope>

    private let batchContinuation: AsyncStream<[PaneEventEnvelope]>.Continuation
    let batchedEvents: AsyncStream<[PaneEventEnvelope]>

    private var criticalBufferByTier: [VisibilityTier: [RuntimeEnvelope]] = [:]
    private var criticalFlushTask: Task<Void, Never>?
    private var lossyBuffer: [String: RuntimeEnvelope] = [:]
    private var frameTimer: Task<Void, Never>?

    init(
        clock: any Clock<Duration> = ContinuousClock(),
        tierResolver: (any VisibilityTierResolver)? = nil
    ) {
        self.clock = clock
        self.tierResolver = tierResolver

        let (criticalEvents, criticalContinuation) = AsyncStream.makeStream(of: PaneEventEnvelope.self)
        self.criticalEvents = criticalEvents
        self.criticalContinuation = criticalContinuation

        let (batchedEvents, batchContinuation) = AsyncStream.makeStream(of: [PaneEventEnvelope].self)
        self.batchedEvents = batchedEvents
        self.batchContinuation = batchContinuation
    }

    isolated deinit {
        criticalFlushTask?.cancel()
        frameTimer?.cancel()
        criticalContinuation.finish()
        batchContinuation.finish()
    }

    func submit(_ envelope: RuntimeEnvelope) {
        switch envelope.actionPolicy {
        case .critical:
            guard tierResolver != nil else {
                emitCriticalLegacyEnvelopeIfPossible(envelope)
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

    func submit(_ envelope: PaneEventEnvelope) {
        submit(RuntimeEnvelope.fromLegacy(envelope))
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
                emitCriticalLegacyEnvelopeIfPossible(envelope)
            }
        }
        criticalBufferByTier.removeAll(keepingCapacity: true)
    }

    private func flushLossyBuffer() {
        guard !lossyBuffer.isEmpty else { return }
        var batch = Array(lossyBuffer.values)
        batch.sort(by: compareEnvelopes)
        lossyBuffer.removeAll(keepingCapacity: true)
        let legacyBatch = batch.compactMap { envelope -> PaneEventEnvelope? in
            guard let legacyEnvelope = envelope.toLegacy() else {
                Self.logger.debug(
                    """
                    Skipped lossy runtime envelope without legacy mapping; \
                    source=\(String(describing: envelope.source), privacy: .public) \
                    seq=\(envelope.seq, privacy: .public)
                    """
                )
                return nil
            }
            return legacyEnvelope
        }
        if !legacyBatch.isEmpty {
            batchContinuation.yield(legacyBatch)
        }
    }

    private func emitCriticalLegacyEnvelopeIfPossible(_ envelope: RuntimeEnvelope) {
        guard let legacyEnvelope = envelope.toLegacy() else {
            Self.logger.debug(
                """
                Skipped critical runtime envelope without legacy mapping; \
                source=\(String(describing: envelope.source), privacy: .public) \
                seq=\(envelope.seq, privacy: .public)
                """
            )
            return
        }
        criticalContinuation.yield(legacyEnvelope)
    }

    private func compareEnvelopes(_ lhs: RuntimeEnvelope, _ rhs: RuntimeEnvelope) -> Bool {
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

    private func tier(for envelope: RuntimeEnvelope) -> VisibilityTier {
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
