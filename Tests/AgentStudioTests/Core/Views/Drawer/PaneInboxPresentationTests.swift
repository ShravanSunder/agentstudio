import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("PaneInboxPresentation")
struct PaneInboxPresentationTests {
    @Test("pane inbox scope resolves parent panes to parent plus drawer children")
    func paneInboxScopeResolvesParentPane() throws {
        let parentPaneId = UUIDv7.generate()
        let firstDrawerPaneId = UUIDv7.generate()
        let secondDrawerPaneId = UUIDv7.generate()
        let panes = makePaneLookup(
            parentPaneId: parentPaneId,
            drawerPaneIds: [firstDrawerPaneId, secondDrawerPaneId]
        )

        let scope = PaneInboxScopeResolver.resolve(
            anchorPaneId: parentPaneId,
            pane: { panes[$0] }
        )

        #expect(scope.parentPaneId == parentPaneId)
        #expect(scope.paneIds == [parentPaneId, firstDrawerPaneId, secondDrawerPaneId])
    }

    @Test("pane inbox scope resolves drawer child panes to parent plus sibling drawer children")
    func paneInboxScopeResolvesDrawerChildPane() throws {
        let parentPaneId = UUIDv7.generate()
        let firstDrawerPaneId = UUIDv7.generate()
        let secondDrawerPaneId = UUIDv7.generate()
        let panes = makePaneLookup(
            parentPaneId: parentPaneId,
            drawerPaneIds: [firstDrawerPaneId, secondDrawerPaneId]
        )

        let scope = PaneInboxScopeResolver.resolve(
            anchorPaneId: firstDrawerPaneId,
            pane: { panes[$0] }
        )

        #expect(scope.parentPaneId == parentPaneId)
        #expect(scope.paneIds == [parentPaneId, firstDrawerPaneId, secondDrawerPaneId])
    }

    private func makePaneLookup(
        parentPaneId: UUID,
        drawerPaneIds: [UUID]
    ) -> [UUID: Pane] {
        var drawer = Drawer()
        drawer.paneIds = drawerPaneIds

        var parentPane = makePane(id: parentPaneId, title: "Parent")
        parentPane.kind = .layout(drawer: drawer)
        let drawerPanes = drawerPaneIds.map { drawerPaneId in
            var drawerPane = makePane(id: drawerPaneId, title: "Drawer")
            drawerPane.kind = .drawerChild(parentPaneId: parentPaneId)
            return drawerPane
        }

        return Dictionary(
            uniqueKeysWithValues: ([parentPane] + drawerPanes).map { pane in
                (pane.id, pane)
            }
        )
    }

}
