import SwiftUI

/// Core seam for a drawer-scoped inbox affordance.
///
/// Core drawer/split views own placement of the bell slot, but the inbox feature
/// owns notification state and popover content. This contract keeps that boundary:
/// Core receives primitive counts, callbacks, and type-erased content only.
@MainActor
struct DrawerInboxPresentation {
    let unreadCount: @MainActor ([UUID]) -> Int
    let open: @MainActor ([UUID]) -> Void
    let requestId: @MainActor () -> UUID?
    let requestDrawerPaneIds: @MainActor () -> [UUID]?
    let clearRequest: @MainActor (UUID) -> Void
    let popoverContent: @MainActor ([UUID], @escaping @MainActor @Sendable () -> Void) -> AnyView

    func trailingActions(
        drawerPaneIds: [UUID],
        baseTrailingActions: DrawerOverlay.TrailingActions
    ) -> DrawerOverlay.TrailingActions {
        DrawerOverlay.TrailingActions(
            canOpenTarget: baseTrailingActions.canOpenTarget,
            editorMenuContent: baseTrailingActions.editorMenuContent,
            editorMenuPresented: baseTrailingActions.editorMenuPresented,
            buttonTitle: baseTrailingActions.buttonTitle,
            onOpenFinder: baseTrailingActions.onOpenFinder,
            onOpenInbox: { open(drawerPaneIds) },
            inboxUnreadCount: unreadCount(drawerPaneIds)
        )
    }
}
