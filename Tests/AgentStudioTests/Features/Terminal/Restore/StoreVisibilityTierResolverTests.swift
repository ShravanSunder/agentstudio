import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct StoreVisibilityTierResolverTests {
    @Test
    func tier_marksOnlyZoomedPaneVisible_whenTabIsZoomed() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-visibility-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner())
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
        let tab = Tab(paneId: firstPane.id, name: "Zoomed")
        store.appendTab(tab)
        store.insertPane(
            secondPane.id,
            inTab: tab.id,
            at: firstPane.id,
            direction: .horizontal,
            position: .after, sizingMode: .halveTarget
        )
        store.toggleZoom(paneId: firstPane.id, inTab: tab.id)

        let resolver = StoreVisibilityTierResolver(store: store)

        #expect(resolver.tier(for: PaneId(existingUUID: firstPane.id)) == .p0Visible)
        #expect(resolver.tier(for: PaneId(existingUUID: secondPane.id)) == .p1Hidden)
    }

    @Test
    func tier_marksMinimizedPaneHidden_inActiveTab() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-visibility-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner())
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
    func tier_marksExpandedDrawerChildrenVisible() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-visibility-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner())
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

        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner())
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
}
