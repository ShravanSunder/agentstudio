import AppKit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCommandBar
@testable import AgentStudioCore

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerQuickOpenDirectoryTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("Quick Open directory inserts a terminal at the exact cwd without inheriting pane identity")
    func executeQuickOpenDirectory_currentTabUsesExactDirectory() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repositoryPath = harness.tempDir.appending(path: "repository")
        let worktreePath = repositoryPath.appending(path: "main")
        let quickOpenDirectory = harness.tempDir.appending(path: "untracked-directory")
        try FileManager.default.createDirectory(at: worktreePath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: quickOpenDirectory, withIntermediateDirectories: true)

        let repository = harness.store.addRepo(at: repositoryPath)
        let worktree = Worktree(
            repoId: repository.id,
            name: "main",
            path: worktreePath,
            isMainWorktree: true
        )
        harness.store.reconcileDiscoveredWorktrees(repository.id, worktrees: [worktree])

        let targetPane = harness.store.createPane(
            launchDirectory: worktreePath,
            provider: .zmx,
            facets: PaneContextFacets(
                repoId: repository.id,
                worktreeId: worktree.id,
                cwd: worktreePath
            )
        )
        let tab = Tab(paneId: targetPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.setActivePane(targetPane.id, inTab: tab.id)
        harness.windowLifecycleStore.recordTerminalContainerBounds(
            CGRect(x: 0, y: 0, width: 1000, height: 600)
        )

        harness.controller.executeQuickOpenDirectory(
            quickOpenDirectory,
            placement: .currentTabPane
        )

        let insertedPaneId = try #require(
            harness.store.tab(tab.id)?.paneIds.first { $0 != targetPane.id }
        )
        let insertedPane = try #require(harness.store.pane(insertedPaneId))
        #expect(insertedPane.metadata.facets.cwd == quickOpenDirectory)
        #expect(insertedPane.repoId == nil)
        #expect(insertedPane.worktreeId == nil)
        #expect(harness.surfaceManager.lastCreatedSurfaceMetadata?.cwd == quickOpenDirectory)
    }

    @Test("Quick Open directory creates a new tab at the exact cwd")
    func executeQuickOpenDirectory_newTabUsesExactDirectory() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let quickOpenDirectory = harness.tempDir.appending(path: "new-tab-directory")
        try FileManager.default.createDirectory(at: quickOpenDirectory, withIntermediateDirectories: true)
        harness.windowLifecycleStore.recordTerminalContainerBounds(
            CGRect(x: 0, y: 0, width: 1000, height: 600)
        )

        harness.controller.executeQuickOpenDirectory(
            quickOpenDirectory,
            placement: .newTab
        )

        let activeTabId = try #require(harness.store.activeTabId)
        let activePaneId = try #require(harness.store.tab(activeTabId)?.activePaneId)
        #expect(harness.store.pane(activePaneId)?.metadata.facets.cwd == quickOpenDirectory)
        #expect(harness.surfaceManager.lastCreatedSurfaceMetadata?.cwd == quickOpenDirectory)
    }

    @Test("Quick Open directory in a known worktree keeps topology identity in a new tab")
    func executeQuickOpenDirectory_newTabKeepsKnownWorktreeIdentity() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repositoryPath = harness.tempDir.appending(path: "repository")
        let worktreePath = repositoryPath.appending(path: "main")
        let nestedDirectory = worktreePath.appending(path: "Sources")
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)

        let repository = harness.store.addRepo(at: repositoryPath)
        let worktree = Worktree(
            repoId: repository.id,
            name: "main",
            path: worktreePath,
            isMainWorktree: true
        )
        harness.store.reconcileDiscoveredWorktrees(repository.id, worktrees: [worktree])
        harness.windowLifecycleStore.recordTerminalContainerBounds(
            CGRect(x: 0, y: 0, width: 1000, height: 600)
        )

        harness.controller.executeQuickOpenDirectory(
            nestedDirectory,
            placement: .newTab
        )

        let activeTabId = try #require(harness.store.activeTabId)
        let activePaneId = try #require(harness.store.tab(activeTabId)?.activePaneId)
        let pane = try #require(harness.store.pane(activePaneId))
        let resolvedContext = try #require(
            harness.store.repositoryTopologyAtom.repoAndWorktree(containing: nestedDirectory)
        )
        #expect(pane.metadata.cwd == nestedDirectory)
        #expect(pane.repoId == resolvedContext.repo.id)
        #expect(pane.worktreeId == resolvedContext.worktree.id)
    }
}
