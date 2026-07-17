import Foundation
import Testing

@testable import AgentStudio

@Suite("Close final pane and remove tab transition")
struct FinalPaneTabRemovalTransitionTests {
    @Test("active middle tab removal carries exact shell suffix and cursor tombstones")
    func activeMiddleTabRemovalIsExact() throws {
        // Arrange
        let fixture = makeFinalPaneRemovalFixture()

        // Act
        let transition = try requireFinalPaneRemovalTransition(
            WorkspaceFinalPaneTabRemovalPlanner.plan(
                fixture.request,
                context: fixture.context(activeTab: .selected(fixture.tab.tabId))
            )
        )

        // Assert
        #expect(transition.previousPane == fixture.pane)
        #expect(transition.removedTab == .init(index: 1, state: fixture.tab))
        #expect(transition.removedShell == .init(index: 1, shell: fixture.shells[1]))
        #expect(transition.shiftedShellSuffix == [.init(index: 2, shell: fixture.shells[2])])
        #expect(
            transition.tabCursor
                == .replace(
                    .init(
                        previous: .selected(fixture.tab.tabId),
                        replacement: .selected(fixture.shells[2].id)
                    )
                )
        )
        #expect(transition.removedActiveArrangementID == fixture.arrangementIDs[0])
        #expect(transition.removedActivePanes == fixture.paneCursors)
        #expect(transition.absentDrawerCursors.arrangementIDs == fixture.arrangementIDs)
        #expect(transition.zoom == .clear(tabID: fixture.tab.tabId, previousPaneID: fixture.pane.id))
    }

    @Test("background and only-tab removals produce strict active-tab outcomes")
    func activeTabOutcomesAreStrict() throws {
        // Arrange
        let fixture = makeFinalPaneRemovalFixture()
        let backgroundSelection = WorkspaceTabCursorSelection.selected(fixture.shells[0].id)
        let onlyShell = [fixture.shells[1]]

        // Act
        let background = try requireFinalPaneRemovalTransition(
            WorkspaceFinalPaneTabRemovalPlanner.plan(
                fixture.request,
                context: fixture.context(activeTab: backgroundSelection)
            )
        )
        let only = try requireFinalPaneRemovalTransition(
            WorkspaceFinalPaneTabRemovalPlanner.plan(
                fixture.request,
                context: fixture.context(
                    tabIndex: 0,
                    shells: onlyShell,
                    activeTab: .selected(fixture.tab.tabId)
                )
            )
        )

        // Assert
        #expect(background.tabCursor == .witness(backgroundSelection))
        #expect(
            only.tabCursor
                == .replace(
                    .init(previous: .selected(fixture.tab.tabId), replacement: .noSelection)
                )
        )
        #expect(only.shiftedShellSuffix.isEmpty)
    }

    @Test("drawer state and nonfinal membership reject without a transition")
    func excludedFamiliesReject() {
        // Arrange
        let fixture = makeFinalPaneRemovalFixture()
        var populated = fixture.pane
        populated.withDrawer { $0.paneIds = [UUIDv7.generate()] }
        var extraPaneTab = fixture.tab
        extraPaneTab.allPaneIds.append(UUIDv7.generate())
        var drawerViewTab = fixture.tab
        let drawerID = fixture.pane.drawer!.drawerId
        drawerViewTab.arrangements[0].drawerViews[drawerID] = DrawerViewGraphState(
            layout: DrawerGridLayout(topRow: Layout(paneId: UUIDv7.generate())),
            minimizedPaneIds: []
        )
        let foreignDrawerCursorKey = ArrangementDrawerCursorKey(
            arrangementId: fixture.arrangementIDs[0],
            drawerId: UUIDv7.generate()
        )

        // Act / Assert
        #expect(
            planFinalPaneRemoval(fixture, pane: .present(populated))
                == .rejected(.paneDrawerPopulated(fixture.pane.id))
        )
        #expect(
            planFinalPaneRemoval(
                fixture,
                drawerCursor: .expanded(drawerID: drawerID)
            ) == .rejected(.paneDrawerExpanded(drawerID: drawerID))
        )
        #expect(
            planFinalPaneRemoval(fixture, tab: .present(extraPaneTab))
                == .rejected(
                    .tabOwnsUnexpectedPanes(tabID: fixture.tab.tabId, paneIDs: extraPaneTab.allPaneIds)
                )
        )
        #expect(
            planFinalPaneRemoval(fixture, tab: .present(drawerViewTab))
                == .rejected(.drawerViewPresent(arrangementID: fixture.arrangementIDs[0], drawerID: drawerID))
        )
        #expect(
            planFinalPaneRemoval(fixture, arrangementDrawerCursorKeys: [foreignDrawerCursorKey])
                == .rejected(.arrangementDrawerCursorPresent(foreignDrawerCursorKey))
        )
    }

    @Test("malformed owner and cursor witnesses reject explicitly")
    func malformedWitnessesReject() {
        // Arrange
        let fixture = makeFinalPaneRemovalFixture()
        var invalidCursor = fixture.paneCursors
        invalidCursor[0] = .init(arrangementID: fixture.arrangementIDs[0], cursor: .present(.noSelection))

        // Act / Assert
        #expect(planFinalPaneRemoval(fixture, pane: .missing) == .rejected(.paneMissing(fixture.pane.id)))
        #expect(
            planFinalPaneRemoval(fixture, ownership: .absent)
                == .rejected(.paneUnowned(fixture.pane.id))
        )
        #expect(
            planFinalPaneRemoval(fixture, tabIndex: nil)
                == .rejected(.tabIndexMissing(fixture.tab.tabId))
        )
        #expect(
            planFinalPaneRemoval(fixture, paneCursors: invalidCursor)
                == .rejected(
                    .cursorInvalid(arrangementID: fixture.arrangementIDs[0], cursor: invalidCursor[0].cursor)
                )
        )
        #expect(
            planFinalPaneRemoval(
                fixture,
                shells: [fixture.shells[0], fixture.shells[2], fixture.shells[1]]
            )
                == .rejected(
                    .tabOwnerIndexMismatch(tabID: fixture.tab.tabId, graphIndex: 1, shellIndex: 2)
                )
        )
    }
}

