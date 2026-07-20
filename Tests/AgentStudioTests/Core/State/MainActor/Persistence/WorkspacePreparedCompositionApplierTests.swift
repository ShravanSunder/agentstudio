import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace prepared composition applier")
@MainActor
struct WorkspacePreparedCompositionApplierTests {
    @Test("prepared composition atomically replaces only composition owners")
    func preparedCompositionAtomicallyReplacesOnlyCompositionOwners() throws {
        // Arrange
        let fixture = try PreparedCompositionApplierFixture.seeded()
        let topologyBefore = fixture.topologyState
        let prepared = try fixture.makePreparedComposition()

        // Act
        let result = fixture.applier.apply(prepared)

        // Assert
        guard case .accepted(let acceptance) = result else {
            Issue.record("expected accepted composition, received \(result)")
            return
        }
        #expect(UUIDv7.isV7(acceptance.contentMountCohort.generation.id))
        #expect(acceptance.terminalActivationInput == prepared.terminalActivationInput)
        #expect(acceptance.nonterminalContentMountInput == prepared.nonterminalContentMountInput)
        #expect(fixture.identityAtom.workspaceId == prepared.identity.workspaceID)
        #expect(fixture.identityAtom.workspaceName == prepared.identity.workspaceName)
        #expect(fixture.windowMemoryAtom.sidebarWidth == prepared.windowMemory.sidebarWidth)
        #expect(fixture.paneGraphAtom.paneStates == prepared.paneGraph.replacement.paneStates)
        #expect(fixture.drawerCursorAtom.expandedDrawerId == prepared.expandedDrawerID)
        #expect(fixture.tabShellAtom.tabShells == prepared.tabShells.shells)
        #expect(fixture.tabCursorAtom.activeTabId == prepared.activeTabID)
        #expect(fixture.tabGraphAtom.tabStates == prepared.tabGraph.states)
        #expect(
            fixture.arrangementCursorAtom.activeArrangementIdsByTabId
                == prepared.arrangementCursors.activeArrangementIDsByTabID
        )
        #expect(fixture.topologyState == topologyBefore)
        #expect(fixture.paneGraphAtom.paneState(fixture.seedPaneID) == nil)
    }

    @Test("preparation rejection mutates nothing")
    func preparationRejectionMutatesNothing() throws {
        // Arrange
        let fixture = try PreparedCompositionApplierFixture.seeded()
        let before = fixture.compositionState
        let duplicatePane = fixture.makeCandidatePane()
        let invalidSnapshot = WorkspaceSQLiteSnapshot(
            id: UUIDv7.generate(),
            panes: [duplicatePane, duplicatePane]
        )

        // Act
        let preparation = WorkspaceCompositionPreparer.prepare(invalidSnapshot)

        // Assert
        #expect(preparation == .rejected(.duplicatePaneID(duplicatePane.id)))
        #expect(fixture.compositionState == before)
    }

    @Test("installed composition rejects a second apply before mutation")
    func installedCompositionRejectsRetainedApplier() throws {
        // Arrange
        let fixture = try PreparedCompositionApplierFixture.seeded()
        let firstPrepared = try fixture.makePreparedComposition()
        guard case .accepted = fixture.applier.apply(firstPrepared) else {
            Issue.record("expected initial composition acceptance")
            return
        }
        let before = fixture.compositionState

        // Act
        let result = fixture.applier.apply(try fixture.makePreparedComposition())

        // Assert
        guard case .failed(.alreadyInstalled) = result else {
            Issue.record("expected installed lifecycle rejection, received \(result)")
            return
        }
        #expect(fixture.compositionState == before)
    }
}

