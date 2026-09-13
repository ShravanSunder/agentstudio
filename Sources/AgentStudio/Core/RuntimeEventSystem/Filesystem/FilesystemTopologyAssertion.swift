import Foundation

package struct WorktreeFilesystemContext: Sendable, Equatable {
    package let repoId: UUID
    package let rootPath: URL

    package init(repoId: UUID, rootPath: URL) {
        self.repoId = repoId
        self.rootPath = rootPath
    }
}

package struct FilesystemTopologyAssertion: Sendable, Equatable {
    package let repositoryLifetimes: [UUID: RepositoryObservationLifetime]
    package let worktreeLifetimes: [UUID: WorktreeObservationLifetime]
    package let generation: UInt64
    package let contextsByWorktreeId: [UUID: WorktreeFilesystemContext]
    package let repositoryStableKeysByWorktreeId: [UUID: String]

    package init(
        generation: UInt64,
        contextsByWorktreeId: [UUID: WorktreeFilesystemContext],
        repositoryStableKeysByWorktreeId: [UUID: String] = [:],
        repositoryLifetimes: [UUID: RepositoryObservationLifetime] = [:],
        worktreeLifetimes: [UUID: WorktreeObservationLifetime] = [:]
    ) {
        self.generation = generation
        self.repositoryLifetimes = repositoryLifetimes
        self.worktreeLifetimes = worktreeLifetimes
        self.contextsByWorktreeId = contextsByWorktreeId
        self.repositoryStableKeysByWorktreeId = repositoryStableKeysByWorktreeId
    }
}
