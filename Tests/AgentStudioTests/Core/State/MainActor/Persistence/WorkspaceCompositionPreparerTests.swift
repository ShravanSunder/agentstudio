import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace composition preparer")
struct WorkspaceCompositionPreparerTests {
    @Test("stale worktree metadata cannot discard composition panes")
    func staleWorktreeMetadataCannotDiscardCompositionPanes() async throws {
        // Arrange
        let staleWorktreeID = UUIDv7.generate()
        let storedText = "frozen-zmx-anchor"
        let zmxSessionID = try #require(ZmxSessionID(restoring: storedText))
        let pane = makeCompositionPane(
            worktreeID: staleWorktreeID,
            zmxSessionID: zmxSessionID
        )
        let tab = makeCompositionTab(paneID: pane.id)
        let snapshot = WorkspaceSQLiteSnapshot(
            id: UUIDv7.generate(),
            name: "Composition",
            panes: [pane],
            tabs: [tab],
            activeTabId: tab.id
        )

        // Act
        // This test deliberately crosses out of inherited MainActor isolation to prove the preparer is Sendable.
        // swiftlint:disable:next no_task_detached
        let result = await Task.detached {
            WorkspaceCompositionPreparer.prepare(snapshot)
        }.value

        // Assert
        let prepared = try requirePreparedComposition(result)
        #expect(prepared.panes.map(\.id) == [pane.id])
        #expect(prepared.panes[0].worktreeId == staleWorktreeID)
        #expect(prepared.panes[0].terminalState?.zmxSessionID.rawValue == storedText)
        #expect(prepared.paneGraph.replacement.paneStates[pane.id] != nil)
        #expect(prepared.tabs.map(\.id) == [tab.id])
        let activation = try #require(prepared.terminalActivationInput.entries.first)
        #expect(activation.paneID.uuid == pane.id)
        #expect(activation.visibilityPriority == .activeVisible)
        #expect(activation.hostPlacement == .tab(tabID: tab.id))
        guard case .zmx(let restoredSessionID) = activation.provider else {
            Issue.record("expected zmx activation backend")
            return
        }
        #expect(restoredSessionID.rawValue == storedText)
        #expect(activation.launchConfiguration.launchDirectory == .stored(URL(filePath: "/tmp/composition")))
        #expect(activation.launchConfiguration.lifetime == .persistent)
    }

    @Test("duplicate composition identities reject off-main before apply")
    func duplicateCompositionIdentitiesRejectOffMainBeforeApply() async {
        // Arrange
        let pane = makeCompositionPane()
        let snapshot = WorkspaceSQLiteSnapshot(
            id: UUIDv7.generate(),
            panes: [pane, pane]
        )

        // Act
        // This test deliberately crosses out of inherited MainActor isolation to prove rejection is prepared off-main.
        // swiftlint:disable:next no_task_detached
        let result = await Task.detached {
            WorkspaceCompositionPreparer.prepare(snapshot)
        }.value

        // Assert
        #expect(result == .rejected(.duplicatePaneID(pane.id)))
    }

    @Test("prepared owner projections match repaired composition")
    func preparedOwnerProjectionsMatchRepairedComposition() throws {
        // Arrange
        let firstPane = makeCompositionPane()
        let secondPane = makeCompositionPane()
        let missingPaneID = UUIDv7.generate()
        var parentPane = firstPane
        parentPane.withDrawer { drawer in
            drawer.paneIds = [secondPane.id, missingPaneID]
            drawer.isExpanded = true
        }
        let tab = makeCompositionTab(
            paneID: parentPane.id,
            allPaneIDs: [parentPane.id, secondPane.id, missingPaneID]
        )
        let snapshot = WorkspaceSQLiteSnapshot(
            id: UUIDv7.generate(),
            name: "Projection",
            panes: [parentPane, secondPane],
            tabs: [tab],
            activeTabId: tab.id,
            sidebarWidth: 333
        )

        // Act
        let prepared = try requirePreparedComposition(
            WorkspaceCompositionPreparer.prepare(snapshot)
        )

        // Assert
        #expect(prepared.identity.workspaceID == snapshot.id)
        #expect(prepared.windowMemory.sidebarWidth == 333)
        #expect(prepared.paneGraph.replacement.paneStates.count == 2)
        #expect(
            prepared.paneGraph.replacement.paneStates[parentPane.id]?.drawer?.paneIds
                == [secondPane.id]
        )
        #expect(prepared.expandedDrawerID == parentPane.drawer?.drawerId)
        #expect(prepared.tabShells.shells.map(\.id) == prepared.tabs.map(\.id))
        #expect(prepared.tabShells.indexByID[tab.id] == 0)
        #expect(prepared.tabGraph.states.map(\.tabId) == prepared.tabs.map(\.id))
        #expect(prepared.tabGraph.indexByID[tab.id] == 0)
        #expect(prepared.arrangementCursors.activeArrangementIDsByTabID[tab.id] == tab.activeArrangementId)
    }
}

private enum WorkspaceCompositionPreparerTestError: Error {
    case preparationRejected
}

private func requirePreparedComposition(
    _ result: WorkspaceCompositionPreparationResult
) throws -> PreparedWorkspaceComposition {
    guard case .prepared(let prepared) = result else {
        throw WorkspaceCompositionPreparerTestError.preparationRejected
    }
    return prepared
}

private func makeCompositionPane(
    id: UUID = UUIDv7.generate(),
    worktreeID: UUID? = nil,
    zmxSessionID: ZmxSessionID = .generateUUIDv7()
) -> Pane {
    Pane(
        id: id,
        content: .terminal(
            TerminalState(
                provider: .zmx,
                lifetime: .persistent,
                zmxSessionID: zmxSessionID
            )),
        metadata: PaneMetadata(
            launchDirectory: URL(filePath: "/tmp/composition"),
            title: "Terminal",
            facets: PaneContextFacets(worktreeId: worktreeID)
        )
    )
}

private func makeCompositionTab(
    paneID: UUID,
    allPaneIDs: [UUID]? = nil
) -> Tab {
    let arrangement = PaneArrangement(
        id: UUIDv7.generate(),
        name: "Default",
        isDefault: true,
        layout: Layout(paneId: paneID),
        activePaneId: paneID
    )
    return Tab(
        id: UUIDv7.generate(),
        name: "Tab",
        allPaneIds: allPaneIDs ?? [paneID],
        arrangements: [arrangement],
        activeArrangementId: arrangement.id
    )
}
