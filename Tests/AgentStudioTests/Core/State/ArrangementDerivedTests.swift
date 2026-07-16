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
            workspacePersistenceRevisionOwner: registry.workspacePersistenceRevisionOwner,
            identityAtom: registry.workspaceIdentity,
            windowMemoryAtom: registry.workspaceWindowMemory,
            repositoryTopologyAtom: registry.workspaceRepositoryTopology,
            paneAtom: registry.workspacePane,
            tabLayoutAtom: registry.workspaceTabLayout)
    }

    @Test
    func paneVisibilityItems_returnsAllPanesWithMinimizedState() {
        AtomScope.$override.withValue(registry) {
            let firstPane = store.createPane()
            let tab = Tab(paneId: firstPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)

            let secondPane = store.createPane()
            _ = store.insertPane(
                secondPane.id,
                inTab: tab.id,
                at: firstPane.id,
                direction: .horizontal,
                position: .after, sizingMode: .halveTarget
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
            let pane = store.createPane()
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
            let firstPane = store.createPane()
            let secondPane = store.createPane()
            let tab = Tab(paneId: firstPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            _ = store.insertPane(
                secondPane.id,
                inTab: tab.id,
                at: firstPane.id,
                direction: .horizontal,
                position: .after, sizingMode: .halveTarget
            )
            let arrangementId = try #require(
                store.createArrangement(
                    name: "Focus",
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

    @Test
    func nextCustomArrangementName_startsAtLayoutOne() {
        AtomScope.$override.withValue(registry) {
            let pane = store.createPane()
            let tab = Tab(paneId: pane.id)
            store.appendTab(tab)

            let derived = ArrangementDerived()
            #expect(derived.nextCustomArrangementName(for: tab.id) == "Layout 1")
        }
    }

    @Test
    func nextCustomArrangementName_skipsUsedIndexes() throws {
        try AtomScope.$override.withValue(registry) {
            let firstPane = store.createPane()
            let tab = Tab(paneId: firstPane.id)
            store.appendTab(tab)

            let secondPane = store.createPane()
            let thirdPane = store.createPane()
            _ = store.insertPane(
                secondPane.id,
                inTab: tab.id,
                at: firstPane.id,
                direction: .horizontal,
                position: .after, sizingMode: .halveTarget
            )
            _ = store.insertPane(
                thirdPane.id,
                inTab: tab.id,
                at: secondPane.id,
                direction: .horizontal,
                position: .after, sizingMode: .halveTarget
            )

            _ = try #require(
                store.createArrangement(
                    name: "Layout 1",
                    inTab: tab.id
                )
            )
            _ = try #require(
                store.createArrangement(
                    name: "Layout 2",
                    inTab: tab.id
                )
            )

            let derived = ArrangementDerived()
            #expect(derived.nextCustomArrangementName(for: tab.id) == "Layout 3")
        }
    }

    @Test
    func paneVisibilityItems_restoresMinimizedStateWhenSwitchingBackToArrangement() throws {
        try AtomScope.$override.withValue(registry) {
            let firstPane = store.createPane()
            let tab = Tab(paneId: firstPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)

            let secondPane = store.createPane()
            let thirdPane = store.createPane()
            _ = store.insertPane(
                secondPane.id,
                inTab: tab.id,
                at: firstPane.id,
                direction: .horizontal,
                position: .after, sizingMode: .halveTarget
            )
            _ = store.insertPane(
                thirdPane.id,
                inTab: tab.id,
                at: secondPane.id,
                direction: .horizontal,
                position: .after, sizingMode: .halveTarget
            )

            _ = store.minimizePane(secondPane.id, inTab: tab.id)
            let focusArrangementId = try #require(
                store.createArrangement(
                    name: "Focus",
                    inTab: tab.id
                )
            )

            store.switchArrangement(to: focusArrangementId, inTab: tab.id)
            store.switchArrangement(to: tab.defaultArrangement.id, inTab: tab.id)

            let items = ArrangementDerived().paneVisibilityItems(for: tab.id)
            #expect(items.first(where: { $0.id == secondPane.id })?.isMinimized == true)
        }
    }
}
