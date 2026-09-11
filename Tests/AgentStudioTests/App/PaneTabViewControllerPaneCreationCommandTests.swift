import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("Pane context terminal creation", .serialized)
struct PaneTabViewControllerPaneCreationCommandTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("new split resolves the clicked pane directory and tab independently of active focus")
    func splitUsesClickedPaneDirectoryAndTab() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let clickedDirectory = harness.tempDir.appending(path: "clicked/subdirectory", directoryHint: .isDirectory)
        let clicked = harness.store.createPane(
            launchDirectory: clickedDirectory, facets: PaneContextFacets(cwd: clickedDirectory)
        )
        let clickedTab = Tab(paneId: clicked.id)
        harness.store.appendTab(clickedTab)
        let other = harness.store.createPane()
        let otherTab = Tab(paneId: other.id)
        harness.store.appendTab(otherTab)
        harness.store.setActiveTab(otherTab.id)

        let action = try #require(
            harness.controller.paneTerminalCreationAction(
                command: .openWorktreeInPane, paneId: clicked.id
            ))
        #expect(
            action
                == .insertPane(
                    source: .newTerminalAtDirectory(clickedDirectory), targetTabId: clickedTab.id,
                    targetPaneId: clicked.id, direction: .right, sizingMode: .halveTarget
                ))
        #expect(harness.store.tabLayoutAtom.activeTabId == otherTab.id)
    }

    @Test("associated pane creates its terminal at CWD rather than the worktree root")
    func associatedPaneUsesSubdirectory() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let repository = harness.store.addRepo(at: harness.tempDir.appending(path: "repo"))
        let worktree = try #require(harness.store.repos.first { $0.id == repository.id }?.worktrees.first)
        let directory = worktree.path.appending(path: "Sources", directoryHint: .isDirectory)
        let pane = harness.store.createPane(
            launchDirectory: worktree.path,
            facets: PaneContextFacets(repoId: repository.id, worktreeId: worktree.id, cwd: directory)
        )
        harness.store.appendTab(Tab(paneId: pane.id))
        #expect(
            harness.controller.paneTerminalCreationAction(
                command: .openNewTerminalInTab, paneId: pane.id
            ) == .openNewTerminalInTab(worktreeId: worktree.id, launchDirectory: directory, title: nil))
    }

    @Test("unassociated pane creates a new terminal tab at its CWD")
    func unassociatedPaneUsesExplicitDirectory() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let directory = harness.tempDir.appending(path: "standalone", directoryHint: .isDirectory)
        let pane = harness.store.createPane(launchDirectory: directory, facets: PaneContextFacets(cwd: directory))
        harness.store.appendTab(Tab(paneId: pane.id))
        #expect(
            harness.controller.paneTerminalCreationAction(
                command: .openNewTerminalInTab, paneId: pane.id
            ) == .openFloatingTerminal(launchDirectory: directory, title: nil))
        #expect(
            harness.controller.paneTerminalCreationAction(
                command: .openNewTerminalInTab, paneId: UUIDv7.generate()
            ) == nil)
    }
}
