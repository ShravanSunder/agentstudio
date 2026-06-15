import Foundation
import Testing

@testable import AgentStudio

@Suite("PaneObservationResolver")
struct PaneObservationResolverTests {
    @Test("expanded drawer redirects attended pane to active drawer child")
    func expandedDrawerRedirectsAttendedPaneToActiveDrawerChild() {
        let parentId = UUIDv7.generate()
        let childId = UUIDv7.generate()
        let panes = [
            parentId: makeLayoutPane(
                id: parentId,
                drawer: .init(paneIds: [childId], isExpanded: true)
            ),
            childId: makeDrawerChildPane(id: childId, parentPaneId: parentId),
        ]
        let drawerView = DrawerView(layout: .init(topRow: .init(paneId: childId)), activeChildId: childId)

        let resolved = PaneObservationResolver.currentAttendedPaneId(
            attendedPaneId: parentId,
            pane: { panes[$0] },
            drawerView: { $0 == parentId ? drawerView : nil }
        )

        #expect(resolved == childId)
        #expect(
            PaneObservationResolver.isPaneCurrentlyAttended(
                paneId: childId,
                attendedPaneId: parentId,
                pane: { panes[$0] },
                drawerView: { $0 == parentId ? drawerView : nil }
            )
        )
    }

    @Test("expanded drawer with minimized active child has no attended pane")
    func expandedDrawerWithMinimizedActiveChildHasNoAttendedPane() {
        let parentId = UUIDv7.generate()
        let childId = UUIDv7.generate()
        let panes = [
            parentId: makeLayoutPane(
                id: parentId,
                drawer: .init(
                    paneIds: [childId],
                    isExpanded: true
                )
            ),
            childId: makeDrawerChildPane(id: childId, parentPaneId: parentId),
        ]
        let drawerView = DrawerView(
            layout: .init(topRow: .init(paneId: childId)),
            activeChildId: childId,
            minimizedPaneIds: [childId]
        )

        let resolved = PaneObservationResolver.currentAttendedPaneId(
            attendedPaneId: parentId,
            pane: { panes[$0] },
            drawerView: { $0 == parentId ? drawerView : nil }
        )

        #expect(resolved == nil)
    }

    @Test("observed pane ids replace expanded drawer parent with active child")
    func observedPaneIdsReplaceExpandedDrawerParentWithActiveChild() {
        let parentId = UUIDv7.generate()
        let childId = UUIDv7.generate()
        let siblingId = UUIDv7.generate()
        let panes = [
            parentId: makeLayoutPane(
                id: parentId,
                drawer: .init(paneIds: [childId], isExpanded: true)
            ),
            childId: makeDrawerChildPane(id: childId, parentPaneId: parentId),
            siblingId: makeLayoutPane(id: siblingId, drawer: .init()),
        ]
        let tab = makeTab(paneIds: [parentId, siblingId], activePaneId: parentId)
        let drawerView = DrawerView(layout: .init(topRow: .init(paneId: childId)), activeChildId: childId)

        let observedPaneIds = PaneObservationResolver.currentObservedPaneIds(
            attendedPaneId: parentId,
            activeTab: tab,
            pane: { panes[$0] },
            drawerView: { $0 == parentId ? drawerView : nil }
        )

        #expect(observedPaneIds == Set([childId, siblingId]))
    }

    private func makeLayoutPane(id: UUID, drawer: Drawer) -> Pane {
        Pane(
            id: id,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(title: "Pane"),
            kind: .layout(drawer: drawer)
        )
    }

    private func makeDrawerChildPane(id: UUID, parentPaneId: UUID) -> Pane {
        Pane(
            id: id,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(title: "Drawer"),
            kind: .drawerChild(parentPaneId: parentPaneId)
        )
    }
}
