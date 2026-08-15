import Foundation

extension GitWorkingDirectoryProjector {
    func registeredContext(for worktreeId: UUID) -> WorktreeFilesystemContext? {
        guard let repoId = repoIdByWorktreeId[worktreeId],
            let rootPath = rootPathByWorktreeId[worktreeId]
        else {
            return nil
        }
        return WorktreeFilesystemContext(repoId: repoId, rootPath: rootPath)
    }
}
