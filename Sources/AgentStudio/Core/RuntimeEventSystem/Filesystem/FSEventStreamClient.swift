import Foundation

package struct FSEventObservation: Equatable, Sendable {
    package let path: String
    package let eventID: UInt64
    package let flags: UInt32

    package init(path: String, eventID: UInt64, flags: UInt32) {
        self.path = path
        self.eventID = eventID
        self.flags = flags
    }
}

package struct FSEventBatch: Sendable {
    let worktreeId: UUID
    let paths: [String]
    let observations: [FSEventObservation]
    let requiresFullGitRefresh: Bool

    package init(
        worktreeId: UUID,
        paths: [String],
        observations: [FSEventObservation] = [],
        requiresFullGitRefresh: Bool = false
    ) {
        self.worktreeId = worktreeId
        self.paths = paths
        self.observations = observations
        self.requiresFullGitRefresh = requiresFullGitRefresh
    }
}

package struct FSEventOverflowRecovery: Equatable, Sendable {
    package let worktreeId: UUID
    package let paths: Set<String>?
    package let containsGitTopologyPath: Bool
    package let requiresFullGitRefresh: Bool

    package init(
        worktreeId: UUID,
        paths: Set<String>?,
        containsGitTopologyPath: Bool = false,
        requiresFullGitRefresh: Bool = false
    ) {
        self.worktreeId = worktreeId
        self.paths = paths
        self.containsGitTopologyPath = containsGitTopologyPath
        self.requiresFullGitRefresh = requiresFullGitRefresh
    }
}

package protocol FSEventStreamClient: Sendable {
    func events() -> AsyncStream<FSEventBatch>
    func consumeOverflowRecoveries() -> [FSEventOverflowRecovery]
    func register(worktreeId: UUID, repoId: UUID, rootPath: URL)
    func unregister(worktreeId: UUID)
    func shutdown()
}
