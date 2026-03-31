import Foundation

/// Snapshot of a single tab's structural state.
/// Contains ONLY IDs and counts — no NSView references.
struct TabSnapshot: Equatable {
    let id: UUID
    let visiblePaneIds: [UUID]
    let ownedPaneIds: [UUID]
    let activePaneId: UUID?

    var isSplit: Bool { visiblePaneIds.count > 1 }
    var visiblePaneCount: Int { visiblePaneIds.count }
    var ownedPaneCount: Int { ownedPaneIds.count }

    func ownsPane(_ paneId: UUID) -> Bool {
        ownedPaneIds.contains(paneId)
    }

    func showsPane(_ paneId: UUID) -> Bool {
        visiblePaneIds.contains(paneId)
    }
}

/// Lightweight, pure-value snapshot of tab/pane state for validation.
/// Contains ONLY structural information (IDs, counts) — no NSView references.
/// Tests construct these directly with UUIDs.
struct ActionStateSnapshot: Equatable {
    let tabs: [TabSnapshot]
    let activeTabId: UUID?
    let isManagementModeActive: Bool
    let knownRepoIds: Set<UUID>
    let knownWorktreeIds: Set<UUID>
    /// Drawer child -> parent layout pane mapping for drag/drop policy checks.
    let drawerParentByPaneId: [UUID: UUID]

    /// Reverse lookup: owned paneId → tabId for O(1) resolution.
    private let ownedPaneToTab: [UUID: UUID]
    /// Reverse lookup: visible paneId → tabId for O(1) resolution.
    private let visiblePaneToTab: [UUID: UUID]

    init(
        tabs: [TabSnapshot],
        activeTabId: UUID?,
        isManagementModeActive: Bool,
        knownRepoIds: Set<UUID> = [],
        knownWorktreeIds: Set<UUID> = [],
        drawerParentByPaneId: [UUID: UUID] = [:]
    ) {
        self.tabs = tabs
        self.activeTabId = activeTabId
        self.isManagementModeActive = isManagementModeActive
        self.knownRepoIds = knownRepoIds
        self.knownWorktreeIds = knownWorktreeIds
        self.drawerParentByPaneId = drawerParentByPaneId

        var ownedLookup: [UUID: UUID] = [:]
        var visibleLookup: [UUID: UUID] = [:]
        for tab in tabs {
            for paneId in tab.ownedPaneIds {
                ownedLookup[paneId] = tab.id
            }
            for paneId in tab.visiblePaneIds {
                visibleLookup[paneId] = tab.id
            }
        }
        // Drawer panes belong to the same tab as their parent layout pane.
        // A drawer cannot exist without its parent, so the parent is always
        // in the lookup by this point.
        for (drawerPaneId, parentPaneId) in drawerParentByPaneId {
            guard let parentTabId = ownedLookup[parentPaneId] else { continue }
            ownedLookup[drawerPaneId] = parentTabId
        }
        self.ownedPaneToTab = ownedLookup
        self.visiblePaneToTab = visibleLookup
    }

    func tab(_ id: UUID) -> TabSnapshot? {
        tabs.first { $0.id == id }
    }

    func tabOwnsPane(_ tabId: UUID, paneId: UUID) -> Bool {
        ownedPaneToTab[paneId] == tabId
    }

    func tabShowsPane(_ tabId: UUID, paneId: UUID) -> Bool {
        visiblePaneToTab[paneId] == tabId
    }

    func tabOwning(paneId: UUID) -> TabSnapshot? {
        guard let tabId = ownedPaneToTab[paneId] else { return nil }
        return tab(tabId)
    }

    func tabShowing(paneId: UUID) -> TabSnapshot? {
        guard let tabId = visiblePaneToTab[paneId] else { return nil }
        return tab(tabId)
    }

    func drawerParentPaneId(of paneId: UUID) -> UUID? {
        drawerParentByPaneId[paneId]
    }

    var tabCount: Int { tabs.count }

    /// All pane IDs across all tabs. Used for cardinality validation.
    var allOwnedPaneIds: Set<UUID> {
        Set(tabs.flatMap(\.ownedPaneIds))
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.tabs == rhs.tabs
            && lhs.activeTabId == rhs.activeTabId
            && lhs.isManagementModeActive == rhs.isManagementModeActive
            && lhs.knownRepoIds == rhs.knownRepoIds
            && lhs.knownWorktreeIds == rhs.knownWorktreeIds
            && lhs.drawerParentByPaneId == rhs.drawerParentByPaneId
    }
}
