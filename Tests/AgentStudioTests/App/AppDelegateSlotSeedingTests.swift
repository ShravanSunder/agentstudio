import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct AppDelegateSlotSeedingTests {
    @Test("seedSlotsForRestoredPanes seeds every restored pane id including drawer panes")
    func seedSlotsForRestoredPanes_seedsAllRestoredPaneIds() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "app-delegate-slot-seeding-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store1 = WorkspaceStore(persistor: persistor)
        store1.restore()

        let parentPane = store1.createPane(
            source: .floating(workingDirectory: tempDir, title: "Parent"),
            provider: .zmx
        )
        let restoredTab = Tab(paneId: parentPane.id, name: "Restored")
        store1.appendTab(restoredTab)
        let drawerPane = try #require(store1.addDrawerPane(to: parentPane.id))
        store1.flush()

        let restoredStore = WorkspaceStore(persistor: persistor)
        restoredStore.restore()

        let appDelegate = AppDelegate()
        appDelegate.store = restoredStore
        appDelegate.viewRegistry = ViewRegistry()

        appDelegate.seedSlotsForRestoredPanes()

        #expect(
            appDelegate.viewRegistry.slotPaneIdsForTesting
                == Set([parentPane.id, drawerPane.id])
        )
        #expect(appDelegate.viewRegistry.slotPaneIdsForTesting == Set(restoredStore.panes.keys))
    }
}
