import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace pane residency stale owner rejection")
struct WorkspacePaneResidencyStaleOwnerTests {
    @Test("rejects stale tab graph before mutation")
    func rejectsStaleTabGraph() throws {
        // Arrange
        let fixture = makeResidencyFixture()
        let transition = try requireBackgroundTransitionForApplier(fixture)
        let atoms = try makeResidencyAtoms(fixture, graph: fixture.tabState)
        var staleGraph = fixture.tabState
        staleGraph.arrangements[0].name = "External"
        atoms.graph.replaceTabStatePreservingIdentity(staleGraph)

        // Act
        let result = makeResidencyApplier(atoms).apply(
            .background(transition),
            retainedDrawerPayload: .absent
        )

        // Assert
        guard case .rejected(.staleTabGraph) = result else {
            Issue.record("expected stale tab graph rejection")
            return
        }
        #expect(atoms.panes.paneState(fixture.parent.id)?.residency == .active)
        #expect(atoms.graph.tabState(fixture.tabID) == staleGraph)
    }

    @Test("rejects stale tab cursor before last-tab removal")
    func rejectsStaleTabCursor() throws {
        // Arrange
        let fixture = makeResidencyFixture(includeOtherPane: false)
        let transition = try makeLastTabBackgroundTransition(fixture)
        let atoms = try makeResidencyAtoms(fixture, graph: fixture.tabState)
        let staleTabID = UUIDv7.generate()
        atoms.tabCursor.replaceActiveTab(staleTabID)

        // Act
        let result = makeResidencyApplier(atoms).apply(
            .background(transition),
            retainedDrawerPayload: .absent
        )

        // Assert
        #expect(
            result
                == .rejected(
                    .staleTabCursor(
                        expected: .selected(fixture.tabID),
                        actual: .selected(staleTabID)
                    )
                )
        )
        #expect(atoms.shells.tabShells.count == 1)
        #expect(atoms.graph.tabState(fixture.tabID) == fixture.tabState)
    }

    @Test("rejects stale active arrangement active pane drawer cursor and zoom")
    func rejectsEachStaleCursorOwner() throws {
        // Arrange
        let fixture = makeResidencyFixture()
        let transition = try requireBackgroundTransitionForApplier(fixture)
        let arrangementAtoms = try makeResidencyAtoms(fixture, graph: fixture.tabState)
        let paneAtoms = try makeResidencyAtoms(fixture, graph: fixture.tabState)
        let drawerAtoms = try makeResidencyAtoms(fixture, graph: fixture.tabState)
        let zoomAtoms = try makeResidencyAtoms(fixture, graph: fixture.tabState)
        arrangementAtoms.cursors.setActiveArrangementId(UUIDv7.generate(), forTab: fixture.tabID)
        paneAtoms.cursors.setPaneCursor(
            .init(activePaneId: fixture.otherPane.id),
            forArrangement: fixture.arrangementIDs[0]
        )
        let drawerKey = ArrangementDrawerCursorKey(
            arrangementId: fixture.arrangementIDs[0],
            drawerId: fixture.drawerID
        )
        drawerAtoms.cursors.setDrawerCursor(
            .init(activeChildId: fixture.children[1].id),
            for: drawerKey
        )
        zoomAtoms.presentation.setZoomedPaneId(fixture.otherPane.id, forTab: fixture.tabID)

        // Act
        let arrangementResult = makeResidencyApplier(arrangementAtoms).apply(
            .background(transition), retainedDrawerPayload: .absent
        )
        let paneResult = makeResidencyApplier(paneAtoms).apply(
            .background(transition), retainedDrawerPayload: .absent
        )
        let drawerResult = makeResidencyApplier(drawerAtoms).apply(
            .background(transition), retainedDrawerPayload: .absent
        )
        let zoomResult = makeResidencyApplier(zoomAtoms).apply(
            .background(transition), retainedDrawerPayload: .absent
        )

        // Assert
        guard case .rejected(.staleActiveArrangement) = arrangementResult else {
            Issue.record("expected stale active arrangement")
            return
        }
        guard case .rejected(.staleActivePane) = paneResult else {
            Issue.record("expected stale active pane")
            return
        }
        guard case .rejected(.staleActiveDrawerChild) = drawerResult else {
            Issue.record("expected stale drawer cursor")
            return
        }
        guard case .rejected(.staleZoom) = zoomResult else {
            Issue.record("expected stale zoom")
            return
        }
        #expect(arrangementAtoms.panes.paneState(fixture.parent.id)?.residency == .active)
        #expect(paneAtoms.graph.tabState(fixture.tabID) == fixture.tabState)
        #expect(drawerAtoms.presentation.zoomedPaneId(forTab: fixture.tabID) == fixture.parent.id)
    }

    @Test("rejects drawer child ownership change after planning without transition mutation")
    func rejectsStalePaneFamilyOwnership() throws {
        // Arrange
        let fixture = makeResidencyFixture()
        let transition = try requireBackgroundTransitionForApplier(fixture)
        let atoms = try makeResidencyAtoms(fixture, graph: fixture.tabState)
        let movedChildID = fixture.children[0].id
        var changedSource = fixture.tabState
        changedSource.allPaneIds.removeAll { $0 == movedChildID }
        atoms.graph.replaceTabStateAndOwnership(changedSource)
        let otherOwner = makeStaleOwnerGraph(paneID: movedChildID)
        atoms.graph.insertTabState(otherOwner, at: 1)

        // Act
        let result = makeResidencyApplier(atoms).apply(
            .background(transition),
            retainedDrawerPayload: .absent
        )

        // Assert
        guard case .rejected(.stalePaneFamilyOwnership(let paneID, _, _)) = result else {
            Issue.record("expected stale family ownership rejection")
            return
        }
        #expect(paneID == movedChildID)
        #expect(atoms.panes.paneState(fixture.parent.id)?.residency == .active)
        #expect(atoms.graph.tabState(fixture.tabID) == changedSource)
        #expect(atoms.graph.tabState(otherOwner.tabId) == otherOwner)
    }

    @Test("prepared apply requires a fresh live runtime payload witness")
    func preparedApplyRejectsChangedRuntimePayload() throws {
        // Arrange
        let fixture = makeResidencyFixture()
        let transition = try requireBackgroundTransitionForApplier(fixture)
        let atoms = try makeResidencyAtoms(fixture, graph: fixture.tabState)
        let applier = makeResidencyApplier(atoms)
        guard
            case .ready(let prepared) = applier.preflight(
                .background(transition), retainedDrawerPayload: .absent
            )
        else {
            Issue.record("expected prepared transition")
            return
        }
        let changedPayload = WorkspaceRetainedDrawerPayloadWitness.present(
            .init(drawerID: fixture.drawerID, viewsByArrangementID: [:])
        )

        // Act
        let result = applier.apply(prepared, retainedDrawerPayload: changedPayload)

        // Assert
        #expect(
            result
                == .rejected(
                    .staleRetainedDrawerPayload(
                        expected: .absent,
                        actual: changedPayload
                    )
                )
        )
        #expect(atoms.panes.paneState(fixture.parent.id)?.residency == .active)
        #expect(atoms.graph.tabState(fixture.tabID) == fixture.tabState)
    }

    @Test("shell delta ignores unrelated prefix value but rejects removed or suffix changes")
    func exactShellRemovalDelta() throws {
        // Arrange
        let fixture = makeResidencyFixture(includeOtherPane: false)
        let prefixID = UUIDv7.generate()
        let suffixID = UUIDv7.generate()
        let shells = [
            TabShell(id: prefixID, name: "Prefix"),
            TabShell(id: fixture.tabID, name: "Target"),
            TabShell(id: suffixID, name: "Suffix"),
        ]
        let transition = try makeLastTabBackgroundTransition(fixture, shells: shells)
        let prefixAtoms = try makeResidencyAtoms(fixture, graph: fixture.tabState)
        prefixAtoms.shells.replaceTabShells(shells)
        prefixAtoms.shells.renameTab(prefixID, name: "Renamed Prefix")
        let suffixAtoms = try makeResidencyAtoms(fixture, graph: fixture.tabState)
        suffixAtoms.shells.replaceTabShells(shells)
        suffixAtoms.shells.renameTab(suffixID, name: "Renamed Suffix")
        let removedAtoms = try makeResidencyAtoms(fixture, graph: fixture.tabState)
        removedAtoms.shells.replaceTabShells(shells)
        removedAtoms.shells.renameTab(fixture.tabID, name: "Renamed Target")

        // Act
        let prefixResult = makeResidencyApplier(prefixAtoms).apply(
            .background(transition), retainedDrawerPayload: .absent
        )
        let suffixResult = makeResidencyApplier(suffixAtoms).apply(
            .background(transition), retainedDrawerPayload: .absent
        )
        let removedResult = makeResidencyApplier(removedAtoms).apply(
            .background(transition), retainedDrawerPayload: .absent
        )

        // Assert
        guard case .applied = prefixResult else {
            Issue.record("unrelated prefix rename should not stale exact removal")
            return
        }
        guard case .rejected(.staleTabShellRemoval) = suffixResult else {
            Issue.record("expected stale shifted suffix rejection")
            return
        }
        guard case .rejected(.staleTabShellRemoval) = removedResult else {
            Issue.record("expected stale removed shell rejection")
            return
        }
        #expect(prefixAtoms.shells.tabShells.map(\.id) == [prefixID, suffixID])
        #expect(suffixAtoms.panes.paneState(fixture.parent.id)?.residency == .active)
    }

    @Test("residency apply preserves pane content metadata and placement identity")
    func residencyAssignmentPreservesAllOtherPaneState() throws {
        // Arrange
        let fixture = makeResidencyFixture()
        let transition = try requireBackgroundTransitionForApplier(fixture)
        let atoms = try makeResidencyAtoms(fixture, graph: fixture.tabState)
        let previous = try #require(atoms.panes.paneState(fixture.parent.id))

        // Act
        let result = makeResidencyApplier(atoms).apply(
            .background(transition), retainedDrawerPayload: .absent
        )

        // Assert
        guard case .applied = result else {
            Issue.record("expected applied transition")
            return
        }
        let replacement = try #require(atoms.panes.paneState(fixture.parent.id))
        #expect(replacement.content == previous.content)
        #expect(replacement.metadata == previous.metadata)
        #expect(replacement.kind == previous.kind)
        #expect(replacement.id == previous.id)
        #expect(replacement.residency == .backgrounded)
    }
}

