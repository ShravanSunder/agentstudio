import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace tab graph leaf transitions")
struct WorkspaceTabGraphLeafTransitionTests {
    @Test("equalize replaces only the active arrangement graph")
    func equalizeReplacesOnlyActiveArrangement() {
        // Arrange
        let fixture = makeTabGraphLeafFixture()

        // Act
        let decision = WorkspaceEqualizePanesTransitionPlanner.plan(
            .init(tabID: fixture.tabState.tabId),
            context: .present(fixture.tabState),
            activeArrangement: .selected(fixture.customArrangementID)
        )

        // Assert
        guard case .changed(let transition) = decision else {
            Issue.record("expected an equalize transition")
            return
        }
        #expect(transition.previousTab == fixture.tabState)
        let replacement = transition.replacementTab
        #expect(replacement.arrangements[0] == fixture.tabState.arrangements[0])
        #expect(replacement.arrangements[1].layout.panes.map(\.ratio) == [0.5, 0.5])
        #expect(
            transition.readWitness
                == .activeArrangement(
                    tabID: fixture.tabState.tabId,
                    expected: .selected(fixture.customArrangementID)
                )
        )
    }

    @Test("equalize reports missing cursor, non-split, and semantic no-op distinctly")
    func equalizeRejectionsAndNoOpAreExplicit() {
        // Arrange
        let fixture = makeTabGraphLeafFixture()
        var singlePaneTab = fixture.tabState
        singlePaneTab.arrangements[1].layout = Layout(paneId: fixture.paneIDs[0])
        var equalTab = fixture.tabState
        equalTab.arrangements[1].layout = equalTab.arrangements[1].layout.equalized()
        let missingTabID = UUIDv7.generate()
        let mismatchedTabID = UUIDv7.generate()
        let missingArrangementID = UUIDv7.generate()

        // Act
        let missingTab = WorkspaceEqualizePanesTransitionPlanner.plan(
            .init(tabID: missingTabID),
            context: .missingTab,
            activeArrangement: .selected(fixture.customArrangementID)
        )
        let missingCursor = WorkspaceEqualizePanesTransitionPlanner.plan(
            .init(tabID: fixture.tabState.tabId),
            context: .present(fixture.tabState),
            activeArrangement: .missing
        )
        let mismatchedTab = WorkspaceEqualizePanesTransitionPlanner.plan(
            .init(tabID: mismatchedTabID),
            context: .present(fixture.tabState),
            activeArrangement: .selected(fixture.customArrangementID)
        )
        let missingArrangement = WorkspaceEqualizePanesTransitionPlanner.plan(
            .init(tabID: fixture.tabState.tabId),
            context: .present(fixture.tabState),
            activeArrangement: .selected(missingArrangementID)
        )
        let nonSplit = WorkspaceEqualizePanesTransitionPlanner.plan(
            .init(tabID: singlePaneTab.tabId),
            context: .present(singlePaneTab),
            activeArrangement: .selected(fixture.customArrangementID)
        )
        let unchanged = WorkspaceEqualizePanesTransitionPlanner.plan(
            .init(tabID: equalTab.tabId),
            context: .present(equalTab),
            activeArrangement: .selected(fixture.customArrangementID)
        )

        // Assert
        #expect(missingTab == .rejected(.missingTab(missingTabID)))
        #expect(
            mismatchedTab
                == .rejected(
                    .tabIdentityMismatch(
                        requested: mismatchedTabID,
                        actual: fixture.tabState.tabId
                    )
                )
        )
        #expect(missingCursor == .rejected(.missingActiveArrangement(fixture.tabState.tabId)))
        #expect(
            missingArrangement
                == .rejected(
                    .missingArrangement(
                        tabID: fixture.tabState.tabId,
                        arrangementID: missingArrangementID
                    )
                )
        )
        #expect(nonSplit == .rejected(.tabNotSplit(singlePaneTab.tabId)))
        #expect(unchanged == .unchanged)
    }

    @Test("rename normalizes once and changes only the requested non-default arrangement")
    func renameNormalizesAndReplacesRequestedArrangement() {
        // Arrange
        let fixture = makeTabGraphLeafFixture()

        // Act
        let decision = WorkspaceRenameArrangementTransitionPlanner.plan(
            .init(
                tabID: fixture.tabState.tabId,
                arrangementID: fixture.customArrangementID,
                name: "  Focus  "
            ),
            context: .present(fixture.tabState)
        )

        // Assert
        guard case .changed(let transition) = decision else {
            Issue.record("expected a rename transition")
            return
        }
        #expect(transition.readWitness == .graphOnly)
        #expect(transition.replacementTab.arrangements[0].name == "Default")
        #expect(transition.replacementTab.arrangements[1].name == "Focus")
    }

    @Test("rename rejects default and empty names and preserves normalized no-op")
    func renameRejectionsAndNoOpAreExplicit() {
        // Arrange
        let fixture = makeTabGraphLeafFixture()
        let missingTabID = UUIDv7.generate()
        let missingArrangementID = UUIDv7.generate()

        // Act
        let missingTab = WorkspaceRenameArrangementTransitionPlanner.plan(
            .init(tabID: missingTabID, arrangementID: fixture.customArrangementID, name: "New"),
            context: .missingTab
        )
        let missingArrangement = WorkspaceRenameArrangementTransitionPlanner.plan(
            .init(tabID: fixture.tabState.tabId, arrangementID: missingArrangementID, name: "New"),
            context: .present(fixture.tabState)
        )
        let defaultRename = WorkspaceRenameArrangementTransitionPlanner.plan(
            .init(tabID: fixture.tabState.tabId, arrangementID: fixture.defaultArrangementID, name: "New"),
            context: .present(fixture.tabState)
        )
        let empty = WorkspaceRenameArrangementTransitionPlanner.plan(
            .init(tabID: fixture.tabState.tabId, arrangementID: fixture.customArrangementID, name: " \n "),
            context: .present(fixture.tabState)
        )
        let unchanged = WorkspaceRenameArrangementTransitionPlanner.plan(
            .init(tabID: fixture.tabState.tabId, arrangementID: fixture.customArrangementID, name: " Custom "),
            context: .present(fixture.tabState)
        )

        // Assert
        #expect(missingTab == .rejected(.missingTab(missingTabID)))
        #expect(
            missingArrangement
                == .rejected(
                    .missingArrangement(
                        tabID: fixture.tabState.tabId,
                        arrangementID: missingArrangementID
                    )
                )
        )
        #expect(
            defaultRename
                == .rejected(
                    .defaultArrangementCannotBeRenamed(
                        tabID: fixture.tabState.tabId,
                        arrangementID: fixture.defaultArrangementID
                    )
                )
        )
        #expect(empty == .rejected(.emptyArrangementName(fixture.customArrangementID)))
        #expect(unchanged == .unchanged)
    }

    @Test("drawer equalize changes only the selected arrangement target drawer")
    func drawerEqualizeIsTargeted() throws {
        // Arrange
        let fixture = makeTabGraphLeafFixture()
        let originalDrawer = try #require(
            fixture.tabState.arrangements[1].drawerViews[fixture.drawerID]
        )
        var expectedDrawer = originalDrawer
        expectedDrawer.layout = originalDrawer.layout.equalized()

        // Act
        let decision = WorkspaceEqualizeDrawerPanesTransitionPlanner.plan(
            .init(tabID: fixture.tabState.tabId, drawerID: fixture.drawerID),
            context: .present(fixture.tabState),
            activeArrangement: .selected(fixture.customArrangementID)
        )

        // Assert
        guard case .changed(let transition) = decision else {
            Issue.record("expected a drawer equalize transition")
            return
        }
        #expect(transition.previousTab == fixture.tabState)
        #expect(
            transition.replacementTab.arrangements[1].drawerViews[fixture.drawerID]
                == expectedDrawer
        )
        #expect(transition.replacementTab.arrangements[1].layout == fixture.tabState.arrangements[1].layout)
    }

    @Test("drawer equalize distinguishes missing drawer, non-split, and no-op")
    func drawerEqualizeOutcomesAreExplicit() {
        // Arrange
        let fixture = makeTabGraphLeafFixture()
        let missingDrawerID = UUIDv7.generate()
        var nonSplit = fixture.tabState
        nonSplit.arrangements[1].drawerViews[fixture.drawerID]?.layout = DrawerGridLayout(
            topRow: Layout(paneId: fixture.drawerPaneIDs[0])
        )
        var equalized = fixture.tabState
        var equalizedDrawer = equalized.arrangements[1].drawerViews[fixture.drawerID]!
        equalizedDrawer.layout = equalizedDrawer.layout.equalized()
        equalized.arrangements[1].drawerViews[fixture.drawerID] = equalizedDrawer

        // Act
        let missing = WorkspaceEqualizeDrawerPanesTransitionPlanner.plan(
            .init(tabID: fixture.tabState.tabId, drawerID: missingDrawerID),
            context: .present(fixture.tabState),
            activeArrangement: .selected(fixture.customArrangementID)
        )
        let notSplit = WorkspaceEqualizeDrawerPanesTransitionPlanner.plan(
            .init(tabID: nonSplit.tabId, drawerID: fixture.drawerID),
            context: .present(nonSplit),
            activeArrangement: .selected(fixture.customArrangementID)
        )
        let unchanged = WorkspaceEqualizeDrawerPanesTransitionPlanner.plan(
            .init(tabID: equalized.tabId, drawerID: fixture.drawerID),
            context: .present(equalized),
            activeArrangement: .selected(fixture.customArrangementID)
        )

        // Assert
        #expect(
            missing
                == .rejected(
                    .missingDrawer(
                        tabID: fixture.tabState.tabId,
                        arrangementID: fixture.customArrangementID,
                        drawerID: missingDrawerID
                    )
                )
        )
        #expect(
            notSplit
                == .rejected(
                    .drawerNotSplit(
                        tabID: nonSplit.tabId,
                        arrangementID: fixture.customArrangementID,
                        drawerID: fixture.drawerID
                    )
                )
        )
        #expect(unchanged == .unchanged)
    }
}

