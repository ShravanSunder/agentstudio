import CoreServices
import Foundation

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

final class NativeSharedExactItemStreamRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let nativeSharedStreamIsEnabled: Bool
    let callbackEvents: AsyncStream<DarwinSharedExactItemRawEvent>
    private let callbackEventsContinuation: AsyncStream<DarwinSharedExactItemRawEvent>.Continuation
    private var startCountByParentPath: [String: Int] = [:]
    private var callbackWaiters: [UUID: (path: String, continuation: AsyncStream<UInt64>.Continuation)] = [:]

    init(nativeSharedStreamIsEnabled: Bool) {
        self.nativeSharedStreamIsEnabled = nativeSharedStreamIsEnabled
        (callbackEvents, callbackEventsContinuation) = AsyncStream.makeStream(
            of: DarwinSharedExactItemRawEvent.self,
            bufferingPolicy: .bufferingNewest(32)
        )
    }

    func startCount(forParentPath parentPath: String) -> Int {
        lock.withLock { startCountByParentPath[parentPath, default: 0] }
    }

    func makeStream(
        parentKey: DarwinSharedExactItemParentKey,
        streamGeneration: UInt64,
        eventHandler: @escaping @Sendable ([DarwinSharedExactItemRawEvent]) -> Void
    ) -> (any DarwinSharedExactItemStreamLifetime)? {
        lock.withLock {
            startCountByParentPath[parentKey.parentPath, default: 0] += 1
        }
        guard nativeSharedStreamIsEnabled else { return nil }
        return DarwinSharedExactItemNativeStream.start(
            parentKey: parentKey,
            streamGeneration: streamGeneration,
            eventHandler: { [weak self] rawEvents in
                eventHandler(rawEvents)
                self?.recordCallbackEvents(rawEvents)
            }
        )
    }

    func armCallbackEvent(at expectedPath: String) -> AsyncStream<UInt64> {
        let waiterID = UUIDv7.generate()
        let (events, continuation) = AsyncStream.makeStream(
            of: UInt64.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        continuation.onTermination = { [weak self] _ in
            _ = self?.lock.withLock { self?.callbackWaiters.removeValue(forKey: waiterID) }
        }
        lock.withLock {
            callbackWaiters[waiterID] = (expectedPath, continuation)
        }
        return events
    }

    func awaitCallbackEvent(_ events: AsyncStream<UInt64>) async -> UInt64? {
        for await eventID in events { return eventID }
        return nil
    }

    func recordCallbackEvents(_ rawEvents: [DarwinSharedExactItemRawEvent]) {
        let completedWaiters = lock.withLock {
            var completed: [(AsyncStream<UInt64>.Continuation, UInt64)] = []
            for rawEvent in rawEvents {
                let callbackPath = DarwinFSEventPathNormalizer.lexicallyNormalizedAbsolutePath(
                    rawEvent.path
                )
                let matchingWaiterIDs = callbackWaiters.compactMap { waiterID, waiter in
                    waiter.path == callbackPath ? waiterID : nil
                }
                for waiterID in matchingWaiterIDs {
                    guard let waiter = callbackWaiters.removeValue(forKey: waiterID) else {
                        continue
                    }
                    completed.append((waiter.continuation, UInt64(rawEvent.eventId)))
                }
                callbackEventsContinuation.yield(rawEvent)
            }
            return completed
        }
        for (continuation, eventID) in completedWaiters {
            continuation.yield(eventID)
            continuation.finish()
        }
    }

}
