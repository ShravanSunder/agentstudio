import Foundation
import Observation

@MainActor
@Observable
final class PaneInboxPresentationAtom {
    private var filterModesByParentPaneId: [UUID: PaneInboxNotificationFilterMode] = [:]
    private var temporaryOverride: InboxNotificationDisplayOverride?
    private(set) var temporaryOverrideGeneration = 0

    func filterMode(for parentPaneId: UUID) -> PaneInboxNotificationFilterMode {
        filterModesByParentPaneId[parentPaneId] ?? .unread
    }

    func setFilterMode(
        _ filterMode: PaneInboxNotificationFilterMode,
        for parentPaneId: UUID
    ) {
        filterModesByParentPaneId[parentPaneId] = filterMode
    }

    @discardableResult
    func toggleFilterMode(for parentPaneId: UUID) -> PaneInboxNotificationFilterMode {
        let updatedMode = filterMode(for: parentPaneId).toggled
        setFilterMode(updatedMode, for: parentPaneId)
        return updatedMode
    }

    func prune(retainingParentPaneIds retainedParentPaneIds: Set<UUID>) {
        filterModesByParentPaneId = filterModesByParentPaneId.filter { parentPaneId, _ in
            retainedParentPaneIds.contains(parentPaneId)
        }
    }

    func requestTemporaryOverride(
        contentMode: InboxNotificationContentMode,
        rowStateFilter: InboxNotificationRowStateFilter
    ) {
        temporaryOverride = .init(contentMode: contentMode, rowStateFilter: rowStateFilter)
        temporaryOverrideGeneration += 1
    }

    func consumeTemporaryOverride() -> InboxNotificationDisplayOverride? {
        let override = temporaryOverride
        temporaryOverride = nil
        return override
    }

}
