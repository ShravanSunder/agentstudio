import CoreServices
import Foundation

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

package final class DarwinFSEventNativeStreamLifetime: @unchecked Sendable {
    private let lifecycleGate = DarwinFSEventStreamLifecycleGate()
    private let stream: FSEventStreamRef
    private let queue: DispatchQueue
    private let releaseCallbackContext: () -> Void

    package init(
        stream: FSEventStreamRef,
        queue: DispatchQueue,
        releaseCallbackContext: @escaping () -> Void
    ) {
        self.stream = stream
        self.queue = queue
        self.releaseCallbackContext = releaseCallbackContext
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
        releaseCallbackContext()
        _ = queue
    }
}
