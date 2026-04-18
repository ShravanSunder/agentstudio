import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct WelcomeAtomTests {
    @Test
    func beginAndEndChoosingFolder_toggleTheFlag() {
        let atom = WelcomeAtom()

        atom.beginChoosingFolder()
        #expect(atom.isChoosingFolder == true)

        atom.endChoosingFolder()
        #expect(atom.isChoosingFolder == false)
    }

    @Test
    func beginFolderScan_setsScanningState() {
        let atom = WelcomeAtom()
        let rootPath = URL(fileURLWithPath: "/tmp/welcome-atom-scan")

        atom.beginFolderScan(rootPath)

        #expect(atom.folderScanState == .scanning(rootPath: rootPath))
    }

    @Test
    func completeFolderScan_withNoRepos_setsEmptyState() {
        let atom = WelcomeAtom()
        let rootPath = URL(fileURLWithPath: "/tmp/welcome-atom-empty")

        atom.completeFolderScan(rootPath: rootPath, discoveredRepoCount: 0)

        #expect(atom.folderScanState == .empty(rootPath: rootPath))
    }

    @Test
    func completeFolderScan_withRepos_clearsToIdle() {
        let atom = WelcomeAtom()
        let rootPath = URL(fileURLWithPath: "/tmp/welcome-atom-clear")
        atom.beginFolderScan(rootPath)

        atom.completeFolderScan(rootPath: rootPath, discoveredRepoCount: 2)

        #expect(atom.folderScanState == .idle)
    }

    @Test
    func clearFolderScanState_setsIdle() {
        let atom = WelcomeAtom()
        atom.beginFolderScan(URL(fileURLWithPath: "/tmp/welcome-atom-reset"))

        atom.clearFolderScanState()

        #expect(atom.folderScanState == .idle)
    }
}
