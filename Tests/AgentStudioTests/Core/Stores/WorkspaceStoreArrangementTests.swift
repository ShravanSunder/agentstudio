import Testing
import Foundation

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class WorkspaceStoreArrangementTests {

    private var store: WorkspaceStore!

    @BeforeEach
    func setUp() {
        store = WorkspaceStore(
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)))
    }

    // MARK: - Helpers

    /// Create a tab with N panes and return (tab, paneIds).
    private func createTabWithPanes(_ count: Int) -> (Tab, [UUID]) {
        let first = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: first.id)
        store.appendTab(tab)

        var paneIds = [first.id]
        for _ in 1..<count {
            let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
            store.insertPane(
                pane.id, inTab: tab.id, at: paneIds.last!,
                direction: .horizontal, position: .after
            )
            paneIds.append(pane.id)
        }
        return (store.tab(tab.id)!, paneIds)
    }

    // MARK: - createArrangement

    @Test

    func test_createArrangement_subsetOfPanes() {
        // Arrange
        let (tab, paneIds) = createTabWithPanes(3)

        // Act
        let arrId = store.createArrangement(
            name: "Focus",
            paneIds: Set([paneIds[0], paneIds[1]]),
            inTab: tab.id
        )

        // Assert
        #expect((arrId) != nil)
        let updatedTab = store.tab(tab.id)!
        #expect(updatedTab.arrangements.count == 2)

        let custom = updatedTab.arrangements.first { $0.id == arrId }!
        #expect(custom.name == "Focus")
        #expect(!(custom.isDefault))
        #expect(Set(custom.layout.paneIds) == Set([paneIds[0], paneIds[1]]))
        #expect(custom.visiblePaneIds == Set([paneIds[0], paneIds[1]]))
    }

    @Test

    func test_createArrangement_singlePane() {
        let (tab, paneIds) = createTabWithPanes(3)

        let arrId = store.createArrangement(
            name: "Solo",
            paneIds: Set([paneIds[2]]),
            inTab: tab.id
        )

        #expect((arrId) != nil)
        let custom = store.tab(tab.id)!.arrangements.first { $0.id == arrId }!
        #expect(custom.layout.paneIds == [paneIds[2]])
    }

    @Test

    func test_createArrangement_allPanes_effectiveDuplicate() {
        let (tab, paneIds) = createTabWithPanes(2)

        let arrId = store.createArrangement(
            name: "All",
            paneIds: Set(paneIds),
            inTab: tab.id
        )

        #expect((arrId) != nil)
        let custom = store.tab(tab.id)!.arrangements.first { $0.id == arrId }!
        #expect(Set(custom.layout.paneIds) == Set(paneIds))
    }

    @Test

    func test_createArrangement_emptyPanes_returnsNil() {
        let (tab, _) = createTabWithPanes(2)

        let arrId = store.createArrangement(
            name: "Empty",
            paneIds: Set(),
            inTab: tab.id
        )

        #expect((arrId) == nil)
        #expect(store.tab(tab.id)!.arrangements.count == 1)  // only default
    }

    @Test

    func test_createArrangement_invalidPaneId_returnsNil() {
        let (tab, _) = createTabWithPanes(2)

        let arrId = store.createArrangement(
            name: "Bad",
            paneIds: Set([UUID()]),
            inTab: tab.id
        )

        #expect((arrId) == nil)
    }

    @Test

    func test_createArrangement_marksDirty() {
        let (tab, paneIds) = createTabWithPanes(2)
        store.flush()

        _ = store.createArrangement(
            name: "Test",
            paneIds: Set([paneIds[0]]),
            inTab: tab.id
        )

        #expect(store.isDirty)
    }

    // MARK: - switchArrangement

    @Test

    func test_switchArrangement_changesActiveArrangement() {
        let (tab, paneIds) = createTabWithPanes(3)
        let arrId = store.createArrangement(
            name: "Focus",
            paneIds: Set([paneIds[0], paneIds[1]]),
            inTab: tab.id
        )!

        // Act
        store.switchArrangement(to: arrId, inTab: tab.id)

        // Assert
        let updatedTab = store.tab(tab.id)!
        #expect(updatedTab.activeArrangementId == arrId)
        #expect(Set(updatedTab.paneIds) == Set([paneIds[0], paneIds[1]]))
    }

    @Test

    func test_switchArrangement_clearsZoom() {
        let (tab, paneIds) = createTabWithPanes(3)
        let arrId = store.createArrangement(
            name: "Focus",
            paneIds: Set([paneIds[0], paneIds[1]]),
            inTab: tab.id
        )!
        store.toggleZoom(paneId: paneIds[0], inTab: tab.id)

        store.switchArrangement(to: arrId, inTab: tab.id)

        #expect((store.tab(tab.id)!.zoomedPaneId) == nil)
    }

    @Test

    func test_switchArrangement_updatesActivePaneIdIfNotInNewArrangement() {
        let (tab, paneIds) = createTabWithPanes(3)
        // Focus arrangement has panes 0 and 1 only
        let arrId = store.createArrangement(
            name: "Focus",
            paneIds: Set([paneIds[0], paneIds[1]]),
            inTab: tab.id
        )!

        // Set active pane to one NOT in focus arrangement
        store.setActivePane(paneIds[2], inTab: tab.id)

        // Act
        store.switchArrangement(to: arrId, inTab: tab.id)

        // Assert: active pane should be reset to one in the arrangement
        let activePaneId = store.tab(tab.id)!.activePaneId
        #expect((activePaneId) != nil)
        #expect([paneIds[0], paneIds[1]].contains(activePaneId!))
    }

    @Test

    func test_switchArrangement_keepActivePaneIfInNewArrangement() {
        let (tab, paneIds) = createTabWithPanes(3)
        let arrId = store.createArrangement(
            name: "Focus",
            paneIds: Set([paneIds[0], paneIds[1]]),
            inTab: tab.id
        )!

        // Set active pane to one IN focus arrangement
        store.setActivePane(paneIds[1], inTab: tab.id)

        store.switchArrangement(to: arrId, inTab: tab.id)

        #expect(store.tab(tab.id)!.activePaneId == paneIds[1])
    }

    @Test

    func test_switchArrangement_sameArrangement_noOp() {
        let (tab, _) = createTabWithPanes(2)
        let defaultArrId = store.tab(tab.id)!.activeArrangementId
        store.flush()

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
        let (tab, paneIds) = createTabWithPanes(2)
        let arrId = store.createArrangement(
            name: "Focus",
            paneIds: Set([paneIds[0]]),
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
        let (tab, paneIds) = createTabWithPanes(3)
        let arrId = store.createArrangement(
            name: "Focus",
            paneIds: Set([paneIds[0]]),
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

    func test_removeArrangement_inactiveArrangement_doesNotChangeActive() {
        let (tab, paneIds) = createTabWithPanes(3)
        let arr1 = store.createArrangement(name: "A", paneIds: Set([paneIds[0]]), inTab: tab.id)!
        _ = store.createArrangement(name: "B", paneIds: Set([paneIds[1]]), inTab: tab.id)!
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
        let (tab, paneIds) = createTabWithPanes(2)
        let arrId = store.createArrangement(
            name: "Old Name",
            paneIds: Set([paneIds[0]]),
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

    // MARK: - Arrangement + Layout Mutations Interaction

    @Test

    func test_insertPane_inCustomArrangement_alsoAddsToDefault() {
        let (tab, paneIds) = createTabWithPanes(2)
        let arrId = store.createArrangement(
            name: "Focus",
            paneIds: Set([paneIds[0]]),
            inTab: tab.id
        )!
        store.switchArrangement(to: arrId, inTab: tab.id)

        // Insert a new pane while in custom arrangement
        let newPane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        store.insertPane(
            newPane.id, inTab: tab.id, at: paneIds[0],
            direction: .horizontal, position: .after
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
            paneIds: Set([paneIds[0], paneIds[1]]),
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

    @Test

    func test_arrangement_persistsAndRestores() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "arr-persist-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store1 = WorkspaceStore(persistor: persistor)

        let pane1 = store1.createPane(source: .floating(workingDirectory: nil, title: nil))
        let pane2 = store1.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane1.id)
        store1.appendTab(tab)
        store1.insertPane(
            pane2.id, inTab: tab.id, at: pane1.id,
            direction: .horizontal, position: .after
        )

        let arrId = store1.createArrangement(
            name: "Focus",
            paneIds: Set([pane1.id]),
            inTab: tab.id
        )!
        store1.switchArrangement(to: arrId, inTab: tab.id)
        store1.flush()

        // Restore into a new store
        let store2 = WorkspaceStore(persistor: persistor)
        store2.restore()

        let restoredTab = store2.tabs.first!
        #expect(restoredTab.arrangements.count == 2)

        let restoredCustom = restoredTab.arrangements.first { !$0.isDefault }!
        #expect(restoredCustom.name == "Focus")
        #expect(restoredCustom.layout.paneIds == [pane1.id])
        #expect(restoredTab.activeArrangementId == arrId)

        try? FileManager.default.removeItem(at: tempDir)
    }
}
