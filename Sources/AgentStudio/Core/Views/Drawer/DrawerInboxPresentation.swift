import SwiftUI

struct DrawerInboxRequest: Equatable, Identifiable {
    let id: UUID
    let parentPaneId: UUID
    let drawerPaneIds: [UUID]
}

/// Core receives primitive counts, callbacks, and type-erased popover content;
/// the inbox feature keeps ownership of notification state.
@MainActor
struct DrawerInboxPresentation {
    let unreadCount: @MainActor ([UUID]) -> Int
    let open: @MainActor (UUID, [UUID]) -> Void
    let pendingRequest: @MainActor () -> DrawerInboxRequest?
    let clearRequest: @MainActor (DrawerInboxRequest) -> Void
    let popoverContent: @MainActor ([UUID], @escaping @MainActor @Sendable () -> Void) -> AnyView

    func trailingActions(
        parentPaneId: UUID,
        drawerPaneIds: [UUID],
        baseTrailingActions: DrawerOverlay.TrailingActions,
        inboxPopoverPresented: Binding<Bool>
    ) -> DrawerOverlay.TrailingActions {
        DrawerOverlay.TrailingActions(
            canOpenTarget: baseTrailingActions.canOpenTarget,
            editorMenuContent: baseTrailingActions.editorMenuContent,
            editorMenuPresented: baseTrailingActions.editorMenuPresented,
            buttonTitle: baseTrailingActions.buttonTitle,
            onOpenFinder: baseTrailingActions.onOpenFinder,
            onOpenInbox: { open(parentPaneId, drawerPaneIds) },
            inboxPopoverPresented: inboxPopoverPresented,
            inboxPopoverContent: popoverContent(
                drawerPaneIds,
                { inboxPopoverPresented.wrappedValue = false }
            ),
            inboxUnreadCount: unreadCount(drawerPaneIds)
        )
    }
}
