import CoreServices
import Foundation

package struct DarwinLocalFSEventRawEvent: @unchecked Sendable {
    package let path: String
    package let eventId: FSEventStreamEventId
    package let flags: FSEventStreamEventFlags

    package init(
        path: String,
        eventId: FSEventStreamEventId,
        flags: FSEventStreamEventFlags
    ) {
        self.path = path
        self.eventId = eventId
        self.flags = flags
    }
}

package struct DarwinLocalFSEventStreamRequest: @unchecked Sendable {
    package let worktreeId: UUID
    package let lifecycleGeneration: UInt64
    package let watchedPaths: [String]
    package let privateStagingExclusionPaths: [String]
    package let eventHandler: @Sendable ([DarwinLocalFSEventRawEvent]) -> Void

    package init(
        worktreeId: UUID,
        lifecycleGeneration: UInt64,
        watchedPaths: [String],
        privateStagingExclusionPaths: [String],
        eventHandler: @escaping @Sendable ([DarwinLocalFSEventRawEvent]) -> Void
    ) {
        self.worktreeId = worktreeId
        self.lifecycleGeneration = lifecycleGeneration
        self.watchedPaths = watchedPaths
        self.privateStagingExclusionPaths = privateStagingExclusionPaths
        self.eventHandler = eventHandler
    }
}

package protocol DarwinLocalFSEventStreamLifetime: Sendable {
    func flush() -> Bool
    func retire()
    func scheduleRetirement()
}

package typealias DarwinLocalFSEventStreamFactory =
    @Sendable (DarwinLocalFSEventStreamRequest) -> (any DarwinLocalFSEventStreamLifetime)?

package struct DarwinFSEventStreamFlushCompletion: Equatable, Sendable {
    package let shouldTeardown: Bool
    package let isCurrent: Bool
}

package final class DarwinFSEventStreamLifecycleGate: @unchecked Sendable {
    private enum State: Equatable {
        case active
        case retiring
        case retired
    }

    private let lock = NSLock()
    private var state = State.active
    private var inFlightFlushCount = 0

    package init() {}

    package func beginFlush() -> Bool {
        lock.withLock {
            guard state == .active else { return false }
            inFlightFlushCount += 1
            return true
        }
    }

    package func finishFlush() -> DarwinFSEventStreamFlushCompletion {
        lock.withLock {
            precondition(inFlightFlushCount > 0, "FSEvent stream flush finished without ownership")
            inFlightFlushCount -= 1
            switch state {
            case .active:
                return DarwinFSEventStreamFlushCompletion(
                    shouldTeardown: false,
                    isCurrent: true
                )
            case .retiring:
                guard inFlightFlushCount == 0 else {
                    return DarwinFSEventStreamFlushCompletion(
                        shouldTeardown: false,
                        isCurrent: false
                    )
                }
                state = .retired
                return DarwinFSEventStreamFlushCompletion(
                    shouldTeardown: true,
                    isCurrent: false
                )
            case .retired:
                preconditionFailure("FSEvent stream retired while a flush remained in flight")
            }
        }
    }

    package func requestRetirement() -> Bool {
        lock.withLock {
            guard state == .active else { return false }
            if inFlightFlushCount == 0 {
                state = .retired
                return true
            }
            state = .retiring
            return false
        }
    }
}

package final class DarwinFSEventNativeStreamLifetime:
    DarwinLocalFSEventStreamLifetime, @unchecked Sendable
{
    private let lifecycleGate = DarwinFSEventStreamLifecycleGate()
    private let stream: FSEventStreamRef
    private let queue: DispatchQueue

    package init(
        stream: FSEventStreamRef,
        queue: DispatchQueue
    ) {
        self.stream = stream
        self.queue = queue
    }

    deinit {
        retire()
    }

    package func flush() -> Bool {
        guard lifecycleGate.beginFlush() else { return false }
        FSEventStreamRetain(stream)
        FSEventStreamFlushSync(stream)
        FSEventStreamRelease(stream)
        let completion = lifecycleGate.finishFlush()
        if completion.shouldTeardown {
            teardown()
        }
        return completion.isCurrent
    }

    package func retire() {
        guard lifecycleGate.requestRetirement() else { return }
        teardown()
    }

    package func scheduleRetirement() {
        queue.async { [self] in
            retire()
        }
    }

    private func teardown() {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        _ = queue
    }
}
