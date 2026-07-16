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
        #expect(acceptance.revision.rawValue == 1)
        #expect(acceptance.repairReport == prepared.repairReport)
        #expect(acceptance.terminalActivationInput == prepared.terminalActivationInput)
        #expect(fixture.revisionOwner.committedRevision == acceptance.revision)
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

    @Test("preparation rejection mutates nothing and advances no revision")
    func preparationRejectionMutatesNothingAndAdvancesNoRevision() throws {
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
        #expect(fixture.revisionOwner.committedRevision == .zero)
    }

    @Test("revision-owner rejection preserves composition and revision")
    func revisionOwnerRejectionPreservesCompositionAndRevision() throws {
        // Arrange
        let fixture = try PreparedCompositionApplierFixture.seeded()
        let prepared = try fixture.makePreparedComposition()
        let before = fixture.compositionState
        var nestedResult: WorkspacePreparedCompositionApplyResult?

        // Act
        #expect(throws: PreparedCompositionApplierTestError.abortOuterTransaction) {
            let _: Void = try fixture.revisionOwner.performSynchronousTransaction { _ in
                nestedResult = fixture.applier.apply(prepared)
                throw PreparedCompositionApplierTestError.abortOuterTransaction
            }
        }

        // Assert
        #expect(nestedResult == .failed(.revisionOwnerReentrantTransaction))
        #expect(fixture.revisionOwner.committedRevision == .zero)
        #expect(fixture.compositionState == before)
    }

    @Test("installed composition rejects retained applier before opening another transaction")
    func installedCompositionRejectsRetainedApplier() throws {
        // Arrange
        let fixture = try PreparedCompositionApplierFixture.seeded()
        let firstPrepared = try fixture.makePreparedComposition()
        guard case .accepted = fixture.applier.apply(firstPrepared) else {
            Issue.record("expected initial composition acceptance")
            return
        }
        let factory = WorkspacePersistenceSnapshotParticipantFactory(adapters: fixture.adapters)
        guard case .constructed = factory.constructCompositionParticipantSet() else {
            Issue.record("expected composition participant installation")
            return
        }
        let before = fixture.compositionState
        let committedRevision = fixture.revisionOwner.committedRevision

        // Act
        let result = fixture.applier.apply(try fixture.makePreparedComposition())

        // Assert
        guard case .failed(.lifecycle(.preinstallAccessUnavailable(let phase))) = result,
            case .installed(let attemptID) = phase
        else {
            Issue.record("expected installed lifecycle rejection, received \(result)")
            return
        }
        #expect(UUIDv7.isV7(attemptID.rawValue))
        #expect(fixture.compositionState == before)
        #expect(fixture.revisionOwner.committedRevision == committedRevision)
    }

    @Test("production participant inventory opens with heterogeneous owner limits")
    func productionParticipantInventoryOpensWithHeterogeneousOwnerLimits() throws {
        // Arrange
        let fixture = try PreparedCompositionApplierFixture.seeded()
        let prepared = try fixture.makePreparedComposition()
        guard case .accepted = fixture.applier.apply(prepared) else {
            Issue.record("expected composition acceptance")
            return
        }
        let participantSet = try fixture.constructParticipantSet()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: fixture.revisionOwner
        )

        // Act
        var membershipCountByParticipant: [WorkspacePersistenceSnapshotParticipantID: Int] = [:]
        for participant in participantSet.participants {
            guard case .opened(let membershipCount) = participant.open(lease: lease) else {
                throw PreparedCompositionApplierTestError.participantOpenFailed(participant.participantID)
            }
            membershipCountByParticipant[participant.participantID] = membershipCount
        }

        // Assert
        #expect(participantSet.participantIDs == WorkspacePersistenceSnapshotParticipantID.allCases)
        #expect(participantSet.participants.count == 14)
        #expect(membershipCountByParticipant[.workspaceIdentity] == 1)
        #expect(membershipCountByParticipant[.workspaceWindowMemory] == 1)
        #expect(membershipCountByParticipant[.paneGraphs] == prepared.panes.count)
        #expect(membershipCountByParticipant[.repositories] == 1)
        #expect(membershipCountByParticipant[.worktrees] == 1)
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

    let revisionOwner = WorkspacePersistenceRevisionOwner()
    let identityAtom = WorkspaceIdentityAtom()
    let windowMemoryAtom = WorkspaceWindowMemoryAtom()
    let repositoryTopologyAtom = RepositoryTopologyAtom()
    let paneGraphAtom = WorkspacePaneGraphAtom()
    let drawerCursorAtom = WorkspaceDrawerCursorAtom()
    let tabCursorAtom = WorkspaceTabCursorAtom()
    let tabGraphAtom = WorkspaceTabGraphAtom()
    let arrangementCursorAtom = WorkspaceArrangementCursorAtom()
    let tabShellAtom: WorkspaceTabShellAtom
    let adapters: WorkspacePersistenceAdapterBundle
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

        adapters = WorkspacePersistenceAdapterBundle(
            revisionOwner: revisionOwner,
            workspaceIdentityAtom: identityAtom,
            workspaceWindowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: repositoryTopologyAtom,
            workspacePaneGraphAtom: paneGraphAtom,
            workspaceDrawerCursorAtom: drawerCursorAtom,
            workspaceTabShellAtom: tabShellAtom,
            workspaceTabCursorAtom: tabCursorAtom,
            workspaceTabGraphAtom: tabGraphAtom,
            workspaceArrangementCursorAtom: arrangementCursorAtom
        )
        applier = WorkspacePreparedCompositionApplier(adapters: adapters)
    }

    func makeCandidatePane() -> Pane {
        makeFixturePane(
            title: "Candidate",
            worktreeID: UUIDv7.generate(),
            zmxSessionID: "candidate-zmx"
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

    func constructParticipantSet() throws -> WorkspacePersistenceSnapshotParticipantSet {
        let factory = WorkspacePersistenceSnapshotParticipantFactory(
            adapters: adapters
        )
        guard case .constructed(let participantSet) = factory.constructParticipantSet() else {
            throw PreparedCompositionApplierTestError.participantConstructionFailed
        }
        return participantSet
    }
}

private enum PreparedCompositionApplierTestError: Error, Equatable {
    case abortOuterTransaction
    case participantConstructionFailed
    case participantOpenFailed(WorkspacePersistenceSnapshotParticipantID)
    case paneGraphReplacementRejected
    case preparationRejected
    case topologyReplacementRejected
}

private func makeFixturePane(
    title: String,
    worktreeID: UUID? = nil,
    zmxSessionID: String? = nil
) -> Pane {
    Pane(
        id: UUIDv7.generate(),
        content: .terminal(
            TerminalState(
                provider: .zmx,
                lifetime: .persistent,
                zmxSessionId: zmxSessionID
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
