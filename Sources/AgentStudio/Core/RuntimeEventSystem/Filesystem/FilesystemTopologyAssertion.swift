import Foundation

struct WorktreeFilesystemContext: Sendable, Equatable {
    let repoId: UUID
    let rootPath: URL
}

struct FilesystemTopologyAssertion: Sendable, Equatable {
    let generation: UInt64
    let contextsByWorktreeId: [UUID: WorktreeFilesystemContext]
}
