import AgentStudioCore
import AgentStudioInfrastructure
import Testing

@testable import AgentStudio
@testable import AgentStudioRepoExplorer
@testable import AgentStudioTestSupport

extension RepoExplorerCommandPresentationBatchTests {
    @Test("sidebar screen switch re-resolves toolbar capabilities without a visible-set change")
    func sidebarScreenSwitchReresolvesToolbarCapabilitiesWithoutVisibleSetChange() async throws {
        try await withIsolatedCommandDispatcher(
            configure: {},
            body: {
                await withAsyncTestCoreAtoms { coreAtoms in
                    let prefs = RepoExplorerSidebarPrefsAtom(
                        sidebarState: coreAtoms.workspaceSidebarState
                    )
                    let atoms = AtomRegistry(core: coreAtoms, repoExplorerSidebarPrefs: prefs)
                    let delegate = AppDelegate()
                    delegate.atomStore = atoms
                    AppCommandDispatcher.shared.appCommandRouter = delegate
                    AppCommandDispatcher.shared.handler = nil

                    let batch = RepoExplorerCommandPresentationBatch(
                        store: WorkspaceStore(),
                        repoExplorerPrefs: prefs,
                        dispatcher: .shared
                    )
                    batch.start()
                    defer { batch.stop() }
                    batch.acceptVisibleWorktreeSnapshot(
                        sidebarCapabilityVisibleSnapshot()
                    )
                    await eventually("initial Repos command capabilities") {
                        toolbarCapability(
                            .setReposGroupingActivity,
                            in: batch.snapshot
                        ) == true
                            && toolbarCapability(
                                .setPanesSubgroupActivity,
                                in: batch.snapshot
                            ) == false
                    }
                    let reposGeneration = batch.snapshot.generation

                    coreAtoms.workspaceSidebarState.setSidebarSurface(.panes)

                    await eventually("Panes command capabilities after screen switch") {
                        batch.snapshot.generation > reposGeneration
                            && toolbarCapability(
                                .setReposGroupingActivity,
                                in: batch.snapshot
                            ) == false
                            && toolbarCapability(
                                .setPanesSubgroupActivity,
                                in: batch.snapshot
                            ) == true
                    }
                }
            }
        )
    }

    @Test("Panes activity grouping re-resolves and disables subgroup commands")
    func panesActivityGroupingReresolvesAndDisablesSubgroupCommands() async throws {
        try await withIsolatedCommandDispatcher(
            configure: {},
            body: {
                await withAsyncTestCoreAtoms { coreAtoms in
                    let prefs = RepoExplorerSidebarPrefsAtom(
                        sidebarState: coreAtoms.workspaceSidebarState
                    )
                    let atoms = AtomRegistry(core: coreAtoms, repoExplorerSidebarPrefs: prefs)
                    let delegate = AppDelegate()
                    delegate.atomStore = atoms
                    AppCommandDispatcher.shared.appCommandRouter = delegate
                    AppCommandDispatcher.shared.handler = nil
                    coreAtoms.workspaceSidebarState.setSidebarSurface(.panes)
                    prefs.setGroupingMode(.repo, for: .panes)

                    let batch = RepoExplorerCommandPresentationBatch(
                        store: WorkspaceStore(),
                        repoExplorerPrefs: prefs,
                        dispatcher: .shared
                    )
                    batch.start()
                    defer { batch.stop() }
                    batch.acceptVisibleWorktreeSnapshot(
                        sidebarCapabilityVisibleSnapshot()
                    )
                    await eventually("initial Panes subgroup capabilities") {
                        toolbarCapability(
                            .setPanesSubgroupNone,
                            in: batch.snapshot
                        ) == true
                            && toolbarCapability(
                                .setPanesSubgroupActivity,
                                in: batch.snapshot
                            ) == true
                    }
                    let repoGroupingGeneration = batch.snapshot.generation

                    prefs.setGroupingMode(.activity, for: .panes)

                    await eventually("disabled Panes subgroup capabilities") {
                        batch.snapshot.generation > repoGroupingGeneration
                            && toolbarCapability(
                                .setPanesSubgroupNone,
                                in: batch.snapshot
                            ) == false
                            && toolbarCapability(
                                .setPanesSubgroupActivity,
                                in: batch.snapshot
                            ) == false
                    }
                }
            }
        )
    }
}

private func sidebarCapabilityVisibleSnapshot() -> RepoExplorerVisibleWorktreeSnapshot {
    RepoExplorerVisibleWorktreeSnapshot(
        target: RepoExplorerCommandPresentationTarget(
            materializationHostLifetimeID: RepoExplorerMaterializationHostLifetimeID(
                rawValue: UUIDv7.generate()
            ),
            materializationGeneration: 1,
            visibleRevision: 1
        ),
        worktreeIDs: []
    )
}

private func toolbarCapability(
    _ command: AppCommand,
    in snapshot: RepoExplorerCommandPresentationSnapshot
) -> Bool? {
    let request = RepoExplorerToolbarCommandPresentation.requests().first {
        $0.command == command
    }
    guard let request else { return nil }
    return snapshot.results[request]
}
