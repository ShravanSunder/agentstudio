import Foundation

package struct WatchedFolderRefreshSummary: Sendable, Equatable {
    package let repoPathsByWatchedFolder: [URL: [URL]]

    package init(repoPathsByWatchedFolder: [URL: [URL]]) {
        self.repoPathsByWatchedFolder = repoPathsByWatchedFolder
    }

    package func repoPaths(in watchedFolder: URL) -> [URL] {
        repoPathsByWatchedFolder[watchedFolder.standardizedFileURL, default: []]
    }
}
