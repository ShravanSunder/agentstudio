import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class WorkspaceCommandValidatorTests {

    // MARK: - Test Helpers

    private func makeSnapshot(
        tabs: [TabSnapshot] = [],
        activeTabId: UUID? = nil,
        isManagementLayerActive: Bool = false,
        drawerParentByPaneId: [UUID: UUID] = [:],
        drawerLayoutByParentPaneId: [UUID: DrawerGridLayout] = [:]
    ) -> ActionStateSnapshot {
        ActionStateSnapshot(
            tabs: tabs,
            activeTabId: activeTabId,
            isManagementLayerActive: isManagementLayerActive,
            drawerParentByPaneId: drawerParentByPaneId,
            drawerLayoutByParentPaneId: drawerLayoutByParentPaneId
        )
    }

    private func makeSinglePaneTab(tabId: UUID = UUID(), paneId: UUID = UUIDv7.generate()) -> (TabSnapshot, UUID, UUID)
    {
        let tab = TabSnapshot(
            id: tabId,
            visiblePaneIds: [paneId],
            ownedPaneIds: [paneId],
            activePaneId: paneId
        )
        return (tab, tabId, paneId)
    }

    private func makeMultiPaneTab(tabId: UUID = UUID(), paneIds: [UUID]? = nil) -> (TabSnapshot, UUID, [UUID]) {
        let ids = paneIds ?? [UUIDv7.generate(), UUIDv7.generate()]
        let tab = TabSnapshot(
            id: tabId,
            visiblePaneIds: ids,
            ownedPaneIds: ids,
            activePaneId: ids.first
        )
        return (tab, tabId, ids)
    }

    // MARK: - selectTab

    @Test

    func test_selectTab_existingTab_succeeds() {
        // Arrange
        let tabId = UUID()
        let snapshot = makeSnapshot(
            tabs: [TabSnapshot(id: tabId, visiblePaneIds: [UUID()], ownedPaneIds: [UUID()], activePaneId: nil)]
        )

        // Act
        let result = WorkspaceCommandValidator.validate(.selectTab(tabId: tabId), state: snapshot)

        // Assert
        #expect((try? result.get()) != nil)
    }

    @Test

    func test_selectTab_missingTab_fails() {
        // Arrange
        let snapshot = makeSnapshot()

        // Act
        let result = WorkspaceCommandValidator.validate(.selectTab(tabId: UUID()), state: snapshot)

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
        let snapshot = makeSnapshot(
            tabs: [TabSnapshot(id: tabId, visiblePaneIds: [UUID()], ownedPaneIds: [UUID()], activePaneId: nil)]
        )

        // Act
        let result = WorkspaceCommandValidator.validate(.closeTab(tabId: tabId), state: snapshot)

        // Assert
        #expect((try? result.get()) != nil)
    }

    @Test

    func test_closeTab_missingTab_fails() {
        // Arrange
        let snapshot = makeSnapshot()

        // Act
        let result = WorkspaceCommandValidator.validate(.closeTab(tabId: UUID()), state: snapshot)

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
        let result = WorkspaceCommandValidator.validate(.breakUpTab(tabId: tabId), state: snapshot)

        // Assert
        #expect((try? result.get()) != nil)
    }

    @Test

    func test_breakUpTab_singlePaneTab_fails() {
        // Arrange
        let (tab, tabId, _) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = WorkspaceCommandValidator.validate(.breakUpTab(tabId: tabId), state: snapshot)

        // Assert
        if case .failure(.tabNotSplit) = result { return }
        Issue.record("Expected tabNotSplit error")
    }

    @Test

    func test_breakUpTab_missingTab_fails() {
        // Arrange
        let snapshot = makeSnapshot()

        // Act
        let result = WorkspaceCommandValidator.validate(.breakUpTab(tabId: UUID()), state: snapshot)

        // Assert
        if case .failure(.tabNotFound) = result { return }
        Issue.record("Expected tabNotFound error")
    }

    // MARK: - renameTab

    @Test
    func test_renameTab_existingTab_trimsAndSucceeds() {
        let tabId = UUID()
        let snapshot = makeSnapshot(
            tabs: [TabSnapshot(id: tabId, visiblePaneIds: [UUID()], ownedPaneIds: [UUID()], activePaneId: nil)]
        )

        let result = WorkspaceCommandValidator.validate(
            .renameTab(tabId: tabId, name: "  Review Queue  "),
            state: snapshot
        )

        guard case .success(let validated) = result else {
            Issue.record("Expected success")
            return
        }
        #expect(validated.action == .renameTab(tabId: tabId, name: "Review Queue"))
    }

    @Test
    func test_renameTab_multilineName_normalizesToSingleLine() {
        let tabId = UUID()
        let snapshot = makeSnapshot(
            tabs: [TabSnapshot(id: tabId, visiblePaneIds: [UUID()], ownedPaneIds: [UUID()], activePaneId: nil)]
        )

        let result = WorkspaceCommandValidator.validate(
            .renameTab(tabId: tabId, name: "  Review Queue\nFor Launch  "),
            state: snapshot
        )

        guard case .success(let validated) = result else {
            Issue.record("Expected success")
            return
        }
        #expect(validated.action == .renameTab(tabId: tabId, name: "Review Queue For Launch"))
    }

    @Test
    func test_renameTab_missingTab_fails() {
        let result = WorkspaceCommandValidator.validate(
            .renameTab(tabId: UUID(), name: "Review Queue"),
            state: makeSnapshot()
        )

        if case .failure(.tabNotFound) = result { return }
        Issue.record("Expected tabNotFound error")
    }

    @Test
    func test_renameTab_emptyName_fails() {
        let tabId = UUID()
        let snapshot = makeSnapshot(
            tabs: [TabSnapshot(id: tabId, visiblePaneIds: [UUID()], ownedPaneIds: [UUID()], activePaneId: nil)]
        )

        let result = WorkspaceCommandValidator.validate(
            .renameTab(tabId: tabId, name: "   "),
            state: snapshot
        )

        if case .failure(.emptyName) = result { return }
        Issue.record("Expected emptyName error")
    }

    // MARK: - closePane

    @Test

    func test_closePane_multiPaneTab_succeeds() {
        // Arrange
        let (tab, tabId, paneIds) = makeMultiPaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = WorkspaceCommandValidator.validate(
            .closePane(tabId: tabId, paneId: paneIds[0]),
            state: snapshot
        )

        // Assert
        #expect((try? result.get()) != nil)
    }

    @Test

    func test_closePane_singlePaneTab_canonicalizesToCloseTab() {
        // Arrange — single-pane close is canonicalized to closeTab during validation
        let (tab, tabId, paneId) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = WorkspaceCommandValidator.validate(
            .closePane(tabId: tabId, paneId: paneId),
            state: snapshot
        )

        // Assert
        guard case .success(let validated) = result else {
            Issue.record("Expected success")
            return
        }
        #expect(validated.action == .closeTab(tabId: tabId))
    }

    @Test
    func test_focusDrawerPaneLeft_wrongParentFails() {
        let parentPaneId = UUIDv7.generate()
        let otherParentPaneId = UUIDv7.generate()
        let drawerPaneId = UUIDv7.generate()

        let snapshot = makeSnapshot(
            tabs: [
                TabSnapshot(
                    id: UUID(),
                    visiblePaneIds: [parentPaneId, otherParentPaneId],
                    ownedPaneIds: [parentPaneId, otherParentPaneId, drawerPaneId],
                    activePaneId: parentPaneId
                )
            ],
            drawerParentByPaneId: [drawerPaneId: otherParentPaneId]
        )

        let result = WorkspaceCommandValidator.validate(
            .focusDrawerPaneLeft(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId),
            state: snapshot
        )

        if case .failure(.paneNotFound) = result { return }
        Issue.record("Expected paneNotFound for wrong-parent drawer membership")
    }

    @Test
    func test_detachDrawerPane_requiresRealDrawerChild() {
        let parentPaneId = UUIDv7.generate()
        let drawerPaneId = UUIDv7.generate()
        let snapshot = makeSnapshot(
            tabs: [
                TabSnapshot(
                    id: UUID(),
                    visiblePaneIds: [parentPaneId],
                    ownedPaneIds: [parentPaneId],
                    activePaneId: parentPaneId
                )
            ]
        )

        let result = WorkspaceCommandValidator.validate(
            .detachDrawerPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId),
            state: snapshot
        )

        if case .failure(.paneNotFound) = result { return }
        Issue.record("Expected paneNotFound when detach targets a non-drawer child")
    }

    @Test
    func test_insertDrawerPane_thirdRowFailsAtValidatorBoundary() {
        let parentPaneId = UUIDv7.generate()
        let topPaneId = UUIDv7.generate()
        let bottomPaneId = UUIDv7.generate()
        let snapshot = makeSnapshot(
            tabs: [
                TabSnapshot(
                    id: UUID(),
                    visiblePaneIds: [parentPaneId],
                    ownedPaneIds: [parentPaneId, topPaneId, bottomPaneId],
                    activePaneId: parentPaneId
                )
            ],
            isManagementLayerActive: true,
            drawerParentByPaneId: [
                topPaneId: parentPaneId,
                bottomPaneId: parentPaneId,
            ],
            drawerLayoutByParentPaneId: [
                parentPaneId: DrawerGridLayout(
                    topRow: Layout.autoTiled([topPaneId]),
                    bottomRow: Layout.autoTiled([bottomPaneId])
                )
            ]
        )

        let result = WorkspaceCommandValidator.validate(
            .insertDrawerPane(
                parentPaneId: parentPaneId,
                targetDrawerPaneId: bottomPaneId,
                direction: .down,
                sizingMode: .halveTarget
            ),
            state: snapshot
        )

        if case .failure(.invalidDrawerLayout) = result { return }
        Issue.record("Expected invalidDrawerLayout when insert would create a third row")
    }

    @Test

    func test_closePane_paneNotInTab_fails() {
        // Arrange
        let (tab, tabId, _) = makeMultiPaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = WorkspaceCommandValidator.validate(
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
        let result = WorkspaceCommandValidator.validate(
            .closePane(tabId: UUID(), paneId: UUID()),
            state: snapshot
        )

        // Assert
        if case .failure(.tabNotFound) = result { return }
        Issue.record("Expected tabNotFound error")
    }

    @Test

    func test_scrollToBottom_existingPane_succeeds() {
        // Arrange
        let (tab, tabId, paneIds) = makeMultiPaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = WorkspaceCommandValidator.validate(
            .scrollToBottom(tabId: tabId, paneId: paneIds[0]),
            state: snapshot
        )

        // Assert
        #expect((try? result.get()) != nil)
    }

    @Test

    func test_scrollToBottom_missingPane_fails() {
        // Arrange
        let (tab, tabId, _) = makeMultiPaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = WorkspaceCommandValidator.validate(
            .scrollToBottom(tabId: tabId, paneId: UUID()),
            state: snapshot
        )

        // Assert
        if case .failure(.paneNotFound) = result { return }
        Issue.record("Expected paneNotFound error")
    }

    // MARK: - extractPaneToTab

    @Test

    func test_extractPaneToTab_multiPaneTab_succeeds() {
        // Arrange
        let (tab, tabId, paneIds) = makeMultiPaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = WorkspaceCommandValidator.validate(
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
        let result = WorkspaceCommandValidator.validate(
            .extractPaneToTab(tabId: tabId, paneId: paneId),
            state: snapshot
        )

        // Assert
        if case .failure(.singlePaneTab) = result { return }
        Issue.record("Expected singlePaneTab error")
    }

    // MARK: - insertPane (self-insertion bug fix)

    @Test

    func test_insertPane_selfInsertion_fails() {
        // Arrange — THE BUG: dragging a pane onto itself
        let paneId = UUID()
        let tabId = UUID()
        let tab = TabSnapshot(id: tabId, visiblePaneIds: [paneId], ownedPaneIds: [paneId], activePaneId: paneId)
        let snapshot = makeSnapshot(tabs: [tab])
        let action = PaneActionCommand.insertPane(
            source: .existingPane(paneId: paneId, sourceTabId: tabId),
            targetTabId: tabId,
            targetPaneId: paneId,
            direction: .right,
            sizingMode: .halveTarget
        )

        // Act
        let result = WorkspaceCommandValidator.validate(action, state: snapshot)

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
        let sourceTab = TabSnapshot(
            id: sourceTabId,
            visiblePaneIds: [sourcePaneId],
            ownedPaneIds: [sourcePaneId],
            activePaneId: sourcePaneId
        )
        let targetTab = TabSnapshot(
            id: targetTabId,
            visiblePaneIds: [targetPaneId],
            ownedPaneIds: [targetPaneId],
            activePaneId: targetPaneId
        )
        let snapshot = makeSnapshot(tabs: [sourceTab, targetTab])
        let action = PaneActionCommand.insertPane(
            source: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId),
            targetTabId: targetTabId,
            targetPaneId: targetPaneId,
            direction: .right,
            sizingMode: .halveTarget
        )

        // Act
        let result = WorkspaceCommandValidator.validate(action, state: snapshot)

        // Assert
        #expect((try? result.get()) != nil)
    }

    @Test

    func test_insertPane_newTerminal_succeeds() {
        // Arrange
        let (tab, tabId, paneId) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])
        let action = PaneActionCommand.insertPane(
            source: .newTerminal,
            targetTabId: tabId,
            targetPaneId: paneId,
            direction: .down,
            sizingMode: .halveTarget
        )

        // Act
        let result = WorkspaceCommandValidator.validate(action, state: snapshot)

        // Assert
        #expect((try? result.get()) != nil)
    }

    @Test

    func test_insertPane_targetTabMissing_fails() {
        // Arrange
        let snapshot = makeSnapshot()
        let action = PaneActionCommand.insertPane(
            source: .newTerminal,
            targetTabId: UUID(),
            targetPaneId: UUID(),
            direction: .right,
            sizingMode: .halveTarget
        )

        // Act
        let result = WorkspaceCommandValidator.validate(action, state: snapshot)

        // Assert
        if case .failure(.tabNotFound) = result { return }
        Issue.record("Expected tabNotFound error")
    }

    @Test

    func test_insertPane_targetPaneMissing_fails() {
        // Arrange
        let (tab, tabId, _) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])
        let action = PaneActionCommand.insertPane(
            source: .newTerminal,
            targetTabId: tabId,
            targetPaneId: UUID(),
            direction: .right,
            sizingMode: .halveTarget
        )

        // Act
        let result = WorkspaceCommandValidator.validate(action, state: snapshot)

        // Assert
        if case .failure(.paneNotFound) = result { return }
        Issue.record("Expected paneNotFound error")
    }

    @Test

    func test_insertPane_sourcePaneMissing_fails() {
        // Arrange
        let (tab, tabId, paneId) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])
        let action = PaneActionCommand.insertPane(
            source: .existingPane(paneId: UUID(), sourceTabId: UUID()),
            targetTabId: tabId,
            targetPaneId: paneId,
            direction: .right,
            sizingMode: .halveTarget
        )

        // Act
        let result = WorkspaceCommandValidator.validate(action, state: snapshot)

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
        let result = WorkspaceCommandValidator.validate(
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
        let result = WorkspaceCommandValidator.validate(
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
        let result = WorkspaceCommandValidator.validate(
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
        let result = WorkspaceCommandValidator.validate(
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
        let result = WorkspaceCommandValidator.validate(.equalizePanes(tabId: tabId), state: snapshot)

        // Assert
        #expect((try? result.get()) != nil)
    }

    @Test

    func test_equalizePanes_singlePaneTab_fails() {
        // Arrange
        let (tab, tabId, _) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = WorkspaceCommandValidator.validate(.equalizePanes(tabId: tabId), state: snapshot)

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
        let action = PaneActionCommand.mergeTab(
            sourceTabId: sourceTabId,
            targetTabId: targetTabId,
            targetPaneId: targetPaneIds[0],
            direction: .right
        )

        // Act
        let result = WorkspaceCommandValidator.validate(action, state: snapshot)

        // Assert
        #expect((try? result.get()) != nil)
    }

    @Test

    func test_mergeTab_sourceTabMissing_fails() {
        // Arrange
        let (targetTab, targetTabId, targetPaneId) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [targetTab])
        let action = PaneActionCommand.mergeTab(
            sourceTabId: UUID(),
            targetTabId: targetTabId,
            targetPaneId: targetPaneId,
            direction: .right
        )

        // Act
        let result = WorkspaceCommandValidator.validate(action, state: snapshot)

        // Assert
        if case .failure(.tabNotFound) = result { return }
        Issue.record("Expected tabNotFound error")
    }

    @Test

    func test_mergeTab_targetTabMissing_fails() {
        // Arrange
        let (sourceTab, sourceTabId, _) = makeMultiPaneTab()
        let snapshot = makeSnapshot(tabs: [sourceTab])
        let action = PaneActionCommand.mergeTab(
            sourceTabId: sourceTabId,
            targetTabId: UUID(),
            targetPaneId: UUID(),
            direction: .right
        )

        // Act
        let result = WorkspaceCommandValidator.validate(action, state: snapshot)

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
        let action = PaneActionCommand.mergeTab(
            sourceTabId: sourceTabId,
            targetTabId: targetTabId,
            targetPaneId: UUID(),
            direction: .right
        )

        // Act
        let result = WorkspaceCommandValidator.validate(action, state: snapshot)

        // Assert
        if case .failure(.paneNotFound) = result { return }
        Issue.record("Expected paneNotFound error")
    }

    @Test

    func test_mergeTab_selfMerge_fails() {
        // Arrange
        let (tab, tabId, paneIds) = makeMultiPaneTab()
        let snapshot = makeSnapshot(tabs: [tab])
        let action = PaneActionCommand.mergeTab(
            sourceTabId: tabId,
            targetTabId: tabId,
            targetPaneId: paneIds[0],
            direction: .right
        )

        // Act
        let result = WorkspaceCommandValidator.validate(action, state: snapshot)

        // Assert
        if case .failure(.selfTabMerge) = result { return }
        Issue.record("Expected selfTabMerge error")
    }

    // MARK: - System Actions (trusted, skip validation)

    @Test

    func test_expireUndoEntry_alwaysSucceeds() {
        // Arrange — empty state, no tabs at all
        let snapshot = makeSnapshot()
        let action = PaneActionCommand.expireUndoEntry(paneId: UUID())

        // Act
        let result = WorkspaceCommandValidator.validate(action, state: snapshot)

        // Assert
        #expect((try? result.get()) != nil)
    }

    @Test

    func test_repair_alwaysSucceeds() {
        // Arrange
        let snapshot = makeSnapshot()
        let action = PaneActionCommand.repair(.recreateSurface(paneId: UUID()))

        // Act
        let result = WorkspaceCommandValidator.validate(action, state: snapshot)

        // Assert
        #expect((try? result.get()) != nil)
    }

    // MARK: - Pane Cardinality

    @Test

    func test_paneCardinality_newPane_succeeds() {
        // Arrange
        let existingPaneId = UUID()
        let newPaneId = UUID()
        let tab = TabSnapshot(
            id: UUID(),
            visiblePaneIds: [existingPaneId],
            ownedPaneIds: [existingPaneId],
            activePaneId: existingPaneId
        )
        let snapshot = makeSnapshot(tabs: [tab])

        // Act
        let result = WorkspaceCommandValidator.validatePaneCardinality(
            paneId: newPaneId, state: snapshot
        )

        // Assert
        #expect((try? result.get()) != nil)
    }

    @Test

    func test_paneCardinality_emptyState_succeeds() {
        // Arrange
        let snapshot = makeSnapshot()

        // Act
        let result = WorkspaceCommandValidator.validatePaneCardinality(
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
        let snapshot = makeSnapshot(
            tabs: [TabSnapshot(id: tabId, visiblePaneIds: [UUID()], ownedPaneIds: [UUID()], activePaneId: nil)]
        )
        let action = PaneActionCommand.selectTab(tabId: tabId)

        // Act
        let result = WorkspaceCommandValidator.validate(action, state: snapshot)

        // Assert
        if case .success(let validated) = result {
            #expect(validated.action == action)
        } else {
            Issue.record("Expected success")
        }
    }
}
