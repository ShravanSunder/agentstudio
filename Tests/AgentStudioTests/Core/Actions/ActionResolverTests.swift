import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class WorkspaceCommandResolverTests {

    // MARK: - Test Helpers

    private func makeSnapshot(
        tabs: [TabSnapshot] = [],
        activeTabId: UUID? = nil
    ) -> ActionStateSnapshot {
        ActionStateSnapshot(
            tabs: tabs,
            activeTabId: activeTabId,
            isManagementLayerActive: false
        )
    }

    private func makeSinglePaneTab(tabId: UUID = UUID(), paneId: UUID = UUIDv7.generate()) -> TabSnapshot {
        TabSnapshot(id: tabId, visiblePaneIds: [paneId], ownedPaneIds: [paneId], activePaneId: paneId)
    }

    private func makeMultiPaneTab(tabId: UUID = UUID(), paneIds: [UUID]? = nil) -> TabSnapshot {
        let ids = paneIds ?? [UUIDv7.generate(), UUIDv7.generate()]
        return TabSnapshot(id: tabId, visiblePaneIds: ids, ownedPaneIds: ids, activePaneId: ids.first)
    }

    // MARK: - existingTabForWorktree

    @Test

    func test_existingTabForWorktree_returnsFirstTabOwningMatchingWorktreePane() {
        // Arrange
        let targetWorktreeId = UUID()
        let firstMatchingTabId = UUID()
        let secondMatchingTabId = UUID()
        let firstPaneId = UUID()
        let secondPaneId = UUID()
        let tabs = [
            MockTab(id: firstMatchingTabId, activePaneId: firstPaneId, allPaneIds: [firstPaneId]),
            MockTab(id: secondMatchingTabId, activePaneId: secondPaneId, allPaneIds: [secondPaneId]),
        ]
        let paneWorktreeIdsByPaneId = [
            firstPaneId: targetWorktreeId,
            secondPaneId: targetWorktreeId,
        ]

        // Act
        let result = WorkspaceCommandResolver.existingTabForWorktree(
            targetWorktreeId,
            in: tabs,
            worktreeIdForPane: { paneWorktreeIdsByPaneId[$0] }
        )

        // Assert
        #expect(result == firstMatchingTabId)
    }

    @Test

    func test_existingTabForWorktree_searchesOwnedPanesNotOnlyVisiblePanes() {
        // Arrange
        let targetWorktreeId = UUID()
        let tabId = UUID()
        let visiblePaneId = UUID()
        let hiddenArrangementPaneId = UUID()
        let tab = MockTab(
            id: tabId,
            activePaneId: visiblePaneId,
            allPaneIds: [visiblePaneId],
            ownedPaneIds: [visiblePaneId, hiddenArrangementPaneId]
        )
        let paneWorktreeIdsByPaneId = [hiddenArrangementPaneId: targetWorktreeId]

        // Act
        let result = WorkspaceCommandResolver.existingTabForWorktree(
            targetWorktreeId,
            in: [tab],
            worktreeIdForPane: { paneWorktreeIdsByPaneId[$0] }
        )

        // Assert
        #expect(result == tabId)
    }

    @Test

    func test_existingTabForWorktree_returnsNilWhenNoOwnedPaneMatches() {
        // Arrange
        let targetWorktreeId = UUID()
        let otherWorktreeId = UUID()
        let paneId = UUID()
        let tab = MockTab(id: UUID(), activePaneId: paneId, allPaneIds: [paneId])
        let paneWorktreeIdsByPaneId = [paneId: otherWorktreeId]

        // Act
        let result = WorkspaceCommandResolver.existingTabForWorktree(
            targetWorktreeId,
            in: [tab],
            worktreeIdForPane: { paneWorktreeIdsByPaneId[$0] }
        )

        // Assert
        #expect(result == nil)
    }

    // MARK: - resolveDrop: Tab payloads are rejected for split targets

    @Test

    func test_resolveDrop_multiPaneTab_returnsNil() {
        // Arrange
        let sourceTabId = UUID()
        let targetTabId = UUID()
        let targetPaneId = UUID()
        let sourceTab = makeMultiPaneTab(tabId: sourceTabId)
        let targetTab = makeSinglePaneTab(tabId: targetTabId, paneId: targetPaneId)
        let snapshot = makeSnapshot(tabs: [sourceTab, targetTab])
        let payload = SplitDropPayload(
            kind: .existingTab(
                tabId: sourceTabId
            ))

        // Act
        let result = WorkspaceCommandResolver.resolveDrop(
            payload: payload,
            destinationPaneId: targetPaneId,
            destinationTabId: targetTabId,
            zone: DropZoneSide.right,
            sizingMode: DropSizingMode.halveTarget,
            state: snapshot
        )

        // Assert
        #expect(result == nil)
    }

    // MARK: - resolveDrop: Single-pane tab rejected for split targets

    @Test

    func test_resolveDrop_singlePaneTab_returnsNil() {
        // Arrange
        let sourceTabId = UUID()
        let sourcePaneId = UUID()
        let targetTabId = UUID()
        let targetPaneId = UUID()
        let sourceTab = makeSinglePaneTab(tabId: sourceTabId, paneId: sourcePaneId)
        let targetTab = makeSinglePaneTab(tabId: targetTabId, paneId: targetPaneId)
        let snapshot = makeSnapshot(tabs: [sourceTab, targetTab])
        let payload = SplitDropPayload(
            kind: .existingTab(
                tabId: sourceTabId
            ))

        // Act
        let result = WorkspaceCommandResolver.resolveDrop(
            payload: payload,
            destinationPaneId: targetPaneId,
            destinationTabId: targetTabId,
            zone: DropZoneSide.left,
            sizingMode: DropSizingMode.halveTarget,
            state: snapshot
        )

        // Assert
        #expect(result == nil)
    }

    // MARK: - resolveDrop: New terminal → insertPane

    @Test

    func test_resolveDrop_newTerminal_returnsInsertPane() {
        // Arrange
        let targetTabId = UUID()
        let targetPaneId = UUID()
        let targetTab = makeSinglePaneTab(tabId: targetTabId, paneId: targetPaneId)
        let snapshot = makeSnapshot(tabs: [targetTab])
        let payload = SplitDropPayload(kind: .newTerminal)

        // Act
        let result = WorkspaceCommandResolver.resolveDrop(
            payload: payload,
            destinationPaneId: targetPaneId,
            destinationTabId: targetTabId,
            zone: DropZoneSide.right,
            sizingMode: DropSizingMode.halveTarget,
            state: snapshot
        )

        // Assert
        #expect(
            result
                == PaneActionCommand.insertPane(
                    source: PaneSource.newTerminal,
                    targetTabId: targetTabId,
                    targetPaneId: targetPaneId,
                    direction: SplitNewDirection.right,
                    sizingMode: DropSizingMode.halveTarget
                ))
    }

    // MARK: - resolveDrop: Cross-tab pane move

    @Test

    func test_resolveDrop_existingPaneAcrossTabs_returnsMovePaneAcrossTabs() {
        // Arrange
        let sourceTabId = UUID()
        let sourcePaneId = UUID()
        let targetTabId = UUID()
        let targetPaneId = UUID()
        let sourceTab = makeSinglePaneTab(tabId: sourceTabId, paneId: sourcePaneId)
        let targetTab = makeSinglePaneTab(tabId: targetTabId, paneId: targetPaneId)
        let snapshot = makeSnapshot(tabs: [sourceTab, targetTab])
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId))

        // Act
        let result = WorkspaceCommandResolver.resolveDrop(
            payload: payload,
            destinationPaneId: targetPaneId,
            destinationTabId: targetTabId,
            zone: DropZoneSide.right,
            sizingMode: DropSizingMode.halveTarget,
            state: snapshot
        )

        // Assert
        #expect(
            result
                == .movePaneAcrossTabs(
                    CrossTabPaneMoveRequest(
                        paneId: sourcePaneId,
                        sourceTabId: sourceTabId,
                        destTabId: targetTabId,
                        targetPaneId: targetPaneId,
                        direction: .horizontal,
                        position: .after
                    )
                )
        )
    }

    // MARK: - resolveDrop: Source tab not found → nil

    @Test

    func test_resolveDrop_sourceTabNotFound_returnsNil() {
        // Arrange
        let targetTabId = UUID()
        let targetPaneId = UUID()
        let targetTab = makeSinglePaneTab(tabId: targetTabId, paneId: targetPaneId)
        let snapshot = makeSnapshot(tabs: [targetTab])
        let payload = SplitDropPayload(
            kind: .existingTab(
                tabId: UUID()
            ))

        // Act
        let result = WorkspaceCommandResolver.resolveDrop(
            payload: payload,
            destinationPaneId: targetPaneId,
            destinationTabId: targetTabId,
            zone: DropZoneSide.right,
            sizingMode: DropSizingMode.halveTarget,
            state: snapshot
        )

        // Assert
        #expect((result) == nil)
    }

    // MARK: - resolveDrop: Self tab payload rejected before validation

    @Test

    func test_resolveDrop_selfDrop_multiPane_returnsNil() {
        // Arrange — dropping a multi-pane tab onto its own pane
        let tabId = UUID()
        let paneIds = [UUID(), UUID()]
        let tab = makeMultiPaneTab(tabId: tabId, paneIds: paneIds)
        let snapshot = makeSnapshot(tabs: [tab])
        let payload = SplitDropPayload(
            kind: .existingTab(
                tabId: tabId
            ))

        // Act
        let result = WorkspaceCommandResolver.resolveDrop(
            payload: payload,
            destinationPaneId: paneIds[0],
            destinationTabId: tabId,
            zone: DropZoneSide.right,
            sizingMode: DropSizingMode.halveTarget,
            state: snapshot
        )

        // Assert
        #expect(result == nil)
    }

    // MARK: - resolve(command:) — Tab Lifecycle

    @Test

    func test_resolve_closeTab_returnsCloseTabWithActiveId() {
        // Arrange
        let tabId = UUID()
        let paneId = UUID()
        let tab = MockTab(id: tabId, activePaneId: paneId, allPaneIds: [paneId])

        // Act
        let result = WorkspaceCommandResolver.resolve(command: .closeTab, tabs: [tab], activeTabId: tabId)

        // Assert
        #expect(result == .closeTab(tabId: tabId))
    }

    @Test

    func test_resolve_breakUpTab_returnsBreakUpTabWithActiveId() {
        // Arrange
        let tabId = UUID()
        let paneId = UUID()
        let tab = MockTab(id: tabId, activePaneId: paneId, allPaneIds: [paneId])

        // Act
        let result = WorkspaceCommandResolver.resolve(command: .breakUpTab, tabs: [tab], activeTabId: tabId)

        // Assert
        #expect(result == .breakUpTab(tabId: tabId))
    }

    @Test

    func test_resolve_nextTab_wrapsAround() {
        // Arrange
        let tab1Id = UUID()
        let tab2Id = UUID()
        let tab1 = MockTab(id: tab1Id, activePaneId: UUID(), allPaneIds: [UUID()])
        let tab2 = MockTab(id: tab2Id, activePaneId: UUID(), allPaneIds: [UUID()])

        // Act — from last tab wraps to first
        let result = WorkspaceCommandResolver.resolve(
            command: .nextTab, tabs: [tab1, tab2], activeTabId: tab2Id
        )

        // Assert
        #expect(result == .selectTab(tabId: tab1Id))
    }

    @Test

    func test_resolve_prevTab_wrapsAround() {
        // Arrange
        let tab1Id = UUID()
        let tab2Id = UUID()
        let tab1 = MockTab(id: tab1Id, activePaneId: UUID(), allPaneIds: [UUID()])
        let tab2 = MockTab(id: tab2Id, activePaneId: UUID(), allPaneIds: [UUID()])

        // Act — from first tab wraps to last
        let result = WorkspaceCommandResolver.resolve(
            command: .prevTab, tabs: [tab1, tab2], activeTabId: tab1Id
        )

        // Assert
        #expect(result == .selectTab(tabId: tab2Id))
    }

    @Test

    func test_resolve_selectTabByIndex_returnsCorrectTab() {
        // Arrange
        let tab1Id = UUID()
        let tab2Id = UUID()
        let tab3Id = UUID()
        let tab1 = MockTab(id: tab1Id, activePaneId: UUID(), allPaneIds: [UUID()])
        let tab2 = MockTab(id: tab2Id, activePaneId: UUID(), allPaneIds: [UUID()])
        let tab3 = MockTab(id: tab3Id, activePaneId: UUID(), allPaneIds: [UUID()])
        let tabs = [tab1, tab2, tab3]

        // Act & Assert
        #expect(
            WorkspaceCommandResolver.resolve(command: .selectTab1, tabs: tabs, activeTabId: nil)
                == .selectTab(tabId: tab1Id))
        #expect(
            WorkspaceCommandResolver.resolve(command: .selectTab3, tabs: tabs, activeTabId: nil)
                == .selectTab(tabId: tab3Id))
        // Out of range
        #expect((WorkspaceCommandResolver.resolve(command: .selectTab4, tabs: tabs, activeTabId: nil)) == nil)
    }

    // MARK: - resolve(command:) — Pane Lifecycle

    @Test

    func test_resolve_closePane_singlePaneEscalatesToCloseTab() {
        // Arrange
        let tabId = UUID()
        let paneId = UUID()
        let tab = MockTab(id: tabId, activePaneId: paneId, allPaneIds: [paneId])

        // Act
        let result = WorkspaceCommandResolver.resolve(command: .closePane, tabs: [tab], activeTabId: tabId)

        // Assert
        #expect(result == .closeTab(tabId: tabId))
    }

    @Test

    func test_resolve_closePane_splitTabReturnsClosePane() {
        // Arrange
        let tabId = UUID()
        let paneA = UUIDv7.generate()
        let paneB = UUIDv7.generate()
        let tab = MockTab(id: tabId, activePaneId: paneA, allPaneIds: [paneA, paneB])

        // Act
        let result = WorkspaceCommandResolver.resolve(command: .closePane, tabs: [tab], activeTabId: tabId)

        // Assert
        #expect(result == .closePane(tabId: tabId, paneId: paneA))
    }

    @Test
    func test_resolve_closePane_usesProvidedVisiblePaneIds() {
        // Arrange
        let tabId = UUID()
        let paneA = UUIDv7.generate()
        let paneB = UUIDv7.generate()
        let tab = MockTab(id: tabId, activePaneId: paneA, allPaneIds: [paneA, paneB])

        // Act
        let result = WorkspaceCommandResolver.resolve(
            command: .closePane,
            tabs: [tab],
            activeTabId: tabId,
            visiblePaneIds: { _ in [paneA] }
        )

        // Assert
        #expect(result == .closeTab(tabId: tabId))
    }

    @Test

    func test_resolve_extractPaneToTab_returnsExtractWithActivePane() {
        // Arrange
        let tabId = UUID()
        let paneId = UUID()
        let tab = MockTab(id: tabId, activePaneId: paneId, allPaneIds: [paneId])

        // Act
        let result = WorkspaceCommandResolver.resolve(
            command: .extractPaneToTab, tabs: [tab], activeTabId: tabId
        )

        // Assert
        #expect(result == .extractPaneToTab(tabId: tabId, paneId: paneId))
    }

    @Test

    func test_resolve_equalizePanes_returnsEqualizeWithActiveTab() {
        // Arrange
        let tabId = UUID()
        let tab = MockTab(id: tabId, activePaneId: UUID(), allPaneIds: [UUID()])

        // Act
        let result = WorkspaceCommandResolver.resolve(
            command: .equalizePanes, tabs: [tab], activeTabId: tabId
        )

        // Assert
        #expect(result == .equalizePanes(tabId: tabId))
    }

    @Test
    func test_resolve_scrollToBottom_returnsActionWithActivePane() {
        // Arrange
        let tabId = UUID()
        let paneId = UUIDv7.generate()
        let tab = MockTab(id: tabId, activePaneId: paneId, allPaneIds: [paneId])

        // Act
        let result = WorkspaceCommandResolver.resolve(
            command: .scrollToBottom,
            tabs: [tab],
            activeTabId: tabId
        )

        // Assert
        #expect(result == .scrollToBottom(tabId: tabId, paneId: paneId))
    }

    // MARK: - resolve(command:) — Pane Focus

    @Test

    func test_resolve_focusPaneLeft_findsNeighbor() {
        // Arrange
        let tabId = UUID()
        let paneA = UUID()
        let paneB = UUID()
        var tab = MockTab(id: tabId, activePaneId: paneA, allPaneIds: [paneA, paneB])
        tab.neighbors = [paneA: [.left: paneB]]

        // Act
        let result = WorkspaceCommandResolver.resolve(
            command: .focusPaneLeft, tabs: [tab], activeTabId: tabId
        )

        // Assert — pane focus now routes through the Pane Focus System, not PaneActionCommand.
        #expect(result == nil)
    }

    @Test

    func test_resolve_focusPaneRight_noNeighbor_returnsNil() {
        // Arrange
        let tabId = UUID()
        let paneA = UUID()
        let tab = MockTab(id: tabId, activePaneId: paneA, allPaneIds: [paneA])
        // No neighbors configured

        // Act
        let result = WorkspaceCommandResolver.resolve(
            command: .focusPaneRight, tabs: [tab], activeTabId: tabId
        )

        // Assert
        #expect((result) == nil)
    }

    @Test

    func test_resolve_focusNextPane_usesNextPaneId() {
        // Arrange
        let tabId = UUID()
        let paneA = UUID()
        let paneB = UUID()
        var tab = MockTab(id: tabId, activePaneId: paneA, allPaneIds: [paneA, paneB])
        tab.nextPanes = [paneA: paneB]

        // Act
        let result = WorkspaceCommandResolver.resolve(
            command: .focusNextPane, tabs: [tab], activeTabId: tabId
        )

        // Assert — pane focus now routes through the Pane Focus System, not PaneActionCommand.
        #expect(result == nil)
    }

    @Test

    func test_resolve_focusPrevPane_usesPreviousPaneId() {
        // Arrange
        let tabId = UUID()
        let paneA = UUID()
        let paneB = UUID()
        var tab = MockTab(id: tabId, activePaneId: paneB, allPaneIds: [paneA, paneB])
        tab.previousPanes = [paneB: paneA]

        // Act
        let result = WorkspaceCommandResolver.resolve(
            command: .focusPrevPane, tabs: [tab], activeTabId: tabId
        )

        // Assert — pane focus now routes through the Pane Focus System, not PaneActionCommand.
        #expect(result == nil)
    }

    // MARK: - resolve(command:) — Split

    @Test

    func test_resolve_splitRight_returnsInsertPane() {
        // Arrange
        let tabId = UUID()
        let paneId = UUID()
        let tab = MockTab(id: tabId, activePaneId: paneId, allPaneIds: [paneId])

        // Act
        let result = WorkspaceCommandResolver.resolve(
            command: .splitRight, tabs: [tab], activeTabId: tabId
        )

        // Assert
        #expect(
            result
                == .insertPane(
                    source: PaneSource.newTerminal,
                    targetTabId: tabId,
                    targetPaneId: paneId,
                    direction: SplitNewDirection.right,
                    sizingMode: DropSizingMode.halveTarget
                ))
    }

    // MARK: - resolve(command:) — Edge Cases

    @Test

    func test_resolve_noActiveTab_returnsNil() {
        // Arrange
        let tab = MockTab(id: UUID(), activePaneId: UUID(), allPaneIds: [UUID()])

        // Act & Assert — all commands requiring activeTabId return nil
        #expect((WorkspaceCommandResolver.resolve(command: .closeTab, tabs: [tab], activeTabId: nil)) == nil)
        #expect((WorkspaceCommandResolver.resolve(command: .closePane, tabs: [tab], activeTabId: nil)) == nil)
        #expect((WorkspaceCommandResolver.resolve(command: .splitRight, tabs: [tab], activeTabId: nil)) == nil)
        #expect((WorkspaceCommandResolver.resolve(command: .focusPaneLeft, tabs: [tab], activeTabId: nil)) == nil)
    }

    @Test

    func test_resolve_nonPaneCommand_returnsNil() {
        // Arrange
        let tabId = UUID()
        let tab = MockTab(id: tabId, activePaneId: UUID(), allPaneIds: [UUID()])

        // Act & Assert — non-structural commands return nil
        #expect((WorkspaceCommandResolver.resolve(command: .watchFolder, tabs: [tab], activeTabId: tabId)) == nil)
        #expect(
            (WorkspaceCommandResolver.resolve(
                command: .toggleSidebar, tabs: [tab], activeTabId: tabId
            )) == nil)
        #expect(
            (WorkspaceCommandResolver.resolve(
                command: .newFloatingTerminal, tabs: [tab], activeTabId: tabId
            )) == nil)
        #expect(
            (WorkspaceCommandResolver.resolve(
                command: .filterSidebar, tabs: [tab], activeTabId: tabId
            )) == nil)
        #expect(
            (WorkspaceCommandResolver.resolve(
                command: .openPaneLocationInBookmarkedEditor, tabs: [tab], activeTabId: tabId
            )) == nil)
        #expect(
            (WorkspaceCommandResolver.resolve(
                command: .openPaneLocationInFinder, tabs: [tab], activeTabId: tabId
            )) == nil)
        #expect(
            (WorkspaceCommandResolver.resolve(
                command: .openPaneLocationInEditorMenu, tabs: [tab], activeTabId: tabId
            )) == nil)
        #expect(
            (WorkspaceCommandResolver.resolve(
                command: .openNewTerminalInTab, tabs: [tab], activeTabId: tabId
            )) == nil)
        // Webview/OAuth commands are non-pane commands
        #expect(
            (WorkspaceCommandResolver.resolve(
                command: .openWebview, tabs: [tab], activeTabId: tabId
            )) == nil)
        #expect(
            (WorkspaceCommandResolver.resolve(
                command: .signInGitHub, tabs: [tab], activeTabId: tabId
            )) == nil)
        #expect(
            (WorkspaceCommandResolver.resolve(
                command: .signInGoogle, tabs: [tab], activeTabId: tabId
            )) == nil)
    }

    @Test

    func test_resolve_noActivePaneId_returnsNil() {
        // Arrange — tab exists but has no activePaneId
        let tabId = UUID()
        let tab = MockTab(id: tabId, activePaneId: nil, allPaneIds: [UUID()])

        // Act & Assert — commands needing active pane return nil
        #expect((WorkspaceCommandResolver.resolve(command: .closePane, tabs: [tab], activeTabId: tabId)) == nil)
        #expect((WorkspaceCommandResolver.resolve(command: .splitRight, tabs: [tab], activeTabId: tabId)) == nil)
    }

    // MARK: - snapshot(from:) with MockTab

    @Test

    func test_snapshot_fromMockTabs_capturesCorrectState() {
        // Arrange
        let tab1Id = UUID()
        let tab2Id = UUID()
        let pane1 = UUID()
        let pane2a = UUID()
        let pane2b = UUID()
        let tab1 = MockTab(id: tab1Id, activePaneId: pane1, allPaneIds: [pane1])
        let tab2 = MockTab(id: tab2Id, activePaneId: pane2a, allPaneIds: [pane2a, pane2b])

        // Act
        let snapshot = WorkspaceCommandResolver.snapshot(
            from: [tab1, tab2], activeTabId: tab1Id, isManagementLayerActive: false
        )

        // Assert
        #expect(snapshot.tabCount == 2)
        #expect(snapshot.activeTabId == tab1Id)
        #expect(snapshot.tab(tab1Id)?.visiblePaneIds == [pane1])
        #expect(snapshot.tab(tab2Id)?.visiblePaneIds == [pane2a, pane2b])
        #expect(snapshot.tab(tab2Id)?.activePaneId == pane2a)
        #expect(snapshot.tab(tab2Id)?.isSplit == true)
        #expect(!(snapshot.tab(tab1Id)?.isSplit == true))
    }

    @Test

    func test_snapshot_usesDerivedVisiblePaneIdsWhenProvided() {
        let tabId = UUID()
        let paneA = UUID()
        let paneB = UUID()
        let tab = MockTab(id: tabId, activePaneId: paneA, allPaneIds: [paneA, paneB])

        let snapshot = WorkspaceCommandResolver.snapshot(
            from: [tab],
            activeTabId: tabId,
            isManagementLayerActive: false,
            visiblePaneIds: { _ in [paneA] }
        )

        #expect(snapshot.tab(tabId)?.visiblePaneIds == [paneA])
        #expect(snapshot.tab(tabId)?.ownedPaneIds == [paneA, paneB])
    }

    // MARK: - resolveDrop: Zone → direction mapping

    @Test

    func test_resolveDrop_zoneMapping() {
        // Arrange
        let tabId = UUID()
        let paneId = UUID()
        let tab = makeSinglePaneTab(tabId: tabId, paneId: paneId)
        let snapshot = makeSnapshot(tabs: [tab])
        let payload = SplitDropPayload(kind: .newTerminal)

        let zoneMappings: [(DropZoneSide, SplitNewDirection)] = [
            (.left, .left),
            (.right, .right),
        ]

        for (zone, expectedDirection) in zoneMappings {
            // Act
            let result = WorkspaceCommandResolver.resolveDrop(
                payload: payload,
                destinationPaneId: paneId,
                destinationTabId: tabId,
                zone: zone,
                sizingMode: DropSizingMode.halveTarget,
                state: snapshot
            )

            // Assert
            #expect(
                result
                    == PaneActionCommand.insertPane(
                        source: PaneSource.newTerminal,
                        targetTabId: tabId,
                        targetPaneId: paneId,
                        direction: expectedDirection,
                        sizingMode: DropSizingMode.halveTarget
                    ), "Zone \(zone) should map to direction \(expectedDirection)")
        }
    }
}
