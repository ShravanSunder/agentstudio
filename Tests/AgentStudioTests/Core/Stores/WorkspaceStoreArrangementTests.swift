import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class WorkspaceStoreArrangementTests {

    private var store: WorkspaceStore!

    init() {
        store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner())
    }

    // MARK: - Helpers

    /// Create a tab with N panes and return (tab, paneIds).
    private func createTabWithPanes(_ count: Int) -> (Tab, [UUID]) {
        let first = store.createPane()
        let tab = Tab(paneId: first.id)
        store.appendTab(tab)

        var paneIds = [first.id]
        for _ in 1..<count {
            let pane = store.createPane()
            store.insertPane(
                pane.id, inTab: tab.id, at: paneIds.last!,
                direction: .horizontal, position: .after, sizingMode: .halveTarget
            )
            paneIds.append(pane.id)
        }
        return (store.tab(tab.id)!, paneIds)
    }

    // MARK: - createArrangement

    @Test

    func test_createArrangement_copiesCompleteActiveView() {
        // Arrange
        let (tab, paneIds) = createTabWithPanes(3)

        // Act
        let arrId = store.createArrangement(name: "Focus", inTab: tab.id)

        // Assert
        #expect((arrId) != nil)
        let updatedTab = store.tab(tab.id)!
        #expect(updatedTab.arrangements.count == 2)

        let custom = updatedTab.arrangements.first { $0.id == arrId }!
        #expect(custom.name == "Focus")
        #expect(!(custom.isDefault))
        #expect(custom.layout.paneIds == paneIds)
    }

    @Test

    func test_createArrangement_hasNoSubsetInputAndCreatesCompleteView() {
        let (tab, paneIds) = createTabWithPanes(3)

        let arrId = store.createArrangement(
            name: "Solo",
            inTab: tab.id
        )

        #expect((arrId) != nil)
        let custom = store.tab(tab.id)!.arrangements.first { $0.id == arrId }!
        #expect(Set(custom.layout.paneIds) == Set(paneIds))
    }

    @Test

    func test_createArrangement_allPanes_effectiveDuplicate() {
        let (tab, paneIds) = createTabWithPanes(2)

        let arrId = store.createArrangement(
            name: "All",
            inTab: tab.id
        )

        #expect((arrId) != nil)
        let custom = store.tab(tab.id)!.arrangements.first { $0.id == arrId }!
        #expect(Set(custom.layout.paneIds) == Set(paneIds))
    }

    @Test

    func test_createArrangement_emptyTabPaneSetStillCreatesNoSubsetState() {
        let (tab, paneIds) = createTabWithPanes(2)

        let arrId = store.createArrangement(
            name: "Empty",
            inTab: tab.id
        )

        #expect((arrId) != nil)
        let custom = store.tab(tab.id)!.arrangements.first { $0.id == arrId }!
        #expect(Set(custom.layout.paneIds) == Set(paneIds))
    }

    @Test

    func test_createArrangement_completeViewDoesNotDependOnCallerPaneSelection() {
        let (tab, paneIds) = createTabWithPanes(2)

        let arrId = store.createArrangement(
            name: "Bad",
            inTab: tab.id
        )

        #expect((arrId) != nil)
        let custom = store.tab(tab.id)!.arrangements.first { $0.id == arrId }!
        #expect(Set(custom.layout.paneIds) == Set(paneIds))
    }

    @Test

    func test_createArrangement_marksDirty() async {
        let (tab, _) = createTabWithPanes(2)
        _ = await store.flushAsync()
        _ = store.createArrangement(
            name: "Test",
            inTab: tab.id
        )

        #expect(store.isDirty)
    }

    @Test
    func test_createArrangement_inheritsMinimizedStateForIncludedPanes() {
        let (tab, paneIds) = createTabWithPanes(3)
        _ = store.minimizePane(paneIds[1], inTab: tab.id)

        let arrId = store.createArrangement(
            name: "#1",
            inTab: tab.id
        )!

        let custom = store.tab(tab.id)!.arrangements.first { $0.id == arrId }!
        #expect(custom.minimizedPaneIds == Set([paneIds[1]]))
    }

    // MARK: - switchArrangement

    @Test

    func test_switchArrangement_changesActiveArrangement() {
        let (tab, paneIds) = createTabWithPanes(3)
        let arrId = store.createArrangement(
            name: "Focus",
            inTab: tab.id
        )!

        // Act
        store.switchArrangement(to: arrId, inTab: tab.id)

        // Assert
        let updatedTab = store.tab(tab.id)!
        #expect(updatedTab.activeArrangementId == arrId)
        #expect(Set(updatedTab.paneIds) == Set(paneIds))
    }

    @Test

    func test_switchArrangement_clearsZoom() {
        let (tab, paneIds) = createTabWithPanes(3)
        let arrId = store.createArrangement(
            name: "Focus",
            inTab: tab.id
        )!
        store.toggleZoom(paneId: paneIds[0], inTab: tab.id)

        store.switchArrangement(to: arrId, inTab: tab.id)

        #expect((store.tab(tab.id)!.zoomedPaneId) == nil)
    }

    @Test

    func test_switchArrangement_restoresTargetArrangementActivePaneWhenCurrentPaneDiffers() {
        let (tab, paneIds) = createTabWithPanes(3)
        let arrId = store.createArrangement(
            name: "Focus",
            inTab: tab.id
        )!

        store.setActivePane(paneIds[2], inTab: tab.id)

        store.switchArrangement(to: arrId, inTab: tab.id)

        #expect(store.tab(tab.id)!.activePaneId == paneIds[2])
    }

    @Test

    func test_switchArrangement_restoresTargetArrangementActivePane() {
        let (tab, paneIds) = createTabWithPanes(3)
        let arrId = store.createArrangement(
            name: "Focus",
            inTab: tab.id
        )!

        store.setActivePane(paneIds[1], inTab: tab.id)

        store.switchArrangement(to: arrId, inTab: tab.id)

        #expect(store.tab(tab.id)!.activePaneId == paneIds[2])
    }

    @Test
    func test_switchArrangement_replacesActivePaneWhenTargetMarksItMinimized() {
        let (tab, paneIds) = createTabWithPanes(3)
        let arrId = store.createArrangement(
            name: "#1",
            inTab: tab.id
        )!
        store.renameArrangement(arrId, name: "#1", inTab: tab.id)
        store.switchArrangement(to: arrId, inTab: tab.id)
        _ = store.minimizePane(paneIds[1], inTab: tab.id)
        store.switchArrangement(to: tab.defaultArrangement.id, inTab: tab.id)
        store.setActivePane(paneIds[1], inTab: tab.id)

        store.switchArrangement(to: arrId, inTab: tab.id)

        #expect(store.tab(tab.id)!.activePaneId == paneIds[2])
    }

    @Test
    func test_switchArrangement_allTargetPanesMinimized_setsActivePaneIdNil() {
        let (tab, paneIds) = createTabWithPanes(3)
        let arrId = store.createArrangement(
            name: "#1",
            inTab: tab.id
        )!

        store.switchArrangement(to: arrId, inTab: tab.id)
        _ = store.minimizePane(paneIds[0], inTab: tab.id)
        _ = store.minimizePane(paneIds[1], inTab: tab.id)
        _ = store.minimizePane(paneIds[2], inTab: tab.id)
        store.switchArrangement(to: tab.defaultArrangement.id, inTab: tab.id)

        store.switchArrangement(to: arrId, inTab: tab.id)

        #expect(store.tab(tab.id)!.activePaneId == nil)
    }

    @Test

    func test_switchArrangement_sameArrangement_noOp() async {
        let (tab, _) = createTabWithPanes(2)
        let defaultArrId = store.tab(tab.id)!.activeArrangementId
        _ = await store.flushAsync()
        store.switchArrangement(to: defaultArrId, inTab: tab.id)

        // No change, so isDirty should NOT have been set by the switch
        #expect(!(store.isDirty))
    }

    @Test

    func test_switchArrangement_invalidArrangementId_noOp() {
        let (tab, _) = createTabWithPanes(2)
        let originalArrId = store.tab(tab.id)!.activeArrangementId

        store.switchArrangement(to: UUID(), inTab: tab.id)

        #expect(store.tab(tab.id)!.activeArrangementId == originalArrId)
    }

    // MARK: - removeArrangement

    @Test

    func test_removeArrangement_removesCustom() {
        let (tab, _) = createTabWithPanes(2)
        let arrId = store.createArrangement(
            name: "Focus",
            inTab: tab.id
        )!

        store.removeArrangement(arrId, inTab: tab.id)

        #expect(store.tab(tab.id)!.arrangements.count == 1)  // only default remains
    }

    @Test

    func test_removeArrangement_cannotRemoveDefault() {
        let (tab, _) = createTabWithPanes(2)
        let defaultArrId = store.tab(tab.id)!.defaultArrangement.id

        store.removeArrangement(defaultArrId, inTab: tab.id)

        // Should still have the default
        #expect(store.tab(tab.id)!.arrangements.count == 1)
    }

    @Test

    func test_removeArrangement_activeArrangement_switchesToDefault() {
        let (tab, _) = createTabWithPanes(3)
        let arrId = store.createArrangement(
            name: "Focus",
            inTab: tab.id
        )!
        store.switchArrangement(to: arrId, inTab: tab.id)
        #expect(store.tab(tab.id)!.activeArrangementId == arrId)

        store.removeArrangement(arrId, inTab: tab.id)

        let updatedTab = store.tab(tab.id)!
        #expect(updatedTab.activeArrangementId == updatedTab.defaultArrangement.id)
        #expect(updatedTab.arrangements.count == 1)
    }

    @Test
    func test_removeArrangement_activeArrangement_fallbackSkipsMinimizedPane() {
        let (tab, paneIds) = createTabWithPanes(3)
        _ = store.minimizePane(paneIds[0], inTab: tab.id)
        let arrId = store.createArrangement(
            name: "#1",
            inTab: tab.id
        )!
        store.switchArrangement(to: arrId, inTab: tab.id)
        store.setActivePane(paneIds[1], inTab: tab.id)

        store.removeArrangement(arrId, inTab: tab.id)

        let updatedTab = store.tab(tab.id)!
        #expect(updatedTab.activeArrangementId == updatedTab.defaultArrangement.id)
        #expect(updatedTab.activePaneId == paneIds[2])
        #expect(updatedTab.defaultArrangement.minimizedPaneIds.contains(paneIds[0]))
    }

    @Test

    func test_removeArrangement_inactiveArrangement_doesNotChangeActive() {
        let (tab, _) = createTabWithPanes(3)
        let arr1 = store.createArrangement(name: "A", inTab: tab.id)!
        _ = store.createArrangement(name: "B", inTab: tab.id)!
        store.switchArrangement(to: arr1, inTab: tab.id)

        // Remove B (not active)
        let bId = store.tab(tab.id)!.arrangements.last!.id
        store.removeArrangement(bId, inTab: tab.id)

        #expect(store.tab(tab.id)!.activeArrangementId == arr1)
        #expect(store.tab(tab.id)!.arrangements.count == 2)  // default + A
    }

    // MARK: - renameArrangement

    @Test

    func test_renameArrangement_changesName() {
        let (tab, _) = createTabWithPanes(2)
        let arrId = store.createArrangement(
            name: "Old Name",
            inTab: tab.id
        )!

        store.renameArrangement(arrId, name: "New Name", inTab: tab.id)

        let arr = store.tab(tab.id)!.arrangements.first { $0.id == arrId }!
        #expect(arr.name == "New Name")
    }

    @Test

    func test_renameArrangement_invalidId_noOp() {
        let (tab, _) = createTabWithPanes(2)

        // Should not crash
        store.renameArrangement(UUID(), name: "Nope", inTab: tab.id)
    }

    // MARK: - renameTab

    @Test
    func test_renameTab_changesName() {
        let (tab, _) = createTabWithPanes(2)

        store.renameTab(tab.id, name: "Review Queue")

        #expect(store.tab(tab.id)?.name == "Review Queue")
    }

    @Test
    func test_renameTab_trimsWhitespace() {
        let (tab, _) = createTabWithPanes(1)

        store.renameTab(tab.id, name: "  Review Queue  ")

        #expect(store.tab(tab.id)?.name == "Review Queue")
    }

    @Test
    func test_renameTab_multilineName_normalizesToSingleLine() {
        let (tab, _) = createTabWithPanes(1)

        store.renameTab(tab.id, name: "  Review Queue\nFor Launch  ")

        #expect(store.tab(tab.id)?.name == "Review Queue For Launch")
    }

    @Test
    func test_renameTab_invalidId_noOp() {
        let (tab, _) = createTabWithPanes(1)
        let originalName = store.tab(tab.id)?.name

        store.renameTab(UUID(), name: "Nope")

        #expect(store.tab(tab.id)?.name == originalName)
    }

    // MARK: - Arrangement + Layout Mutations Interaction

    @Test

    func test_insertPane_inCustomArrangement_alsoAddsToDefault() {
        let (tab, paneIds) = createTabWithPanes(2)
        let arrId = store.createArrangement(
            name: "Focus",
            inTab: tab.id
        )!
        store.switchArrangement(to: arrId, inTab: tab.id)

        // Insert a new pane while in custom arrangement
        let newPane = store.createPane()
        store.insertPane(
            newPane.id, inTab: tab.id, at: paneIds[0],
            direction: .horizontal, position: .after, sizingMode: .halveTarget
        )

        // Should be in custom arrangement (active)
        let customArr = store.tab(tab.id)!.arrangements.first { $0.id == arrId }!
        #expect(customArr.layout.contains(newPane.id))

        // Should also be in default arrangement (since pane[0] is there)
        let defaultArr = store.tab(tab.id)!.defaultArrangement
        #expect(defaultArr.layout.contains(newPane.id))
    }

    @Test

    func test_removePaneFromLayout_inCustomArrangement_alsoRemovesFromDefault() {
        let (tab, paneIds) = createTabWithPanes(3)
        let arrId = store.createArrangement(
            name: "Focus",
            inTab: tab.id
        )!
        store.switchArrangement(to: arrId, inTab: tab.id)

        // Remove pane[1] from active (custom) arrangement
        store.removePaneFromLayout(paneIds[1], inTab: tab.id)

        // Should be removed from custom
        let customArr = store.tab(tab.id)!.arrangements.first { $0.id == arrId }!
        #expect(!(customArr.layout.contains(paneIds[1])))

        // Should also be removed from default
        let defaultArr = store.tab(tab.id)!.defaultArrangement
        #expect(!(defaultArr.layout.contains(paneIds[1])))
    }

    // MARK: - Persistence Round-Trip
}
