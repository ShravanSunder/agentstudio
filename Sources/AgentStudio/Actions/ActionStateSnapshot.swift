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

    func tab(_ id: UUID) -> TabSnapshot? {
        tabs.first { $0.id == id }
    }

    func tabContainsPane(_ tabId: UUID, paneId: UUID) -> Bool {
        tab(tabId)?.paneIds.contains(paneId) ?? false
    }

    func tabContaining(paneId: UUID) -> TabSnapshot? {
        tabs.first { $0.paneIds.contains(paneId) }
    }

    var tabCount: Int { tabs.count }
}
