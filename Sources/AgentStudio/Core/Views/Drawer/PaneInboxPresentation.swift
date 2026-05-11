import SwiftUI

enum PaneInboxRequestIntent: Equatable {
    case open
    case close
}

struct PaneInboxRequest: Equatable, Identifiable {
    let id: UUID
    let parentPaneId: UUID
    let paneIds: [UUID]
    let intent: PaneInboxRequestIntent

    func matches(parentPaneId: UUID, paneIds: [UUID]) -> Bool {
        self.parentPaneId == parentPaneId && Set(self.paneIds) == Set(paneIds)
    }
}

struct PaneInboxUnreadBadge: Equatable {
    let text: String

    init?(
        unreadCount: Int,
        visibleLimit: Int = AppPolicies.PaneInbox.maxVisibleNotifications
    ) {
        guard unreadCount > 0 else { return nil }
        text = unreadCount > visibleLimit ? "\(visibleLimit)+" : "\(unreadCount)"
    }
}

/// Core receives primitive counts, callbacks, and type-erased popover content;
/// the inbox feature keeps ownership of notification state.
@MainActor
struct PaneInboxPresentation {
    let unreadCount: @MainActor ([UUID]) -> Int
    let clear: @MainActor (UUID, [UUID]) -> Void
    let open: @MainActor (UUID, [UUID]) -> Void
    let toggle: @MainActor (UUID, [UUID]) -> Void
    let setPresented: @MainActor (UUID, [UUID], Bool) -> Void
    let pendingRequest: @MainActor () -> PaneInboxRequest?
    let clearRequest: @MainActor (PaneInboxRequest) -> Void
    let popoverContent: @MainActor (UUID, [UUID], @escaping @MainActor @Sendable () -> Void) -> AnyView
    let pruneFilterModes: @MainActor (Set<UUID>) -> Void

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
            onOpenInbox: { toggle(parentPaneId, paneIds) },
            inboxPopoverPresented: inboxPopoverPresented,
            inboxPopoverContent: popoverContent(
                parentPaneId,
                paneIds,
                { inboxPopoverPresented.wrappedValue = false }
            ),
            inboxUnreadBadge: PaneInboxUnreadBadge(unreadCount: unreadCount(paneIds))
        )
    }
}
