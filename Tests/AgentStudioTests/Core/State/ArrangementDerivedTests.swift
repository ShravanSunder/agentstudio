import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class ArrangementDerivedTests {

    private var registry: AtomRegistry!
    private var store: WorkspaceStore!

    init() {
        registry = AtomRegistry()
        store = WorkspaceStore(
            metadataAtom: registry.workspaceMetadata,
            repositoryTopologyAtom: registry.workspaceRepositoryTopology,
            paneAtom: registry.workspacePane,
            tabLayoutAtom: registry.workspaceTabLayout,
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            )
        )
    }

    @Test
    func paneVisibilityItems_returnsAllPanesWithMinimizedState() {
        AtomScope.$override.withValue(registry) {
            let firstPane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
            let tab = Tab(paneId: firstPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)

            let secondPane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
            _ = store.insertPane(
                secondPane.id,
                inTab: tab.id,
                at: firstPane.id,
                direction: .horizontal,
                position: .after
            )
            _ = store.minimizePane(secondPane.id, inTab: tab.id)

            let derived = ArrangementDerived()
            let items = derived.paneVisibilityItems(for: tab.id)

            #expect(items.count == 2)
            #expect(items[0].id == firstPane.id)
            #expect(items[0].isMinimized == false)
            #expect(items[1].id == secondPane.id)
            #expect(items[1].isMinimized == true)
        }
    }

    @Test
    func arrangementItems_returnsArrangementsWithActiveState() {
        AtomScope.$override.withValue(registry) {
            let pane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
            let tab = Tab(paneId: pane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)

            let derived = ArrangementDerived()
            let items = derived.arrangementItems(for: tab.id)

            #expect(items.count == 1)
            #expect(items[0].name == "Default")
            #expect(items[0].isDefault == true)
            #expect(items[0].isActive == true)
        }
    }

    @Test
    func paneVisibilityItems_invalidTab_returnsEmpty() {
        AtomScope.$override.withValue(registry) {
            let derived = ArrangementDerived()

            #expect(derived.paneVisibilityItems(for: UUID()).isEmpty)
        }
    }

    @Test
    func arrangementItems_marksOnlyActiveArrangement() throws {
        try AtomScope.$override.withValue(registry) {
            let firstPane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
            let secondPane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
            let tab = Tab(paneId: firstPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            _ = store.insertPane(
                secondPane.id,
                inTab: tab.id,
                at: firstPane.id,
                direction: .horizontal,
                position: .after
            )
            let arrangementId = try #require(
                store.createArrangement(
                    name: "Focus",
                    paneIds: [firstPane.id],
                    inTab: tab.id
                )
            )
            store.switchArrangement(to: arrangementId, inTab: tab.id)

            let items = ArrangementDerived().arrangementItems(for: tab.id)

            #expect(items.count == 2)
            #expect(items.first(where: { $0.id == arrangementId })?.isActive == true)
            #expect(items.first(where: { $0.id != arrangementId })?.isActive == false)
        }
    }
}