@MainActor
private final class PreparedCompositionApplierFixture {
    struct CompositionState: Equatable {
        let workspaceID: UUID
        let workspaceName: String
        let sidebarWidth: CGFloat
        let paneStates: [UUID: PaneGraphState]
        let expandedDrawerID: UUID?
        let tabShells: [TabShell]
        let activeTabID: UUID?
        let tabStates: [TabGraphState]
        let activeArrangementIDsByTabID: [UUID: UUID]
        let paneCursorsByArrangementID: [UUID: ArrangementPaneCursorState]
        let drawerCursorsByKey: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState]
    }

    struct TopologyState: Equatable {
        let repositories: [Repo]
        let watchedPaths: [WatchedPath]
        let unavailableRepositoryIDs: Set<UUID>
    }

    let identityAtom = WorkspaceIdentityAtom(workspaceId: UUIDv7.generate())
    let windowMemoryAtom = WorkspaceWindowMemoryAtom()
    let repositoryTopologyAtom = RepositoryTopologyAtom()
    let paneGraphAtom = WorkspacePaneGraphAtom()
    let drawerCursorAtom = WorkspaceDrawerCursorAtom()
    let tabCursorAtom = WorkspaceTabCursorAtom()
    let tabGraphAtom = WorkspaceTabGraphAtom()
    let arrangementCursorAtom = WorkspaceArrangementCursorAtom()
    let tabShellAtom: WorkspaceTabShellAtom
    let applier: WorkspacePreparedCompositionApplier
    let seedPaneID: UUID

    var compositionState: CompositionState {
        CompositionState(
            workspaceID: identityAtom.workspaceId,
            workspaceName: identityAtom.workspaceName,
            sidebarWidth: windowMemoryAtom.sidebarWidth,
            paneStates: paneGraphAtom.paneStates,
            expandedDrawerID: drawerCursorAtom.expandedDrawerId,
            tabShells: tabShellAtom.tabShells,
            activeTabID: tabCursorAtom.activeTabId,
            tabStates: tabGraphAtom.tabStates,
            activeArrangementIDsByTabID: arrangementCursorAtom.activeArrangementIdsByTabId,
            paneCursorsByArrangementID: arrangementCursorAtom.paneCursorsByArrangementId,
            drawerCursorsByKey: arrangementCursorAtom.drawerCursorsByKey
        )
    }

    var topologyState: TopologyState {
        TopologyState(
            repositories: repositoryTopologyAtom.repos,
            watchedPaths: repositoryTopologyAtom.watchedPaths,
            unavailableRepositoryIDs: repositoryTopologyAtom.unavailableRepoIds
        )
    }

    static func seeded() throws -> PreparedCompositionApplierFixture {
        let seedPane = makeFixturePane(title: "Seed")
        let seedTab = makeFixtureTab(paneID: seedPane.id, name: "Seed")
        return try PreparedCompositionApplierFixture(seedPane: seedPane, seedTab: seedTab)
    }

    private init(seedPane: Pane, seedTab: Tab) throws {
        seedPaneID = seedPane.id
        tabShellAtom = WorkspaceTabShellAtom(cursorAtom: tabCursorAtom)
        identityAtom.replaceIdentity(
            workspaceId: UUIDv7.generate(),
            workspaceName: "Seed workspace",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        windowMemoryAtom.replaceWindowMemory(sidebarWidth: 777, windowFrame: nil)
        guard
            case .success(let seedPaneGraphReplacement) = WorkspacePaneGraphReplacement.prepare([
                seedPane.id: PaneGraphState(pane: seedPane)
            ])
        else {
            throw PreparedCompositionApplierTestError.paneGraphReplacementRejected
        }
        paneGraphAtom.replacePaneStates(seedPaneGraphReplacement)
        drawerCursorAtom.replaceExpandedDrawer(
            seedPane.drawer.flatMap { $0.isExpanded ? $0.drawerId : nil }
        )
        tabShellAtom.replaceTabShells([
            TabShell(id: seedTab.id, name: seedTab.name, colorHex: seedTab.colorHex)
        ])
        tabCursorAtom.replaceActiveTab(seedTab.id)
        tabGraphAtom.replaceStates([
            TabGraphState(
                tabId: seedTab.id,
                allPaneIds: seedTab.allPaneIds,
                arrangements: seedTab.arrangements.map(PaneArrangementGraphState.init)
            )
        ])
        arrangementCursorAtom.replaceCursors(
            activeArrangementIdsByTabId: [seedTab.id: seedTab.activeArrangementId],
            paneCursorsByArrangementId: Dictionary(
                uniqueKeysWithValues: seedTab.arrangements.map {
                    ($0.id, ArrangementPaneCursorState(activePaneId: $0.activePaneId))
                }
            ),
            drawerCursorsByKey: [:]
        )

        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        guard
            case .prepared(let topologyReplacement) = RepositoryTopologyReplacement.prepare(
                repositories: [
                    Repo(
                        id: repositoryID,
                        name: "Topology",
                        repoPath: URL(filePath: "/tmp/topology"),
                        worktrees: [
                            Worktree(
                                id: worktreeID,
                                repoId: repositoryID,
                                name: "main",
                                path: URL(filePath: "/tmp/topology"),
                                isMainWorktree: true
                            )
                        ]
                    )
                ],
                watchedPaths: [WatchedPath(path: URL(filePath: "/tmp"))],
                unavailableRepositoryIDs: []
            )
        else {
            throw PreparedCompositionApplierTestError.topologyReplacementRejected
        }
        repositoryTopologyAtom.replaceTopology(topologyReplacement)

        applier = WorkspacePreparedCompositionApplier(
            owners: WorkspacePreparedCompositionOwners(
                workspaceIdentityAtom: identityAtom,
                workspaceWindowMemoryAtom: windowMemoryAtom,
                workspacePaneGraphAtom: paneGraphAtom,
                workspaceDrawerCursorAtom: drawerCursorAtom,
                workspaceTabShellAtom: tabShellAtom,
                workspaceTabCursorAtom: tabCursorAtom,
                workspaceTabGraphAtom: tabGraphAtom,
                workspaceArrangementCursorAtom: arrangementCursorAtom
            )
        )
    }

    func makeCandidatePane() -> Pane {
        makeFixturePane(
            title: "Candidate",
            worktreeID: UUIDv7.generate(),
            zmxSessionID: .generateUUIDv7()
        )
    }

    func makePreparedComposition() throws -> PreparedWorkspaceComposition {
        let pane = makeCandidatePane()
        let tab = makeFixtureTab(paneID: pane.id, name: "Candidate")
        let snapshot = WorkspaceSQLiteSnapshot(
            id: UUIDv7.generate(),
            name: "Candidate workspace",
            panes: [pane],
            tabs: [tab],
            activeTabId: tab.id,
            sidebarWidth: 321,
            createdAt: Date(timeIntervalSince1970: 123)
        )
        guard case .prepared(let prepared) = WorkspaceCompositionPreparer.prepare(snapshot) else {
            throw PreparedCompositionApplierTestError.preparationRejected
        }
        return prepared
    }

}

private enum PreparedCompositionApplierTestError: Error, Equatable {
    case paneGraphReplacementRejected
    case preparationRejected
    case topologyReplacementRejected
}

private func makeFixturePane(
    title: String,
    worktreeID: UUID? = nil,
    zmxSessionID: ZmxSessionID = .generateUUIDv7()
) -> Pane {
    Pane(
        id: UUIDv7.generate(),
        content: .terminal(
            TerminalState(
                provider: .zmx,
                lifetime: .persistent,
                zmxSessionID: zmxSessionID
            )),
        metadata: PaneMetadata(
            launchDirectory: URL(filePath: "/tmp/\(title)"),
            title: title,
            facets: PaneContextFacets(worktreeId: worktreeID)
        )
    )
}

private func makeFixtureTab(paneID: UUID, name: String) -> Tab {
    let arrangement = PaneArrangement(
        id: UUIDv7.generate(),
        name: "Default",
        isDefault: true,
        layout: Layout(paneId: paneID),
        activePaneId: paneID
    )
    return Tab(
        id: UUIDv7.generate(),
        name: name,
        allPaneIds: [paneID],
        arrangements: [arrangement],
        activeArrangementId: arrangement.id
    )
}
