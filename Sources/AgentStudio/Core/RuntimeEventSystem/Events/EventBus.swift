import Foundation
import os

private let paneEventBusLogger = Logger(subsystem: "com.agentstudio", category: "PaneEventBus")

enum BusSubscriberPolicy: Hashable, Sendable {
    static let standardLossyBufferLimit = 256
    static let criticalPressureWarningLimit = standardLossyBufferLimit * 4

    case criticalUnbounded
    case lossyNewest(Int)
}

enum EventBusReplayStatus: Equatable, Sendable {
    case notConfigured
    case complete
    case possiblyTruncated(sourceLabels: [String])
}

enum EventBusFailureClass: String, Hashable, Sendable {
    case lossyDrop
    case criticalDrop
    case criticalPressure
    case replayPossiblyTruncated
}

struct EventBusSubscriberDiagnostics: Equatable, Sendable {
    let subscriberID: UUID
    let subscriberName: String
    let policy: BusSubscriberPolicy
    let yieldedCount: UInt64
    let consumedCount: UInt64
    let liveDroppedCount: UInt64
    let replayDroppedCount: UInt64
    let highWaterLag: UInt64
    let replayStatus: EventBusReplayStatus
    let failureClasses: Set<EventBusFailureClass>

    var requiresRecovery: Bool {
        failureClasses.contains(.criticalDrop)
            || failureClasses.contains(.criticalPressure)
            || failureClasses.contains(.replayPossiblyTruncated)
    }
}

struct EventBusDiagnosticsSnapshot: Equatable, Sendable {
    let busName: String
    let activeSubscribers: [EventBusSubscriberDiagnostics]
    let retainedRecoveryDiagnostics: [EventBusSubscriberDiagnostics]
    let totalDroppedEvents: UInt64
}

struct EventBusSubscription<Envelope: Sendable>: AsyncSequence, Sendable {
    typealias Element = Envelope

    struct Iterator: AsyncIteratorProtocol {
        private var iterator: AsyncStream<Envelope>.Iterator
        private let recordConsumed: @Sendable () async -> Void

        init(iterator: AsyncStream<Envelope>.Iterator, recordConsumed: @escaping @Sendable () async -> Void) {
            self.iterator = iterator
            self.recordConsumed = recordConsumed
        }

        mutating func next() async -> Envelope? {
            guard let envelope = await iterator.next() else { return nil }
            await recordConsumed()
            return envelope
        }
    }

    let subscriberName: String
    let policy: BusSubscriberPolicy
    let replayStatus: EventBusReplayStatus

    private let stream: AsyncStream<Envelope>
    private let recordConsumed: @Sendable () async -> Void

    init(
        subscriberName: String,
        policy: BusSubscriberPolicy,
        replayStatus: EventBusReplayStatus,
        stream: AsyncStream<Envelope>,
        recordConsumed: @escaping @Sendable () async -> Void
    ) {
        self.subscriberName = subscriberName
        self.policy = policy
        self.replayStatus = replayStatus
        self.stream = stream
        self.recordConsumed = recordConsumed
    }

    func makeAsyncIterator() -> Iterator {
        Iterator(iterator: stream.makeAsyncIterator(), recordConsumed: recordConsumed)
    }
}

