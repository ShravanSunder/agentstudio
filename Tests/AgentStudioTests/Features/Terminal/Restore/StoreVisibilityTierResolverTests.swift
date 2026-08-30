import AgentStudioCore
import Foundation
import Testing

@testable import AgentStudioTerminal

@MainActor
@Suite(.serialized)
struct StoreVisibilityTierResolverTests {
    @Test
    func tier_marksPaneHidden_whenNoTabIsActive() {
        let store = WorkspaceStore()
        let pane = store.createPane()
        let resolver = StoreVisibilityTierResolver(store: store)

        #expect(resolver.tier(for: PaneId(existingUUID: pane.id)) == .p1Hidden)
    }

    @Test
    func tier_marksInactiveTabPaneHidden() {
        let store = WorkspaceStore()
        let firstPane = store.createPane()
        let firstTab = Tab(paneId: firstPane.id)
        store.appendTab(firstTab)
        let secondPane = store.createPane()
        let secondTab = Tab(paneId: secondPane.id)
        store.appendTab(secondTab)
        store.setActiveTab(firstTab.id)
        let resolver = StoreVisibilityTierResolver(store: store)

        #expect(resolver.tier(for: PaneId(existingUUID: firstPane.id)) == .p0Visible)
        #expect(resolver.tier(for: PaneId(existingUUID: secondPane.id)) == .p1Hidden)
    }

    @Test
    func tier_marksOnlyZoomSourcePaneVisible_whenTabIsZoomed() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-visibility-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WorkspaceStore()
        let repo = store.addRepo(at: tempDir)
        let worktree = try #require(repo.worktrees.first)
        let firstPane = store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let secondPane = store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: firstPane.id, name: "Focused")
        store.appendTab(tab)
        store.insertPane(
            secondPane.id,
            inTab: tab.id,
            at: firstPane.id,
            direction: .horizontal,
            position: .after, sizingMode: .halveTarget
        )
        store.panePresentationAtom.enterZoom(
            inTab: tab.id,
            sourcePaneId: firstPane.id,
            viewerPresentation: .unavailable
        )

        let resolver = StoreVisibilityTierResolver(store: store)

        #expect(resolver.tier(for: PaneId(existingUUID: firstPane.id)) == .p0Visible)
        #expect(resolver.tier(for: PaneId(existingUUID: secondPane.id)) == .p1Hidden)
    }

    @Test
    func tier_marksMinimizedPaneHidden_inActiveTab() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-visibility-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WorkspaceStore()
        let repo = store.addRepo(at: tempDir)
        let worktree = try #require(repo.worktrees.first)
        let firstPane = store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let secondPane = store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: firstPane.id, name: "Minimized")
        store.appendTab(tab)
        store.insertPane(
            secondPane.id,
            inTab: tab.id,
            at: firstPane.id,
            direction: .horizontal,
            position: .after, sizingMode: .halveTarget
        )
        _ = store.minimizePane(secondPane.id, inTab: tab.id)

        let resolver = StoreVisibilityTierResolver(store: store)

        #expect(resolver.tier(for: PaneId(existingUUID: firstPane.id)) == .p0Visible)
        #expect(resolver.tier(for: PaneId(existingUUID: secondPane.id)) == .p1Hidden)
    }

    @Test
    func tier_marksOrphanedLayoutPaneHidden_inActiveTab() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-visibility-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WorkspaceStore()
        let repo = store.addRepo(at: tempDir)
        let worktree = try #require(repo.worktrees.first)
        let pane = store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: pane.id, name: "Orphaned")
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        store.setResidency(.orphaned(reason: .worktreeNotFound(path: worktree.path.path)), for: pane.id)

        let resolver = StoreVisibilityTierResolver(store: store)

        #expect(resolver.tier(for: PaneId(existingUUID: pane.id)) == .p1Hidden)
        #expect(!resolver.isActive(PaneId(existingUUID: pane.id)))
    }

    @Test
    func tier_marksExpandedDrawerChildrenVisible() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-visibility-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WorkspaceStore()
        let repo = store.addRepo(at: tempDir)
        let worktree = try #require(repo.worktrees.first)
        let parentPane = store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: parentPane.id, name: "Drawer")
        store.appendTab(tab)
        let firstDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let secondDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))

        let resolver = StoreVisibilityTierResolver(store: store)

        #expect(resolver.tier(for: PaneId(existingUUID: parentPane.id)) == .p0Visible)
        #expect(resolver.tier(for: PaneId(existingUUID: firstDrawerPane.id)) == .p0Visible)
        #expect(resolver.tier(for: PaneId(existingUUID: secondDrawerPane.id)) == .p0Visible)
    }

    @Test
    func tier_marksDrawerChildrenHidden_whenDrawerCollapsed() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-visibility-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WorkspaceStore()
        let repo = store.addRepo(at: tempDir)
        let worktree = try #require(repo.worktrees.first)
        let parentPane = store.createPane(
            launchDirectory: worktree.path,
            provider: .zmx,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: parentPane.id, name: "Drawer")
        store.appendTab(tab)
        let drawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        store.toggleDrawer(for: parentPane.id)

        let resolver = StoreVisibilityTierResolver(store: store)

        #expect(resolver.tier(for: PaneId(existingUUID: drawerPane.id)) == .p1Hidden)
    }

    @Test
    func tier_marksMinimizedDrawerChildHidden() throws {
        let store = WorkspaceStore()
        let parentPane = store.createPane()
        store.appendTab(Tab(paneId: parentPane.id))
        let drawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        #expect(store.minimizeDrawerPane(drawerPane.id, in: parentPane.id))
        let resolver = StoreVisibilityTierResolver(store: store)

        #expect(resolver.tier(for: PaneId(existingUUID: drawerPane.id)) == .p1Hidden)
    }

    @Test
    func tier_marksDrawerChildrenHidden_whenParentPaneIsMinimized() throws {
        let store = WorkspaceStore()
        let parentPane = store.createPane()
        let siblingPane = store.createPane()
        let tab = Tab(paneId: parentPane.id)
        store.appendTab(tab)
        store.insertPane(
            siblingPane.id,
            inTab: tab.id,
            at: parentPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        let drawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        #expect(store.minimizePane(parentPane.id, inTab: tab.id))
        let resolver = StoreVisibilityTierResolver(store: store)

        #expect(resolver.tier(for: PaneId(existingUUID: parentPane.id)) == .p1Hidden)
        #expect(resolver.tier(for: PaneId(existingUUID: drawerPane.id)) == .p1Hidden)
        #expect(resolver.tier(for: PaneId(existingUUID: siblingPane.id)) == .p0Visible)
    }
}
