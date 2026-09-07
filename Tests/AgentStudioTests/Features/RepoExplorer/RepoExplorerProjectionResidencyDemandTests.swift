import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
private struct RepoExplorerPaneResidencyFixture {
    let store: WorkspaceStore
    let visiblePane: Pane
    let residencyPane: Pane
    let tab: Tab
    let adapter: RepoExplorerProjectionAdapter
    let host: RepoExplorerMaterializationHost

    init(atoms: CoreAtoms) throws {
        store = WorkspaceStore(
            catalogAtom: atoms.workspaceRepositoryTopology,
            graphAtom: atoms.workspacePane,
            interactionAtom: atoms.workspaceTabLayout
        )
        let repository = store.addRepo(at: URL(filePath: "/tmp/repo-explorer-pane-residency"))
        let worktree = try #require(repository.worktrees.first)
        visiblePane = store.createPane(
            launchDirectory: worktree.path,
            title: "visible",
            facets: PaneContextFacets(cwd: worktree.path)
        )
        residencyPane = store.createPane(
            launchDirectory: worktree.path,
            title: "residency",
            facets: PaneContextFacets(cwd: worktree.path)
        )
        tab = Tab(paneId: visiblePane.id)
        store.appendTab(tab)
        #expect(
            store.insertPane(
                residencyPane.id,
                inTab: tab.id,
                at: visiblePane.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )
        )
        atoms.repoCache.setRepoEnrichment(
            .resolvedLocal(
                repoId: repository.id,
                identity: RemoteIdentityNormalizer.localIdentity(repoName: repository.name),
                updatedAt: Date()
            )
        )
        atoms.workspaceSidebarState.setSidebarSurface(.panes)
        let preferences = RepoExplorerSidebarPrefsAtom()
        preferences.setGroupingMode(.repo, for: .panes)
        let capture = RepoExplorerProjectionInputCapture(
            store: store,
            preferences: preferences,
            repoCache: atoms.repoCache,
            sidebarState: atoms.workspaceSidebarState,
            sidebarCache: atoms.sidebarCache,
            coreAtoms: atoms,
            bridgeAttendanceSnapshot: { _ in nil },
            latestPaneMessageSnapshot: { _ in nil }
        )
        adapter = RepoExplorerProjectionAdapter(
            inputCapture: capture,
            recencyDelay: AsyncDelay { _ in throw CancellationError() }
        )
        host = registerProjectionTestMaterializationHost(adapter: adapter)
    }

    func stop() {
        host.detach()
        adapter.stop()
    }
}

extension RepoExplorerProjectionDemandTests {
    @MainActor
    @Test("Panes follows residency-only background and reactivation")
    func panesFollowResidencyOnlyLifecycle() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let fixture = try RepoExplorerPaneResidencyFixture(atoms: atoms)
            defer { fixture.stop() }

            fixture.adapter.updateDemand(isVisible: true, query: "")
            for _ in 0..<400
            where !Self.renderedPaneIDs(in: fixture.adapter.publishedResult).isSuperset(
                of: [fixture.visiblePane.id, fixture.residencyPane.id]
            ) {
                await Task.yield()
            }
            #expect(
                Self.renderedPaneIDs(in: fixture.adapter.publishedResult)
                    == [fixture.visiblePane.id, fixture.residencyPane.id]
            )

            #expect(fixture.store.mutationCoordinator.backgroundPane(fixture.residencyPane.id))
            for _ in 0..<400
            where Self.renderedPaneIDs(in: fixture.adapter.publishedResult).contains(
                fixture.residencyPane.id
            ) {
                await Task.yield()
            }
            #expect(Self.renderedPaneIDs(in: fixture.adapter.publishedResult) == [fixture.visiblePane.id])
            #expect(fixture.adapter.publishedResult?.paneRowFactsByPaneId[fixture.residencyPane.id] == nil)
            #expect(fixture.adapter.observationTokens.contains(.paneStructure(fixture.residencyPane.id)))
            #expect(!fixture.adapter.observationTokens.contains(.pane(fixture.residencyPane.id)))
            let backgroundedRevision = fixture.adapter.publishedRevision

            #expect(
                fixture.store.mutationCoordinator.reactivatePane(
                    fixture.residencyPane.id,
                    inTab: fixture.tab.id,
                    at: fixture.visiblePane.id,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )
            )
            for _ in 0..<400
            where fixture.adapter.publishedRevision == backgroundedRevision
                || !Self.renderedPaneIDs(in: fixture.adapter.publishedResult).contains(
                    fixture.residencyPane.id
                )
            {
                await Task.yield()
            }

            #expect(fixture.adapter.publishedRevision == backgroundedRevision + 1)
            #expect(
                Self.renderedPaneIDs(in: fixture.adapter.publishedResult)
                    == [fixture.visiblePane.id, fixture.residencyPane.id]
            )
            #expect(fixture.adapter.publishedResult?.paneRowFactsByPaneId[fixture.residencyPane.id] != nil)
        }
    }

    fileprivate static func renderedPaneIDs(
        in result: RepoExplorerProjectionResult?
    ) -> Set<UUID> {
        Set(
            result?.rowIndex.entries.compactMap { entry in
                switch entry {
                case .resolvedPaneRow(_, let identity, _): identity.paneId
                case .unassociatedPaneRow(let destination): destination.paneId
                case .activitySubgroup, .sectionHeader, .loadingSectionHeader, .loadingRepoRow,
                    .resolvedGroupHeader, .resolvedWorktreeRow, .topologyFault:
                    nil
                }
            } ?? []
        )
    }
}
