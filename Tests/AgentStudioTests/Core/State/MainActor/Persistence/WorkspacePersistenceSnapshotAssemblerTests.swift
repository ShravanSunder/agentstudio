import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace persistence snapshot assembler")
@MainActor
struct WorkspacePersistenceSnapshotAssemblerTests {
    @Test("assembled pages serialize accepted canonical composition exactly")
    func assembledPagesSerializeAcceptedCanonicalCompositionExactly() throws {
        // Arrange
        let fixture = makeRepresentativeFixture()
        let expected = WorkspacePersistenceTransformer.sqliteSaveBundle(from: fixture.state)

        // Act
        let assembly = try requireAssembly(participants: participantItems(state: fixture.state))
        let actual = try assembly.finalize(
            input: WorkspacePersistenceSnapshotFinalizationInput(persistedAt: fixture.persistedAt)
        )

        // Assert
        #expect(actual == expected)
        #expect(actual.repositoryTopology.repos.map(\.id) == fixture.state.repos.map(\.id))
        #expect(actual.repositoryTopology.worktrees.map(\.id) == fixture.state.worktrees.map(\.id))
        #expect(actual.repositoryTopology.watchedPaths.map(\.id) == fixture.state.watchedPaths.map(\.id))
        #expect(
            actual.workspace.tabs
                == fixture.state.tabs.map { tab in
                    var persistedTab = tab
                    persistedTab.zoomedPaneId = nil
                    return persistedTab
                })
        #expect(actual.workspace.activeTabId == fixture.state.activeTabId)
    }

    @Test("empty optional cursor membership preserves nil semantics")
    func emptyOptionalCursorMembershipPreservesNil() throws {
        // Arrange
        let persistedAt = Date(timeIntervalSince1970: 1_730_000_100)
        let state = WorkspacePersistor.PersistableState(
            id: UUIDv7.generate(),
            name: "Empty workspace",
            sidebarWidth: 291,
            windowFrame: nil,
            createdAt: Date(timeIntervalSince1970: 1_730_000_000),
            updatedAt: persistedAt
        )
        let expected = WorkspacePersistenceTransformer.sqliteSaveBundle(from: state)

        // Act
        let assembly = try requireAssembly(participants: participantItems(state: state))
        let actual = try assembly.finalize(
            input: WorkspacePersistenceSnapshotFinalizationInput(persistedAt: persistedAt)
        )

        // Assert
        #expect(actual == expected)
        #expect(actual.workspace.activeTabId == nil)
        #expect(assembly.expandedDrawerID == nil)
        #expect(assembly.activeArrangementIDsByTabID.isEmpty)
        #expect(assembly.activePaneIDsByArrangementID.isEmpty)
        #expect(assembly.activeDrawerChildIDsByKey.isEmpty)
    }

    @Test("envelope violations are rejected before assembly")
    func envelopeViolationsAreRejected() {
        // Arrange
        let fixture = makeRepresentativeFixture()
        let valid = participantItems(state: fixture.state)
        var duplicateParticipant = valid
        duplicateParticipant.append(valid[0])
        var foreignItem = valid
        foreignItem[2] = WorkspacePersistenceSnapshotParticipantItems(
            participantID: .repositories,
            items: [.worktree(fixture.state.worktrees[0])]
        )
        var missingSingleton = valid
        missingSingleton[0] = WorkspacePersistenceSnapshotParticipantItems(
            participantID: .workspaceIdentity,
            items: []
        )

        // Act / Assert
        #expect(
            WorkspacePersistenceSnapshotAssembler.assemble(participants: duplicateParticipant)
                == .rejected(.duplicateParticipant(.workspaceIdentity))
        )
        #expect(
            WorkspacePersistenceSnapshotAssembler.assemble(participants: foreignItem)
                == .rejected(
                    .foreignItem(
                        declaredParticipant: .repositories,
                        actualParticipant: .worktrees,
                        itemID: .worktree(fixture.state.worktrees[0].id)
                    ))
        )
        #expect(
            WorkspacePersistenceSnapshotAssembler.assemble(participants: missingSingleton)
                == .rejected(.missingSingleton(.workspaceIdentity))
        )
    }

    @Test("broken references and tab ordering are rejected")
    func brokenReferencesAndTabOrderingAreRejected() {
        // Arrange
        let fixture = makeRepresentativeFixture()
        var brokenWorktree = participantItems(state: fixture.state)
        let invalidWorktree = CanonicalWorktree(
            id: UUIDv7.generate(),
            repoId: UUIDv7.generate(),
            name: "orphan",
            path: URL(filePath: "/tmp/orphan")
        )
        brokenWorktree[3] = WorkspacePersistenceSnapshotParticipantItems(
            participantID: .worktrees,
            items: [.worktree(invalidWorktree)]
        )
        var invalidTabOrder = participantItems(state: fixture.state)
        let firstShell: WorkspacePersistenceSnapshotItem
        if case .tabShell(let shell) = invalidTabOrder[8].items[0] {
            firstShell = .tabShell(.init(shell: shell.shell, sortIndex: 1))
        } else {
            Issue.record("Expected a tab shell fixture")
            return
        }
        invalidTabOrder[8] = WorkspacePersistenceSnapshotParticipantItems(
            participantID: .tabShells,
            items: [firstShell]
        )

        // Act / Assert
        #expect(
            WorkspacePersistenceSnapshotAssembler.assemble(participants: brokenWorktree)
                == .rejected(
                    .missingRepositoryForWorktree(
                        worktreeID: invalidWorktree.id,
                        repositoryID: invalidWorktree.repoId
                    ))
        )
        #expect(
            WorkspacePersistenceSnapshotAssembler.assemble(participants: invalidTabOrder)
                == .rejected(
                    .invalidTabSortIndex(
                        tabID: fixture.state.tabs[0].id,
                        expected: 0,
                        actual: 1
                    ))
        )
    }

    @Test("unreferenced canonical tab membership is rejected instead of repaired")
    func unreferencedCanonicalTabMembershipIsRejected() {
        // Arrange
        let fixture = makeRepresentativeFixture()
        var participants = participantItems(state: fixture.state)
        let unreferencedPaneID = UUIDv7.generate()
        let unreferencedPane = makeTerminalPane(
            id: unreferencedPaneID,
            title: "Unreferenced",
            kind: .layout(drawer: Drawer(parentPaneId: unreferencedPaneID))
        )
        participants[6] = WorkspacePersistenceSnapshotParticipantItems(
            participantID: .paneGraphs,
            items: participants[6].items + [.paneGraph(PaneGraphState(pane: unreferencedPane))]
        )
        guard case .tabGraph(var tabGraph) = participants[10].items[0] else {
            Issue.record("Expected a tab graph fixture")
            return
        }
        tabGraph.allPaneIds.append(unreferencedPane.id)
        participants[10] = WorkspacePersistenceSnapshotParticipantItems(
            participantID: .tabGraphs,
            items: [.tabGraph(tabGraph)]
        )

        // Act
        let result = WorkspacePersistenceSnapshotAssembler.assemble(participants: participants)

        // Assert
        #expect(
            result
                == .rejected(
                    .tabPaneNotReferenced(
                        tabID: fixture.state.tabs[0].id,
                        paneID: unreferencedPane.id
                    ))
        )
    }

    @Test("multi-drawer membership preserves accepted canonical order")
    func multiDrawerMembershipPreservesAcceptedCanonicalOrder() throws {
        // Arrange
        let parentPaneAID = UUIDv7.generate()
        let parentPaneBID = UUIDv7.generate()
        let childPaneAID = UUIDv7.generate()
        let childPaneBID = UUIDv7.generate()
        let lexicallyLaterDrawerID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let lexicallyEarlierDrawerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let parentPaneA = makeTerminalPane(
            id: parentPaneAID,
            title: "Parent A",
            kind: .layout(
                drawer: Drawer(
                    drawerId: lexicallyLaterDrawerID,
                    parentPaneId: parentPaneAID,
                    paneIds: [childPaneAID]
                ))
        )
        let parentPaneB = makeTerminalPane(
            id: parentPaneBID,
            title: "Parent B",
            kind: .layout(
                drawer: Drawer(
                    drawerId: lexicallyEarlierDrawerID,
                    parentPaneId: parentPaneBID,
                    paneIds: [childPaneBID]
                ))
        )
        let childPaneA = makeTerminalPane(
            id: childPaneAID,
            title: "Child A",
            kind: .drawerChild(parentPaneId: parentPaneAID)
        )
        let childPaneB = makeTerminalPane(
            id: childPaneBID,
            title: "Child B",
            kind: .drawerChild(parentPaneId: parentPaneBID)
        )
        let arrangement = PaneArrangement(
            id: UUIDv7.generate(),
            name: "Two drawers",
            isDefault: true,
            layout: Layout.autoTiled([parentPaneAID, parentPaneBID]),
            activePaneId: parentPaneAID,
            drawerViews: [
                lexicallyLaterDrawerID: DrawerView(
                    layout: DrawerGridLayout(topRow: Layout(paneId: childPaneAID)),
                    activeChildId: childPaneAID
                ),
                lexicallyEarlierDrawerID: DrawerView(
                    layout: DrawerGridLayout(topRow: Layout(paneId: childPaneBID)),
                    activeChildId: childPaneBID
                ),
            ]
        )
        let tab = Tab(
            id: UUIDv7.generate(),
            name: "Parent order",
            allPaneIds: [parentPaneAID, parentPaneBID, childPaneBID, childPaneAID],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )
        let persistedAt = Date(timeIntervalSince1970: 1_730_000_300)
        let state = WorkspacePersistor.PersistableState(
            id: UUIDv7.generate(),
            name: "Multi-drawer order",
            panes: [parentPaneA, parentPaneB, childPaneA, childPaneB],
            tabs: [tab],
            activeTabId: tab.id,
            createdAt: Date(timeIntervalSince1970: 1_730_000_000),
            updatedAt: persistedAt
        )

        // Act
        let assembly = try requireAssembly(participants: participantItems(state: state))
        let finalized = try assembly.finalize(
            input: WorkspacePersistenceSnapshotFinalizationInput(persistedAt: persistedAt)
        )
        let finalizedTab = try #require(finalized.workspace.tabs.first)

        // Assert
        #expect(lexicallyLaterDrawerID.uuidString > lexicallyEarlierDrawerID.uuidString)
        #expect(finalizedTab.arrangements[0].layout.paneIds == [parentPaneAID, parentPaneBID])
        #expect(finalizedTab.allPaneIds == [parentPaneAID, parentPaneBID, childPaneBID, childPaneAID])
        #expect(
            finalizedTab.arrangements[0].drawerViews[lexicallyLaterDrawerID]?.layout.paneIds
                == [childPaneAID]
        )
        #expect(
            finalizedTab.arrangements[0].drawerViews[lexicallyEarlierDrawerID]?.layout.paneIds
                == [childPaneBID]
        )
    }
}

