import SwiftUI

/// Renders the drawer icon bar at the bottom of a pane leaf.
/// Panel rendering has moved to the tab-level DrawerPanelOverlay so it can
/// overlay across all panes without being clipped by the pane's bounds.
struct DrawerOverlay: View {
    struct TrailingActions {
        let canOpenTarget: Bool
        let editorMenuContent: AnyView
        let editorMenuPresented: Binding<Bool>
        let buttonTitle: String?
        let onOpenFinder: () -> Void
        let onOpenInbox: (() -> Void)?
        let inboxPopoverPresented: Binding<Bool>
        let inboxPopoverContent: AnyView?
        let inboxUnreadBadge: PaneInboxUnreadBadge?

        init(
            canOpenTarget: Bool,
            editorMenuContent: AnyView,
            editorMenuPresented: Binding<Bool>,
            buttonTitle: String?,
            onOpenFinder: @escaping () -> Void,
            onOpenInbox: (() -> Void)? = nil,
            inboxPopoverPresented: Binding<Bool> = .constant(false),
            inboxPopoverContent: AnyView? = nil,
            inboxUnreadBadge: PaneInboxUnreadBadge? = nil
        ) {
            self.canOpenTarget = canOpenTarget
            self.editorMenuContent = editorMenuContent
            self.editorMenuPresented = editorMenuPresented
            self.buttonTitle = buttonTitle
            self.onOpenFinder = onOpenFinder
            self.onOpenInbox = onOpenInbox
            self.inboxPopoverPresented = inboxPopoverPresented
            self.inboxPopoverContent = inboxPopoverContent
            self.inboxUnreadBadge = inboxUnreadBadge
        }
    }

    let paneId: UUID
    let drawer: Drawer?
    let isIconBarVisible: Bool
    let trailingActions: TrailingActions?
    let action: (WorkspaceActionCommand) -> Void
    let onPaneFocusTrigger: PaneFocusTriggerHandler

    var body: some View {
        DrawerIconBar(
            isExpanded: drawer?.isExpanded ?? false,
            onAdd: { addDrawerPane() },
            onToggleExpand: {
                action(.toggleDrawer(paneId: paneId))
                onPaneFocusTrigger(.drawer(.toggle(parentPaneId: paneId)))
            },
            trailingActions: trailingActions
        )
    }

    private func addDrawerPane() {
        action(.addDrawerPane(parentPaneId: paneId))
    }
}
