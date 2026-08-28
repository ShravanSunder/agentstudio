import Foundation

package struct FSEventParticipant: Equatable, Hashable, Sendable {
    package let scopeKey: String
    package let generation: UInt64
    package let volumeIdentifier: String

    package init(scopeKey: String, generation: UInt64, volumeIdentifier: String) {
        self.scopeKey = scopeKey
        self.generation = generation
        self.volumeIdentifier = volumeIdentifier
    }
}

package struct FSEventParticipantBinding: Equatable, Hashable, Sendable {
    package let worktreeId: UUID
    package let participant: FSEventParticipant

    package init(worktreeId: UUID, participant: FSEventParticipant) {
        self.worktreeId = worktreeId
        self.participant = participant
    }
}

package struct FSEventActivityBarrier: Equatable, Sendable {
    package let bindings: [FSEventParticipantBinding]
    package let deliveredEventIDByParticipant: [FSEventParticipant: UInt64]

    package init(
        bindings: [FSEventParticipantBinding],
        deliveredEventIDByParticipant: [FSEventParticipant: UInt64]
    ) {
        self.bindings = bindings
        self.deliveredEventIDByParticipant = deliveredEventIDByParticipant
    }
}

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
    let participant: FSEventParticipant?
    let observations: [FSEventObservation]
    let requiresFullGitRefresh: Bool

    package init(
        worktreeId: UUID,
        paths: [String],
        participant: FSEventParticipant? = nil,
        observations: [FSEventObservation] = [],
        requiresFullGitRefresh: Bool = false
    ) {
        self.worktreeId = worktreeId
        self.paths = paths
        self.participant = participant
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
    func captureActivityBarrier() async -> FSEventActivityBarrier?
}

extension FSEventStreamClient {
    package func captureActivityBarrier() async -> FSEventActivityBarrier? {
        nil
    }
}
