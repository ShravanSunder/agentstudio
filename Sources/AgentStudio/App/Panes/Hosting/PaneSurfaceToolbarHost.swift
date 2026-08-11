import AgentStudioCore
import AgentStudioEditorChooser
import AgentStudioInfrastructure
import AppKit
import SwiftUI

@MainActor
struct DrawerToolbarCommandPresentation {
    let toggleDrawer: TargetedCommandControlAction?
    let addDrawerPane: TargetedCommandControlAction?
    let openEditorMenu: TargetedCommandControlAction?
    let openFinder: TargetedCommandControlAction?
    let copyPath: TargetedCommandControlAction?
    let showPaneInbox: TargetedCommandControlAction?

    static func resolve(
        anchorPaneId: UUID,
        locationTargetPaneId: UUID,
        toolbarSurface: AppCommandToolbarSurface,
        actionResolver: TargetedCommandControlActionResolver
    ) -> Self {
        let commandSurface = AppCommandSurface.toolbar(toolbarSurface)
        return Self(
            toggleDrawer: actionResolver(
                .toggleDrawer,
                commandSurface,
                anchorPaneId,
                .pane
            ),
            addDrawerPane: actionResolver(
                .addDrawerPane,
                commandSurface,
                anchorPaneId,
                .pane
            ),
            openEditorMenu: actionResolver(
                .openPaneLocationInEditorMenu,
                commandSurface,
                locationTargetPaneId,
                .pane
            ),
            openFinder: actionResolver(
                .openPaneLocationInFinder,
                commandSurface,
                locationTargetPaneId,
                .pane
            ),
            copyPath: actionResolver(
                .copyCurrentPanePath,
                commandSurface,
                locationTargetPaneId,
                .pane
            ),
            showPaneInbox: actionResolver(
                .showPaneInboxNotifications,
                commandSurface,
                anchorPaneId,
                .pane
            )
        )
    }
}

@MainActor
struct PaneSurfaceToolbarHost: View {
    let anchorPaneId: UUID
    let locationTargetPaneId: UUID
    let toolbarSurface: AppCommandToolbarSurface
    let drawer: Drawer?
    let leadingToolbarActions: [PaneSurfaceToolbarAction]
    let contextToolbarActions: [PaneSurfaceToolbarAction]
    let store: WorkspaceStore
    let repoCache: RepoCacheAtom
    let octiconLoader: OcticonLoader
    let editorChooser: EditorChooserState
    let paneInboxPresentation: PaneInboxPresentation?
    let workspaceWindowId: UUID?
    let actionDispatcher: PaneActionDispatching
    let onPaneFocusTrigger: PaneFocusTriggerHandler

    @State private var paneInboxPopoverOpen = false

    var body: some View {
        let commandPresentation = DrawerToolbarCommandPresentation.resolve(
            anchorPaneId: anchorPaneId,
            locationTargetPaneId: locationTargetPaneId,
            toolbarSurface: toolbarSurface,
            actionResolver: { command, surface, target, targetType in
                TargetedCommandControlAction.resolve(
                    command: command,
                    surface: surface,
                    target: target,
                    targetType: targetType,
                    dispatcher: AppCommandDispatcher.shared
                )
            }
        )
        let locationContext = PaneManagementContext.project(
            paneId: locationTargetPaneId,
            store: store
        )
        let openPullRequestAction = PanePullRequestToolbarActionFactory.make(
            paneId: locationTargetPaneId,
            store: store,
            repoCache: repoCache,
            openExternalURL: { NSWorkspace.shared.open($0) }
        )
        let trailingActions = DrawerEditorChooserFactory.makeTrailingActions(
            editorChooser: editorChooser,
            paneId: locationTargetPaneId,
            workspaceWindowId: workspaceWindowId,
            commandPresentation: commandPresentation,
            refreshInstalledTargets: {
                ExternalEditorTarget.refreshInstalledTargets()
            },
            onOpenEditor: { editorId in
                guard let targetPath = locationContext.targetPath else { return }
                _ = ExternalWorkspaceOpener.openInEditor(id: editorId, path: targetPath)
            },
            openPullRequestAction: openPullRequestAction
        )
        let paneInboxScope = PaneInboxScopeResolver.resolve(
            anchorPaneId: anchorPaneId,
            pane: { store.paneAtom.pane($0) }
        )
        let hostedActions =
            paneInboxPresentation?.trailingActions(
                parentPaneId: paneInboxScope.parentPaneId,
                paneIds: paneInboxScope.paneIds,
                baseTrailingActions: trailingActions,
                showPaneInboxAction: commandPresentation.showPaneInbox,
                inboxPopoverPresented: $paneInboxPopoverOpen
            ) ?? trailingActions

        DrawerOverlay(
            octiconLoader: octiconLoader,
            drawer: drawer,
            isIconBarVisible: true,
            toggleDrawerAction: commandPresentation.toggleDrawer,
            addDrawerPaneAction: commandPresentation.addDrawerPane,
            trailingActions: hostedActions,
            paneSurfaceActions: leadingToolbarActions,
            paneContextActions: contextToolbarActions
        )
        .onAppear {
            consumePendingPaneInboxRequest(in: paneInboxScope)
        }
        .onChange(of: paneInboxPresentation?.pendingRequest()?.id) { _, _ in
            consumePendingPaneInboxRequest(in: paneInboxScope)
        }
        .onChange(of: paneInboxPopoverOpen) { _, isPresented in
            paneInboxPresentation?.setPresented(
                paneInboxScope.parentPaneId,
                paneInboxScope.paneIds,
                isPresented
            )
        }
    }

    private func consumePendingPaneInboxRequest(in scope: PaneInboxScope) {
        guard let request = paneInboxPresentation?.pendingRequest() else { return }
        guard request.matches(parentPaneId: scope.parentPaneId, paneIds: scope.paneIds) else { return }

        switch request.intent {
        case .open:
            paneInboxPopoverOpen = true
            paneInboxPresentation?.setPresented(scope.parentPaneId, scope.paneIds, true)
        case .close:
            paneInboxPopoverOpen = false
            paneInboxPresentation?.setPresented(scope.parentPaneId, scope.paneIds, false)
        }
        paneInboxPresentation?.clearRequest(request)
    }

}
