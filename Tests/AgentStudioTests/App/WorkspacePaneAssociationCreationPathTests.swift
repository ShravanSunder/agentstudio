import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct WorkspacePaneAssociationCreationPathTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("worktree terminal tab and split creation persist the requested association")
    func worktreeTerminalCreationPathsPersistAssociation() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)

        let sidebarPane = try #require(harness.coordinator.openTerminal(for: worktree, in: repo))
        expectDurableAssociation(sidebarPane.id, repo: repo, worktree: worktree, store: harness.store)

        let newTabPane = try #require(harness.coordinator.openNewTerminal(for: worktree, in: repo))
        expectDurableAssociation(newTabPane.id, repo: repo, worktree: worktree, store: harness.store)

        let splitPane = try #require(harness.coordinator.openWorktreeInPane(for: worktree, in: repo))
        expectDurableAssociation(splitPane.id, repo: repo, worktree: worktree, store: harness.store)
    }

    @Test("ordinary and explicit-directory terminal splits persist inherited or resolved association")
    func terminalSplitCreationPathsPersistAssociation() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let nestedDirectory = worktree.path.appending(path: "Sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        let sourcePane = harness.store.createPane(
            launchDirectory: worktree.path,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: sourcePane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        let paneIdsBeforeOrdinarySplit = harness.store.paneAtom.graphAtom.paneIDs
        harness.coordinator.executeInsertPane(
            source: .newTerminal,
            targetTabId: tab.id,
            targetPaneId: sourcePane.id,
            direction: .right,
            sizingMode: .halveTarget
        )
        let ordinarySplitId = try #require(
            harness.store.paneAtom.graphAtom.paneIDs.subtracting(paneIdsBeforeOrdinarySplit).first
        )
        expectDurableAssociation(ordinarySplitId, repo: repo, worktree: worktree, store: harness.store)

        let paneIdsBeforeDirectorySplit = harness.store.paneAtom.graphAtom.paneIDs
        harness.coordinator.executeInsertPane(
            source: .newTerminalAtDirectory(nestedDirectory),
            targetTabId: tab.id,
            targetPaneId: ordinarySplitId,
            direction: .right,
            sizingMode: .halveTarget
        )
        let directorySplitId = try #require(
            harness.store.paneAtom.graphAtom.paneIDs.subtracting(paneIdsBeforeDirectorySplit).first
        )
        expectDurableAssociation(
            directorySplitId,
            repo: repo,
            worktree: worktree,
            expectedCWD: nestedDirectory,
            store: harness.store
        )
    }

    @Test("floating terminals remain durably unassociated")
    func floatingTerminalCreationRemainsUnassociated() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        _ = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let freeDirectory = harness.tempDir.appending(path: "free", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: freeDirectory, withIntermediateDirectories: true)

        let pane = try #require(
            harness.coordinator.openFloatingTerminal(launchDirectory: freeDirectory, title: "Floating")
        )

        expectDurablyUnassociated(pane.id, expectedCWD: freeDirectory, store: harness.store)
    }

    @Test("drawer creation inherits the parent pane association")
    func drawerCreationPersistsParentAssociation() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let parentPane = harness.store.createPane(
            launchDirectory: worktree.path,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.setActivePane(parentPane.id, inTab: tab.id)

        harness.controller.execute(.addDrawerPane)

        let drawerPaneId = try #require(harness.store.drawerView(forParent: parentPane.id)?.activeChildId)
        expectDurableAssociation(drawerPaneId, repo: repo, worktree: worktree, store: harness.store)
    }

    @Test("existing-pane insertion and cross-tab move preserve durable association")
    func existingPaneCrossTabMovePreservesAssociation() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let movingPane = harness.store.createPane(
            launchDirectory: worktree.path,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let targetPane = harness.store.createPane()
        let sourceTab = Tab(paneId: movingPane.id)
        let targetTab = Tab(paneId: targetPane.id)
        harness.store.appendTab(sourceTab)
        harness.store.appendTab(targetTab)

        harness.coordinator.executeInsertPane(
            source: .existingPane(paneId: movingPane.id, sourceTabId: sourceTab.id),
            targetTabId: targetTab.id,
            targetPaneId: targetPane.id,
            direction: .right,
            sizingMode: .halveTarget
        )

        #expect(harness.store.tab(targetTab.id)?.paneIds.contains(movingPane.id) == true)
        expectDurableAssociation(movingPane.id, repo: repo, worktree: worktree, store: harness.store)
    }
}

@MainActor
private func expectDurableAssociation(
    _ paneId: UUID,
    repo: Repo,
    worktree: Worktree,
    expectedCWD: URL? = nil,
    store: WorkspaceStore
) {
    let facets = store.paneAtom.graphAtom.paneState(paneId)?.durableContextFacets
    #expect(facets?.repoId == repo.id)
    #expect(facets?.worktreeId == worktree.id)
    #expect(facets?.cwd?.standardizedFileURL == (expectedCWD ?? worktree.path).standardizedFileURL)
}

@MainActor
private func expectDurablyUnassociated(
    _ paneId: UUID,
    expectedCWD: URL?,
    store: WorkspaceStore
) {
    let facets = store.paneAtom.graphAtom.paneState(paneId)?.durableContextFacets
    #expect(facets?.repoId == nil)
    #expect(facets?.worktreeId == nil)
    #expect(facets?.cwd?.standardizedFileURL == expectedCWD?.standardizedFileURL)
}