struct FinalPaneRemovalFixture {
    let pane: PaneGraphState
    let tab: TabGraphState
    let shells: [TabShell]
    let arrangementIDs: [UUID]
    let paneCursors: [WorkspaceClosePaneCursorWitness]
    let drawerCursorKeys: [ArrangementDrawerCursorKey]

    var request: WorkspaceCloseFinalPaneAndRemoveTabRequest {
        .init(paneID: pane.id, tabID: tab.tabId)
    }

    func context(
        pane paneWitness: WorkspaceClosePaneWitness? = nil,
        ownership: WorkspaceClosePaneOwnershipWitness? = nil,
        tab tabWitness: WorkspaceClosePaneTabWitness? = nil,
        tabIndex: Int? = 1,
        shells: [TabShell]? = nil,
        activeTab: WorkspaceTabCursorSelection? = nil,
        activeArrangement: WorkspaceActiveArrangementSelection? = nil,
        paneCursors: [WorkspaceClosePaneCursorWitness]? = nil,
        arrangementDrawerCursorKeys: [ArrangementDrawerCursorKey]? = nil,
        drawerCursor: WorkspaceDrawerCursorSelection = .collapsed,
        zoom: WorkspaceZoomSelection? = nil
    ) -> WorkspaceCloseFinalPaneAndRemoveTabPlanningContext {
        .init(
            pane: paneWitness ?? .present(pane),
            ownership: ownership ?? .owned(tabID: tab.tabId),
            tab: tabWitness ?? .present(tab),
            tabIndex: tabIndex,
            tabShells: shells ?? self.shells,
            activeTab: activeTab ?? .selected(tab.tabId),
            activeArrangement: activeArrangement ?? .selected(arrangementIDs[0]),
            paneCursors: paneCursors ?? self.paneCursors,
            arrangementDrawerCursorKeys: arrangementDrawerCursorKeys ?? drawerCursorKeys,
            drawerCursor: drawerCursor,
            zoom: zoom ?? .zoomed(pane.id)
        )
    }
}

