import Foundation

package struct WatchedFolderRefreshSummary: Sendable, Equatable {
    package let repoPathsByWatchedFolder: [URL: [URL]]
    package let linkedWorktreePathsByWatchedFolder: [URL: [URL]]
    package let topologyFingerprint: String?
    package let filesystemLogicalDebtCount: Int

    package init(
        repoPathsByWatchedFolder: [URL: [URL]],
        linkedWorktreePathsByWatchedFolder: [URL: [URL]] = [:],
        topologyFingerprint: String? = nil,
        filesystemLogicalDebtCount: Int = 0
    ) {
        self.repoPathsByWatchedFolder = repoPathsByWatchedFolder
        self.linkedWorktreePathsByWatchedFolder = linkedWorktreePathsByWatchedFolder
        self.topologyFingerprint = topologyFingerprint
        self.filesystemLogicalDebtCount = filesystemLogicalDebtCount
    }

    package func repoPaths(in watchedFolder: URL) -> [URL] {
        repoPathsByWatchedFolder[watchedFolder.standardizedFileURL, default: []]
    }

    package func linkedWorktreePaths(in watchedFolder: URL) -> [URL] {
        linkedWorktreePathsByWatchedFolder[watchedFolder.standardizedFileURL, default: []]
    }

    package func replacingFilesystemLogicalDebtCount(_ count: Int) -> Self {
        Self(
            repoPathsByWatchedFolder: repoPathsByWatchedFolder,
            linkedWorktreePathsByWatchedFolder: linkedWorktreePathsByWatchedFolder,
            topologyFingerprint: topologyFingerprint,
            filesystemLogicalDebtCount: count
        )
    }
}
