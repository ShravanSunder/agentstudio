import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace tab transition applier")
struct WorkspaceTabTransitionApplierTests {
    @Test("applies exact tab-owner insertions and preserves explicit empty cursors")
    func appliesExactTabOwnerInsertions() throws {
        // Arrange
        let existingFleet = makeExistingTabFleet(count: 1)
        let fixture = makeAppendTabFixture()
        let transition = try requireAppendTransition(
            tab: fixture.tab,
            existingFleet: existingFleet
        )
        let owners = makeTabOwners(existingFleet: existingFleet)
        let applier = WorkspaceTabTransitionApplier(
            workspaceTabShellAtom: owners.shellAtom,
            workspaceTabGraphAtom: owners.graphAtom,
            workspaceArrangementCursorAtom: owners.arrangementCursorAtom
        )

        // Act
        let result = applier.apply(transition)

        // Assert
        #expect(result == .applied)
        #expect(owners.shellAtom.tabShells == existingFleet.shells + [fixture.expectedShell])
        #expect(owners.graphAtom.tabStates == existingFleet.graphs + [fixture.expectedGraph])
        #expect(
            owners.arrangementCursorAtom.activeArrangementIdsByTabId[fixture.tab.id]
                == fixture.arrangementID
        )
        #expect(
            owners.arrangementCursorAtom.paneCursorsByArrangementId[fixture.arrangementID]
                == ArrangementPaneCursorState(activePaneId: nil)
        )
        #expect(
            owners.arrangementCursorAtom.drawerCursorsByKey[fixture.drawerCursorKey]
                == ArrangementDrawerCursorState(activeChildId: nil)
        )
        #expect(owners.shellCursorAtom.activeTabId == fixture.tab.id)
    }

    @Test("inserts without replacing or changing 300 unrelated tab owners")
    func preservesUnrelatedFleet() throws {
        // Arrange
        let existingFleet = makeExistingTabFleet(count: 300)
        let fixture = makeAppendTabFixture()
        let transition = try requireAppendTransition(
            tab: fixture.tab,
            existingFleet: existingFleet
        )
        let owners = makeTabOwners(existingFleet: existingFleet)
        let originalActiveArrangements = owners.arrangementCursorAtom.activeArrangementIdsByTabId
        let originalPaneCursors = owners.arrangementCursorAtom.paneCursorsByArrangementId
        let originalDrawerCursors = owners.arrangementCursorAtom.drawerCursorsByKey
        let applier = WorkspaceTabTransitionApplier(
            workspaceTabShellAtom: owners.shellAtom,
            workspaceTabGraphAtom: owners.graphAtom,
            workspaceArrangementCursorAtom: owners.arrangementCursorAtom
        )

        // Act
        let result = applier.apply(transition)

        // Assert
        #expect(result == .applied)
        #expect(Array(owners.shellAtom.tabShells.prefix(300)) == existingFleet.shells)
        #expect(Array(owners.graphAtom.tabStates.prefix(300)) == existingFleet.graphs)
        #expect(owners.shellAtom.tabShells.count == 301)
        #expect(owners.graphAtom.tabStates.count == 301)
        #expect(
            originalActiveArrangements.allSatisfy {
                owners.arrangementCursorAtom.activeArrangementIdsByTabId[$0.key] == $0.value
            }
        )
        #expect(
            originalPaneCursors.allSatisfy {
                owners.arrangementCursorAtom.paneCursorsByArrangementId[$0.key] == $0.value
            }
        )
        #expect(
            owners.arrangementCursorAtom.drawerCursorsByKey
                == originalDrawerCursors.merging(
                    [fixture.drawerCursorKey: .init(activeChildId: nil)],
                    uniquingKeysWith: { original, _ in original }
                ))
    }

    @Test("preflight rejects an occupied expected-absent key before any owner mutation")
    func preflightRejectsOccupiedKeyAtomically() throws {
        // Arrange
        let existingFleet = makeExistingTabFleet(count: 1)
        let fixture = makeAppendTabFixture()
        let transition = try requireAppendTransition(
            tab: fixture.tab,
            existingFleet: existingFleet
        )
        let owners = makeTabOwners(existingFleet: existingFleet)
        owners.arrangementCursorAtom.replaceCursors(
            activeArrangementIdsByTabId: existingFleet.activeArrangementIDsByTabID,
            paneCursorsByArrangementId: existingFleet.paneCursorsByArrangementID.merging(
                [fixture.arrangementID: .init(activePaneId: fixture.mainPaneID)],
                uniquingKeysWith: { original, _ in original }
            ),
            drawerCursorsByKey: existingFleet.drawerCursorsByKey
        )
        let originalShells = owners.shellAtom.tabShells
        let originalGraphs = owners.graphAtom.tabStates
        let originalActiveTabID = owners.shellCursorAtom.activeTabId
        let originalActiveArrangements = owners.arrangementCursorAtom.activeArrangementIdsByTabId
        let originalPaneCursors = owners.arrangementCursorAtom.paneCursorsByArrangementId
        let originalDrawerCursors = owners.arrangementCursorAtom.drawerCursorsByKey
        let applier = WorkspaceTabTransitionApplier(
            workspaceTabShellAtom: owners.shellAtom,
            workspaceTabGraphAtom: owners.graphAtom,
            workspaceArrangementCursorAtom: owners.arrangementCursorAtom
        )

        // Act
        let result = applier.apply(transition)

        // Assert
        #expect(result == .rejected(.activePaneCursorAlreadyExists(fixture.arrangementID)))
        #expect(owners.shellAtom.tabShells == originalShells)
        #expect(owners.graphAtom.tabStates == originalGraphs)
        #expect(owners.shellCursorAtom.activeTabId == originalActiveTabID)
        #expect(owners.arrangementCursorAtom.activeArrangementIdsByTabId == originalActiveArrangements)
        #expect(owners.arrangementCursorAtom.paneCursorsByArrangementId == originalPaneCursors)
        #expect(owners.arrangementCursorAtom.drawerCursorsByKey == originalDrawerCursors)
    }
}

