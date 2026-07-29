import AgentStudioCore
import AgentStudioEditorChooser
import AgentStudioInfrastructure
import SwiftUI

@MainActor
struct PaneSurfaceToolbarHost: View {
    let anchorPaneId: UUID
    let locationTargetPaneId: UUID
    let drawer: Drawer?
    let leadingToolbarActions: [PaneSurfaceToolbarAction]
    let contextToolbarActions: [PaneSurfaceToolbarAction]
    let store: WorkspaceStore
    let octiconLoader: OcticonLoader
    let editorChooser: EditorChooserState
    let paneInboxPresentation: PaneInboxPresentation?
    let workspaceWindowId: UUID?
    let actionDispatcher: PaneActionDispatching
    let onPaneFocusTrigger: PaneFocusTriggerHandler

    @State private var paneInboxPopoverOpen = false

    var body: some View {
        let locationContext = PaneManagementContext.project(
            paneId: locationTargetPaneId,
            store: store
        )
        let trailingActions = DrawerEditorChooserFactory.makeTrailingActions(
            editorChooser: editorChooser,
            paneId: locationTargetPaneId,
            workspaceWindowId: workspaceWindowId,
            canOpenTarget: locationContext.targetPath != nil,
            refreshInstalledTargets: {
                ExternalEditorTarget.refreshInstalledTargets()
            },
            onOpenFinder: {
                guard let targetPath = locationContext.targetPath else { return }
                ExternalWorkspaceOpener.openInFinder(targetPath)
            },
            onCopyPath: {
                guard let targetPath = locationContext.targetPath else { return }
                PathActions.copyPath(targetPath)
            },
            onOpenEditor: { editorId in
                guard let targetPath = locationContext.targetPath else { return }
                _ = ExternalWorkspaceOpener.openInEditor(id: editorId, path: targetPath)
            }
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
                inboxPopoverPresented: $paneInboxPopoverOpen
            ) ?? trailingActions

        DrawerOverlay(
            paneId: anchorPaneId,
            octiconLoader: octiconLoader,
            drawer: drawer,
            isIconBarVisible: true,
            trailingActions: hostedActions,
            paneSurfaceActions: leadingToolbarActions,
            paneContextActions: contextToolbarActions,
            action: actionDispatcher.dispatch,
            onPaneFocusTrigger: onPaneFocusTrigger
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