private struct SnapshotAssemblerFixture {
    let state: WorkspacePersistor.PersistableState
    let persistedAt: Date
}

private func makeRepresentativeFixture() -> SnapshotAssemblerFixture {
    let repositoryA = CanonicalRepo(
        id: UUID(uuidString: "01990000-0000-7000-8000-000000000020")!,
        name: "Zulu",
        repoPath: URL(filePath: "/tmp/zulu")
    )
    let repositoryB = CanonicalRepo(
        id: UUID(uuidString: "01990000-0000-7000-8000-000000000010")!,
        name: "Alpha",
        repoPath: URL(filePath: "/tmp/alpha")
    )
    let worktree = CanonicalWorktree(
        id: UUIDv7.generate(),
        repoId: repositoryA.id,
        name: "zulu-main",
        path: repositoryA.repoPath,
        isMainWorktree: true
    )
    let pane = Pane(
        id: UUIDv7.generate(),
        content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())),
        metadata: PaneMetadata(
            title: "Assembler pane",
            facets: PaneContextFacets(repoId: repositoryA.id, worktreeId: worktree.id)
        )
    )
    var tab = Tab(id: UUIDv7.generate(), paneId: pane.id, name: "Assembler tab")
    tab.colorHex = "#102030"
    let persistedAt = Date(timeIntervalSince1970: 1_730_000_200)
    return SnapshotAssemblerFixture(
        state: WorkspacePersistor.PersistableState(
            id: UUIDv7.generate(),
            name: "Assembler workspace",
            repos: [repositoryA, repositoryB],
            worktrees: [worktree],
            unavailableRepoIds: [repositoryB.id],
            panes: [pane],
            tabs: [tab],
            activeTabId: tab.id,
            sidebarWidth: 333,
            windowFrame: CGRect(x: 11, y: 22, width: 1200, height: 800),
            watchedPaths: [
                WatchedPath(path: URL(filePath: "/tmp/zulu")),
                WatchedPath(path: URL(filePath: "/tmp/alpha")),
            ],
            createdAt: Date(timeIntervalSince1970: 1_730_000_000),
            updatedAt: persistedAt
        ),
        persistedAt: persistedAt
    )
}