private struct ExistingTabFleet {
    let shells: [TabShell]
    let graphs: [TabGraphState]
    let activeArrangementIDsByTabID: [UUID: UUID]
    let paneCursorsByArrangementID: [UUID: ArrangementPaneCursorState]
    let drawerCursorsByKey: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState]
}

private struct AppendTabFixture {
    let tab: Tab
    let mainPaneID: UUID
    let drawerChildPaneID: UUID
    let arrangementID: UUID
    let drawerID: UUID

    var drawerCursorKey: ArrangementDrawerCursorKey {
        ArrangementDrawerCursorKey(arrangementId: arrangementID, drawerId: drawerID)
    }

    var expectedShell: TabShell {
        TabShell(id: tab.id, name: tab.name, colorHex: tab.colorHex)
    }

    var expectedGraph: TabGraphState {
        TabGraphState(
            tabId: tab.id,
            allPaneIds: tab.allPaneIds,
            arrangements: tab.arrangements.map(PaneArrangementGraphState.init)
        )
    }
}

@MainActor
private struct TabOwners {
    let shellCursorAtom: WorkspaceTabCursorAtom
    let shellAtom: WorkspaceTabShellAtom
    let graphAtom: WorkspaceTabGraphAtom
    let arrangementCursorAtom: WorkspaceArrangementCursorAtom
}

private func makeExistingTabFleet(count: Int) -> ExistingTabFleet {
    var shells: [TabShell] = []
    var graphs: [TabGraphState] = []
    var activeArrangementIDsByTabID: [UUID: UUID] = [:]
    var paneCursorsByArrangementID: [UUID: ArrangementPaneCursorState] = [:]
    shells.reserveCapacity(count)
    graphs.reserveCapacity(count)
    for index in 0..<count {
        let tabID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let arrangementID = UUIDv7.generate()
        shells.append(TabShell(id: tabID, name: "Existing \(index)"))
        graphs.append(
            TabGraphState(
                tabId: tabID,
                allPaneIds: [paneID],
                arrangements: [
                    PaneArrangementGraphState(
                        id: arrangementID,
                        name: "Default",
                        isDefault: true,
                        layout: Layout(paneId: paneID),
                        minimizedPaneIds: [],
                        showsMinimizedPanes: false,
                        drawerViews: [:]
                    )
                ]
            )
        )
        activeArrangementIDsByTabID[tabID] = arrangementID
        paneCursorsByArrangementID[arrangementID] = .init(activePaneId: paneID)
    }
    return ExistingTabFleet(
        shells: shells,
        graphs: graphs,
        activeArrangementIDsByTabID: activeArrangementIDsByTabID,
        paneCursorsByArrangementID: paneCursorsByArrangementID,
        drawerCursorsByKey: [:]
    )
}

