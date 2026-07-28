import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class ArrangementDerivedTests {

    private var registry: AtomRegistry!
    private var store: WorkspaceStore!

    init() {
        registry = makeInstalledTestAtomRegistry()
        store = WorkspaceStore(
            identityAtom: registry.workspaceIdentity,
            windowMemoryAtom: registry.workspaceWindowMemory,
            repositoryTopologyAtom: registry.workspaceRepositoryTopology,
            paneAtom: registry.workspacePane,
            tabLayoutAtom: registry.workspaceTabLayout)
    }

    @Test
    func paneVisibilityItems_returnsAllPanesWithMinimizedState() {
        AtomScope.$override.withValue(registry) {
            let firstPane = store.createPane()
            let tab = Tab(paneId: firstPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)

            let secondPane = store.createPane()
            _ = store.insertPane(
                secondPane.id,
                inTab: tab.id,
                at: firstPane.id,
                direction: .horizontal,
                position: .after, sizingMode: .halveTarget
            )
            _ = store.minimizePane(secondPane.id, inTab: tab.id)

            let derived = ArrangementDerived()
            let items = derived.paneVisibilityItems(for: tab.id)

            #expect(items.count == 2)
            #expect(items[0].id == firstPane.id)
            #expect(items[0].isMinimized == false)
            #expect(items[1].id == secondPane.id)
            #expect(items[1].isMinimized == true)
        }
    }

    @Test
    func arrangementItems_returnsArrangementsWithActiveState() {
        AtomScope.$override.withValue(registry) {
            let pane = store.createPane()
            let tab = Tab(paneId: pane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)

            let derived = ArrangementDerived()
            let items = derived.arrangementItems(for: tab.id)

            #expect(items.count == 1)
            #expect(items[0].name == "Default")
            #expect(items[0].isDefault == true)
            #expect(items[0].isActive == true)
        }
    }

    @Test
    func paneVisibilityItems_invalidTab_returnsEmpty() {
        AtomScope.$override.withValue(registry) {
            let derived = ArrangementDerived()

            #expect(derived.paneVisibilityItems(for: UUID()).isEmpty)
        }
    }

    @Test
    func arrangementItems_marksOnlyActiveArrangement() throws {
        try AtomScope.$override.withValue(registry) {
            let firstPane = store.createPane()
            let secondPane = store.createPane()
            let tab = Tab(paneId: firstPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            _ = store.insertPane(
                secondPane.id,
                inTab: tab.id,
                at: firstPane.id,
                direction: .horizontal,
                position: .after, sizingMode: .halveTarget
            )
            let arrangementId = try #require(
                store.createArrangement(
                    name: "Focus",
                    inTab: tab.id
                )
            )
            store.switchArrangement(to: arrangementId, inTab: tab.id)

            let items = ArrangementDerived().arrangementItems(for: tab.id)

            #expect(items.count == 2)
            #expect(items.first(where: { $0.id == arrangementId })?.isActive == true)
            #expect(items.first(where: { $0.id != arrangementId })?.isActive == false)
        }
    }

    @Test
    func zoomMode_projectsRepoBranchWorktreeFolderAndFullCwd() throws {
        try AtomScope.$override.withValue(registry) {
            let repo = store.addRepo(
                at: URL(filePath: "/tmp/pane-zoom/agent-studio")
            )
            let worktree = Worktree(
                repoId: repo.id,
                name: "feature-zoom",
                path: URL(filePath: "/tmp/pane-zoom/agent-studio-feature"),
                isMainWorktree: false
            )
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
            registry.repoCache.setWorktreeEnrichment(
                WorktreeEnrichment(
                    worktreeId: worktree.id,
                    repoId: repo.id,
                    branch: "feature/pane-zoom"
                )
            )

            let cwd = worktree.path.appending(path: "Sources/App")
            let pane = store.createPane(
                launchDirectory: cwd,
                facets: PaneContextFacets(
                    repoId: repo.id,
                    worktreeId: worktree.id,
                    cwd: cwd
                )
            )
            let tab = Tab(paneId: pane.id)
            store.appendTab(tab)
            registry.workspacePanePresentation.enterZoom(
                inTab: tab.id,
                sourcePaneId: pane.id,
                viewerPresentation: .retryable
            )

            let mode = try #require(ArrangementDerived().zoomMode(for: tab.id))
            let sourceIdentity = try #require(mode.sourceIdentity)

            #expect(mode.label == "Cancel Zoom")
            #expect(
                sourceIdentity.title
                    == "\(repo.name) | feature/pane-zoom | \(worktree.path.lastPathComponent)"
            )
            #expect(sourceIdentity.detail == cwd.path)
            #expect(sourceIdentity.fullPath == cwd.path)
        }
    }

    @Test
    func nextCustomArrangementName_startsAtLayoutOne() {
        AtomScope.$override.withValue(registry) {
            let pane = store.createPane()
            let tab = Tab(paneId: pane.id)
            store.appendTab(tab)

            let derived = ArrangementDerived()
            #expect(derived.nextCustomArrangementName(for: tab.id) == "Layout 1")
        }
    }

    @Test
    func nextCustomArrangementName_skipsUsedIndexes() throws {
        try AtomScope.$override.withValue(registry) {
            let firstPane = store.createPane()
            let tab = Tab(paneId: firstPane.id)
            store.appendTab(tab)

            let secondPane = store.createPane()
            let thirdPane = store.createPane()
            _ = store.insertPane(
                secondPane.id,
                inTab: tab.id,
                at: firstPane.id,
                direction: .horizontal,
                position: .after, sizingMode: .halveTarget
            )
            _ = store.insertPane(
                thirdPane.id,
                inTab: tab.id,
                at: secondPane.id,
                direction: .horizontal,
                position: .after, sizingMode: .halveTarget
            )

            _ = try #require(
                store.createArrangement(
                    name: "Layout 1",
                    inTab: tab.id
                )
            )
            _ = try #require(
                store.createArrangement(
                    name: "Layout 2",
                    inTab: tab.id
                )
            )

            let derived = ArrangementDerived()
            #expect(derived.nextCustomArrangementName(for: tab.id) == "Layout 3")
        }
    }

    @Test
    func paneVisibilityItems_restoresMinimizedStateOnlyInUserLayout() throws {
        try AtomScope.$override.withValue(registry) {
            let firstPane = store.createPane()
            let tab = Tab(paneId: firstPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)

            let secondPane = store.createPane()
            let thirdPane = store.createPane()
            _ = store.insertPane(
                secondPane.id,
                inTab: tab.id,
                at: firstPane.id,
                direction: .horizontal,
                position: .after, sizingMode: .halveTarget
            )
            _ = store.insertPane(
                thirdPane.id,
                inTab: tab.id,
                at: secondPane.id,
                direction: .horizontal,
                position: .after, sizingMode: .halveTarget
            )

            _ = store.minimizePane(secondPane.id, inTab: tab.id)
            let minimizedLayoutId = try #require(store.tab(tab.id)?.activeArrangementId)
            let focusArrangementId = try #require(
                store.createArrangement(
                    name: "Focus",
                    inTab: tab.id
                )
            )

            store.switchArrangement(to: focusArrangementId, inTab: tab.id)
            store.switchArrangement(to: tab.defaultArrangement.id, inTab: tab.id)

            let defaultItems = ArrangementDerived().paneVisibilityItems(for: tab.id)
            #expect(defaultItems.first(where: { $0.id == secondPane.id })?.isMinimized == false)

            store.switchArrangement(to: minimizedLayoutId, inTab: tab.id)

            let minimizedLayoutItems = ArrangementDerived().paneVisibilityItems(for: tab.id)
            #expect(minimizedLayoutItems.first(where: { $0.id == secondPane.id })?.isMinimized == true)
        }
    }
}
