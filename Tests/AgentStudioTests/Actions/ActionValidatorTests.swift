import XCTest
@testable import AgentStudio

final class ActionValidatorTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeSnapshot(
        tabs: [TabSnapshot] = [],
        activeTabId: UUID? = nil,
        isManagementModeActive: Bool = false
    ) -> ActionStateSnapshot {
        ActionStateSnapshot(
            tabs: tabs,
            activeTabId: activeTabId,
            isManagementModeActive: isManagementModeActive
        )
    }

    private func makeSinglePaneTab(tabId: UUID = UUID(), paneId: UUID = UUID()) -> (TabSnapshot, UUID, UUID) {
        let tab = TabSnapshot(id: tabId, paneIds: [paneId], activePaneId: paneId)
        return (tab, tabId, paneId)
    }

    private func makeMultiPaneTab(tabId: UUID = UUID(), paneIds: [UUID]? = nil) -> (TabSnapshot, UUID, [UUID]) {
        let ids = paneIds ?? [UUID(), UUID()]
        let tab = TabSnapshot(id: tabId, paneIds: ids, activePaneId: ids.first)
        return (tab, tabId, ids)
    }

    // MARK: - selectTab

    func test_selectTab_existingTab_succeeds() {
        // Arrange
        let tabId = UUID()
        let snapshot = makeSnapshot(tabs: [TabSnapshot(id: tabId, paneIds: [UUID()], activePaneId: nil)])

        // Act
        let result = ActionValidator.validate(.selectTab(tabId: tabId), state: snapshot)

        // Assert
        XCTAssertNotNil(try? result.get())
    }

    func test_selectTab_missingTab_fails() {
        // Arrange
        let snapshot = makeSnapshot()

        // Act
        let result = ActionValidator.validate(.selectTab(tabId: UUID()), state: snapshot)

        // Assert
        if case .failure(let error) = result {
            if case .tabNotFound = error { return }
        }
        XCTFail("Expected tabNotFound error")
    }

    // MARK: - closeTab

    func test_closeTab_existingTab_succeeds() {
        // Arrange
        let tabId = UUID()
        let snapshot = makeSnapshot(tabs: [TabSnapshot(id: tabId, paneIds: [UUID()], activePaneId: nil)])

        // Act
        let result = ActionValidator.validate(.closeTab(tabId: tabId), state: snapshot)

        // Assert
        XCTAssertNotNil(try? result.get())
    }

    func test_closeTab_missingTab_fails() {
        // Arrange
        let snapshot = makeSnapshot()

        // Act
        let result = ActionValidator.validate(.closeTab(tabId: UUID()), state: snapshot)

        // Assert
        if case .failure(.tabNotFound) = result { return }
        XCTFail("Expected tabNotFound error")
    }

    // MARK: - breakUpTab

    func test_breakUpTab_splitTab_succeeds() {
        // Arrange
        let (tab, tabId, _) = makeMultiPaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = ActionValidator.validate(.breakUpTab(tabId: tabId), state: snapshot)

        // Assert
        XCTAssertNotNil(try? result.get())
    }

    func test_breakUpTab_singlePaneTab_fails() {
        // Arrange
        let (tab, tabId, _) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = ActionValidator.validate(.breakUpTab(tabId: tabId), state: snapshot)

        // Assert
        if case .failure(.tabNotSplit) = result { return }
        XCTFail("Expected tabNotSplit error")
    }

    func test_breakUpTab_missingTab_fails() {
        // Arrange
        let snapshot = makeSnapshot()

        // Act
        let result = ActionValidator.validate(.breakUpTab(tabId: UUID()), state: snapshot)

        // Assert
        if case .failure(.tabNotFound) = result { return }
        XCTFail("Expected tabNotFound error")
    }

    // MARK: - closePane

    func test_closePane_multiPaneTab_succeeds() {
        // Arrange
        let (tab, tabId, paneIds) = makeMultiPaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = ActionValidator.validate(
            .closePane(tabId: tabId, paneId: paneIds[0]),
            state: snapshot
        )

        // Assert
        XCTAssertNotNil(try? result.get())
    }

    func test_closePane_singlePaneTab_fails() {
        // Arrange
        let (tab, tabId, paneId) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = ActionValidator.validate(
            .closePane(tabId: tabId, paneId: paneId),
            state: snapshot
        )

        // Assert
        if case .failure(.singlePaneTab) = result { return }
        XCTFail("Expected singlePaneTab error")
    }

    func test_closePane_paneNotInTab_fails() {
        // Arrange
        let (tab, tabId, _) = makeMultiPaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = ActionValidator.validate(
            .closePane(tabId: tabId, paneId: UUID()),
            state: snapshot
        )

        // Assert
        if case .failure(.paneNotFound) = result { return }
        XCTFail("Expected paneNotFound error")
    }

    func test_closePane_missingTab_fails() {
        // Arrange
        let snapshot = makeSnapshot()

        // Act
        let result = ActionValidator.validate(
            .closePane(tabId: UUID(), paneId: UUID()),
            state: snapshot
        )

        // Assert
        if case .failure(.tabNotFound) = result { return }
        XCTFail("Expected tabNotFound error")
    }

    // MARK: - extractPaneToTab

    func test_extractPaneToTab_multiPaneTab_succeeds() {
        // Arrange
        let (tab, tabId, paneIds) = makeMultiPaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = ActionValidator.validate(
            .extractPaneToTab(tabId: tabId, paneId: paneIds[0]),
            state: snapshot
        )

        // Assert
        XCTAssertNotNil(try? result.get())
    }

    func test_extractPaneToTab_singlePaneTab_fails() {
        // Arrange
        let (tab, tabId, paneId) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = ActionValidator.validate(
            .extractPaneToTab(tabId: tabId, paneId: paneId),
            state: snapshot
        )

        // Assert
        if case .failure(.singlePaneTab) = result { return }
        XCTFail("Expected singlePaneTab error")
    }

    // MARK: - focusPane

    func test_focusPane_validPane_succeeds() {
        // Arrange
        let paneId = UUID()
        let tabId = UUID()
        let tab = TabSnapshot(id: tabId, paneIds: [paneId], activePaneId: paneId)
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = ActionValidator.validate(
            .focusPane(tabId: tabId, paneId: paneId),
            state: snapshot
        )

        // Assert
        XCTAssertNotNil(try? result.get())
    }

    func test_focusPane_paneNotInTab_fails() {
        // Arrange
        let (tab, tabId, _) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = ActionValidator.validate(
            .focusPane(tabId: tabId, paneId: UUID()),
            state: snapshot
        )

        // Assert
        if case .failure(.paneNotFound) = result { return }
        XCTFail("Expected paneNotFound error")
    }

    // MARK: - insertPane (self-insertion bug fix)

    func test_insertPane_selfInsertion_fails() {
        // Arrange — THE BUG: dragging a pane onto itself
        let paneId = UUID()
        let tabId = UUID()
        let tab = TabSnapshot(id: tabId, paneIds: [paneId], activePaneId: paneId)
        let snapshot = makeSnapshot(tabs: [tab])
        let action = PaneAction.insertPane(
            source: .existingPane(paneId: paneId, sourceTabId: tabId),
            targetTabId: tabId,
            targetPaneId: paneId,
            direction: .right
        )

        // Act
        let result = ActionValidator.validate(action, state: snapshot)

        // Assert
        if case .failure(.selfPaneInsertion(let id)) = result {
            XCTAssertEqual(id, paneId)
            return
        }
        XCTFail("Expected selfPaneInsertion error")
    }

    func test_insertPane_existingPane_differentTarget_succeeds() {
        // Arrange
        let sourcePaneId = UUID()
        let targetPaneId = UUID()
        let sourceTabId = UUID()
        let targetTabId = UUID()
        let sourceTab = TabSnapshot(id: sourceTabId, paneIds: [sourcePaneId], activePaneId: sourcePaneId)
        let targetTab = TabSnapshot(id: targetTabId, paneIds: [targetPaneId], activePaneId: targetPaneId)
        let snapshot = makeSnapshot(tabs: [sourceTab, targetTab])
        let action = PaneAction.insertPane(
            source: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId),
            targetTabId: targetTabId,
            targetPaneId: targetPaneId,
            direction: .right
        )

        // Act
        let result = ActionValidator.validate(action, state: snapshot)

        // Assert
        XCTAssertNotNil(try? result.get())
    }

    func test_insertPane_newTerminal_succeeds() {
        // Arrange
        let (tab, tabId, paneId) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])
        let action = PaneAction.insertPane(
            source: .newTerminal,
            targetTabId: tabId,
            targetPaneId: paneId,
            direction: .down
        )

        // Act
        let result = ActionValidator.validate(action, state: snapshot)

        // Assert
        XCTAssertNotNil(try? result.get())
    }

    func test_insertPane_targetTabMissing_fails() {
        // Arrange
        let snapshot = makeSnapshot()
        let action = PaneAction.insertPane(
            source: .newTerminal,
            targetTabId: UUID(),
            targetPaneId: UUID(),
            direction: .right
        )

        // Act
        let result = ActionValidator.validate(action, state: snapshot)

        // Assert
        if case .failure(.tabNotFound) = result { return }
        XCTFail("Expected tabNotFound error")
    }

    func test_insertPane_targetPaneMissing_fails() {
        // Arrange
        let (tab, tabId, _) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])
        let action = PaneAction.insertPane(
            source: .newTerminal,
            targetTabId: tabId,
            targetPaneId: UUID(),
            direction: .right
        )

        // Act
        let result = ActionValidator.validate(action, state: snapshot)

        // Assert
        if case .failure(.paneNotFound) = result { return }
        XCTFail("Expected paneNotFound error")
    }

    func test_insertPane_sourcePaneMissing_fails() {
        // Arrange
        let (tab, tabId, paneId) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])
        let action = PaneAction.insertPane(
            source: .existingPane(paneId: UUID(), sourceTabId: UUID()),
            targetTabId: tabId,
            targetPaneId: paneId,
            direction: .right
        )

        // Act
        let result = ActionValidator.validate(action, state: snapshot)

        // Assert
        if case .failure(.sourcePaneNotFound) = result { return }
        XCTFail("Expected sourcePaneNotFound error")
    }

    // MARK: - resizePane

    func test_resizePane_validRatio_succeeds() {
        // Arrange
        let (tab, tabId, _) = makeMultiPaneTab()
        let snapshot = makeSnapshot(tabs: [tab])
        let splitId = UUID()

        // Act
        let result = ActionValidator.validate(
            .resizePane(tabId: tabId, splitId: splitId, ratio: 0.5),
            state: snapshot
        )

        // Assert
        XCTAssertNotNil(try? result.get())
    }

    func test_resizePane_ratioTooLow_fails() {
        // Arrange
        let (tab, tabId, _) = makeMultiPaneTab()
        let snapshot = makeSnapshot(tabs: [tab])
        let splitId = UUID()

        // Act
        let result = ActionValidator.validate(
            .resizePane(tabId: tabId, splitId: splitId, ratio: 0.05),
            state: snapshot
        )

        // Assert
        if case .failure(.invalidRatio) = result { return }
        XCTFail("Expected invalidRatio error")
    }

    func test_resizePane_ratioTooHigh_fails() {
        // Arrange
        let (tab, tabId, _) = makeMultiPaneTab()
        let snapshot = makeSnapshot(tabs: [tab])
        let splitId = UUID()

        // Act
        let result = ActionValidator.validate(
            .resizePane(tabId: tabId, splitId: splitId, ratio: 0.95),
            state: snapshot
        )

        // Assert
        if case .failure(.invalidRatio) = result { return }
        XCTFail("Expected invalidRatio error")
    }

    func test_resizePane_singlePaneTab_fails() {
        // Arrange
        let (tab, tabId, _) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])
        let splitId = UUID()

        // Act
        let result = ActionValidator.validate(
            .resizePane(tabId: tabId, splitId: splitId, ratio: 0.5),
            state: snapshot
        )

        // Assert
        if case .failure(.tabNotSplit) = result { return }
        XCTFail("Expected tabNotSplit error")
    }

    // MARK: - equalizePanes

    func test_equalizePanes_splitTab_succeeds() {
        // Arrange
        let (tab, tabId, _) = makeMultiPaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = ActionValidator.validate(.equalizePanes(tabId: tabId), state: snapshot)

        // Assert
        XCTAssertNotNil(try? result.get())
    }

    func test_equalizePanes_singlePaneTab_fails() {
        // Arrange
        let (tab, tabId, _) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = ActionValidator.validate(.equalizePanes(tabId: tabId), state: snapshot)

        // Assert
        if case .failure(.tabNotSplit) = result { return }
        XCTFail("Expected tabNotSplit error")
    }

    // MARK: - mergeTab

    func test_mergeTab_validTabs_succeeds() {
        // Arrange
        let (sourceTab, sourceTabId, _) = makeMultiPaneTab()
        let (targetTab, targetTabId, targetPaneIds) = makeMultiPaneTab()
        let snapshot = makeSnapshot(tabs: [sourceTab, targetTab])
        let action = PaneAction.mergeTab(
            sourceTabId: sourceTabId,
            targetTabId: targetTabId,
            targetPaneId: targetPaneIds[0],
            direction: .right
        )

        // Act
        let result = ActionValidator.validate(action, state: snapshot)

        // Assert
        XCTAssertNotNil(try? result.get())
    }

    func test_mergeTab_sourceTabMissing_fails() {
        // Arrange
        let (targetTab, targetTabId, targetPaneId) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [targetTab])
        let action = PaneAction.mergeTab(
            sourceTabId: UUID(),
            targetTabId: targetTabId,
            targetPaneId: targetPaneId,
            direction: .right
        )

        // Act
        let result = ActionValidator.validate(action, state: snapshot)

        // Assert
        if case .failure(.tabNotFound) = result { return }
        XCTFail("Expected tabNotFound error")
    }

    func test_mergeTab_targetTabMissing_fails() {
        // Arrange
        let (sourceTab, sourceTabId, _) = makeMultiPaneTab()
        let snapshot = makeSnapshot(tabs: [sourceTab])
        let action = PaneAction.mergeTab(
            sourceTabId: sourceTabId,
            targetTabId: UUID(),
            targetPaneId: UUID(),
            direction: .right
        )

        // Act
        let result = ActionValidator.validate(action, state: snapshot)

        // Assert
        if case .failure(.tabNotFound) = result { return }
        XCTFail("Expected tabNotFound error")
    }

    func test_mergeTab_targetPaneMissing_fails() {
        // Arrange
        let (sourceTab, sourceTabId, _) = makeMultiPaneTab()
        let (targetTab, targetTabId, _) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [sourceTab, targetTab])
        let action = PaneAction.mergeTab(
            sourceTabId: sourceTabId,
            targetTabId: targetTabId,
            targetPaneId: UUID(),
            direction: .right
        )

        // Act
        let result = ActionValidator.validate(action, state: snapshot)

        // Assert
        if case .failure(.paneNotFound) = result { return }
        XCTFail("Expected paneNotFound error")
    }

    func test_mergeTab_selfMerge_fails() {
        // Arrange
        let (tab, tabId, paneIds) = makeMultiPaneTab()
        let snapshot = makeSnapshot(tabs: [tab])
        let action = PaneAction.mergeTab(
            sourceTabId: tabId,
            targetTabId: tabId,
            targetPaneId: paneIds[0],
            direction: .right
        )

        // Act
        let result = ActionValidator.validate(action, state: snapshot)

        // Assert
        if case .failure(.selfTabMerge) = result { return }
        XCTFail("Expected selfTabMerge error")
    }

    // MARK: - System Actions (trusted, skip validation)

    func test_expireUndoEntry_alwaysSucceeds() {
        // Arrange — empty state, no tabs at all
        let snapshot = makeSnapshot()
        let action = PaneAction.expireUndoEntry(paneId: UUID())

        // Act
        let result = ActionValidator.validate(action, state: snapshot)

        // Assert
        XCTAssertNotNil(try? result.get())
    }

    func test_repair_alwaysSucceeds() {
        // Arrange
        let snapshot = makeSnapshot()
        let action = PaneAction.repair(.recreateSurface(paneId: UUID()))

        // Act
        let result = ActionValidator.validate(action, state: snapshot)

        // Assert
        XCTAssertNotNil(try? result.get())
    }

    // MARK: - Pane Cardinality

    func test_paneCardinality_newPane_succeeds() {
        // Arrange
        let existingPaneId = UUID()
        let newPaneId = UUID()
        let tab = TabSnapshot(id: UUID(), paneIds: [existingPaneId], activePaneId: existingPaneId)
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = ActionValidator.validatePaneCardinality(
            paneId: newPaneId, state: snapshot
        )

        // Assert
        XCTAssertNotNil(try? result.get())
    }

    func test_paneCardinality_duplicatePane_fails() {
        // Arrange
        let paneId = UUID()
        let tab = TabSnapshot(id: UUID(), paneIds: [paneId], activePaneId: paneId)
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = ActionValidator.validatePaneCardinality(
            paneId: paneId, state: snapshot
        )

        // Assert
        if case .failure(.paneAlreadyInLayout(let id)) = result {
            XCTAssertEqual(id, paneId)
            return
        }
        XCTFail("Expected paneAlreadyInLayout error")
    }

    func test_paneCardinality_emptyState_succeeds() {
        // Arrange
        let snapshot = makeSnapshot()

        // Act
        let result = ActionValidator.validatePaneCardinality(
            paneId: UUID(), state: snapshot
        )

        // Assert
        XCTAssertNotNil(try? result.get())
    }

    // MARK: - ValidatedAction preserves action

    func test_validatedAction_preservesOriginalAction() {
        // Arrange
        let tabId = UUID()
        let snapshot = makeSnapshot(tabs: [TabSnapshot(id: tabId, paneIds: [UUID()], activePaneId: nil)])
        let action = PaneAction.selectTab(tabId: tabId)

        // Act
        let result = ActionValidator.validate(action, state: snapshot)

        // Assert
        if case .success(let validated) = result {
            XCTAssertEqual(validated.action, action)
        } else {
            XCTFail("Expected success")
        }
    }
}
