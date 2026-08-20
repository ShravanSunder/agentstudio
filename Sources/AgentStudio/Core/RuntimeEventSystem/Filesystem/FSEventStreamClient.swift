import Foundation

package struct FSEventBatch: Sendable {
    let worktreeId: UUID
    let paths: [String]
}

package enum FSEventStreamRegistrationUnavailableReason: Sendable, Equatable {
    case streamCreationFailed
    case streamStartFailed
    case clientShutdown
}

package enum FSEventStreamRegistrationOutcome: Sendable, Equatable {
    case observing
    case unavailable(FSEventStreamRegistrationUnavailableReason)
}

package protocol FSEventStreamClient: Sendable {
    func events() -> AsyncStream<FSEventBatch>
    func consumeCoarseRefreshDebt() -> Set<UUID>
    @discardableResult
    func register(
        worktreeId: UUID,
        repoId: UUID,
        rootPath: URL
    ) -> FSEventStreamRegistrationOutcome
    func unregister(worktreeId: UUID)
    func shutdown()
}
