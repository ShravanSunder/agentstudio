import XCTest
@testable import AgentStudio

final class ActionResolverTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeSnapshot(
        tabs: [TabSnapshot] = [],
        activeTabId: UUID? = nil
    ) -> ActionStateSnapshot {
        ActionStateSnapshot(
            tabs: tabs,
            activeTabId: activeTabId,
            isManagementModeActive: false
        )
    }

    private func makeSinglePaneTab(tabId: UUID = UUID(), paneId: UUID = UUID()) -> TabSnapshot {
        TabSnapshot(id: tabId, paneIds: [paneId], activePaneId: paneId)
    }

    private func makeMultiPaneTab(tabId: UUID = UUID(), paneIds: [UUID]? = nil) -> TabSnapshot {
        let ids = paneIds ?? [UUID(), UUID()]
        return TabSnapshot(id: tabId, paneIds: ids, activePaneId: ids.first)
    }

    // MARK: - resolveDrop: Multi-pane tab → mergeTab

    func test_resolveDrop_multiPaneTab_returnsMergeTab() {
        // Arrange
        let sourceTabId = UUID()
        let targetTabId = UUID()
        let targetPaneId = UUID()
        let sourceTab = makeMultiPaneTab(tabId: sourceTabId)
        let targetTab = makeSinglePaneTab(tabId: targetTabId, paneId: targetPaneId)
        let snapshot = makeSnapshot(tabs: [sourceTab, targetTab])
        let payload = SplitDropPayload(kind: .existingTab(
            tabId: sourceTabId, worktreeId: UUID(), repoId: UUID(), title: "test"
        ))

        // Act
        let result = ActionResolver.resolveDrop(
            payload: payload,
            destinationPaneId: targetPaneId,
            destinationTabId: targetTabId,
            zone: .right,
            state: snapshot
        )

        // Assert
        XCTAssertEqual(result, .mergeTab(
            sourceTabId: sourceTabId,
            targetTabId: targetTabId,
            targetPaneId: targetPaneId,
            direction: .right
        ))
    }

    // MARK: - resolveDrop: Single-pane tab → insertPane

    func test_resolveDrop_singlePaneTab_returnsInsertPane() {
        // Arrange
        let sourceTabId = UUID()
        let sourcePaneId = UUID()
        let targetTabId = UUID()
        let targetPaneId = UUID()
        let sourceTab = makeSinglePaneTab(tabId: sourceTabId, paneId: sourcePaneId)
        let targetTab = makeSinglePaneTab(tabId: targetTabId, paneId: targetPaneId)
        let snapshot = makeSnapshot(tabs: [sourceTab, targetTab])
        let payload = SplitDropPayload(kind: .existingTab(
            tabId: sourceTabId, worktreeId: UUID(), repoId: UUID(), title: "test"
        ))

        // Act
        let result = ActionResolver.resolveDrop(
            payload: payload,
            destinationPaneId: targetPaneId,
            destinationTabId: targetTabId,
            zone: .left,
            state: snapshot
        )

        // Assert
        XCTAssertEqual(result, .insertPane(
            source: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId),
            targetTabId: targetTabId,
            targetPaneId: targetPaneId,
            direction: .left
        ))
    }

    // MARK: - resolveDrop: New terminal → insertPane

    func test_resolveDrop_newTerminal_returnsInsertPane() {
        // Arrange
        let targetTabId = UUID()
        let targetPaneId = UUID()
        let targetTab = makeSinglePaneTab(tabId: targetTabId, paneId: targetPaneId)
        let snapshot = makeSnapshot(tabs: [targetTab])
        let payload = SplitDropPayload(kind: .newTerminal)

        // Act
        let result = ActionResolver.resolveDrop(
            payload: payload,
            destinationPaneId: targetPaneId,
            destinationTabId: targetTabId,
            zone: .bottom,
            state: snapshot
        )

        // Assert
        XCTAssertEqual(result, .insertPane(
            source: .newTerminal,
            targetTabId: targetTabId,
            targetPaneId: targetPaneId,
            direction: .down
        ))
    }

    // MARK: - resolveDrop: Source tab not found → nil

    func test_resolveDrop_sourceTabNotFound_returnsNil() {
        // Arrange
        let targetTabId = UUID()
        let targetPaneId = UUID()
        let targetTab = makeSinglePaneTab(tabId: targetTabId, paneId: targetPaneId)
        let snapshot = makeSnapshot(tabs: [targetTab])
        let payload = SplitDropPayload(kind: .existingTab(
            tabId: UUID(), worktreeId: UUID(), repoId: UUID(), title: "missing"
        ))

        // Act
        let result = ActionResolver.resolveDrop(
            payload: payload,
            destinationPaneId: targetPaneId,
            destinationTabId: targetTabId,
            zone: .right,
            state: snapshot
        )

        // Assert
        XCTAssertNil(result)
    }

    // MARK: - resolveDrop: Self-drop produces mergeTab (validator rejects)

    func test_resolveDrop_selfDrop_multiPane_producesMergeTab() {
        // Arrange — dropping a multi-pane tab onto its own pane
        let tabId = UUID()
        let paneIds = [UUID(), UUID()]
        let tab = makeMultiPaneTab(tabId: tabId, paneIds: paneIds)
        let snapshot = makeSnapshot(tabs: [tab])
        let payload = SplitDropPayload(kind: .existingTab(
            tabId: tabId, worktreeId: UUID(), repoId: UUID(), title: "self"
        ))

        // Act
        let result = ActionResolver.resolveDrop(
            payload: payload,
            destinationPaneId: paneIds[0],
            destinationTabId: tabId,
            zone: .right,
            state: snapshot
        )

        // Assert — resolver produces the action, validator will reject it
        XCTAssertEqual(result, .mergeTab(
            sourceTabId: tabId,
            targetTabId: tabId,
            targetPaneId: paneIds[0],
            direction: .right
        ))

        // Verify validator rejects self-merge
        let validation = ActionValidator.validate(result!, state: snapshot)
        if case .failure(.selfInsertion) = validation { return }
        XCTFail("Expected selfInsertion error from validator")
    }

    // MARK: - resolve(command:) — Tab Lifecycle

    func test_resolve_closeTab_returnsCloseTabWithActiveId() {
        // Arrange
        let tabId = UUID()
        let paneId = UUID()
        let tab = MockTab(id: tabId, activePaneId: paneId, allPaneIds: [paneId])

        // Act
        let result = ActionResolver.resolve(command: .closeTab, tabs: [tab], activeTabId: tabId)

        // Assert
        XCTAssertEqual(result, .closeTab(tabId: tabId))
    }

    func test_resolve_breakUpTab_returnsBreakUpTabWithActiveId() {
        // Arrange
        let tabId = UUID()
        let paneId = UUID()
        let tab = MockTab(id: tabId, activePaneId: paneId, allPaneIds: [paneId])

        // Act
        let result = ActionResolver.resolve(command: .breakUpTab, tabs: [tab], activeTabId: tabId)

        // Assert
        XCTAssertEqual(result, .breakUpTab(tabId: tabId))
    }

    func test_resolve_nextTab_wrapsAround() {
        // Arrange
        let tab1Id = UUID()
        let tab2Id = UUID()
        let tab1 = MockTab(id: tab1Id, activePaneId: UUID(), allPaneIds: [UUID()])
        let tab2 = MockTab(id: tab2Id, activePaneId: UUID(), allPaneIds: [UUID()])

        // Act — from last tab wraps to first
        let result = ActionResolver.resolve(
            command: .nextTab, tabs: [tab1, tab2], activeTabId: tab2Id
        )

        // Assert
        XCTAssertEqual(result, .selectTab(tabId: tab1Id))
    }

    func test_resolve_prevTab_wrapsAround() {
        // Arrange
        let tab1Id = UUID()
        let tab2Id = UUID()
        let tab1 = MockTab(id: tab1Id, activePaneId: UUID(), allPaneIds: [UUID()])
        let tab2 = MockTab(id: tab2Id, activePaneId: UUID(), allPaneIds: [UUID()])

        // Act — from first tab wraps to last
        let result = ActionResolver.resolve(
            command: .prevTab, tabs: [tab1, tab2], activeTabId: tab1Id
        )

        // Assert
        XCTAssertEqual(result, .selectTab(tabId: tab2Id))
    }

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
        XCTAssertEqual(
            ActionResolver.resolve(command: .selectTab1, tabs: tabs, activeTabId: nil),
            .selectTab(tabId: tab1Id)
        )
        XCTAssertEqual(
            ActionResolver.resolve(command: .selectTab3, tabs: tabs, activeTabId: nil),
            .selectTab(tabId: tab3Id)
        )
        // Out of range
        XCTAssertNil(
            ActionResolver.resolve(command: .selectTab4, tabs: tabs, activeTabId: nil)
        )
    }

    // MARK: - resolve(command:) — Pane Lifecycle

    func test_resolve_closePane_returnsClosePaneWithActivePane() {
        // Arrange
        let tabId = UUID()
        let paneId = UUID()
        let tab = MockTab(id: tabId, activePaneId: paneId, allPaneIds: [paneId])

        // Act
        let result = ActionResolver.resolve(command: .closePane, tabs: [tab], activeTabId: tabId)

        // Assert
        XCTAssertEqual(result, .closePane(tabId: tabId, paneId: paneId))
    }

    func test_resolve_extractPaneToTab_returnsExtractWithActivePane() {
        // Arrange
        let tabId = UUID()
        let paneId = UUID()
        let tab = MockTab(id: tabId, activePaneId: paneId, allPaneIds: [paneId])

        // Act
        let result = ActionResolver.resolve(
            command: .extractPaneToTab, tabs: [tab], activeTabId: tabId
        )

        // Assert
        XCTAssertEqual(result, .extractPaneToTab(tabId: tabId, paneId: paneId))
    }

    func test_resolve_equalizePanes_returnsEqualizeWithActiveTab() {
        // Arrange
        let tabId = UUID()
        let tab = MockTab(id: tabId, activePaneId: UUID(), allPaneIds: [UUID()])

        // Act
        let result = ActionResolver.resolve(
            command: .equalizePanes, tabs: [tab], activeTabId: tabId
        )

        // Assert
        XCTAssertEqual(result, .equalizePanes(tabId: tabId))
    }

    // MARK: - resolve(command:) — Pane Focus

    func test_resolve_focusPaneLeft_findsNeighbor() {
        // Arrange
        let tabId = UUID()
        let paneA = UUID()
        let paneB = UUID()
        var tab = MockTab(id: tabId, activePaneId: paneA, allPaneIds: [paneA, paneB])
        tab.neighbors = [paneA: [.left: paneB]]

        // Act
        let result = ActionResolver.resolve(
            command: .focusPaneLeft, tabs: [tab], activeTabId: tabId
        )

        // Assert
        XCTAssertEqual(result, .focusPane(tabId: tabId, paneId: paneB))
    }

    func test_resolve_focusPaneRight_noNeighbor_returnsNil() {
        // Arrange
        let tabId = UUID()
        let paneA = UUID()
        let tab = MockTab(id: tabId, activePaneId: paneA, allPaneIds: [paneA])
        // No neighbors configured

        // Act
        let result = ActionResolver.resolve(
            command: .focusPaneRight, tabs: [tab], activeTabId: tabId
        )

        // Assert
        XCTAssertNil(result)
    }

    func test_resolve_focusNextPane_usesNextPaneId() {
        // Arrange
        let tabId = UUID()
        let paneA = UUID()
        let paneB = UUID()
        var tab = MockTab(id: tabId, activePaneId: paneA, allPaneIds: [paneA, paneB])
        tab.nextPanes = [paneA: paneB]

        // Act
        let result = ActionResolver.resolve(
            command: .focusNextPane, tabs: [tab], activeTabId: tabId
        )

        // Assert
        XCTAssertEqual(result, .focusPane(tabId: tabId, paneId: paneB))
    }

    func test_resolve_focusPrevPane_usesPreviousPaneId() {
        // Arrange
        let tabId = UUID()
        let paneA = UUID()
        let paneB = UUID()
        var tab = MockTab(id: tabId, activePaneId: paneB, allPaneIds: [paneA, paneB])
        tab.previousPanes = [paneB: paneA]

        // Act
        let result = ActionResolver.resolve(
            command: .focusPrevPane, tabs: [tab], activeTabId: tabId
        )

        // Assert
        XCTAssertEqual(result, .focusPane(tabId: tabId, paneId: paneA))
    }

    // MARK: - resolve(command:) — Split

    func test_resolve_splitRight_returnsInsertPane() {
        // Arrange
        let tabId = UUID()
        let paneId = UUID()
        let tab = MockTab(id: tabId, activePaneId: paneId, allPaneIds: [paneId])

        // Act
        let result = ActionResolver.resolve(
            command: .splitRight, tabs: [tab], activeTabId: tabId
        )

        // Assert
        XCTAssertEqual(result, .insertPane(
            source: .newTerminal,
            targetTabId: tabId,
            targetPaneId: paneId,
            direction: .right
        ))
    }

    func test_resolve_splitBelow_returnsInsertPane() {
        // Arrange
        let tabId = UUID()
        let paneId = UUID()
        let tab = MockTab(id: tabId, activePaneId: paneId, allPaneIds: [paneId])

        // Act
        let result = ActionResolver.resolve(
            command: .splitBelow, tabs: [tab], activeTabId: tabId
        )

        // Assert
        XCTAssertEqual(result, .insertPane(
            source: .newTerminal,
            targetTabId: tabId,
            targetPaneId: paneId,
            direction: .down
        ))
    }

    // MARK: - resolve(command:) — Edge Cases

    func test_resolve_noActiveTab_returnsNil() {
        // Arrange
        let tab = MockTab(id: UUID(), activePaneId: UUID(), allPaneIds: [UUID()])

        // Act & Assert — all commands requiring activeTabId return nil
        XCTAssertNil(ActionResolver.resolve(command: .closeTab, tabs: [tab], activeTabId: nil))
        XCTAssertNil(ActionResolver.resolve(command: .closePane, tabs: [tab], activeTabId: nil))
        XCTAssertNil(ActionResolver.resolve(command: .splitRight, tabs: [tab], activeTabId: nil))
        XCTAssertNil(ActionResolver.resolve(command: .focusPaneLeft, tabs: [tab], activeTabId: nil))
    }

    func test_resolve_nonPaneCommand_returnsNil() {
        // Arrange
        let tabId = UUID()
        let tab = MockTab(id: tabId, activePaneId: UUID(), allPaneIds: [UUID()])

        // Act & Assert — non-structural commands return nil
        XCTAssertNil(ActionResolver.resolve(command: .addRepo, tabs: [tab], activeTabId: tabId))
        XCTAssertNil(ActionResolver.resolve(
            command: .toggleSidebar, tabs: [tab], activeTabId: tabId
        ))
        XCTAssertNil(ActionResolver.resolve(
            command: .newFloatingTerminal, tabs: [tab], activeTabId: tabId
        ))
    }

    func test_resolve_noActivePaneId_returnsNil() {
        // Arrange — tab exists but has no activePaneId
        let tabId = UUID()
        let tab = MockTab(id: tabId, activePaneId: nil, allPaneIds: [UUID()])

        // Act & Assert — commands needing active pane return nil
        XCTAssertNil(ActionResolver.resolve(command: .closePane, tabs: [tab], activeTabId: tabId))
        XCTAssertNil(ActionResolver.resolve(command: .splitRight, tabs: [tab], activeTabId: tabId))
    }

    // MARK: - snapshot(from:) with MockTab

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
        let snapshot = ActionResolver.snapshot(
            from: [tab1, tab2], activeTabId: tab1Id, isManagementModeActive: false
        )

        // Assert
        XCTAssertEqual(snapshot.tabCount, 2)
        XCTAssertEqual(snapshot.activeTabId, tab1Id)
        XCTAssertEqual(snapshot.tab(tab1Id)?.paneIds, [pane1])
        XCTAssertEqual(snapshot.tab(tab2Id)?.paneIds, [pane2a, pane2b])
        XCTAssertEqual(snapshot.tab(tab2Id)?.activePaneId, pane2a)
        XCTAssertTrue(snapshot.tab(tab2Id)?.isSplit == true)
        XCTAssertFalse(snapshot.tab(tab1Id)?.isSplit == true)
    }

    // MARK: - resolveDrop: Zone → direction mapping

    func test_resolveDrop_zoneMapping() {
        // Arrange
        let tabId = UUID()
        let paneId = UUID()
        let tab = makeSinglePaneTab(tabId: tabId, paneId: paneId)
        let snapshot = makeSnapshot(tabs: [tab])
        let payload = SplitDropPayload(kind: .newTerminal)

        let zoneMappings: [(DropZone, SplitNewDirection)] = [
            (.left, .left),
            (.right, .right),
            (.top, .up),
            (.bottom, .down),
        ]

        for (zone, expectedDirection) in zoneMappings {
            // Act
            let result = ActionResolver.resolveDrop(
                payload: payload,
                destinationPaneId: paneId,
                destinationTabId: tabId,
                zone: zone,
                state: snapshot
            )

            // Assert
            XCTAssertEqual(result, .insertPane(
                source: .newTerminal,
                targetTabId: tabId,
                targetPaneId: paneId,
                direction: expectedDirection
            ), "Zone \(zone) should map to direction \(expectedDirection)")
        }
    }
}
