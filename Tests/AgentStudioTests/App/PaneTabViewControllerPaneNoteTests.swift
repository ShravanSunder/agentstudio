import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("Pane note and current pane path commands", .serialized)
struct PaneTabViewControllerPaneNoteTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("editPaneNote presents note editor for active main pane")
    func editPaneNote_targetsActiveMainPane() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = makeMainPane(in: harness)

        harness.controller.execute(.editPaneNote)

        #expect(harness.launchRecorder.paneNoteRequests == [pane.id])
    }

    @Test("targeted editPaneNote presents note editor for the requested main pane")
    func targetedEditPaneNote_targetsRequestedMainPane() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = makeMainPane(in: harness)

        #expect(harness.controller.canExecute(.editPaneNote, target: pane.id, targetType: .pane))
        let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        try attachPaneHost(paneId: pane.id, in: harness, to: window)
        await harness.executeCommand(.editPaneNote, target: pane.id, targetType: .pane)

        #expect(harness.launchRecorder.paneNoteRequests == [pane.id])
    }

    @Test("targeted note editing accepts a drawer child and preserves its owner")
    func targetedEditPaneNote_targetsDrawerChild() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            let parent = makeMainPane(in: harness)
            let child = try #require(harness.store.addDrawerPane(to: parent.id))
            let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            try attachPaneHost(paneId: parent.id, in: harness, to: window)
            try attachPaneHost(paneId: child.id, in: harness, to: window)
            #expect(harness.controller.canExecute(.editPaneNote, target: child.id, targetType: .pane))
            harness.controller.execute(.editPaneNote, target: child.id, targetType: .pane)
            _ = await harness.executor.submitGesture { _ in true }.value
            #expect(harness.launchRecorder.paneNoteRequests == [child.id])
            #expect(harness.store.paneAtom.pane(parent.id)?.metadata.note == nil)
        }
    }

    @Test("targeted note waits for queued focus completion before presentation")
    func targetedEditPaneNoteWaitsForFocusCompletion() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let pane = makeMainPane(in: harness)
        let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        try attachPaneHost(paneId: pane.id, in: harness, to: window)
        let release = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        var predecessorStarted = false
        let predecessor = harness.executor.submitGesture { _ in
            predecessorStarted = true
            for await _ in release.stream { break }
            return true
        }
        await eventually("the predecessor should suspend before targeted note focus") {
            predecessorStarted
        }

        harness.controller.execute(.editPaneNote, target: pane.id, targetType: .pane)
        #expect(harness.launchRecorder.paneNoteRequests.isEmpty)
        release.continuation.yield(())
        release.continuation.finish()
        #expect(await predecessor.value)
        _ = await harness.executor.submitGesture { _ in true }.value

        #expect(harness.launchRecorder.paneNoteRequests == [pane.id])
    }

    @Test("targeted note does not present when native focus cannot be applied")
    func targetedEditPaneNoteStopsAfterFocusFailure() async {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let pane = makeMainPane(in: harness)

        await harness.executeCommand(.editPaneNote, target: pane.id, targetType: .pane)

        #expect(harness.launchRecorder.paneNoteRequests.isEmpty)
    }

    @Test("copyCurrentPanePath copies active main pane cwd")
    func copyCurrentPanePath_usesMainPaneCWD() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = makeMainPane(in: harness)
        let cwd = harness.tempDir.appending(path: "live-cwd")
        harness.store.updatePaneCWD(pane.id, cwd: cwd)

        harness.controller.execute(.copyCurrentPanePath)

        #expect(harness.launchRecorder.copiedPaths.map(\.standardizedFileURL.path) == [cwd.standardizedFileURL.path])
    }

    @Test("copyCurrentPanePath falls back to active main pane launch directory")
    func copyCurrentPanePath_fallsBackToLaunchDirectory() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let launchDirectory = harness.tempDir.appending(path: "launch", directoryHint: .isDirectory)
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
