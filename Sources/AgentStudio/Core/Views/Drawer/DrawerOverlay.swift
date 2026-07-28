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
        let onCopyPath: () -> Void
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
            onCopyPath: @escaping () -> Void = {},
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
            self.onCopyPath = onCopyPath
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
    let paneSurfaceActions: [PaneSurfaceToolbarAction]
    let paneContextActions: [PaneSurfaceToolbarAction]
    let action: (WorkspaceActionCommand) -> Void
    let onPaneFocusTrigger: PaneFocusTriggerHandler

    init(
        paneId: UUID,
        drawer: Drawer?,
        isIconBarVisible: Bool,
        trailingActions: TrailingActions?,
        paneSurfaceActions: [PaneSurfaceToolbarAction] = [],
        paneContextActions: [PaneSurfaceToolbarAction] = [],
        action: @escaping (WorkspaceActionCommand) -> Void,
        onPaneFocusTrigger: @escaping PaneFocusTriggerHandler
    ) {
        self.paneId = paneId
        self.drawer = drawer
        self.isIconBarVisible = isIconBarVisible
        self.trailingActions = trailingActions
        self.paneSurfaceActions = paneSurfaceActions
        self.paneContextActions = paneContextActions
        self.action = action
        self.onPaneFocusTrigger = onPaneFocusTrigger
    }

    var body: some View {
        if isIconBarVisible {
            DrawerIconBar(
                isExpanded: drawer?.isExpanded ?? false,
                onAdd: { addDrawerPane() },
                onToggleExpand: {
                    action(.toggleDrawer(paneId: paneId))
                    onPaneFocusTrigger(.drawer(.toggle(parentPaneId: paneId)))
                },
                trailingActions: trailingActions,
                paneSurfaceActions: paneSurfaceActions,
                paneContextActions: paneContextActions
            )
        }
    }

    private func addDrawerPane() {
        action(.addDrawerPane(parentPaneId: paneId))
    }
}
