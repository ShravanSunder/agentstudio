import AgentStudioInfrastructure
import SwiftUI

/// Renders the drawer icon bar at the bottom of a pane leaf.
/// Panel rendering has moved to the tab-level DrawerPanelOverlay so it can
/// overlay across all panes without being clipped by the pane's bounds.
package struct DrawerOverlay: View {
    package struct TrailingActions {
        let canOpenTarget: Bool
        let editorMenuContent: AnyView
        let editorMenuPresented: Binding<Bool>
        let buttonTitle: String?
        let onOpenFinder: () -> Void
        let onOpenInbox: (() -> Void)?
        let inboxPopoverPresented: Binding<Bool>
        let inboxPopoverContent: AnyView?
        let inboxUnreadBadge: PaneInboxUnreadBadge?

        package init(
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
    let octiconLoader: OcticonLoader
    let drawer: Drawer?
    let isIconBarVisible: Bool
    let trailingActions: TrailingActions?
    let action: (WorkspaceActionCommand) -> Void
    let onPaneFocusTrigger: PaneFocusTriggerHandler

    package init(
        paneId: UUID,
        octiconLoader: OcticonLoader,
        drawer: Drawer?,
        isIconBarVisible: Bool,
        trailingActions: TrailingActions?,
        action: @escaping (WorkspaceActionCommand) -> Void,
        onPaneFocusTrigger: @escaping PaneFocusTriggerHandler
    ) {
        self.paneId = paneId
        self.octiconLoader = octiconLoader
        self.drawer = drawer
        self.isIconBarVisible = isIconBarVisible
        self.trailingActions = trailingActions
        self.action = action
        self.onPaneFocusTrigger = onPaneFocusTrigger
    }

    package var body: some View {
        DrawerIconBar(
            octiconLoader: octiconLoader,
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
