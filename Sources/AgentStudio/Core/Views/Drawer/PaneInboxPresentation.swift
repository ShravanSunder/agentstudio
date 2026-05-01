import SwiftUI

struct PaneInboxRequest: Equatable, Identifiable {
    let id: UUID
    let parentPaneId: UUID
    let paneIds: [UUID]
}

/// Core receives primitive counts, callbacks, and type-erased popover content;
/// the inbox feature keeps ownership of notification state.
@MainActor
struct PaneInboxPresentation {
    let unreadCount: @MainActor ([UUID]) -> Int
    let open: @MainActor (UUID, [UUID]) -> Void
    let pendingRequest: @MainActor () -> PaneInboxRequest?
    let clearRequest: @MainActor (PaneInboxRequest) -> Void
    let popoverContent: @MainActor ([UUID], @escaping @MainActor @Sendable () -> Void) -> AnyView

    func trailingActions(
        parentPaneId: UUID,
        paneIds: [UUID],
        baseTrailingActions: DrawerOverlay.TrailingActions,
        inboxPopoverPresented: Binding<Bool>
    ) -> DrawerOverlay.TrailingActions {
        DrawerOverlay.TrailingActions(
            canOpenTarget: baseTrailingActions.canOpenTarget,
            editorMenuContent: baseTrailingActions.editorMenuContent,
            editorMenuPresented: baseTrailingActions.editorMenuPresented,
            buttonTitle: baseTrailingActions.buttonTitle,
            onOpenFinder: baseTrailingActions.onOpenFinder,
            onOpenInbox: { open(parentPaneId, paneIds) },
            inboxPopoverPresented: inboxPopoverPresented,
            inboxPopoverContent: popoverContent(
                paneIds,
                { inboxPopoverPresented.wrappedValue = false }
            ),
            inboxUnreadCount: unreadCount(paneIds)
        )
    }
}
