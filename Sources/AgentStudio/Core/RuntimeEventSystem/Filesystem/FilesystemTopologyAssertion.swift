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
    package let generation: UInt64
    package let contextsByWorktreeId: [UUID: WorktreeFilesystemContext]

    package init(generation: UInt64, contextsByWorktreeId: [UUID: WorktreeFilesystemContext]) {
        self.generation = generation
        self.contextsByWorktreeId = contextsByWorktreeId
    }
}
