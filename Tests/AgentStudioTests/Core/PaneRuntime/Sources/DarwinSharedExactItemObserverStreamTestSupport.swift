import Foundation

@testable import AgentStudioCore

final class RecordingSharedExactItemStreamLifetime:
    DarwinSharedExactItemStreamLifetime, @unchecked Sendable
{
    private let lock = NSLock()
    private let onFlush: @Sendable () -> Bool
    private let onRetire: @Sendable () -> Void
    private var hasRetired = false

    init(
        onFlush: @escaping @Sendable () -> Bool = { true },
        onRetire: @escaping @Sendable () -> Void
    ) {
        self.onFlush = onFlush
        self.onRetire = onRetire
    }

    func flush() -> Bool { onFlush() }

    func retire() {
        let shouldRetire = lock.withLock { () -> Bool in
            guard !hasRetired else { return false }
            hasRetired = true
            return true
        }
        if shouldRetire { onRetire() }
    }
}

final class ControllableSharedExactItemStreamFactory: @unchecked Sendable {
    private let condition = NSCondition()
    private let startEvents: AsyncStream<Void>
    private let startEventsContinuation: AsyncStream<Void>.Continuation
    private var canCompleteStreamStart = false
    private var startedStreamCount = 0
    private var retiredStreamCount = 0

    init() {
        (startEvents, startEventsContinuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    var startCount: Int { condition.withLock { startedStreamCount } }
    var retirementCount: Int { condition.withLock { retiredStreamCount } }

    func waitUntilStreamStartBegins() async {
        for await _ in startEvents { return }
    }

    func allowStreamStartToComplete() {
        condition.withLock {
            canCompleteStreamStart = true
            condition.broadcast()
        }
    }

    func makeStream(
        parentKey _: DarwinSharedExactItemParentKey,
        streamGeneration _: UInt64,
        eventHandler _: @escaping @Sendable ([DarwinSharedExactItemRawEvent]) -> Void
    ) -> (any DarwinSharedExactItemStreamLifetime)? {
        condition.lock()
        startedStreamCount += 1
        startEventsContinuation.yield(())
        while !canCompleteStreamStart { condition.wait() }
        condition.unlock()
        return RecordingSharedExactItemStreamLifetime(
            onRetire: { [weak self] in
                self?.condition.withLock { self?.retiredStreamCount += 1 }
            }
        )
    }
}
