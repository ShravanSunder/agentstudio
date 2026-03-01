import Foundation
import os

private let paneEventBusLogger = Logger(subsystem: "com.agentstudio", category: "PaneEventBus")

/// Typed async fan-out bus.
///
/// Producers `await post(_:)` and consumers iterate `for await` over independent streams
/// returned by `subscribe()`.
actor EventBus<Envelope: Sendable> {
    struct PostResult: Sendable {
        let subscriberCount: Int
        let droppedCount: Int
        let terminatedCount: Int
    }

    struct ReplayConfiguration: Sendable {
        let capacityPerSource: Int
        let sourceKey: @Sendable (Envelope) -> String

        init(capacityPerSource: Int, sourceKey: @escaping @Sendable (Envelope) -> String) {
            self.capacityPerSource = capacityPerSource
            self.sourceKey = sourceKey
        }
    }

    private struct ReplayRecord: Sendable {
        let order: UInt64
        let envelope: Envelope
    }

    private let replayConfiguration: ReplayConfiguration?
    private var subscribers: [UUID: AsyncStream<Envelope>.Continuation] = [:]
    private var droppedEventCount: UInt64 = 0
    private var replayBySource: [String: [ReplayRecord]] = [:]
    private var nextReplayOrder: UInt64 = 0

    init(replayConfiguration: ReplayConfiguration? = nil) {
        self.replayConfiguration = replayConfiguration
    }

    isolated deinit {
        for continuation in subscribers.values {
            continuation.finish()
        }
        subscribers.removeAll(keepingCapacity: false)
    }

    func subscribe(
        bufferingPolicy: AsyncStream<Envelope>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<Envelope> {
        let subscriberID = UUID()
        let replaySnapshot = replaySnapshot()
        let stream = AsyncStream<Envelope>(bufferingPolicy: bufferingPolicy) { continuation in
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(subscriberID) }
            }
            self.subscribers[subscriberID] = continuation
            var replayDroppedCount = 0
            replayLoop: for envelope in replaySnapshot {
                switch continuation.yield(envelope) {
                case .enqueued:
                    continue replayLoop
                case .dropped:
                    replayDroppedCount += 1
                case .terminated:
                    break replayLoop
                @unknown default:
                    continue replayLoop
                }
            }
            if replayDroppedCount > 0 {
                self.droppedEventCount += UInt64(replayDroppedCount)
                paneEventBusLogger.warning(
                    "Dropped \(replayDroppedCount, privacy: .public) replay event(s) for subscriber due to buffering policy overflow"
                )
            }
        }
        return stream
    }

    @discardableResult
    func post(_ envelope: Envelope) -> PostResult {
        appendReplay(envelope)

        var droppedCount = 0
        var terminatedSubscriberIds: [UUID] = []

        for (subscriberId, continuation) in subscribers {
            switch continuation.yield(envelope) {
            case .enqueued:
                continue
            case .dropped:
                droppedCount += 1
            case .terminated:
                terminatedSubscriberIds.append(subscriberId)
            @unknown default:
                continue
            }
        }

        if droppedCount > 0 {
            droppedEventCount += UInt64(droppedCount)
            paneEventBusLogger.warning(
                "Dropped pane event for \(droppedCount, privacy: .public) subscriber(s) due to buffering policy overflow"
            )
        }

        for subscriberId in terminatedSubscriberIds {
            subscribers.removeValue(forKey: subscriberId)
        }

        return PostResult(
            subscriberCount: subscribers.count,
            droppedCount: droppedCount,
            terminatedCount: terminatedSubscriberIds.count
        )
    }

    func totalDroppedEvents() -> UInt64 {
        droppedEventCount
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    private func appendReplay(_ envelope: Envelope) {
        guard let replayConfiguration, replayConfiguration.capacityPerSource > 0 else { return }

        let sourceKey = replayConfiguration.sourceKey(envelope)
        nextReplayOrder += 1
        var sourceRecords = replayBySource[sourceKey] ?? []
        sourceRecords.append(
            ReplayRecord(order: nextReplayOrder, envelope: envelope)
        )
        if sourceRecords.count > replayConfiguration.capacityPerSource {
            sourceRecords.removeFirst(sourceRecords.count - replayConfiguration.capacityPerSource)
        }
        replayBySource[sourceKey] = sourceRecords
    }

    private func replaySnapshot() -> [Envelope] {
        guard replayConfiguration != nil else { return [] }
        var records: [ReplayRecord] = []
        for sourceRecords in replayBySource.values {
            records.append(contentsOf: sourceRecords)
        }
        records.sort { $0.order < $1.order }
        return records.map(\.envelope)
    }
}
