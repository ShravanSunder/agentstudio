import SwiftUI
import Testing

@testable import AgentStudio

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

    @Test("pane inbox requests match semantically identical scopes regardless of pane-id ordering")
    func paneInboxRequestMatchesScopeBySetIdentity() {
        let parentPaneId = UUIDv7.generate()
        let firstDrawerPaneId = UUIDv7.generate()
        let secondDrawerPaneId = UUIDv7.generate()
        let request = PaneInboxRequest(
            id: UUIDv7.generate(),
            parentPaneId: parentPaneId,
            paneIds: [parentPaneId, firstDrawerPaneId, secondDrawerPaneId],
            intent: .open
        )

        #expect(
            request.matches(
                parentPaneId: parentPaneId,
                paneIds: [secondDrawerPaneId, parentPaneId, firstDrawerPaneId]
            )
        )
        #expect(!request.matches(parentPaneId: UUIDv7.generate(), paneIds: request.paneIds))
    }

    @Test("trailing actions inject pane inbox unread count and preserve existing actions")
    func trailingActionsInjectUnreadBadgeAndPreserveExistingActions() {
        let parentPaneId = UUID()
        let drawerChildPaneId = UUID()
        let paneIds = [parentPaneId, drawerChildPaneId]
        var openedParentPaneId: UUID?
        var openedPaneIds: [UUID]?
        var didOpenFinder = false
        let baseActions = DrawerOverlay.TrailingActions(
            canOpenTarget: true,
            editorMenuContent: AnyView(EmptyView()),
            editorMenuPresented: .constant(false),
            buttonTitle: "Cursor",
            onOpenFinder: { didOpenFinder = true }
        )
        let presentation = PaneInboxPresentation(
            unreadCount: { requestedPaneIds in requestedPaneIds == paneIds ? 1 : 0 },
            clear: { _, _ in },
            open: { _, _ in },
            toggle: { parentPaneId, paneIds in
                openedParentPaneId = parentPaneId
                openedPaneIds = paneIds
            },
            setPresented: { _, _, _ in },
            pendingRequest: { nil },
            clearRequest: { _ in },
            popoverContent: { _, _, _ in AnyView(EmptyView()) },
            pruneFilterModes: { _ in }
        )
        var isPopoverPresented = false

        let actions = presentation.trailingActions(
            parentPaneId: parentPaneId,
            paneIds: paneIds,
            baseTrailingActions: baseActions,
            inboxPopoverPresented: Binding(
                get: { isPopoverPresented },
                set: { isPopoverPresented = $0 }
            )
        )

        #expect(actions.canOpenTarget == true)
        #expect(actions.buttonTitle == "Cursor")
        #expect(actions.inboxUnreadBadge?.text == "1")
        #expect(actions.inboxPopoverContent != nil)

        actions.inboxPopoverPresented.wrappedValue = true
        #expect(isPopoverPresented)

        actions.onOpenFinder()
        #expect(didOpenFinder)

        actions.onOpenInbox?()
        #expect(openedParentPaneId == parentPaneId)
        #expect(openedPaneIds == paneIds)
    }

    @Test("pane inbox badge caps at nine plus")
    func paneInboxBadgeCapsAtNinePlus() {
        let badge = PaneInboxUnreadBadge(
            unreadCount: 10
        )

        #expect(badge?.text == "9+")
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
