import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace pane residency strict planning")
struct WorkspacePaneResidencyStrictPlanningTests {
    @Test("background requires every drawer child to share the exact source owner")
    func backgroundRejectsCrossTabChildOwner() {
        // Arrange
        let fixture = makeResidencyFixture()
        let otherTab = makeOwnershipTab(paneID: fixture.children[0].id)
        var ownership = fixture.ownershipByPaneID
        ownership[fixture.children[0].id] = .owned(otherTab)

        // Act
        let decision = WorkspaceBackgroundPaneTransitionPlanner.plan(
            .init(paneID: fixture.parent.id),
            context: fixture.backgroundContext(ownershipByPaneID: ownership)
        )

        // Assert
        #expect(
            decision
                == .rejected(
                    .paneOwnerMismatch(
                        paneID: fixture.children[0].id,
                        expectedTabID: fixture.tabID,
                        actualTabID: otherTab.state.tabId
                    )
                )
        )
    }

    @Test("reactivate rejects child already present in target membership")
    func reactivateRejectsChildInTarget() {
        // Arrange
        let fixture = makeResidencyFixture(parentResidency: .backgrounded)
        var target = fixture.targetGraphForReactivation()
        target.allPaneIds.append(fixture.children[0].id)

        // Act
        let decision = WorkspaceReactivatePaneTransitionPlanner.plan(
            fixture.reactivateRequest(),
            context: fixture.reactivateContext(targetTab: .present(.init(index: 0, state: target)))
        )

        // Assert
        #expect(
            decision
                == .rejected(
                    .paneAlreadyOwnedByTab(
                        paneID: fixture.children[0].id,
                        tabID: fixture.tabID
                    )
                )
        )
    }

    @Test("reactivate rejects drawer child owned by another tab")
    func reactivateRejectsCrossTabChildOwner() {
        // Arrange
        let fixture = makeResidencyFixture(parentResidency: .backgrounded)
        let otherTab = makeOwnershipTab(paneID: fixture.children[1].id)
        var ownership = Dictionary(
            uniqueKeysWithValues: ([fixture.parent.id] + fixture.children.map(\.id)).map {
                ($0, WorkspacePaneResidencyTabOwnershipWitness.absent)
            }
        )
        ownership[fixture.children[1].id] = .owned(otherTab)

        // Act
        let decision = WorkspaceReactivatePaneTransitionPlanner.plan(
            fixture.reactivateRequest(),
            context: fixture.reactivateContext(ownershipByPaneID: ownership)
        )

        // Assert
        #expect(
            decision
                == .rejected(
                    .paneAlreadyOwnedByTab(
                        paneID: fixture.children[1].id,
                        tabID: otherTab.state.tabId
                    )
                )
        )
    }

    @Test("reactivate rejects retained payload for another drawer")
    func reactivateRejectsWrongDrawerPayload() {
        // Arrange
        let fixture = makeResidencyFixture(parentResidency: .backgrounded)
        let wrongDrawerID = UUIDv7.generate()
        let payload = WorkspaceRetainedDrawerPayloadWitness.present(
            .init(drawerID: wrongDrawerID, viewsByArrangementID: [:])
        )

        // Act
        let decision = WorkspaceReactivatePaneTransitionPlanner.plan(
            fixture.reactivateRequest(),
            context: fixture.reactivateContext(retainedPayload: payload)
        )

        // Assert
        #expect(
            decision
                == .rejected(
                    .retainedDrawerPayloadMismatch(
                        expectedDrawerID: fixture.drawerID,
                        actualDrawerID: wrongDrawerID
                    )
                )
        )
    }

    @Test("reactivate rejects retained view with foreign active child")
    func reactivateRejectsForeignRetainedActiveChild() {
        // Arrange
        let fixture = makeResidencyFixture(parentResidency: .backgrounded)
        var view = DrawerView(
            layout: DrawerGridLayout(topRow: Layout.autoTiled(fixture.children.map(\.id))),
            activeChildId: fixture.children[0].id
        )
        let foreignChildID = UUIDv7.generate()
        view.activeChildId = foreignChildID
        let payload = WorkspaceRetainedDrawerPayloadWitness.present(
            .init(
                drawerID: fixture.drawerID,
                viewsByArrangementID: [fixture.arrangementIDs[0]: view]
            )
        )

        // Act
        let decision = WorkspaceReactivatePaneTransitionPlanner.plan(
            fixture.reactivateRequest(),
            context: fixture.reactivateContext(retainedPayload: payload)
        )

        // Assert
        #expect(
            decision
                == .rejected(
                    .retainedDrawerPayloadInvalidActiveChild(
                        arrangementID: fixture.arrangementIDs[0],
                        activeChildID: foreignChildID
                    )
                )
        )
    }

    @Test("reactivate validates selected and nil active pane cursors against current layouts")
    func reactivateRejectsInvalidCurrentPaneCursors() {
        // Arrange
        let fixture = makeResidencyFixture(parentResidency: .backgrounded)
        var nilCursor = fixture.targetCursorsForReactivation()
        nilCursor = .init(
            activeArrangement: nilCursor.activeArrangement,
            activePanesByArrangementID: [
                fixture.arrangementIDs[0]: .present(.noSelection),
                fixture.arrangementIDs[1]: .present(.selected(fixture.otherPane.id)),
            ],
            activeDrawerChildrenByKey: nilCursor.activeDrawerChildrenByKey,
            zoom: nilCursor.zoom
        )
        let danglingPaneID = UUIDv7.generate()
        let danglingCursor = WorkspacePaneResidencyTabCursorSnapshot(
            activeArrangement: .selected(fixture.arrangementIDs[0]),
            activePanesByArrangementID: [
                fixture.arrangementIDs[0]: .present(.selected(fixture.otherPane.id)),
                fixture.arrangementIDs[1]: .present(.selected(danglingPaneID)),
            ],
            activeDrawerChildrenByKey: [:],
            zoom: .notZoomed
        )

        // Act
        let nilDecision = WorkspaceReactivatePaneTransitionPlanner.plan(
            fixture.reactivateRequest(),
            context: fixture.reactivateContext(targetCursors: nilCursor)
        )
        let danglingDecision = WorkspaceReactivatePaneTransitionPlanner.plan(
            fixture.reactivateRequest(),
            context: fixture.reactivateContext(targetCursors: danglingCursor)
        )

        // Assert
        #expect(nilDecision == .rejected(.paneSelectionInvalid(arrangementID: fixture.arrangementIDs[0])))
        #expect(danglingDecision == .rejected(.paneSelectionInvalid(arrangementID: fixture.arrangementIDs[1])))
    }
}

private func makeOwnershipTab(paneID: UUID) -> WorkspaceIndexedTabGraphState {
    let tabID = UUIDv7.generate()
    let arrangementID = UUIDv7.generate()
    return .init(
        index: 1,
        state: .init(
            tabId: tabID,
            allPaneIds: [paneID],
            arrangements: [
                .init(
                    id: arrangementID,
                    name: "Other",
                    isDefault: true,
                    layout: Layout(paneId: paneID),
                    minimizedPaneIds: [],
                    showsMinimizedPanes: true,
                    drawerViews: [:]
                )
            ]
        )
    )
}