func makeFinalPaneRemovalFixture() -> FinalPaneRemovalFixture {
    let paneID = UUIDv7.generate()
    let drawerID = UUIDv7.generate()
    let firstArrangementID = UUIDv7.generate()
    let secondArrangementID = UUIDv7.generate()
    let tabID = UUIDv7.generate()
    let pane = PaneGraphState(
        pane: Pane(
            id: paneID,
            content: .webview(WebviewState(url: URL(string: "https://example.com/final")!)),
            metadata: .init(title: "Final"),
            residency: .active,
            kind: .layout(drawer: Drawer(drawerId: drawerID, parentPaneId: paneID))
        )
    )
    let arrangements = [
        PaneArrangementGraphState(
            id: firstArrangementID,
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneID),
            minimizedPaneIds: [],
            showsMinimizedPanes: false,
            drawerViews: [:]
        ),
        PaneArrangementGraphState(
            id: secondArrangementID,
            name: "Minimized",
            isDefault: false,
            layout: Layout(paneId: paneID),
            minimizedPaneIds: [paneID],
            showsMinimizedPanes: true,
            drawerViews: [:]
        ),
    ]
    let tab = TabGraphState(tabId: tabID, allPaneIds: [paneID], arrangements: arrangements)
    let prefix = TabShell(id: UUIDv7.generate(), name: "Prefix")
    let target = TabShell(id: tabID, name: "Target")
    let suffix = TabShell(id: UUIDv7.generate(), name: "Suffix")
    let paneCursors = [
        WorkspaceClosePaneCursorWitness(
            arrangementID: firstArrangementID,
            cursor: .present(.selected(paneID))
        ),
        WorkspaceClosePaneCursorWitness(
            arrangementID: secondArrangementID,
            cursor: .present(.noSelection)
        ),
    ]
    return .init(
        pane: pane,
        tab: tab,
        shells: [prefix, target, suffix],
        arrangementIDs: [firstArrangementID, secondArrangementID],
        paneCursors: paneCursors,
        drawerCursorKeys: []
    )
}

func planFinalPaneRemoval(
    _ fixture: FinalPaneRemovalFixture,
    pane: WorkspaceClosePaneWitness? = nil,
    ownership: WorkspaceClosePaneOwnershipWitness? = nil,
    tab: WorkspaceClosePaneTabWitness? = nil,
    tabIndex: Int? = 1,
    shells: [TabShell]? = nil,
    paneCursors: [WorkspaceClosePaneCursorWitness]? = nil,
    arrangementDrawerCursorKeys: [ArrangementDrawerCursorKey]? = nil,
    drawerCursor: WorkspaceDrawerCursorSelection = .collapsed
) -> WorkspaceCloseFinalPaneAndRemoveTabDecision {
    WorkspaceFinalPaneTabRemovalPlanner.plan(
        fixture.request,
        context: fixture.context(
            pane: pane,
            ownership: ownership,
            tab: tab,
            tabIndex: tabIndex,
            shells: shells,
            paneCursors: paneCursors,
            arrangementDrawerCursorKeys: arrangementDrawerCursorKeys,
            drawerCursor: drawerCursor
        )
    )
}

func requireFinalPaneRemovalTransition(
    _ decision: WorkspaceCloseFinalPaneAndRemoveTabDecision
) throws -> WorkspaceCloseFinalPaneAndRemoveTabTransition {
    guard case .changed(let transition) = decision else {
        throw FinalPaneRemovalTestError.expectedTransition
    }
    return transition
}

enum FinalPaneRemovalTestError: Error {
    case expectedTransition
}
