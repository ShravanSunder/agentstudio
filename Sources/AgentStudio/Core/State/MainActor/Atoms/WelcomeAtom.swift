import Foundation
import Observation

enum WorkspaceFolderScanState: Equatable {
    case idle
    case scanning(rootPath: URL)
    case empty(rootPath: URL)
}

@MainActor
@Observable
final class WelcomeAtom {
    private(set) var isChoosingFolder = false
    private(set) var folderScanState: WorkspaceFolderScanState = .idle

    func beginChoosingFolder() {
        isChoosingFolder = true
    }

    func endChoosingFolder() {
        isChoosingFolder = false
    }

    func beginFolderScan(_ path: URL) {
        folderScanState = .scanning(rootPath: path.standardizedFileURL)
    }

    func completeFolderScan(rootPath: URL, discoveredRepoCount: Int) {
        let normalizedRootPath = rootPath.standardizedFileURL
        if discoveredRepoCount == 0 {
            folderScanState = .empty(rootPath: normalizedRootPath)
            return
        }
        folderScanState = .idle
    }

    func clearFolderScanState() {
        folderScanState = .idle
    }
}
