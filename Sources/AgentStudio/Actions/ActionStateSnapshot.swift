import Foundation

/// Snapshot of a single tab's structural state.
/// Contains ONLY IDs and counts — no NSView references.
struct TabSnapshot: Equatable {
    let id: UUID
    let paneIds: [UUID]
    let activePaneId: UUID?

    var isSplit: Bool { paneIds.count > 1 }
    var paneCount: Int { paneIds.count }
}

/// Lightweight, pure-value snapshot of tab/pane state for validation.
/// Contains ONLY structural information (IDs, counts) — no NSView references.
/// Tests construct these directly with UUIDs.
struct ActionStateSnapshot: Equatable {
    let tabs: [TabSnapshot]
    let activeTabId: UUID?
    let isManagementModeActive: Bool

    /// Reverse lookup: paneId → tabId for O(1) resolution.
    private let paneToTab: [UUID: UUID]

    init(tabs: [TabSnapshot], activeTabId: UUID?, isManagementModeActive: Bool) {
        self.tabs = tabs
        self.activeTabId = activeTabId
        self.isManagementModeActive = isManagementModeActive

        var lookup: [UUID: UUID] = [:]
        for tab in tabs {
            for paneId in tab.paneIds {
                lookup[paneId] = tab.id
            }
        }
        self.paneToTab = lookup
    }

    func tab(_ id: UUID) -> TabSnapshot? {
        tabs.first { $0.id == id }
    }

    func tabContainsPane(_ tabId: UUID, paneId: UUID) -> Bool {
        paneToTab[paneId] == tabId
    }

    func tabContaining(paneId: UUID) -> TabSnapshot? {
        guard let tabId = paneToTab[paneId] else { return nil }
        return tab(tabId)
    }

    var tabCount: Int { tabs.count }

    /// All session/pane IDs across all tabs. Used for cardinality validation.
    var allSessionIds: Set<UUID> {
        Set(tabs.flatMap(\.paneIds))
    }

    static func == (lhs: ActionStateSnapshot, rhs: ActionStateSnapshot) -> Bool {
        lhs.tabs == rhs.tabs
            && lhs.activeTabId == rhs.activeTabId
            && lhs.isManagementModeActive == rhs.isManagementModeActive
    }
}
