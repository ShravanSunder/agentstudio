import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Pane note and current pane path commands", .serialized)
struct PaneTabViewControllerPaneNoteTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("editPaneNote presents note editor for active main pane")
    func editPaneNote_targetsActiveMainPane() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = makeMainPane(in: harness)

        harness.controller.execute(.editPaneNote)

        #expect(harness.launchRecorder.paneNoteRequests == [pane.id])
    }

    @Test("copyCurrentPanePath copies active main pane cwd")
    func copyCurrentPanePath_usesMainPaneCWD() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = makeMainPane(in: harness)
        let cwd = harness.tempDir.appending(path: "live-cwd")
        harness.store.updatePaneCWD(pane.id, cwd: cwd)

        harness.controller.execute(.copyCurrentPanePath)

        #expect(harness.launchRecorder.copiedPaths.map(\.standardizedFileURL) == [cwd.standardizedFileURL])
    }

    @Test("copyCurrentPanePath falls back to active main pane launch directory")
    func copyCurrentPanePath_fallsBackToLaunchDirectory() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let launchDirectory = harness.tempDir.appending(path: "launch")
        _ = makeMainPane(in: harness, launchDirectory: launchDirectory)

        harness.controller.execute(.copyCurrentPanePath)

        #expect(harness.launchRecorder.copiedPaths.map(\.standardizedFileURL) == [launchDirectory.standardizedFileURL])
    }

    @Test("main pane note command is unavailable while drawer pane owns focus")
    func editPaneNote_doesNotTargetDrawerPane() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = makeMainPane(in: harness)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        harness.store.setActiveDrawerPane(drawerPane.id, in: parentPane.id)
        atom(\.workspaceFocusOwner).focusDrawerPane(parentPaneId: parentPane.id, paneId: drawerPane.id)

        #expect(!harness.controller.canExecute(.editPaneNote))
        harness.controller.execute(.editPaneNote)

        #expect(harness.launchRecorder.paneNoteRequests.isEmpty)
    }

    @Test("current pane path command is unavailable while drawer pane owns focus")
    func copyCurrentPanePath_doesNotTargetDrawerPane() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = makeMainPane(
            in: harness,
            launchDirectory: harness.tempDir.appending(path: "parent-launch")
        )
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        harness.store.setActiveDrawerPane(drawerPane.id, in: parentPane.id)
        atom(\.workspaceFocusOwner).focusDrawerPane(parentPaneId: parentPane.id, paneId: drawerPane.id)

        #expect(!harness.controller.canExecute(.copyCurrentPanePath))
        harness.controller.execute(.copyCurrentPanePath)

        #expect(harness.launchRecorder.copiedPaths.isEmpty)
    }

    private func makeMainPane(
        in harness: PaneTabViewControllerCommandHarness,
        launchDirectory: URL? = nil
    ) -> Pane {
        let pane = harness.store.createPane(
            launchDirectory: launchDirectory,
            title: "Terminal",
            provider: .zmx
        )
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        atom(\.workspaceFocusOwner).focusMainPane(pane.id)
        return pane
    }
}
