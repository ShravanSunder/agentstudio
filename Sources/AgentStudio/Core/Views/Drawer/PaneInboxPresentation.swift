import AgentStudioInfrastructure
import SwiftUI

package enum PaneInboxRequestIntent: Equatable {
    case open
    case close
}

package struct PaneInboxRequest: Equatable, Identifiable {
    package let id: UUID
    package let parentPaneId: UUID
    package let paneIds: [UUID]
    package let intent: PaneInboxRequestIntent

    package init(id: UUID, parentPaneId: UUID, paneIds: [UUID], intent: PaneInboxRequestIntent) {
        self.id = id
        self.parentPaneId = parentPaneId
        self.paneIds = paneIds
        self.intent = intent
    }

    package func matches(parentPaneId: UUID, paneIds: [UUID]) -> Bool {
        self.parentPaneId == parentPaneId && Set(self.paneIds) == Set(paneIds)
    }
}

package struct PaneInboxUnreadBadge: Equatable {
    let text: String

    init?(
        unreadCount: Int,
        visibleLimit: Int = AppPolicies.PaneInbox.unreadBadgeDisplayLimit
    ) {
        guard unreadCount > 0 else { return nil }
        text = unreadCount > visibleLimit ? "\(visibleLimit)+" : "\(unreadCount)"
    }
}

/// Core receives primitive counts, callbacks, and type-erased popover content;
/// the inbox feature keeps ownership of notification state.
@MainActor
package struct PaneInboxPresentation {
    let unreadCount: @MainActor ([UUID]) -> Int
    package let clear: @MainActor (UUID, [UUID]) -> Void
    let open: @MainActor (UUID, [UUID]) -> Void
    let openRollUpAlerts: @MainActor (UUID, [UUID]) -> Void
    package let toggle: @MainActor (UUID, [UUID]) -> Void
    package let setPresented: @MainActor (UUID, [UUID], Bool) -> Void
    package let pendingRequest: @MainActor () -> PaneInboxRequest?
    package let clearRequest: @MainActor (PaneInboxRequest) -> Void
    let popoverContent:
        @MainActor (UUID, [UUID], @escaping @MainActor @Sendable () -> Void)
            -> AnyView
    package let pruneFilterModes: @MainActor (Set<UUID>) -> Void

    package init(
        unreadCount: @escaping @MainActor ([UUID]) -> Int,
        clear: @escaping @MainActor (UUID, [UUID]) -> Void,
        open: @escaping @MainActor (UUID, [UUID]) -> Void,
        openRollUpAlerts: @escaping @MainActor (UUID, [UUID]) -> Void,
        toggle: @escaping @MainActor (UUID, [UUID]) -> Void,
        setPresented: @escaping @MainActor (UUID, [UUID], Bool) -> Void,
        pendingRequest: @escaping @MainActor () -> PaneInboxRequest?,
        clearRequest: @escaping @MainActor (PaneInboxRequest) -> Void,
        popoverContent:
            @escaping @MainActor (
                UUID,
                [UUID],
                @escaping @MainActor @Sendable () -> Void
            ) -> AnyView,
        pruneFilterModes: @escaping @MainActor (Set<UUID>) -> Void
    ) {
        self.unreadCount = unreadCount
        self.clear = clear
        self.open = open
        self.openRollUpAlerts = openRollUpAlerts
        self.toggle = toggle
        self.setPresented = setPresented
        self.pendingRequest = pendingRequest
        self.clearRequest = clearRequest
        self.popoverContent = popoverContent
        self.pruneFilterModes = pruneFilterModes
    }

    package func trailingActions(
        parentPaneId: UUID,
        paneIds: [UUID],
        baseTrailingActions: DrawerOverlay.TrailingActions,
        showPaneInboxAction: TargetedCommandControlAction?,
        inboxPopoverPresented: Binding<Bool>
    ) -> DrawerOverlay.TrailingActions {
        DrawerOverlay.TrailingActions(
            openEditorMenuAction: baseTrailingActions.openEditorMenuAction,
            openFinderAction: baseTrailingActions.openFinderAction,
            copyPathAction: baseTrailingActions.copyPathAction,
            showPaneInboxAction: showPaneInboxAction,
            editorMenuContent: baseTrailingActions.editorMenuContent,
            editorMenuPresented: baseTrailingActions.editorMenuPresented,
            buttonTitle: baseTrailingActions.buttonTitle,
            inboxPopoverPresented: inboxPopoverPresented,
            inboxPopoverContent: popoverContent(
                parentPaneId, paneIds,
                {
                    inboxPopoverPresented.wrappedValue = false
                }),
            inboxUnreadBadge: PaneInboxUnreadBadge(unreadCount: unreadCount(paneIds))
        )
    }
}