private func makeLastTabBackgroundTransition(
    _ fixture: PaneResidencyFixture,
    shells: [TabShell]? = nil
) throws -> WorkspaceBackgroundPaneTransition {
    let base = fixture.backgroundContext()
    let exactShells = shells ?? [TabShell(id: fixture.tabID, name: "Target")]
    let context = WorkspaceBackgroundPanePlanningContext(
        pane: base.pane,
        declaredDrawerChildrenByID: base.declaredDrawerChildrenByID,
        ownershipByPaneID: base.ownershipByPaneID,
        tabCursors: base.tabCursors,
        tabRemoval: .current(tabShells: exactShells, activeTab: .selected(fixture.tabID)),
        retainedDrawerPayload: .absent
    )
    return try requireBackgroundTransitionForApplier(fixture, context: context)
}

private func makeStaleOwnerGraph(paneID: UUID) -> TabGraphState {
    let tabID = UUIDv7.generate()
    return .init(
        tabId: tabID,
        allPaneIds: [paneID],
        arrangements: [
            .init(
                id: UUIDv7.generate(),
                name: "Other",
                isDefault: true,
                layout: Layout(paneId: paneID),
                minimizedPaneIds: [],
                showsMinimizedPanes: true,
                drawerViews: [:]
            )
        ]
    )
}