struct TabGraphLeafFixture {
    let tabState: TabGraphState
    let defaultArrangementID: UUID
    let customArrangementID: UUID
    let paneIDs: [UUID]
    let drawerID: UUID
    let drawerPaneIDs: [UUID]
}

func makeTabGraphLeafFixture() -> TabGraphLeafFixture {
    let paneIDs = [UUIDv7.generate(), UUIDv7.generate()]
    let dividerID = UUIDv7.generate()
    let defaultArrangementID = UUIDv7.generate()
    let customArrangementID = UUIDv7.generate()
    let drawerID = UUIDv7.generate()
    let drawerPaneIDs = [UUIDv7.generate(), UUIDv7.generate()]
    let defaultArrangement = PaneArrangementGraphState(
        id: defaultArrangementID,
        name: "Default",
        isDefault: true,
        layout: Layout(paneId: paneIDs[0]),
        minimizedPaneIds: [],
        showsMinimizedPanes: false,
        drawerViews: [:]
    )
    let customArrangement = PaneArrangementGraphState(
        id: customArrangementID,
        name: "Custom",
        isDefault: false,
        layout: Layout(
            panes: [
                Layout.PaneEntry(paneId: paneIDs[0], ratio: 0.7),
                Layout.PaneEntry(paneId: paneIDs[1], ratio: 0.3),
            ],
            dividerIds: [dividerID]
        ),
        minimizedPaneIds: [],
        showsMinimizedPanes: false,
        drawerViews: [
            drawerID: DrawerViewGraphState(
                layout: DrawerGridLayout(
                    topRow: Layout(
                        panes: [
                            .init(paneId: drawerPaneIDs[0], ratio: 0.8),
                            .init(paneId: drawerPaneIDs[1], ratio: 0.2),
                        ],
                        dividerIds: [UUIDv7.generate()]
                    )
                ),
                minimizedPaneIds: []
            )
        ]
    )
    return TabGraphLeafFixture(
        tabState: TabGraphState(
            tabId: UUIDv7.generate(),
            allPaneIds: paneIDs,
            arrangements: [defaultArrangement, customArrangement]
        ),
        defaultArrangementID: defaultArrangementID,
        customArrangementID: customArrangementID,
        paneIDs: paneIDs,
        drawerID: drawerID,
        drawerPaneIDs: drawerPaneIDs
    )
}
