import AgentStudioInfrastructure
import SwiftUI
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("DrawerIconBar inbox slot")
struct DrawerIconBarInboxSlotTests {
    @Test("trailing actions carry optional inbox command and unread badge")
    func trailingActionsCarryInboxConfiguration() {
        var didOpenInbox = false
        let actions = makeTrailingActions(
            inboxUnreadCount: 3,
            showPaneInboxAction: makeCommandAction(
                .showPaneInboxNotifications,
                perform: {
                    didOpenInbox = true
                }
            )
        )

        #expect(actions.inboxUnreadBadge?.text == "3")
        #expect(actions.inboxPopoverContent == nil)
        actions.showPaneInboxAction?.perform()
        #expect(didOpenInbox)
    }

    @Test("pane inbox unread badge uses compact overflow text")
    func paneInboxUnreadBadgeUsesCompactOverflowText() {
        #expect(PaneInboxUnreadBadge(unreadCount: AppPolicies.PaneInbox.unreadBadgeDisplayLimit)?.text == "9")
        #expect(PaneInboxUnreadBadge(unreadCount: 10)?.text == "9+")
    }

    @Test("icon bar accepts trailing inbox action configuration")
    func iconBarAcceptsInboxConfiguration() {
        let actions = makeTrailingActions(
            inboxUnreadCount: 2,
            showPaneInboxAction: makeCommandAction(.showPaneInboxNotifications)
        )

        let view = DrawerIconBar(
            octiconLoader: makeCoreTestOcticonLoader(),
            leadingControls: .drawer(
                isExpanded: false,
                addDrawerPaneAction: makeCommandAction(.addDrawerPane),
                toggleDrawerAction: makeCommandAction(.toggleDrawer)
            ),
            trailingActions: actions
        )

        _ = view.body
    }

    private func makeTrailingActions(
        inboxUnreadCount: Int,
        showPaneInboxAction: TargetedCommandControlAction?
    ) -> DrawerOverlay.TrailingActions {
        DrawerOverlay.TrailingActions(
            openEditorMenuAction: makeCommandAction(.openPaneLocationInEditorMenu),
            openFinderAction: makeCommandAction(.openPaneLocationInFinder),
            copyPathAction: makeCommandAction(.copyCurrentPanePath),
            showPaneInboxAction: showPaneInboxAction,
            editorMenuContent: AnyView(EmptyView()),
            editorMenuPresented: .constant(false),
            buttonTitle: "Cursor",
            inboxUnreadBadge: PaneInboxUnreadBadge(unreadCount: inboxUnreadCount)
        )
    }

    private func makeCommandAction(
        _ command: AppCommand,
        perform: @escaping @MainActor () -> Void = {}
    ) -> TargetedCommandControlAction {
        TargetedCommandControlAction(
            commandSpec: command.definition,
            isEnabled: true,
            perform: perform
        )
    }
}
