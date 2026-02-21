import Testing
import Foundation

@testable import AgentStudio

@Suite(.serialized)
final class ActionValidatorTests {

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

    @Test

    func test_selectTab_existingTab_succeeds() {
        // Arrange
        let tabId = UUID()
        let snapshot = makeSnapshot(tabs: [TabSnapshot(id: tabId, paneIds: [UUID()], activePaneId: nil)])

        // Act
        let result = ActionValidator.validate(.selectTab(tabId: tabId), state: snapshot)

        // Assert
        #expect((try? result.get()) != nil)
    }

    @Test

    func test_selectTab_missingTab_fails() {
        // Arrange
        let snapshot = makeSnapshot()

        // Act
        let result = ActionValidator.validate(.selectTab(tabId: UUID()), state: snapshot)

        // Assert
        if case .failure(let error) = result {
            if case .tabNotFound = error { return }
        }
        Issue.record("Expected tabNotFound error")
    }

    // MARK: - closeTab

    @Test

    func test_closeTab_existingTab_succeeds() {
        // Arrange
        let tabId = UUID()
        let snapshot = makeSnapshot(tabs: [TabSnapshot(id: tabId, paneIds: [UUID()], activePaneId: nil)])

        // Act
        let result = ActionValidator.validate(.closeTab(tabId: tabId), state: snapshot)

        // Assert
        #expect((try? result.get()) != nil)
    }

    @Test

    func test_closeTab_missingTab_fails() {
        // Arrange
        let snapshot = makeSnapshot()

        // Act
        let result = ActionValidator.validate(.closeTab(tabId: UUID()), state: snapshot)

        // Assert
        if case .failure(.tabNotFound) = result { return }
        Issue.record("Expected tabNotFound error")
    }

    // MARK: - breakUpTab

    @Test

    func test_breakUpTab_splitTab_succeeds() {
        // Arrange
        let (tab, tabId, _) = makeMultiPaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = ActionValidator.validate(.breakUpTab(tabId: tabId), state: snapshot)

        // Assert
        #expect((try? result.get()) != nil)
    }

    @Test

    func test_breakUpTab_singlePaneTab_fails() {
        // Arrange
        let (tab, tabId, _) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = ActionValidator.validate(.breakUpTab(tabId: tabId), state: snapshot)

        // Assert
        if case .failure(.tabNotSplit) = result { return }
        Issue.record("Expected tabNotSplit error")
    }

    @Test

    func test_breakUpTab_missingTab_fails() {
        // Arrange
        let snapshot = makeSnapshot()

        // Act
        let result = ActionValidator.validate(.breakUpTab(tabId: UUID()), state: snapshot)

        // Assert
        if case .failure(.tabNotFound) = result { return }
        Issue.record("Expected tabNotFound error")
    }

    // MARK: - closePane

    @Test

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
        #expect((try? result.get()) != nil)
    }

    @Test

    func test_closePane_singlePaneTab_succeeds_escalatesToCloseTab() {
        // Arrange — single-pane close is valid; executor escalates to closeTab with undo
        let (tab, tabId, paneId) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = ActionValidator.validate(
            .closePane(tabId: tabId, paneId: paneId),
            state: snapshot
        )

        // Assert
        #expect((try? result.get()) != nil)
    }

    @Test

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
        Issue.record("Expected paneNotFound error")
    }

    @Test

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
        Issue.record("Expected tabNotFound error")
    }

    // MARK: - extractPaneToTab

    @Test

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
        #expect((try? result.get()) != nil)
    }

    @Test

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
        Issue.record("Expected singlePaneTab error")
    }

    // MARK: - focusPane

    @Test

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
        #expect((try? result.get()) != nil)
    }

    @Test

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
        Issue.record("Expected paneNotFound error")
    }

    // MARK: - insertPane (self-insertion bug fix)

    @Test

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
            #expect(id == paneId)
            return
        }
        Issue.record("Expected selfPaneInsertion error")
    }

    @Test

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
        #expect((try? result.get()) != nil)
    }

    @Test

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
        #expect((try? result.get()) != nil)
    }

    @Test

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
        Issue.record("Expected tabNotFound error")
    }

    @Test

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
        Issue.record("Expected paneNotFound error")
    }

    @Test

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
        Issue.record("Expected sourcePaneNotFound error")
    }

    // MARK: - resizePane

    @Test

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
        #expect((try? result.get()) != nil)
    }

    @Test

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
        Issue.record("Expected invalidRatio error")
    }

    @Test

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
        Issue.record("Expected invalidRatio error")
    }

    @Test

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
        Issue.record("Expected tabNotSplit error")
    }

    // MARK: - equalizePanes

    @Test

    func test_equalizePanes_splitTab_succeeds() {
        // Arrange
        let (tab, tabId, _) = makeMultiPaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = ActionValidator.validate(.equalizePanes(tabId: tabId), state: snapshot)

        // Assert
        #expect((try? result.get()) != nil)
    }

    @Test

    func test_equalizePanes_singlePaneTab_fails() {
        // Arrange
        let (tab, tabId, _) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = ActionValidator.validate(.equalizePanes(tabId: tabId), state: snapshot)

        // Assert
        if case .failure(.tabNotSplit) = result { return }
        Issue.record("Expected tabNotSplit error")
    }

    // MARK: - mergeTab

    @Test

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
        #expect((try? result.get()) != nil)
    }

    @Test

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
        Issue.record("Expected tabNotFound error")
    }

    @Test

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
        Issue.record("Expected tabNotFound error")
    }

    @Test

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
        Issue.record("Expected paneNotFound error")
    }

    @Test

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
        Issue.record("Expected selfTabMerge error")
    }

    // MARK: - System Actions (trusted, skip validation)

    @Test

    func test_expireUndoEntry_alwaysSucceeds() {
        // Arrange — empty state, no tabs at all
        let snapshot = makeSnapshot()
        let action = PaneAction.expireUndoEntry(paneId: UUID())

        // Act
        let result = ActionValidator.validate(action, state: snapshot)

        // Assert
        #expect((try? result.get()) != nil)
    }

    @Test

    func test_repair_alwaysSucceeds() {
        // Arrange
        let snapshot = makeSnapshot()
        let action = PaneAction.repair(.recreateSurface(paneId: UUID()))

        // Act
        let result = ActionValidator.validate(action, state: snapshot)

        // Assert
        #expect((try? result.get()) != nil)
    }

    // MARK: - Pane Cardinality

    @Test

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
        #expect((try? result.get()) != nil)
    }

    @Test

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
            #expect(id == paneId)
            return
        }
        Issue.record("Expected paneAlreadyInLayout error")
    }

    @Test

    func test_paneCardinality_emptyState_succeeds() {
        // Arrange
        let snapshot = makeSnapshot()

        // Act
        let result = ActionValidator.validatePaneCardinality(
            paneId: UUID(), state: snapshot
        )

        // Assert
        #expect((try? result.get()) != nil)
    }

    // MARK: - ValidatedAction preserves action

    @Test

    func test_validatedAction_preservesOriginalAction() {
        // Arrange
        let tabId = UUID()
        let snapshot = makeSnapshot(tabs: [TabSnapshot(id: tabId, paneIds: [UUID()], activePaneId: nil)])
        let action = PaneAction.selectTab(tabId: tabId)

        // Act
        let result = ActionValidator.validate(action, state: snapshot)

        // Assert
        if case .success(let validated) = result {
            #expect(validated.action == action)
        } else {
            Issue.record("Expected success")
        }
    }
}
