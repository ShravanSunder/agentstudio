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
            tabStates: [fixture.tabState],
            activeArrangement: .selected(fixture.customArrangementID)
        )

        // Assert
        guard case .changed(let transition) = decision else {
            Issue.record("expected an equalize transition")
            return
        }
        #expect(transition.affectedTab.previous == .init(index: 0, state: fixture.tabState))
        let replacement = transition.affectedTab.replacement.state
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
        let missingArrangementID = UUIDv7.generate()

        // Act
        let missingTab = WorkspaceEqualizePanesTransitionPlanner.plan(
            .init(tabID: missingTabID),
            tabStates: [fixture.tabState],
            activeArrangement: .selected(fixture.customArrangementID)
        )
        let missingCursor = WorkspaceEqualizePanesTransitionPlanner.plan(
            .init(tabID: fixture.tabState.tabId),
            tabStates: [fixture.tabState],
            activeArrangement: .missing
        )
        let missingArrangement = WorkspaceEqualizePanesTransitionPlanner.plan(
            .init(tabID: fixture.tabState.tabId),
            tabStates: [fixture.tabState],
            activeArrangement: .selected(missingArrangementID)
        )
        let nonSplit = WorkspaceEqualizePanesTransitionPlanner.plan(
            .init(tabID: singlePaneTab.tabId),
            tabStates: [singlePaneTab],
            activeArrangement: .selected(fixture.customArrangementID)
        )
        let unchanged = WorkspaceEqualizePanesTransitionPlanner.plan(
            .init(tabID: equalTab.tabId),
            tabStates: [equalTab],
            activeArrangement: .selected(fixture.customArrangementID)
        )

        // Assert
        #expect(missingTab == .rejected(.missingTab(missingTabID)))
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
            tabStates: [fixture.tabState]
        )

        // Assert
        guard case .changed(let transition) = decision else {
            Issue.record("expected a rename transition")
            return
        }
        #expect(transition.readWitness == .graphOnly)
        #expect(transition.affectedTab.replacement.state.arrangements[0].name == "Default")
        #expect(transition.affectedTab.replacement.state.arrangements[1].name == "Focus")
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
            tabStates: [fixture.tabState]
        )
        let missingArrangement = WorkspaceRenameArrangementTransitionPlanner.plan(
            .init(tabID: fixture.tabState.tabId, arrangementID: missingArrangementID, name: "New"),
            tabStates: [fixture.tabState]
        )
        let defaultRename = WorkspaceRenameArrangementTransitionPlanner.plan(
            .init(tabID: fixture.tabState.tabId, arrangementID: fixture.defaultArrangementID, name: "New"),
            tabStates: [fixture.tabState]
        )
        let empty = WorkspaceRenameArrangementTransitionPlanner.plan(
            .init(tabID: fixture.tabState.tabId, arrangementID: fixture.customArrangementID, name: " \n "),
            tabStates: [fixture.tabState]
        )
        let unchanged = WorkspaceRenameArrangementTransitionPlanner.plan(
            .init(tabID: fixture.tabState.tabId, arrangementID: fixture.customArrangementID, name: " Custom "),
            tabStates: [fixture.tabState]
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
}

struct TabGraphLeafFixture {
    let tabState: TabGraphState
    let defaultArrangementID: UUID
    let customArrangementID: UUID
    let paneIDs: [UUID]
}

func makeTabGraphLeafFixture() -> TabGraphLeafFixture {
    let paneIDs = [UUIDv7.generate(), UUIDv7.generate()]
    let dividerID = UUIDv7.generate()
    let defaultArrangementID = UUIDv7.generate()
    let customArrangementID = UUIDv7.generate()
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
        drawerViews: [:]
    )
    return TabGraphLeafFixture(
        tabState: TabGraphState(
            tabId: UUIDv7.generate(),
            allPaneIds: paneIDs,
            arrangements: [defaultArrangement, customArrangement]
        ),
        defaultArrangementID: defaultArrangementID,
        customArrangementID: customArrangementID,
        paneIDs: paneIDs
    )
}
