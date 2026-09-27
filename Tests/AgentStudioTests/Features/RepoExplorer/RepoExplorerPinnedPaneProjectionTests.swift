import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Pinned raw snapshot projection", .serialized)
struct RepoExplorerPinnedPaneProjectionTests {
    @Test("pinned traversal follows displayed activity buckets, nil last, and UUID ties")
    func traversalMatchesDisplayedPinnedRows() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                windowMemoryAtom: atoms.workspaceWindowMemory,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
                paneAtom: atoms.workspacePane,
                tabLayoutAtom: atoms.workspaceTabLayout,
                mutationCoordinator: atoms.workspaceMutationCoordinator,
                startsObserving: false
            )
            let panes = (0..<4).map { store.createPane(title: "Pinned \($0)") }
            let tabIDsByPaneID = Dictionary(
                uniqueKeysWithValues: panes.map { pane in
                    let tab = Tab(paneId: pane.id)
                    store.appendTab(tab)
                    return (pane.id, tab.id)
                })
            let paneIDs = await PinnedPaneFixtureOrdering.byUUID(panes.map(\.id))
            for paneID in paneIDs {
                #expect(atoms.workspaceMutationCoordinator.setPanePinned(paneID, isPinned: true))
            }
            let referenceInstant = ContinuousClock.now
            let recentTime = PaneActivityTime(
                orderingInstant: referenceInstant.advanced(by: .seconds(-10)),
                wallTime: Date(timeIntervalSince1970: 1), source: .terminal
            )
            let olderTime = PaneActivityTime(
                orderingInstant: referenceInstant.advanced(by: .seconds(-120)),
                wallTime: Date(timeIntervalSince1970: 2), source: .hook
            )
            let timesByPaneID: [UUID: PaneActivityTime] = [
                paneIDs[1]: olderTime,
                paneIDs[2]: recentTime,
                paneIDs[3]: recentTime,
            ]
            atoms.paneActivityTime.apply(timesByPaneID.map { .set($0.key, $0.value) })
            let request = RepoExplorerPinnedPaneProjectionRequest(coreAtoms: atoms)

            let traversalOrder = try await RepoExplorerPinnedPaneProjector.project(request)
            let snapshot = RepoExplorerSnapshot(
                repos: [], repoEnrichmentByRepoId: [:], surface: .panes,
                groupingMode: .activity, sortField: .activity,
                referenceDate: Date(timeIntervalSince1970: 1_000_000),
                referenceInstant: referenceInstant, sortOrder: .descending, query: "",
                unassociatedPaneLocations: try paneIDs.enumerated().map { index, paneID in
                    let tabID = try #require(tabIDsByPaneID[paneID])
                    return WorkspacePaneLocation(
                        paneId: paneID, tabId: tabID,
                        tabIndex: index, paneIndexInTab: 0, isActiveInTab: true
                    )
                }
            )
            let rowFacts = Dictionary(
                uniqueKeysWithValues: paneIDs.map { paneID in
                    (
                        paneID,
                        RepoExplorerPaneRowFacts(
                            terminalTitle: "Pinned", paneActivityTime: timesByPaneID[paneID], isPinned: true,
                            latestMessageText: nil, recencyReferenceDate: snapshot.referenceDate,
                            recencyText: "—", isActive: false
                        )
                    )
                })
            let display = RepoExplorerProjection.project(snapshot, paneRowFactsByPaneId: rowFacts)
            let displayedOrder = display.sections
                .filter { $0.kind == .pinnedPanes }
                .flatMap(\.resolvedGroups)
                .flatMap { display.paneRowsByGroupId[$0.id, default: []].map(\.destination.paneId) }

            #expect(displayedOrder == [paneIDs[2], paneIDs[3], paneIDs[1], paneIDs[0]])
            #expect(traversalOrder == displayedOrder)
        }
    }

    @Test("pinned drawer follows its Older owner and disappears from traversal when hidden")
    func drawerTraversalMatchesDisplayedPinnedRows() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                windowMemoryAtom: atoms.workspaceWindowMemory,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
                paneAtom: atoms.workspacePane,
                tabLayoutAtom: atoms.workspaceTabLayout,
                mutationCoordinator: atoms.workspaceMutationCoordinator,
                startsObserving: false
            )
            let owner = store.createPane(title: "Older owner")
            let ownerTab = Tab(paneId: owner.id)
            store.appendTab(ownerTab)
            let drawer = try #require(store.addDrawerPane(to: owner.id))
            let recent = store.createPane(title: "Recent pane")
            let recentTab = Tab(paneId: recent.id)
            store.appendTab(recentTab)
            for paneID in [owner.id, drawer.id, recent.id] {
                #expect(atoms.workspaceMutationCoordinator.setPanePinned(paneID, isPinned: true))
            }
            let referenceInstant = ContinuousClock.now
            let timesByPaneID = [
                owner.id: PaneActivityTime(
                    orderingInstant: referenceInstant.advanced(by: .seconds(-10_800)),
                    wallTime: .distantPast, source: .terminal
                ),
                drawer.id: PaneActivityTime(
                    orderingInstant: referenceInstant.advanced(by: .seconds(-10)),
                    wallTime: .distantPast, source: .terminal
                ),
                recent.id: PaneActivityTime(
                    orderingInstant: referenceInstant.advanced(by: .seconds(-300)),
                    wallTime: .distantPast, source: .terminal
                ),
            ]
            atoms.paneActivityTime.apply(timesByPaneID.map { .set($0.key, $0.value) })
            for showsDrawers in [true, false] {
                atoms.workspaceSidebarState.setShowsDrawerPanes(showsDrawers)
                let request = RepoExplorerPinnedPaneProjectionRequest(coreAtoms: atoms)
                let traversal = try await RepoExplorerPinnedPaneProjector.project(request)
                let snapshot = RepoExplorerSnapshot(
                    repos: [], repoEnrichmentByRepoId: [:], surface: .panes,
                    groupingMode: .activity, sortField: .activity,
                    showsDrawerPanes: showsDrawers,
                    referenceDate: Date(timeIntervalSince1970: 1_000_000),
                    referenceInstant: referenceInstant, sortOrder: .descending, query: "",
                    unassociatedPaneLocations: [
                        WorkspacePaneLocation(
                            paneId: owner.id, tabId: ownerTab.id, tabIndex: 0,
                            paneIndexInTab: 0, isActiveInTab: true
                        ),
                        WorkspacePaneLocation(
                            paneId: drawer.id, tabId: ownerTab.id, tabIndex: 0,
                            paneIndexInTab: 1, isActiveInTab: false
                        ),
                        WorkspacePaneLocation(
                            paneId: recent.id, tabId: recentTab.id, tabIndex: 1,
                            paneIndexInTab: 0, isActiveInTab: true
                        ),
                    ]
                )
                let rowFacts = Dictionary(
                    uniqueKeysWithValues: [owner.id, drawer.id, recent.id].map { paneID in
                        (
                            paneID,
                            RepoExplorerPaneRowFacts(
                                terminalTitle: "Pinned", paneActivityTime: timesByPaneID[paneID],
                                isPinned: true, latestMessageText: nil,
                                recencyReferenceDate: snapshot.referenceDate,
                                recencyText: "—", isActive: false,
                                isDrawerPane: paneID == drawer.id,
                                drawerOwnerPaneID: paneID == drawer.id ? owner.id : nil
                            )
                        )
                    })
                let display = RepoExplorerProjection.project(snapshot, paneRowFactsByPaneId: rowFacts)
                let displayed = display.sections.filter { $0.kind == .pinnedPanes }
                    .flatMap(\.resolvedGroups)
                    .flatMap { display.paneRowsByGroupId[$0.id, default: []].map(\.destination.paneId) }
                #expect(displayed == (showsDrawers ? [recent.id, owner.id, drawer.id] : [recent.id, owner.id]))
                #expect(traversal == displayed)
            }
        }
    }

    @Test("all pane content kinds and drawer children participate; inactive and unowned panes do not")
    func eligibleMembershipAndSnapshotIsolation() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                windowMemoryAtom: atoms.workspaceWindowMemory,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
                paneAtom: atoms.workspacePane,
                tabLayoutAtom: atoms.workspaceTabLayout,
                mutationCoordinator: atoms.workspaceMutationCoordinator,
                startsObserving: false
            )
            let terminal = store.createPane(title: "Alpha")
            let bridge = try #require(
                store.paneAtom.createPane(
                    content: .bridgePanel(BridgePaneState(panelKind: .fileViewer, source: nil)),
                    metadata: PaneMetadata(
                        contentType: .diff, launchDirectory: URL(filePath: "/tmp"), title: "Bridge", isPinned: true)
                ))
            let browser = try #require(
                store.paneAtom.createPane(
                    content: .webview(WebviewState(url: URL(string: "https://example.test")!)),
                    metadata: PaneMetadata(contentType: .browser, title: "Browser", isPinned: true)
                ))
            let code = try #require(
                store.paneAtom.createPane(
                    content: .codeViewer(
                        CodeViewerState(filePath: URL(filePath: "/tmp/pinned.swift"), scrollToLine: nil)),
                    metadata: PaneMetadata(contentType: .codeViewer, title: "Code", isPinned: true)
                ))
            let backgrounded = store.createPane(title: "Background", residency: .backgrounded)
            let unpinned = store.createPane(title: "Unpinned")
            let unowned = store.createPane(title: "Unowned")
            for pane in [terminal, backgrounded, unowned] {
                #expect(atoms.workspaceMutationCoordinator.setPanePinned(pane.id, isPinned: true))
            }
            for pane in [terminal, bridge, browser, code, backgrounded, unpinned] {
                store.appendTab(Tab(paneId: pane.id))
            }
            let drawer = try #require(store.addDrawerPane(to: terminal.id))
            #expect(atoms.workspaceMutationCoordinator.setPanePinned(drawer.id, isPinned: true))
            let captured = RepoExplorerPinnedPaneProjectionRequest(coreAtoms: atoms)
            let expected = Set([terminal.id, bridge.id, browser.id, code.id, drawer.id])
            #expect(Set(try await RepoExplorerPinnedPaneProjector.project(captured)) == expected)

            #expect(atoms.workspaceMutationCoordinator.setPanePinned(bridge.id, isPinned: false))
            #expect(atoms.workspaceMutationCoordinator.backgroundPane(browser.id))
            let fresh = RepoExplorerPinnedPaneProjectionRequest(coreAtoms: atoms)
            #expect(Set(try await RepoExplorerPinnedPaneProjector.project(captured)) == expected)
            #expect(
                Set(try await RepoExplorerPinnedPaneProjector.project(fresh)) == Set([terminal.id, code.id, drawer.id]))
        }
    }

    @Test("drawer placeholder and content title normalization match sidebar sorting")
    func titleNormalizationMatchesSidebar() {
        #expect(
            RepoExplorerPaneTitleNormalizer.normalizedTitle(
                liveTitle: " Drawer ", cwd: nil, shellExecutablePath: "/bin/fish", isDrawer: true
            ) == "zsh")
        #expect(
            RepoExplorerPaneTitleNormalizer.normalizedTitle(
                liveTitle: "/tmp/work", cwd: URL(filePath: "/tmp/work"), shellExecutablePath: "/bin/fish"
            ) == "fish")
        #expect(
            RepoExplorerPaneTitleNormalizer.normalizedTitle(
                liveTitle: " Review ", cwd: nil, shellExecutablePath: nil
            ) == "Review")
    }
}

private enum PinnedPaneFixtureOrdering {
    @concurrent nonisolated static func byUUID(_ paneIDs: [UUID]) async -> [UUID] {
        paneIDs.sorted { $0.uuidString < $1.uuidString }
    }
}