private func makeAppendTabFixture() -> AppendTabFixture {
    let mainPaneID = UUIDv7.generate()
    let drawerChildPaneID = UUIDv7.generate()
    let arrangementID = UUIDv7.generate()
    let drawerID = UUIDv7.generate()
    var drawerView = DrawerView(
        layout: DrawerGridLayout(topRow: Layout(paneId: drawerChildPaneID)),
        activeChildId: drawerChildPaneID
    )
    drawerView.activeChildId = nil
    var arrangement = PaneArrangement(
        id: arrangementID,
        name: "Default",
        isDefault: true,
        layout: Layout(paneId: mainPaneID),
        activePaneId: mainPaneID,
        drawerViews: [drawerID: drawerView]
    )
    arrangement.activePaneId = nil
    let tab = Tab(
        id: UUIDv7.generate(),
        name: "Appended",
        allPaneIds: [mainPaneID, drawerChildPaneID],
        arrangements: [arrangement],
        activeArrangementId: arrangementID,
        colorHex: "#11CC88"
    )
    return AppendTabFixture(
        tab: tab,
        mainPaneID: mainPaneID,
        drawerChildPaneID: drawerChildPaneID,
        arrangementID: arrangementID,
        drawerID: drawerID
    )
}

@MainActor
private func makeTabOwners(existingFleet: ExistingTabFleet) -> TabOwners {
    let shellCursorAtom = WorkspaceTabCursorAtom(activeTabId: existingFleet.shells.last?.id)
    let shellAtom = WorkspaceTabShellAtom(cursorAtom: shellCursorAtom)
    let graphAtom = WorkspaceTabGraphAtom()
    let arrangementCursorAtom = WorkspaceArrangementCursorAtom()
    shellAtom.replaceTabShells(existingFleet.shells)
    graphAtom.replaceTabStates(existingFleet.graphs)
    arrangementCursorAtom.replaceCursors(
        activeArrangementIdsByTabId: existingFleet.activeArrangementIDsByTabID,
        paneCursorsByArrangementId: existingFleet.paneCursorsByArrangementID,
        drawerCursorsByKey: existingFleet.drawerCursorsByKey
    )
    return TabOwners(
        shellCursorAtom: shellCursorAtom,
        shellAtom: shellAtom,
        graphAtom: graphAtom,
        arrangementCursorAtom: arrangementCursorAtom
    )
}

private func requireAppendTransition(
    tab: Tab,
    existingFleet: ExistingTabFleet
) throws -> WorkspaceTabTransition {
    let arrangement = try #require(tab.arrangements.first)
    let parentPaneID = try #require(arrangement.layout.paneIds.first)
    let drawerEntry = try #require(arrangement.drawerViews.first)
    let drawerChildPaneID = try #require(drawerEntry.value.layout.paneIds.first)
    let alignedTabOwners = try #require(
        WorkspaceAlignedTabOwnerIndex.prepare(
            shellTabIDs: existingFleet.shells.map(\.id),
            graphTabIDs: existingFleet.graphs.map(\.tabId)
        ).validatedIndex
    )
    let placementIndex = try #require(
        WorkspacePanePlacementIndex.prepare([
            .drawerParent(
                paneID: parentPaneID,
                drawerID: drawerEntry.key,
                drawerChildPaneIDs: Set(drawerEntry.value.layout.paneIds)
            ),
            .drawerChild(
                paneID: drawerChildPaneID,
                parentPaneID: parentPaneID
            ),
        ]).validatedIndex
    )
    let paneOwnerByPaneID = Dictionary(
        uniqueKeysWithValues: existingFleet.graphs.flatMap { graph in
            graph.allPaneIds.map { ($0, graph.tabId) }
        }
    )
    let context = WorkspaceAppendTabContext(
        activeTab: existingFleet.shells.last.map { .selected($0.id) } ?? .noSelection,
        alignedTabOwners: alignedTabOwners,
        panePlacements: placementIndex,
        paneOwnerByPaneID: paneOwnerByPaneID,
        existingArrangementIDs: Set(existingFleet.graphs.flatMap { $0.arrangements.map(\.id) }),
        existingActiveArrangementTabIDs: Set(existingFleet.activeArrangementIDsByTabID.keys),
        existingActivePaneArrangementIDs: Set(existingFleet.paneCursorsByArrangementID.keys),
        existingActiveDrawerChildKeys: Set(existingFleet.drawerCursorsByKey.keys)
    )
    guard
        case .changed(let transition) = WorkspaceAppendTabTransitionDecider.decide(
            tab: tab,
            context: context
        )
    else {
        Issue.record("expected a validated append transition")
        throw AppendTransitionFixtureError.decisionDidNotChange
    }
    return transition
}

private enum AppendTransitionFixtureError: Error {
    case decisionDidNotChange
}

extension WorkspaceAlignedTabOwnerIndexPreparation {
    fileprivate var validatedIndex: WorkspaceAlignedTabOwnerIndex? {
        guard case .validated(let index) = self else { return nil }
        return index
    }
}

extension WorkspacePanePlacementIndexPreparation {
    fileprivate var validatedIndex: WorkspacePanePlacementIndex? {
        guard case .validated(let index) = self else { return nil }
        return index
    }
}