private func makeTerminalPane(id: UUID, title: String, kind: PaneKind) -> Pane {
    Pane(
        id: id,
        content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())),
        metadata: PaneMetadata(title: title),
        kind: kind
    )
}

private func participantItems(
    state: WorkspacePersistor.PersistableState
) -> [WorkspacePersistenceSnapshotParticipantItems] {
    let tabGraphs = state.tabs.map { tab in
        TabGraphState(
            tabId: tab.id,
            allPaneIds: tab.allPaneIds,
            arrangements: tab.arrangements.map(PaneArrangementGraphState.init)
        )
    }
    return [
        .init(
            participantID: .workspaceIdentity,
            items: [
                .workspaceIdentity(
                    .init(workspaceID: state.id, workspaceName: state.name, createdAt: state.createdAt))
            ]
        ),
        .init(
            participantID: .workspaceWindowMemory,
            items: [.windowMemory(.init(sidebarWidth: state.sidebarWidth, windowFrame: state.windowFrame))]
        ),
        .init(participantID: .repositories, items: state.repos.map(WorkspacePersistenceSnapshotItem.repository)),
        .init(participantID: .worktrees, items: state.worktrees.map(WorkspacePersistenceSnapshotItem.worktree)),
        .init(
            participantID: .watchedPaths, items: state.watchedPaths.map(WorkspacePersistenceSnapshotItem.watchedPath)),
        .init(
            participantID: .unavailableRepositories,
            items: state.repos.compactMap { repository in
                state.unavailableRepoIds.contains(repository.id) ? .unavailableRepository(repository.id) : nil
            }
        ),
        .init(participantID: .paneGraphs, items: state.panes.map { .paneGraph(PaneGraphState(pane: $0)) }),
        .init(participantID: .expandedDrawer, items: []),
        .init(
            participantID: .tabShells,
            items: state.tabs.enumerated().map { index, tab in
                .tabShell(
                    .init(
                        shell: TabShell(id: tab.id, name: tab.name, colorHex: tab.colorHex),
                        sortIndex: index
                    ))
            }
        ),
        .init(participantID: .activeTab, items: state.activeTabId.map { [.activeTab($0)] } ?? []),
        .init(participantID: .tabGraphs, items: tabGraphs.map(WorkspacePersistenceSnapshotItem.tabGraph)),
        .init(
            participantID: .activeArrangements,
            items: state.tabs.map { .activeArrangement(tabID: $0.id, arrangementID: $0.activeArrangementId) }
        ),
        .init(
            participantID: .activePanes,
            items: state.tabs.flatMap { tab in
                tab.arrangements.compactMap { arrangement in
                    arrangement.activePaneId.map {
                        .activePane(arrangementID: arrangement.id, paneID: $0)
                    }
                }
            }
        ),
        .init(
            participantID: .activeDrawerChildren,
            items: state.tabs.flatMap { tab in
                tab.arrangements.flatMap { arrangement in
                    arrangement.drawerViews.compactMap { drawerID, drawerView in
                        drawerView.activeChildId.map {
                            .activeDrawerChild(
                                key: .init(arrangementId: arrangement.id, drawerId: drawerID),
                                childPaneID: $0
                            )
                        }
                    }
                }
            }
        ),
    ]
}

private func requireAssembly(
    participants: [WorkspacePersistenceSnapshotParticipantItems]
) throws -> WorkspacePersistenceSnapshotAssembly {
    switch WorkspacePersistenceSnapshotAssembler.assemble(participants: participants) {
    case .assembled(let assembly):
        return assembly
    case .rejected(let rejection):
        Issue.record("Unexpected assembly rejection: \(rejection)")
        throw rejection
    }
}
