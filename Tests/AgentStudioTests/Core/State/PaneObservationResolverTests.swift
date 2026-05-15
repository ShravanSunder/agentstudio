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
                drawer: .init(paneIds: [childId], activeChildId: childId, isExpanded: true)
            ),
            childId: makeDrawerChildPane(id: childId, parentPaneId: parentId),
        ]

        let resolved = PaneObservationResolver.currentAttendedPaneId(
            attendedPaneId: parentId,
            pane: { panes[$0] },
            drawerView: { _ in
                DrawerView(layout: DrawerGridLayout(topRow: Layout(paneId: childId)), activeChildId: childId)
            }
        )

        #expect(resolved == childId)
        #expect(
            PaneObservationResolver.isPaneCurrentlyAttended(
                paneId: childId,
                attendedPaneId: parentId,
                pane: { panes[$0] },
                drawerView: { _ in
                    DrawerView(layout: DrawerGridLayout(topRow: Layout(paneId: childId)), activeChildId: childId)
                }
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
                    activeChildId: childId,
                    isExpanded: true,
                    minimizedPaneIds: [childId]
                )
            ),
            childId: makeDrawerChildPane(id: childId, parentPaneId: parentId),
        ]

        let resolved = PaneObservationResolver.currentAttendedPaneId(
            attendedPaneId: parentId,
            pane: { panes[$0] },
            drawerView: { _ in
                DrawerView(
                    layout: DrawerGridLayout(topRow: Layout(paneId: childId)),
                    activeChildId: childId,
                    minimizedPaneIds: [childId]
                )
            }
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
                drawer: .init(paneIds: [childId], activeChildId: childId, isExpanded: true)
            ),
            childId: makeDrawerChildPane(id: childId, parentPaneId: parentId),
            siblingId: makeLayoutPane(id: siblingId, drawer: .init()),
        ]
        let tab = makeTab(paneIds: [parentId, siblingId], activePaneId: parentId)

        let observedPaneIds = PaneObservationResolver.currentObservedPaneIds(
            attendedPaneId: parentId,
            activeTab: tab,
            pane: { panes[$0] },
            drawerView: { _ in
                DrawerView(layout: DrawerGridLayout(topRow: Layout(paneId: childId)), activeChildId: childId)
            }
        )

        #expect(observedPaneIds == Set([childId, siblingId]))
    }

    private func makeLayoutPane(id: UUID, drawer: Drawer) -> Pane {
        Pane(
            id: id,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(source: .init(.floating(launchDirectory: nil, title: nil)), title: "Pane"),
            kind: .layout(drawer: drawer)
        )
    }

    private func makeDrawerChildPane(id: UUID, parentPaneId: UUID) -> Pane {
        Pane(
            id: id,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(source: .init(.floating(launchDirectory: nil, title: nil)), title: "Drawer"),
            kind: .drawerChild(parentPaneId: parentPaneId)
        )
    }
}
