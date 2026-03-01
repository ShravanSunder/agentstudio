import Foundation
import os

/// Shared event channel for pane runtimes:
/// - Tracks envelope sequence numbers
/// - Manages subscriber fanout streams
/// - Stores replayable envelopes
/// - Posts envelopes to the app-wide pane event bus
@MainActor
final class PaneRuntimeEventChannel {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "PaneRuntimeEventChannel")
    private let clock: ContinuousClock
    private let replayBuffer: EventReplayBuffer
    private let paneEventBus: EventBus<RuntimeEnvelope>

    private var sequence: UInt64 = 0
    private var nextSubscriberId: UInt64 = 0
    private var subscribers: [UInt64: AsyncStream<RuntimeEnvelope>.Continuation] = [:]

    init(
        clock: ContinuousClock = ContinuousClock(),
        replayBuffer: EventReplayBuffer = EventReplayBuffer(),
        paneEventBus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared
    ) {
        self.clock = clock
        self.replayBuffer = replayBuffer
        self.paneEventBus = paneEventBus
    }

    var lastSequence: UInt64 {
        sequence
    }

    func subscribe(isTerminated: Bool) -> AsyncStream<RuntimeEnvelope> {
        let (stream, continuation) = AsyncStream.makeStream(of: RuntimeEnvelope.self)
        guard !isTerminated else {
            continuation.finish()
            return stream
        }

        let subscriberId = nextSubscriberId
        nextSubscriberId += 1
        subscribers[subscriberId] = continuation

        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.subscribers.removeValue(forKey: subscriberId)
            }
        }

        return stream
    }

    func eventsSince(seq: UInt64) -> EventReplayBuffer.ReplayResult {
        replayBuffer.eventsSince(seq: seq)
    }

    func snapshot(
        paneId: PaneId,
        metadata: PaneMetadata,
        lifecycle: PaneRuntimeLifecycle,
        capabilities: Set<PaneCapability>
    ) -> PaneRuntimeSnapshot {
        PaneRuntimeSnapshot(
            paneId: paneId,
            metadata: metadata,
            lifecycle: lifecycle,
            capabilities: capabilities,
            lastSeq: sequence,
            timestamp: Date()
        )
    }

    func finishSubscribers() {
        let activeSubscribers = Array(subscribers.values)
        subscribers.removeAll(keepingCapacity: true)
        for continuation in activeSubscribers {
            continuation.finish()
        }
    }

    func emit(
        paneId: PaneId,
        metadata: PaneMetadata,
        paneKind: PaneContentType,
        commandId: UUID? = nil,
        correlationId: UUID? = nil,
        event: PaneRuntimeEvent,
        persistForReplay: Bool = true
    ) {
        sequence += 1
        let envelope = RuntimeEnvelope.pane(
            PaneEnvelope(
                source: .pane(paneId),
                seq: sequence,
                timestamp: clock.now,
                correlationId: correlationId,
                commandId: commandId,
                paneId: paneId,
                paneKind: paneKind,
                event: event
            )
        )

        if persistForReplay {
            replayBuffer.append(envelope)
        }

        for continuation in subscribers.values {
            continuation.yield(envelope)
        }

        // Intentional fire-and-forget hop to keep runtime emit paths non-blocking.
        // Tradeoff: global bus post does not participate in structured backpressure.
        // Ordering is guaranteed for local subscribers/replay (yield + append above),
        // while cross-runtime bus fanout is best-effort and eventually consistent.
        Task { [paneEventBus] in
            let postResult = await paneEventBus.post(envelope)
            if postResult.droppedCount > 0 {
                Self.logger.warning(
                    "Dropped pane runtime bus event for \(postResult.droppedCount, privacy: .public) subscriber(s); seq=\(envelope.seq, privacy: .public)"
                )
            }
        }

        _ = metadata
    }
}
