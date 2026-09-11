import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioRepoExplorer
@testable import AgentStudioTestSupport

extension RepoExplorerCommandPresentationBatchTests {
    @Test("pane split capability refreshes when a nonfocused target is minimized and restored")
    func paneSplitCapabilityTracksTargetVisibility() async throws {
        installTestCoreAtomsIfNeeded()
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            try await withIsolatedCommandDispatcher(
                configure: {
                    AppCommandDispatcher.shared.handler = harness.controller
                    AppCommandDispatcher.shared.appCommandRouter = nil
                },
                body: {
                    let directory = harness.tempDir.appending(path: "cwd", directoryHint: .isDirectory)
                    let focused = harness.store.createPane(launchDirectory: directory)
                    let target = harness.store.createPane(launchDirectory: directory)
                    let tab = Tab(paneId: focused.id)
                    harness.store.appendTab(tab)
                    #expect(
                        harness.store.insertPane(
                            target.id, inTab: tab.id, at: focused.id,
                            direction: .horizontal, position: .after, sizingMode: .halveTarget
                        ))
                    harness.store.setActiveTab(tab.id)
                    harness.store.tabLayoutAtom.setActivePane(focused.id, inTab: tab.id)
                    let batch = RepoExplorerCommandPresentationBatch(
                        store: harness.store, repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(), dispatcher: .shared
                    )
                    batch.start()
                    defer { batch.stop() }
                    let request = RepoExplorerCommandPresentationRequest(
                        command: .openWorktreeInPane, surface: .contextMenu,
                        target: target.id, targetType: .pane, arguments: .noArguments
                    )
                    batch.acceptVisibleWorktreeSnapshot(
                        RepoExplorerVisibleWorktreeSnapshot(
                            target: RepoExplorerCommandPresentationTarget(
                                materializationHostLifetimeID: .init(rawValue: UUIDv7.generate()),
                                materializationGeneration: 1, visibleRevision: 1
                            ),
                            worktreeIDs: [], paneIDs: [target.id]
                        ))
                    await eventually("initial pane split capability") { batch.snapshot.results[request] == true }
                    #expect(harness.store.minimizePane(target.id, inTab: tab.id))
                    #expect(harness.store.tabLayoutAtom.tab(tab.id)?.activePaneId == focused.id)
                    #expect(!harness.controller.canExecute(.openWorktreeInPane, target: target.id, targetType: .pane))
                    await eventually("minimized pane disables split") { batch.snapshot.results[request] == false }
                    harness.store.tabLayoutAtom.expandPane(target.id, inTab: tab.id)
                    harness.store.tabLayoutAtom.setActivePane(focused.id, inTab: tab.id)
                    #expect(harness.store.tabLayoutAtom.tab(tab.id)?.activePaneId == focused.id)
                    await eventually("restored pane enables split") { batch.snapshot.results[request] == true }
                }
            )
        }
    }

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
