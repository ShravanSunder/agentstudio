import AgentStudioCore
import Foundation

package enum ProcessExitWatchFailure: Equatable, Sendable {
    case permissionDenied, resourceExhausted, other
}

package enum ProcessExitWatchEvent: Equatable, Sendable {
    case exited(watchId: UUID)
    case alreadyGone(watchId: UUID)
    case unavailable(watchId: UUID, ProcessExitWatchFailure)
}

package struct ProcessExitWatch: Sendable {
    package let events: AsyncStream<ProcessExitWatchEvent>
    package let cancel: @Sendable () -> Void
}

package protocol ProcessExitWatching: Sendable {
    func watchExit(of process: ProcessIncarnation, watchId: UUID) -> ProcessExitWatch
}

package protocol ProcessExitSource: AnyObject, Sendable {
    func setRegistrationHandler(_ handler: @escaping @Sendable () -> Void)
    func setEventHandler(_ handler: @escaping @Sendable () -> Void)
    func setCancelHandler(_ handler: @escaping @Sendable () -> Void)
    func resume()
    func cancel()
}

package protocol ProcessExitSourceMaking: Sendable {
    func makeSource(pid: Int32) throws -> any ProcessExitSource
}

package enum ProcessExitWatcherFact: Equatable, Sendable {
    case sourceCreated, resumed, registered
    case checked(ColdStartLeaderState)
    case sourceCancelled
    case cancelled
    case settled(ProcessExitWatchEvent)
    case lateRequestDropped
}

package typealias ProcessExitWatcherFactSink = @Sendable (UUID, ProcessExitWatcherFact) -> Void

/// S2 RED compile-level stand-in; it creates no native sources.
package final class DarwinProcessExitWatcher: ProcessExitWatching, Sendable {
    private let factSink: ProcessExitWatcherFactSink

    package init(
        sourceMaker: (any ProcessExitSourceMaking)? = nil,
        leaderState: @escaping @Sendable (ProcessIncarnation) -> ColdStartLeaderState = {
            DarwinColdStartObserverSyscalls().leaderState(of: $0)
        },
        factSink: @escaping ProcessExitWatcherFactSink = { _, _ in }
    ) {
        self.factSink = factSink
    }

    package func watchExit(of process: ProcessIncarnation, watchId: UUID) -> ProcessExitWatch {
        let stream = AsyncStream.makeStream(of: ProcessExitWatchEvent.self, bufferingPolicy: .bufferingOldest(1))
        let event = ProcessExitWatchEvent.unavailable(watchId: watchId, .other)
        stream.continuation.yield(event)
        stream.continuation.finish()
        factSink(watchId, .settled(event))
        return ProcessExitWatch(events: stream.stream, cancel: {})
    }

    package func shutdown() {}
}