/// Typed async fan-out bus.
///
/// Producers `await post(_:)` and consumers iterate `for await` over independent
/// subscriptions returned by `subscribe(policy:subscriberName:)`.
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

    private struct ReplaySnapshot: Sendable {
        let envelopes: [Envelope]
        let status: EventBusReplayStatus
    }

    private struct SubscriberRecord: Sendable {
        let continuation: AsyncStream<Envelope>.Continuation
        let subscriberName: String
        let policy: BusSubscriberPolicy
        let replayStatus: EventBusReplayStatus
        var yieldedCount: UInt64 = 0
        var consumedCount: UInt64 = 0
        var liveDroppedCount: UInt64 = 0
        var replayDroppedCount: UInt64 = 0
        var highWaterLag: UInt64 = 0
        var failureClasses: Set<EventBusFailureClass> = []
    }

    private enum DeliveryPhase {
        case live
        case replay
    }

    private let busName: String
    private let replayConfiguration: ReplayConfiguration?
    private var subscribers: [UUID: SubscriberRecord] = [:]
    private var retainedRecoveryDiagnostics: [EventBusSubscriberDiagnostics] = []
    private var droppedEventCount: UInt64 = 0
    private var replayBySource: [String: [ReplayRecord]] = [:]
    private var truncatedReplaySourceKeys: Set<String> = []
    private var nextReplayOrder: UInt64 = 0

    init(
        name: String = "eventBus",
        replayConfiguration: ReplayConfiguration? = nil
    ) {
        self.busName = name
        self.replayConfiguration = replayConfiguration
    }

    isolated deinit {
        for subscriber in subscribers.values {
            subscriber.continuation.finish()
        }
        subscribers.removeAll(keepingCapacity: false)
    }

    func subscribe(
        policy: BusSubscriberPolicy,
        subscriberName: String
    ) -> EventBusSubscription<Envelope> {
        let subscriberID = UUID()
        let replaySnapshot = replaySnapshot()
        let stream = AsyncStream<Envelope>(bufferingPolicy: bufferingPolicy(for: policy)) { continuation in
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(subscriberID) }
            }
            self.subscribers[subscriberID] = SubscriberRecord(
                continuation: continuation,
                subscriberName: subscriberName,
                policy: policy,
                replayStatus: replaySnapshot.status
            )
            replayLoop: for envelope in replaySnapshot.envelopes {
                switch continuation.yield(envelope) {
                case .enqueued:
                    self.recordYielded(subscriberID)
                    continue replayLoop
                case .dropped:
                    self.recordDrop(subscriberID, phase: .replay)
                case .terminated:
                    break replayLoop
                @unknown default:
                    continue replayLoop
                }
            }
            if case .possiblyTruncated = replaySnapshot.status {
                self.recordReplayTruncation(subscriberID)
            }
        }
        return EventBusSubscription(
            subscriberName: subscriberName,
            policy: policy,
            replayStatus: replaySnapshot.status,
            stream: stream,
            recordConsumed: { [weak self] in
                await self?.recordConsumed(subscriberID)
            }
        )
    }

    @discardableResult
    func post(_ envelope: Envelope) -> PostResult {
        appendReplay(envelope)

        var droppedCount = 0
        var terminatedSubscriberIds: [UUID] = []

        for (subscriberId, subscriber) in subscribers {
            switch subscriber.continuation.yield(envelope) {
            case .enqueued:
                recordYielded(subscriberId)
                continue
            case .dropped:
                droppedCount += 1
                recordDrop(subscriberId, phase: .live)
            case .terminated:
                terminatedSubscriberIds.append(subscriberId)
            @unknown default:
                continue
            }
        }

        if droppedCount > 0 {
            paneEventBusLogger.warning(
                "Dropped pane event for \(droppedCount, privacy: .public) subscriber(s) due to buffering policy overflow"
            )
        }

        for subscriberId in terminatedSubscriberIds {
            removeSubscriber(subscriberId)
        }

        return PostResult(
            subscriberCount: subscribers.count,
            droppedCount: droppedCount,
            terminatedCount: terminatedSubscriberIds.count
        )
    }

    @discardableResult
    func post(contentsOf envelopes: [Envelope]) -> PostResult {
        var droppedCount = 0
        var terminatedSubscriberIds: Set<UUID> = []

        for envelope in envelopes {
            appendReplay(envelope)
            for (subscriberId, subscriber) in subscribers where !terminatedSubscriberIds.contains(subscriberId) {
                switch subscriber.continuation.yield(envelope) {
                case .enqueued:
                    recordYielded(subscriberId)
                    continue
                case .dropped:
                    droppedCount += 1
                    recordDrop(subscriberId, phase: .live)
                case .terminated:
                    terminatedSubscriberIds.insert(subscriberId)
                @unknown default:
                    continue
                }
            }
        }

        if droppedCount > 0 {
            paneEventBusLogger.warning(
                "Dropped pane event for \(droppedCount, privacy: .public) subscriber(s) due to buffering policy overflow"
            )
        }

        for subscriberId in terminatedSubscriberIds {
            removeSubscriber(subscriberId)
        }

        return PostResult(
            subscriberCount: subscribers.count,
            droppedCount: droppedCount,
            terminatedCount: terminatedSubscriberIds.count
        )
    }

    var subscriberCount: Int {
        subscribers.count
    }

    func totalDroppedEvents() -> UInt64 {
        droppedEventCount
    }

    func diagnosticsSnapshot() -> EventBusDiagnosticsSnapshot {
        EventBusDiagnosticsSnapshot(
            busName: busName,
            activeSubscribers:
                subscribers
                .map { subscriberID, subscriber in
                    diagnostics(subscriberID: subscriberID, subscriber: subscriber)
                }
                .sorted(by: compareDiagnostics),
            retainedRecoveryDiagnostics: retainedRecoveryDiagnostics.sorted(by: compareDiagnostics),
            totalDroppedEvents: droppedEventCount
        )
    }

    func clearRetainedRecoveryDiagnostics() {
        retainedRecoveryDiagnostics.removeAll(keepingCapacity: false)
    }

    func evictReplay(sourceKey: String) {
        replayBySource.removeValue(forKey: sourceKey)
        truncatedReplaySourceKeys.remove(sourceKey)
    }

    private func removeSubscriber(_ id: UUID) {
        guard let subscriber = subscribers.removeValue(forKey: id) else { return }
        let diagnostics = diagnostics(subscriberID: id, subscriber: subscriber)
        if diagnostics.requiresRecovery {
            retainedRecoveryDiagnostics.append(diagnostics)
        }
    }

    private func recordConsumed(_ id: UUID) {
        guard var subscriber = subscribers[id] else { return }
        subscriber.consumedCount += 1
        subscribers[id] = subscriber
    }

    private func recordYielded(_ id: UUID) {
        guard var subscriber = subscribers[id] else { return }
        subscriber.yieldedCount += 1
        let lag = subscriber.yieldedCount.saturatingSubtract(subscriber.consumedCount)
        subscriber.highWaterLag = max(subscriber.highWaterLag, lag)
        if subscriber.policy == .criticalUnbounded, lag > UInt64(BusSubscriberPolicy.criticalPressureWarningLimit) {
            subscriber.failureClasses.insert(.criticalPressure)
        }
        subscribers[id] = subscriber
    }

    private func recordDrop(_ id: UUID, phase: DeliveryPhase) {
        guard var subscriber = subscribers[id] else { return }
        droppedEventCount += 1
        switch phase {
        case .live:
            subscriber.liveDroppedCount += 1
        case .replay:
            subscriber.replayDroppedCount += 1
        }
        switch subscriber.policy {
        case .criticalUnbounded:
            subscriber.failureClasses.insert(.criticalDrop)
        case .lossyNewest:
            subscriber.failureClasses.insert(.lossyDrop)
        }
        subscribers[id] = subscriber
    }

    private func recordReplayTruncation(_ id: UUID) {
        guard var subscriber = subscribers[id] else { return }
        subscriber.failureClasses.insert(.replayPossiblyTruncated)
        subscribers[id] = subscriber
    }

    private func bufferingPolicy(
        for policy: BusSubscriberPolicy
    ) -> AsyncStream<Envelope>.Continuation.BufferingPolicy {
        switch policy {
        case .criticalUnbounded:
            return .unbounded
        case .lossyNewest(let limit):
            return .bufferingNewest(limit)
        }
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
            truncatedReplaySourceKeys.insert(sourceKey)
            sourceRecords.removeFirst(sourceRecords.count - replayConfiguration.capacityPerSource)
        }
        replayBySource[sourceKey] = sourceRecords
    }

    private func replaySnapshot() -> ReplaySnapshot {
        guard replayConfiguration != nil else {
            return ReplaySnapshot(envelopes: [], status: .notConfigured)
        }
        var records: [ReplayRecord] = []
        for sourceRecords in replayBySource.values {
            records.append(contentsOf: sourceRecords)
        }
        records.sort { $0.order < $1.order }
        let sourceLabels =
            truncatedReplaySourceKeys
            .map(Self.safeDiagnosticSourceLabel)
            .sorted()
        let status: EventBusReplayStatus =
            sourceLabels.isEmpty
            ? .complete
            : .possiblyTruncated(sourceLabels: sourceLabels)
        return ReplaySnapshot(envelopes: records.map(\.envelope), status: status)
    }

    private static func safeDiagnosticSourceLabel(for sourceKey: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in sourceKey.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return "source-\(String(hash, radix: 16))"
    }

    private func diagnostics(
        subscriberID: UUID,
        subscriber: SubscriberRecord
    ) -> EventBusSubscriberDiagnostics {
        EventBusSubscriberDiagnostics(
            subscriberID: subscriberID,
            subscriberName: subscriber.subscriberName,
            policy: subscriber.policy,
            yieldedCount: subscriber.yieldedCount,
            consumedCount: subscriber.consumedCount,
            liveDroppedCount: subscriber.liveDroppedCount,
            replayDroppedCount: subscriber.replayDroppedCount,
            highWaterLag: subscriber.highWaterLag,
            replayStatus: subscriber.replayStatus,
            failureClasses: subscriber.failureClasses
        )
    }

    private func compareDiagnostics(
        _ lhs: EventBusSubscriberDiagnostics,
        _ rhs: EventBusSubscriberDiagnostics
    ) -> Bool {
        if lhs.subscriberName != rhs.subscriberName {
            return lhs.subscriberName < rhs.subscriberName
        }
        return lhs.subscriberID.uuidString < rhs.subscriberID.uuidString
    }
}

extension UInt64 {
    fileprivate func saturatingSubtract(_ other: UInt64) -> UInt64 {
        self >= other ? self - other : 0
    }
}
