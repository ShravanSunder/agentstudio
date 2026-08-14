import AgentStudioInfrastructure
import SwiftUI

/// Renders the drawer icon bar at the bottom of a pane leaf.
/// Panel rendering has moved to the tab-level DrawerPanelOverlay so it can
/// overlay across all panes without being clipped by the pane's bounds.
package struct DrawerOverlay: View {
    package struct TrailingActions {
        let openEditorMenuAction: TargetedCommandControlAction?
        let openFinderAction: TargetedCommandControlAction?
        let copyPathAction: TargetedCommandControlAction?
        let openPullRequestAction: PaneSurfaceToolbarAction?
        let showPaneInboxAction: TargetedCommandControlAction?
        let editorMenuContent: AnyView
        let editorMenuPresented: Binding<Bool>
        let buttonTitle: String?
        let inboxPopoverPresented: Binding<Bool>
        let inboxPopoverContent: AnyView?
        let inboxUnreadBadge: PaneInboxUnreadBadge?

        package init(
            openEditorMenuAction: TargetedCommandControlAction?,
            openFinderAction: TargetedCommandControlAction?,
            copyPathAction: TargetedCommandControlAction?,
            openPullRequestAction: PaneSurfaceToolbarAction? = nil,
            showPaneInboxAction: TargetedCommandControlAction? = nil,
            editorMenuContent: AnyView,
            editorMenuPresented: Binding<Bool>,
            buttonTitle: String?,
            inboxPopoverPresented: Binding<Bool> = .constant(false),
            inboxPopoverContent: AnyView? = nil,
            inboxUnreadBadge: PaneInboxUnreadBadge? = nil
        ) {
            self.openEditorMenuAction = openEditorMenuAction
            self.openFinderAction = openFinderAction
            self.copyPathAction = copyPathAction
            self.openPullRequestAction = openPullRequestAction
            self.showPaneInboxAction = showPaneInboxAction
            self.editorMenuContent = editorMenuContent
            self.editorMenuPresented = editorMenuPresented
            self.buttonTitle = buttonTitle
            self.inboxPopoverPresented = inboxPopoverPresented
            self.inboxPopoverContent = inboxPopoverContent
            self.inboxUnreadBadge = inboxUnreadBadge
        }
    }

    let octiconLoader: OcticonLoader
    let drawer: Drawer?
    let isIconBarVisible: Bool
    let toggleDrawerAction: TargetedCommandControlAction?
    let addDrawerPaneAction: TargetedCommandControlAction?
    let trailingActions: TrailingActions?
    let paneSurfaceActions: [PaneSurfaceToolbarAction]
    let paneContextActions: [PaneSurfaceToolbarAction]

    package init(
        octiconLoader: OcticonLoader,
        drawer: Drawer?,
        isIconBarVisible: Bool,
        toggleDrawerAction: TargetedCommandControlAction?,
        addDrawerPaneAction: TargetedCommandControlAction?,
        trailingActions: TrailingActions?,
        paneSurfaceActions: [PaneSurfaceToolbarAction] = [],
        paneContextActions: [PaneSurfaceToolbarAction] = []
    ) {
        self.octiconLoader = octiconLoader
        self.drawer = drawer
        self.isIconBarVisible = isIconBarVisible
        self.toggleDrawerAction = toggleDrawerAction
        self.addDrawerPaneAction = addDrawerPaneAction
        self.trailingActions = trailingActions
        self.paneSurfaceActions = paneSurfaceActions
        self.paneContextActions = paneContextActions
    }

    package var body: some View {
        if isIconBarVisible {
            DrawerIconBar(
                octiconLoader: octiconLoader,
                leadingControls: .drawer(
                    isExpanded: drawer?.isExpanded ?? false,
                    addDrawerPaneAction: addDrawerPaneAction,
                    toggleDrawerAction: toggleDrawerAction
                ),
                trailingActions: trailingActions,
                paneSurfaceActions: paneSurfaceActions,
                paneContextActions: paneContextActions
            )
        }
    }
}
