import Foundation
import Observation

package enum WorkspaceFolderScanState: Equatable {
    case idle
    case scanning(rootPath: URL)
    case empty(rootPath: URL)
}

@MainActor
@Observable
package final class WelcomeAtom {
    package private(set) var isChoosingFolder = false
    package private(set) var folderScanState: WorkspaceFolderScanState = .idle

    package init() {}

    package func beginChoosingFolder() {
        isChoosingFolder = true
    }

    package func endChoosingFolder() {
        isChoosingFolder = false
    }

    package func beginFolderScan(_ path: URL) {
        folderScanState = .scanning(rootPath: path.standardizedFileURL)
    }

    package func completeFolderScan(rootPath: URL, discoveredRepoCount: Int) {
        let normalizedRootPath = rootPath.standardizedFileURL
        if discoveredRepoCount == 0 {
            folderScanState = .empty(rootPath: normalizedRootPath)
            return
        }
        folderScanState = .idle
    }

    package func clearFolderScanState() {
        folderScanState = .idle
    }
}
