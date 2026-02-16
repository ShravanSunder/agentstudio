import Foundation
import Observation
import os.log

private let storeLogger = Logger(subsystem: "com.agentstudio", category: "WorkspaceStore")

/// Owns ALL persisted workspace state. Single source of truth.
/// All mutations go through here. Collaborators (WorkspacePersistor, ViewRegistry)
/// are internal — not peers.
///
/// All mutations MUST happen on the main thread (enforced by @MainActor).
/// SwiftUI views observe properties via @Observable's withObservationTracking.
/// AppKit controllers set up NSHostingView once; SwiftUI drives re-renders automatically.
/// See docs/architecture/appkit_swiftui_architecture.md for the hosting pattern.
@Observable
@MainActor
final class WorkspaceStore {

    // MARK: - Persisted State

    private(set) var repos: [Repo] = []
    private(set) var panes: [UUID: Pane] = [:]
    private(set) var tabs: [Tab] = []
    private(set) var activeTabId: UUID?

    // MARK: - Transient UI State

    var draggingTabId: UUID?
    var dropTargetIndex: Int?
    var tabFrames: [UUID: CGRect] = [:]

    // MARK: - Internal State

    private(set) var workspaceId: UUID = UUID()
    private(set) var workspaceName: String = "Default Workspace"
    private(set) var sidebarWidth: CGFloat = 250
    private(set) var windowFrame: CGRect?
    private(set) var createdAt: Date = Date()
    private(set) var updatedAt: Date = Date()

    // MARK: - Constants

    /// Ratio change per keyboard resize increment (5% per default Ghostty step).
    private static let resizeRatioStep: Double = 0.05
    /// Ghostty's default resize_split pixel amount.
    private static let resizeBaseAmount: Double = 10.0

    // MARK: - Collaborators

    private let persistor: WorkspacePersistor
    private var debouncedSaveTask: Task<Void, Never>?
    private(set) var isDirty: Bool = false

    // MARK: - Init

    init(persistor: WorkspacePersistor = WorkspacePersistor()) {
        self.persistor = persistor
    }

    // MARK: - Derived State

    var activeTab: Tab? {
        tabs.first { $0.id == activeTabId }
    }

    /// All pane IDs visible in the active tab's active arrangement.
    var activePaneIds: Set<UUID> {
        Set(activeTab?.paneIds ?? [])
    }

    /// Is a worktree active (has any pane)?
    func isWorktreeActive(_ worktreeId: UUID) -> Bool {
        panes.values.contains { $0.worktreeId == worktreeId }
    }

    /// Count of panes for a worktree.
    func paneCount(for worktreeId: UUID) -> Int {
        panes.values.filter { $0.worktreeId == worktreeId }.count
    }

    // MARK: - Orphaned Pane Pool

    /// Panes that exist in the store but are not in any tab layout.
    /// These are backgrounded panes waiting to be reactivated or garbage-collected.
    var orphanedPanes: [Pane] {
        let layoutPaneIds = Set(tabs.flatMap(\.panes))
        return panes.values.filter { !layoutPaneIds.contains($0.id) && $0.residency == .backgrounded }
    }

    /// Remove a pane from all tab layouts and move to the background pool.
    /// The pane stays in the dict with `.backgrounded` residency — its zmx session stays alive.
    func backgroundPane(_ paneId: UUID) {
        guard panes[paneId] != nil else {
            storeLogger.warning("backgroundPane: pane \(paneId) not found")
            return
        }

        // Remove from all tab layouts
        for tabIndex in tabs.indices {
            tabs[tabIndex].panes.removeAll { $0 == paneId }
            for arrIndex in tabs[tabIndex].arrangements.indices {
                tabs[tabIndex].arrangements[arrIndex].visiblePaneIds.remove(paneId)
                if let newLayout = tabs[tabIndex].arrangements[arrIndex].layout.removing(paneId: paneId) {
                    tabs[tabIndex].arrangements[arrIndex].layout = newLayout
                } else {
                    tabs[tabIndex].arrangements[arrIndex].layout = Layout()
                }
            }
            // If active arrangement is now empty but default still has panes,
            // fall back to default so the tab doesn't render as blank.
            if tabs[tabIndex].activeArrangement.layout.isEmpty
                && !tabs[tabIndex].defaultArrangement.layout.isEmpty {
                tabs[tabIndex].activeArrangementId = tabs[tabIndex].defaultArrangement.id
            }
            if tabs[tabIndex].activePaneId == paneId {
                tabs[tabIndex].activePaneId = tabs[tabIndex].activeArrangement.layout.paneIds.first
            }
            if tabs[tabIndex].zoomedPaneId == paneId {
                tabs[tabIndex].zoomedPaneId = nil
            }
            tabs[tabIndex].minimizedPaneIds.remove(paneId)
        }
        // Remove empty tabs
        tabs.removeAll { $0.defaultArrangement.layout.isEmpty }
        if let atId = activeTabId, !tabs.contains(where: { $0.id == atId }) {
            activeTabId = tabs.last?.id
        }

        panes[paneId]!.residency = .backgrounded
        markDirty()
    }

    /// Reactivate a backgrounded pane by inserting it into a tab layout.
    func reactivatePane(
        _ paneId: UUID,
        inTab tabId: UUID,
        at targetPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position
    ) {
        guard panes[paneId] != nil else {
            storeLogger.warning("reactivatePane: pane \(paneId) not found")
            return
        }
        guard panes[paneId]!.residency == .backgrounded else {
            storeLogger.warning("reactivatePane: pane \(paneId) is not backgrounded")
            return
        }
        // Verify insertion target is valid before changing residency.
        // insertPane can fail silently if the tab or target pane no longer exist,
        // which would leave the pane active but not in any layout.
        guard let tabIndex = findTabIndex(tabId) else {
            storeLogger.warning("reactivatePane: tab \(tabId) not found — keeping pane backgrounded")
            return
        }
        let arrIndex = tabs[tabIndex].activeArrangementIndex
        guard tabs[tabIndex].arrangements[arrIndex].layout.contains(targetPaneId) else {
            storeLogger.warning("reactivatePane: targetPaneId \(targetPaneId) not in active arrangement — keeping pane backgrounded")
            return
        }

        panes[paneId]!.residency = .active
        insertPane(paneId, inTab: tabId, at: targetPaneId, direction: direction, position: position)
    }

    /// Permanently destroy backgrounded panes that have been in the pool too long
    /// or are no longer needed.
    func purgeOrphanedPane(_ paneId: UUID) {
        guard let pane = panes[paneId], pane.residency == .backgrounded else {
            storeLogger.warning("purgeOrphanedPane: pane \(paneId) is not backgrounded")
            return
        }
        panes.removeValue(forKey: paneId)
        markDirty()
    }

    // MARK: - Queries

    func pane(_ id: UUID) -> Pane? {
        guard let pane = panes[id] else {
            storeLogger.warning("pane(\(id)): not found in store")
            return nil
        }
        return pane
    }

    func tab(_ id: UUID) -> Tab? {
        tabs.first { $0.id == id }
    }

    func tabContaining(paneId: UUID) -> Tab? {
        tabs.first { $0.panes.contains(paneId) }
    }

    func repo(_ id: UUID) -> Repo? {
        repos.first { $0.id == id }
    }

    func worktree(_ id: UUID) -> Worktree? {
        repos.flatMap(\.worktrees).first { $0.id == id }
    }

    func repo(containing worktreeId: UUID) -> Repo? {
        repos.first { repo in
            repo.worktrees.contains { $0.id == worktreeId }
        }
    }

    func panes(for worktreeId: UUID) -> [Pane] {
        panes.values.filter { $0.worktreeId == worktreeId }
    }

    // MARK: - Pane Mutations

    @discardableResult
    func createPane(
        source: TerminalSource,
        title: String = "Terminal",
        provider: SessionProvider = .zmx,
        lifetime: SessionLifetime = .persistent,
        residency: SessionResidency = .active
    ) -> Pane {
        let pane = Pane(
            content: .terminal(TerminalState(provider: provider, lifetime: lifetime)),
            metadata: PaneMetadata(source: source, title: title),
            residency: residency
        )
        panes[pane.id] = pane
        markDirty()
        return pane
    }

    /// Create a pane with arbitrary content (webview, code viewer, etc.).
    @discardableResult
    func createPane(
        content: PaneContent,
        metadata: PaneMetadata,
        residency: SessionResidency = .active
    ) -> Pane {
        let pane = Pane(
            content: content,
            metadata: metadata,
            residency: residency
        )
        panes[pane.id] = pane
        markDirty()
        return pane
    }

    func removePane(_ paneId: UUID) {
        // Cascade-delete drawer children before removing the parent.
        // Prevents orphaned drawer child panes with dangling parentPaneId references.
        if let drawer = panes[paneId]?.drawer {
            for childId in drawer.paneIds {
                panes.removeValue(forKey: childId)
            }
        }

        panes.removeValue(forKey: paneId)

        // Remove from all tab layouts
        for tabIndex in tabs.indices {
            tabs[tabIndex].panes.removeAll { $0 == paneId }
            // Remove from all arrangements
            for arrIndex in tabs[tabIndex].arrangements.indices {
                tabs[tabIndex].arrangements[arrIndex].visiblePaneIds.remove(paneId)
                if let newLayout = tabs[tabIndex].arrangements[arrIndex].layout.removing(paneId: paneId) {
                    tabs[tabIndex].arrangements[arrIndex].layout = newLayout
                } else {
                    // Layout became empty
                    tabs[tabIndex].arrangements[arrIndex].layout = Layout()
                }
            }
            // Update activePaneId if it was the removed pane
            if tabs[tabIndex].activePaneId == paneId {
                tabs[tabIndex].activePaneId = tabs[tabIndex].activeArrangement.layout.paneIds.first
            }
            if tabs[tabIndex].zoomedPaneId == paneId {
                tabs[tabIndex].zoomedPaneId = nil
            }
            tabs[tabIndex].minimizedPaneIds.remove(paneId)
        }
        // Remove empty tabs (default arrangement has empty layout)
        tabs.removeAll { $0.defaultArrangement.layout.isEmpty }
        // Fix activeTabId if it was removed
        if let atId = activeTabId, !tabs.contains(where: { $0.id == atId }) {
            activeTabId = tabs.last?.id
        }
        markDirty()
    }

    func updatePaneTitle(_ paneId: UUID, title: String) {
        guard panes[paneId] != nil else {
            storeLogger.warning("updatePaneTitle: pane \(paneId) not found")
            return
        }
        panes[paneId]!.metadata.title = title
        markDirty()
    }

    func updatePaneCWD(_ paneId: UUID, cwd: URL?) {
        guard panes[paneId] != nil else {
            storeLogger.warning("updatePaneCWD: pane \(paneId) not found")
            return
        }
        guard panes[paneId]!.metadata.cwd != cwd else { return }
        panes[paneId]!.metadata.cwd = cwd
        markDirty()
    }

    func updatePaneAgent(_ paneId: UUID, agent: AgentType?) {
        guard panes[paneId] != nil else {
            storeLogger.warning("updatePaneAgent: pane \(paneId) not found")
            return
        }
        panes[paneId]!.metadata.agentType = agent
        markDirty()
    }

    func setResidency(_ residency: SessionResidency, for paneId: UUID) {
        guard panes[paneId] != nil else {
            storeLogger.warning("setResidency: pane \(paneId) not found")
            return
        }
        panes[paneId]!.residency = residency
        markDirty()
    }

    // MARK: - Tab Mutations

    func appendTab(_ tab: Tab) {
        tabs.append(tab)
        activeTabId = tab.id
        markDirty()
    }

    func removeTab(_ tabId: UUID) {
        tabs.removeAll { $0.id == tabId }
        if activeTabId == tabId {
            activeTabId = tabs.last?.id
        }
        markDirty()
    }

    func insertTab(_ tab: Tab, at index: Int) {
        let clampedIndex = min(index, tabs.count)
        tabs.insert(tab, at: clampedIndex)
        markDirty()
    }

    func moveTab(fromId: UUID, toIndex: Int) {
        guard let fromIndex = tabs.firstIndex(where: { $0.id == fromId }) else {
            storeLogger.warning("moveTab: tab \(fromId) not found")
            return
        }
        let tab = tabs.remove(at: fromIndex)
        // After removal, indices shift left. Adjust toIndex to compensate.
        let adjustedIndex = toIndex > fromIndex ? toIndex - 1 : toIndex
        let clampedIndex = max(0, min(adjustedIndex, tabs.count))
        tabs.insert(tab, at: clampedIndex)
        markDirty()
    }

    /// Move a tab by a relative delta. Clamps at boundaries (no cyclic wrap),
    /// matching Ghostty's TerminalController.onMoveTab behavior.
    func moveTabByDelta(tabId: UUID, delta: Int) {
        guard let fromIndex = tabs.firstIndex(where: { $0.id == tabId }) else {
            storeLogger.warning("moveTabByDelta: tab \(tabId) not found")
            return
        }
        let count = tabs.count
        guard count > 1 else { return }

        // Clamp at boundaries — matches Ghostty's behavior.
        let finalIndex: Int
        if delta < 0 {
            let magnitude = delta == Int.min ? Int.max : -delta
            finalIndex = fromIndex - min(fromIndex, magnitude)
        } else {
            let remaining = count - 1 - fromIndex
            finalIndex = fromIndex + min(remaining, delta)
        }
        guard finalIndex != fromIndex else { return }

        let tab = tabs.remove(at: fromIndex)
        tabs.insert(tab, at: finalIndex)
        markDirty()
    }

    func setActiveTab(_ tabId: UUID?) {
        activeTabId = tabId
        markDirty()
    }

    // MARK: - Layout Mutations (within a tab's active arrangement)

    func insertPane(
        _ paneId: UUID,
        inTab tabId: UUID,
        at targetPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position
    ) {
        guard let tabIndex = findTabIndex(tabId) else { return }
        let arrIndex = tabs[tabIndex].activeArrangementIndex

        // Validate targetPaneId exists in active arrangement
        guard tabs[tabIndex].arrangements[arrIndex].layout.contains(targetPaneId) else {
            storeLogger.warning("insertPane: targetPaneId \(targetPaneId) not in active arrangement")
            return
        }

        // Clear zoom on new split — user needs to see all panes
        tabs[tabIndex].zoomedPaneId = nil
        tabs[tabIndex].arrangements[arrIndex].layout = tabs[tabIndex].arrangements[arrIndex].layout
            .inserting(paneId: paneId, at: targetPaneId, direction: direction, position: position)
        tabs[tabIndex].arrangements[arrIndex].visiblePaneIds.insert(paneId)

        // Also add to default arrangement if active is not default
        if !tabs[tabIndex].arrangements[arrIndex].isDefault {
            let defIdx = tabs[tabIndex].defaultArrangementIndex
            // Only insert into default if targetPaneId exists there too
            if tabs[tabIndex].arrangements[defIdx].layout.contains(targetPaneId) {
                tabs[tabIndex].arrangements[defIdx].layout = tabs[tabIndex].arrangements[defIdx].layout
                    .inserting(paneId: paneId, at: targetPaneId, direction: direction, position: position)
                tabs[tabIndex].arrangements[defIdx].visiblePaneIds.insert(paneId)
            }
        }

        // Add to tab's pane list
        if !tabs[tabIndex].panes.contains(paneId) {
            tabs[tabIndex].panes.append(paneId)
        }
        markDirty()
    }

    /// Remove a pane from a tab's layouts. Returns `true` if the tab is now empty
    /// (last pane was removed) — caller is responsible for handling tab closure with undo.
    @discardableResult
    func removePaneFromLayout(_ paneId: UUID, inTab tabId: UUID) -> Bool {
        guard let tabIndex = findTabIndex(tabId) else { return false }
        let arrIndex = tabs[tabIndex].activeArrangementIndex

        // Clear zoom if the zoomed pane is being removed
        if tabs[tabIndex].zoomedPaneId == paneId {
            tabs[tabIndex].zoomedPaneId = nil
        }

        // Clear minimized state for the removed pane
        tabs[tabIndex].minimizedPaneIds.remove(paneId)

        if let newLayout = tabs[tabIndex].arrangements[arrIndex].layout.removing(paneId: paneId) {
            tabs[tabIndex].arrangements[arrIndex].layout = newLayout
            tabs[tabIndex].arrangements[arrIndex].visiblePaneIds.remove(paneId)
            // Update active pane if removed
            if tabs[tabIndex].activePaneId == paneId {
                tabs[tabIndex].activePaneId = newLayout.paneIds.first
            }
            // Auto-expand if only one pane remains and it's minimized
            let remainingPaneIds = newLayout.paneIds
            let nonMinimized = remainingPaneIds.filter { !tabs[tabIndex].minimizedPaneIds.contains($0) }
            if nonMinimized.isEmpty, let lastMinimized = remainingPaneIds.first {
                tabs[tabIndex].minimizedPaneIds.remove(lastMinimized)
                tabs[tabIndex].activePaneId = lastMinimized
            }
        } else {
            // Last pane removed — signal to caller that tab is now empty.
            // Do NOT call removeTab here: let ActionExecutor handle it with undo support.
            return true
        }

        // Also remove from default arrangement if active is not default
        if !tabs[tabIndex].arrangements[arrIndex].isDefault {
            let defIdx = tabs[tabIndex].defaultArrangementIndex
            tabs[tabIndex].arrangements[defIdx].visiblePaneIds.remove(paneId)
            if let newDefLayout = tabs[tabIndex].arrangements[defIdx].layout.removing(paneId: paneId) {
                tabs[tabIndex].arrangements[defIdx].layout = newDefLayout
            }
        }

        // Remove from tab's pane list
        tabs[tabIndex].panes.removeAll { $0 == paneId }

        markDirty()
        return false
    }

    func resizePane(tabId: UUID, splitId: UUID, ratio: Double) {
        guard let tabIndex = findTabIndex(tabId) else { return }
        let arrIndex = tabs[tabIndex].activeArrangementIndex
        tabs[tabIndex].arrangements[arrIndex].layout = tabs[tabIndex].arrangements[arrIndex].layout
            .resizing(splitId: splitId, ratio: ratio)
        markDirty()
    }

    func equalizePanes(tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else { return }
        let arrIndex = tabs[tabIndex].activeArrangementIndex
        tabs[tabIndex].arrangements[arrIndex].layout = tabs[tabIndex].arrangements[arrIndex].layout.equalized()
        markDirty()
    }

    func setActivePane(_ paneId: UUID?, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else { return }
        // Validate paneId exists in the pane dict and in the tab's pane list
        if let paneId = paneId {
            guard panes[paneId] != nil, tabs[tabIndex].panes.contains(paneId) else {
                storeLogger.warning("setActivePane: paneId \(paneId) not found in tab \(tabId)")
                return
            }
        }
        tabs[tabIndex].activePaneId = paneId
        markDirty()
    }

    // MARK: - Arrangement Mutations

    /// Create a new custom arrangement with a subset of the tab's panes.
    /// The layout is derived from the default arrangement by removing panes not in the subset.
    @discardableResult
    func createArrangement(name: String, paneIds: Set<UUID>, inTab tabId: UUID) -> UUID? {
        guard let tabIndex = findTabIndex(tabId) else { return nil }
        guard !paneIds.isEmpty else {
            storeLogger.warning("createArrangement: empty paneIds")
            return nil
        }

        // Validate all paneIds are in the tab
        let tabPaneSet = Set(tabs[tabIndex].panes)
        guard paneIds.isSubset(of: tabPaneSet) else {
            storeLogger.warning("createArrangement: paneIds not all in tab \(tabId)")
            return nil
        }

        // Build layout by filtering the default arrangement's layout
        let defLayout = tabs[tabIndex].defaultArrangement.layout
        let paneIdsToRemove = Set(defLayout.paneIds).subtracting(paneIds)
        var filteredLayout = defLayout
        for removeId in paneIdsToRemove {
            if let newLayout = filteredLayout.removing(paneId: removeId) {
                filteredLayout = newLayout
            }
        }

        let arrangement = PaneArrangement(
            name: name,
            isDefault: false,
            layout: filteredLayout,
            visiblePaneIds: paneIds
        )
        tabs[tabIndex].arrangements.append(arrangement)
        markDirty()
        return arrangement.id
    }

    /// Remove a custom arrangement. Cannot remove the default arrangement.
    /// If the removed arrangement was active, switches to the default.
    func removeArrangement(_ arrangementId: UUID, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else { return }
        guard let arrIndex = tabs[tabIndex].arrangements.firstIndex(where: { $0.id == arrangementId }) else {
            storeLogger.warning("removeArrangement: arrangement \(arrangementId) not found in tab \(tabId)")
            return
        }
        guard !tabs[tabIndex].arrangements[arrIndex].isDefault else {
            storeLogger.warning("removeArrangement: cannot remove default arrangement")
            return
        }

        // If removing the active arrangement, switch to default first
        if tabs[tabIndex].activeArrangementId == arrangementId {
            tabs[tabIndex].activeArrangementId = tabs[tabIndex].defaultArrangement.id
            // Update activePaneId to one visible in default
            if let activePaneId = tabs[tabIndex].activePaneId,
               !tabs[tabIndex].defaultArrangement.layout.contains(activePaneId) {
                tabs[tabIndex].activePaneId = tabs[tabIndex].defaultArrangement.layout.paneIds.first
            }
        }

        tabs[tabIndex].arrangements.remove(at: arrIndex)
        markDirty()
    }

    /// Switch to a different arrangement within a tab.
    func switchArrangement(to arrangementId: UUID, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else { return }
        guard tabs[tabIndex].arrangements.contains(where: { $0.id == arrangementId }) else {
            storeLogger.warning("switchArrangement: arrangement \(arrangementId) not found in tab \(tabId)")
            return
        }
        guard tabs[tabIndex].activeArrangementId != arrangementId else { return }

        // Clear transient state when switching arrangements
        tabs[tabIndex].zoomedPaneId = nil
        tabs[tabIndex].minimizedPaneIds = []
        tabs[tabIndex].activeArrangementId = arrangementId

        // Update activePaneId if current one isn't in the new arrangement
        if let activePaneId = tabs[tabIndex].activePaneId,
           !tabs[tabIndex].activeArrangement.layout.contains(activePaneId) {
            tabs[tabIndex].activePaneId = tabs[tabIndex].activeArrangement.layout.paneIds.first
        }

        markDirty()
    }

    /// Rename a custom arrangement.
    func renameArrangement(_ arrangementId: UUID, name: String, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else { return }
        guard let arrIndex = tabs[tabIndex].arrangements.firstIndex(where: { $0.id == arrangementId }) else {
            storeLogger.warning("renameArrangement: arrangement \(arrangementId) not found in tab \(tabId)")
            return
        }
        tabs[tabIndex].arrangements[arrIndex].name = name
        markDirty()
    }

    // MARK: - Drawer Mutations

    /// Add a drawer pane to a parent pane. Creates a real `Pane` with `kind: .drawerChild`.
    /// The new pane is added to `store.panes` and the parent's drawer.
    @discardableResult
    func addDrawerPane(
        to parentPaneId: UUID,
        content: PaneContent,
        metadata: PaneMetadata
    ) -> Pane? {
        guard panes[parentPaneId] != nil else {
            storeLogger.warning("addDrawerPane: parent pane \(parentPaneId) not found")
            return nil
        }

        let drawerPane = Pane(
            content: content,
            metadata: metadata,
            kind: .drawerChild(parentPaneId: parentPaneId)
        )

        // Add to store as first-class pane
        panes[drawerPane.id] = drawerPane

        // Add to parent's drawer
        panes[parentPaneId]!.withDrawer { drawer in
            if let existingLeaf = drawer.layout.paneIds.last {
                drawer.layout = drawer.layout.inserting(
                    paneId: drawerPane.id, at: existingLeaf,
                    direction: .horizontal, position: .after
                )
            } else {
                drawer.layout = Layout(paneId: drawerPane.id)
            }
            drawer.paneIds.append(drawerPane.id)
            drawer.activePaneId = drawerPane.id
            drawer.isExpanded = true
        }

        markDirty()
        return drawerPane
    }

    /// Remove a drawer pane from its parent. Removes the drawer panes list entry,
    /// the layout leaf, and the store entry. Resets drawer if empty.
    func removeDrawerPane(_ drawerPaneId: UUID, from parentPaneId: UUID) {
        guard panes[parentPaneId] != nil,
              panes[parentPaneId]!.drawer != nil else {
            storeLogger.warning("removeDrawerPane: parent pane \(parentPaneId) has no drawer")
            return
        }

        // Remove from parent's drawer
        panes[parentPaneId]!.withDrawer { drawer in
            drawer.paneIds.removeAll { $0 == drawerPaneId }
            drawer.minimizedPaneIds.remove(drawerPaneId)

            // Remove from layout
            if drawer.layout.contains(drawerPaneId) {
                drawer.layout = drawer.layout.removing(paneId: drawerPaneId) ?? Layout()
            }

            // Update active drawer pane if removed
            if drawer.activePaneId == drawerPaneId {
                drawer.activePaneId = drawer.paneIds.first
            }
        }

        // Reset drawer to empty state if no panes left, preserving isExpanded.
        if panes[parentPaneId]!.drawer!.paneIds.isEmpty {
            let wasExpanded = panes[parentPaneId]!.drawer!.isExpanded
            panes[parentPaneId]!.kind = .layout(drawer: Drawer(isExpanded: wasExpanded))
        }

        // Remove the drawer pane from the store
        panes.removeValue(forKey: drawerPaneId)

        markDirty()
    }

    /// Toggle the expanded/collapsed state of a pane's drawer.
    func toggleDrawer(for paneId: UUID) {
        guard panes[paneId] != nil,
              panes[paneId]!.drawer != nil,
              !panes[paneId]!.drawer!.paneIds.isEmpty else {
            storeLogger.warning("toggleDrawer: pane \(paneId) has no drawer or drawer is empty")
            return
        }

        let willExpand = !panes[paneId]!.drawer!.isExpanded

        // Invariant: only one drawer expanded at a time.
        // Collapse all others when expanding this one.
        if willExpand {
            for otherPaneId in panes.keys where otherPaneId != paneId {
                if panes[otherPaneId]?.drawer?.isExpanded == true {
                    panes[otherPaneId]!.withDrawer { $0.isExpanded = false }
                }
            }
        }

        panes[paneId]!.withDrawer { $0.isExpanded = willExpand }
        markDirty()
    }

    /// Set the active drawer pane within a pane's drawer.
    func setActiveDrawerPane(_ drawerPaneId: UUID, in parentPaneId: UUID) {
        guard panes[parentPaneId] != nil,
              let drawer = panes[parentPaneId]!.drawer,
              drawer.paneIds.contains(drawerPaneId) else {
            storeLogger.warning("setActiveDrawerPane: drawer pane \(drawerPaneId) not found in pane \(parentPaneId)")
            return
        }

        panes[parentPaneId]!.withDrawer { $0.activePaneId = drawerPaneId }
        markDirty()
    }

    /// Resize a split within a drawer's layout.
    func resizeDrawerPane(parentPaneId: UUID, splitId: UUID, ratio: Double) {
        guard panes[parentPaneId] != nil,
              panes[parentPaneId]!.drawer != nil else { return }
        panes[parentPaneId]!.withDrawer { drawer in
            drawer.layout = drawer.layout.resizing(splitId: splitId, ratio: ratio)
        }
        markDirty()
    }

    /// Equalize all splits within a drawer's layout.
    func equalizeDrawerPanes(parentPaneId: UUID) {
        guard panes[parentPaneId] != nil,
              panes[parentPaneId]!.drawer != nil else { return }
        panes[parentPaneId]!.withDrawer { drawer in
            drawer.layout = drawer.layout.equalized()
        }
        markDirty()
    }

    /// Minimize a pane within a drawer (add to minimizedPaneIds).
    func minimizeDrawerPane(_ drawerPaneId: UUID, in parentPaneId: UUID) {
        guard panes[parentPaneId] != nil,
              let drawer = panes[parentPaneId]!.drawer,
              drawer.paneIds.contains(drawerPaneId) else { return }

        // Cannot minimize the last non-minimized pane
        let nonMinimized = drawer.paneIds.filter { !drawer.minimizedPaneIds.contains($0) }
        guard nonMinimized.count > 1 else {
            storeLogger.warning("minimizeDrawerPane: cannot minimize last visible drawer pane")
            return
        }

        panes[parentPaneId]!.withDrawer { drawer in
            drawer.minimizedPaneIds.insert(drawerPaneId)
            // If minimized pane was active, switch to next non-minimized
            if drawer.activePaneId == drawerPaneId {
                drawer.activePaneId = drawer.paneIds.first { !drawer.minimizedPaneIds.contains($0) }
            }
        }
    }

    /// Expand a minimized pane within a drawer (remove from minimizedPaneIds).
    func expandDrawerPane(_ drawerPaneId: UUID, in parentPaneId: UUID) {
        guard panes[parentPaneId] != nil,
              panes[parentPaneId]!.drawer?.minimizedPaneIds.contains(drawerPaneId) == true else { return }

        panes[parentPaneId]!.withDrawer { drawer in
            drawer.minimizedPaneIds.remove(drawerPaneId)
        }
    }

    // MARK: - Zoom

    func toggleZoom(paneId: UUID, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else { return }
        if tabs[tabIndex].zoomedPaneId == paneId {
            tabs[tabIndex].zoomedPaneId = nil
        } else if tabs[tabIndex].layout.contains(paneId) {
            tabs[tabIndex].zoomedPaneId = paneId
        }
        // Do NOT markDirty() — zoom is transient, not persisted
    }

    // MARK: - Minimize / Expand

    /// Minimize a pane — collapse it to a narrow bar in the UI.
    /// Cannot minimize the last non-minimized pane in the active arrangement.
    @discardableResult
    func minimizePane(_ paneId: UUID, inTab tabId: UUID) -> Bool {
        guard let tabIndex = findTabIndex(tabId) else { return false }
        let visiblePaneIds = tabs[tabIndex].paneIds
        let nonMinimized = visiblePaneIds.filter { !tabs[tabIndex].minimizedPaneIds.contains($0) }
        guard nonMinimized.count > 1 else {
            storeLogger.warning("minimizePane: cannot minimize last visible pane \(paneId)")
            return false
        }
        guard visiblePaneIds.contains(paneId) else {
            storeLogger.warning("minimizePane: pane \(paneId) not in active arrangement")
            return false
        }

        tabs[tabIndex].minimizedPaneIds.insert(paneId)

        // Update activePaneId if minimizing the active pane
        if tabs[tabIndex].activePaneId == paneId {
            tabs[tabIndex].activePaneId = nonMinimized.first { $0 != paneId }
        }

        // Clear zoom if minimizing the zoomed pane
        if tabs[tabIndex].zoomedPaneId == paneId {
            tabs[tabIndex].zoomedPaneId = nil
        }

        markDirty()
        return true
    }

    /// Expand a minimized pane — restore it from the collapsed bar.
    func expandPane(_ paneId: UUID, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else { return }
        guard tabs[tabIndex].minimizedPaneIds.contains(paneId) else { return }

        tabs[tabIndex].minimizedPaneIds.remove(paneId)
        tabs[tabIndex].activePaneId = paneId
        markDirty()
    }

    // MARK: - Keyboard Resize

    func resizePaneByDelta(tabId: UUID, paneId: UUID, direction: SplitResizeDirection, amount: UInt16) {
        guard let tabIndex = findTabIndex(tabId) else { return }
        let tab = tabs[tabIndex]

        // No-op while zoomed — no visual feedback for resize
        guard tab.zoomedPaneId == nil else {
            storeLogger.debug("Ignoring resize while zoomed")
            return
        }

        guard let (splitId, increase) = tab.layout.resizeTarget(for: paneId, direction: direction) else {
            storeLogger.debug("No resize target for pane \(paneId) direction \(direction)")
            return
        }

        guard let currentRatio = tab.layout.ratioForSplit(splitId) else { return }

        // Ratio step per Ghostty resize increment, clamped to safe bounds
        let delta = Self.resizeRatioStep * (Double(amount) / Self.resizeBaseAmount)
        let newRatio = min(0.9, max(0.1, increase ? currentRatio + delta : currentRatio - delta))

        let arrIndex = tabs[tabIndex].activeArrangementIndex
        tabs[tabIndex].arrangements[arrIndex].layout = tabs[tabIndex].arrangements[arrIndex].layout
            .resizing(splitId: splitId, ratio: newRatio)
        markDirty()
    }

    // MARK: - Compound Operations

    /// Break a split tab into individual tabs, one per pane.
    func breakUpTab(_ tabId: UUID) -> [Tab] {
        guard let tabIndex = findTabIndex(tabId) else { return [] }
        let tabPaneIds = tabs[tabIndex].paneIds
        guard tabPaneIds.count > 1 else { return [] }

        // Validate all pane IDs exist in the dict
        let validPaneIds = tabPaneIds.filter { panes[$0] != nil }
        guard !validPaneIds.isEmpty else {
            storeLogger.warning("breakUpTab: no valid panes found for tab \(tabId)")
            return []
        }

        // Clear zoom — tab is being decomposed
        tabs[tabIndex].zoomedPaneId = nil

        // Remove original tab
        tabs.remove(at: tabIndex)

        // Create individual tabs
        var newTabs: [Tab] = []
        for paneId in validPaneIds {
            let tab = Tab(paneId: paneId)
            newTabs.append(tab)
        }

        // Insert at original position
        let insertIndex = min(tabIndex, tabs.count)
        tabs.insert(contentsOf: newTabs, at: insertIndex)
        activeTabId = newTabs.first?.id

        markDirty()
        return newTabs
    }

    /// Extract a pane from a tab into its own new tab.
    func extractPane(_ paneId: UUID, fromTab tabId: UUID) -> Tab? {
        guard let tabIndex = findTabIndex(tabId) else { return nil }
        guard tabs[tabIndex].paneIds.count > 1 else { return nil }
        guard tabs[tabIndex].panes.contains(paneId) else {
            storeLogger.warning("extractPane: paneId \(paneId) not in tab \(tabId)")
            return nil
        }

        // Clear zoom if extracting the zoomed pane
        if tabs[tabIndex].zoomedPaneId == paneId {
            tabs[tabIndex].zoomedPaneId = nil
        }

        // Remove pane from source tab's arrangements
        for arrIndex in tabs[tabIndex].arrangements.indices {
            if let newLayout = tabs[tabIndex].arrangements[arrIndex].layout.removing(paneId: paneId) {
                tabs[tabIndex].arrangements[arrIndex].layout = newLayout
                tabs[tabIndex].arrangements[arrIndex].visiblePaneIds.remove(paneId)
            }
        }
        tabs[tabIndex].panes.removeAll { $0 == paneId }
        if tabs[tabIndex].activePaneId == paneId {
            tabs[tabIndex].activePaneId = tabs[tabIndex].activeArrangement.layout.paneIds.first
        }

        // Create new tab
        let newTab = Tab(paneId: paneId)
        let insertIndex = tabIndex + 1
        tabs.insert(newTab, at: min(insertIndex, tabs.count))
        activeTabId = newTab.id

        markDirty()
        return newTab
    }

    /// Merge all panes from source tab into target tab's layout.
    func mergeTab(
        sourceId: UUID,
        intoTarget targetId: UUID,
        at targetPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position
    ) {
        guard let sourceTabIndex = tabs.firstIndex(where: { $0.id == sourceId }),
              let targetTabIndex = tabs.firstIndex(where: { $0.id == targetId }) else { return }

        // Validate targetPaneId exists in target arrangement
        let targetArrIndex = tabs[targetTabIndex].activeArrangementIndex
        guard tabs[targetTabIndex].arrangements[targetArrIndex].layout.contains(targetPaneId) else {
            storeLogger.warning("mergeTab: targetPaneId \(targetPaneId) not in target arrangement")
            return
        }

        // Clear zoom on target tab — merging changes the layout structure
        tabs[targetTabIndex].zoomedPaneId = nil

        let sourcePaneIds = tabs[sourceTabIndex].paneIds

        // Insert each source pane into target layout
        var currentTarget = targetPaneId
        for paneId in sourcePaneIds {
            tabs[targetTabIndex].arrangements[targetArrIndex].layout = tabs[targetTabIndex].arrangements[targetArrIndex].layout
                .inserting(paneId: paneId, at: currentTarget, direction: direction, position: position)
            tabs[targetTabIndex].arrangements[targetArrIndex].visiblePaneIds.insert(paneId)
            if !tabs[targetTabIndex].panes.contains(paneId) {
                tabs[targetTabIndex].panes.append(paneId)
            }
            currentTarget = paneId
        }

        // Remove source tab
        tabs.remove(at: sourceTabIndex)

        // Fix activeTabId
        activeTabId = targetId

        markDirty()
    }

    // MARK: - Repo Mutations

    @discardableResult
    func addRepo(at path: URL) -> Repo {
        if let existing = repos.first(where: { $0.repoPath == path }) {
            return existing
        }
        let repo = Repo(name: path.lastPathComponent, repoPath: path)
        repos.append(repo)
        markDirty()
        return repo
    }

    func removeRepo(_ repoId: UUID) {
        repos.removeAll { $0.id == repoId }
        markDirty()
    }

    func updateRepoWorktrees(_ repoId: UUID, worktrees: [Worktree]) {
        guard let index = repos.firstIndex(where: { $0.id == repoId }) else { return }
        let existing = repos[index].worktrees

        // Merge discovered worktrees with existing ones, preserving UUIDs for
        // worktrees that match by path. Panes reference worktreeId, so changing
        // IDs on refresh would break active detection and lookups.
        let existingByPath = Dictionary(existing.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let merged = worktrees.map { discovered -> Worktree in
            if let existing = existingByPath[discovered.path] {
                // Preserve ID and agent; update name/branch/status from discovery
                var updated = existing
                updated.name = discovered.name
                updated.branch = discovered.branch
                updated.status = discovered.status
                return updated
            }
            return discovered
        }

        repos[index].worktrees = merged
        repos[index].updatedAt = Date()
        markDirty()
    }

    // MARK: - Persistence

    func restore() {
        persistor.ensureDirectory()
        if let state = persistor.load() {
            workspaceId = state.id
            workspaceName = state.name
            repos = state.repos
            // Convert persisted pane array to dictionary
            panes = Dictionary(state.panes.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            tabs = state.tabs
            activeTabId = state.activeTabId
            sidebarWidth = state.sidebarWidth
            windowFrame = state.windowFrame
            createdAt = state.createdAt
            updatedAt = state.updatedAt
            storeLogger.info("Restored workspace '\(state.name)' with \(state.panes.count) pane(s), \(state.tabs.count) tab(s)")
        } else if persistor.hasWorkspaceFiles() {
            storeLogger.error("Workspace files exist on disk but failed to load — starting with empty state.")
        } else {
            storeLogger.info("No workspace files found — first launch")
        }

        // Remove panes whose worktree no longer exists (deleted between launches)
        let validWorktreeIds = Set(repos.flatMap(\.worktrees).map(\.id))
        panes = panes.filter { id, pane in
            if let wid = pane.worktreeId, !validWorktreeIds.contains(wid) {
                storeLogger.warning("Removing pane \(id) — worktree \(wid) no longer exists")
                return false
            }
            return true
        }

        // Prune tabs: remove dangling pane IDs from layouts
        let validPaneIds = Set(panes.keys)
        pruneInvalidPanes(from: &tabs, validPaneIds: validPaneIds, activeTabId: &activeTabId)

        // Validate and repair tab structural invariants
        validateTabInvariants()

        // Ensure at least one tab exists
        if activeTabId == nil, let firstTab = tabs.first {
            activeTabId = firstTab.id
        }
    }

    /// Schedule a debounced save. All mutations call this instead of saving inline.
    /// Coalesces writes within a 500ms window. Disables sudden termination while dirty
    /// so macOS won't kill the process before the write lands.
    func markDirty() {
        if !isDirty {
            isDirty = true
            ProcessInfo.processInfo.disableSuddenTermination()
        }
        debouncedSaveTask?.cancel()
        debouncedSaveTask = Task { @MainActor [weak self] in
            // try? is intentional — Task.sleep only throws CancellationError
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    /// Immediate persist — cancels any pending debounce. Use for app termination.
    /// Returns true if save succeeded, false if it failed.
    @discardableResult
    func flush() -> Bool {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        return persistNow()
    }

    @discardableResult
    private func persistNow() -> Bool {
        persistor.ensureDirectory()
        updatedAt = Date()

        // Filter out temporary panes — they are never persisted
        let persistablePanes = Array(panes.values.filter { pane in
            if case .terminal(let termState) = pane.content {
                return termState.lifetime != .temporary
            }
            return true
        })
        let validPaneIds = Set(persistablePanes.map(\.id))

        // Prune tabs: remove temporary pane IDs from layouts in the PERSISTED COPY.
        // Live state is not mutated — only the serialized output is cleaned.
        var prunedTabs = tabs
        var prunedActiveTabId = activeTabId
        pruneInvalidPanes(from: &prunedTabs, validPaneIds: validPaneIds, activeTabId: &prunedActiveTabId)

        let state = WorkspacePersistor.PersistableState(
            id: workspaceId,
            name: workspaceName,
            repos: repos,
            panes: persistablePanes,
            tabs: prunedTabs,
            activeTabId: prunedActiveTabId,
            sidebarWidth: sidebarWidth,
            windowFrame: windowFrame,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        do {
            try persistor.save(state)
            if isDirty {
                isDirty = false
                ProcessInfo.processInfo.enableSuddenTermination()
            }
            return true
        } catch {
            storeLogger.error("Failed to persist workspace: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - UI State

    func setSidebarWidth(_ width: CGFloat) {
        sidebarWidth = width
        markDirty()
    }

    func setWindowFrame(_ frame: CGRect?) {
        windowFrame = frame
        // Transient — saved on quit only via flush()
    }

    // MARK: - Undo

    /// Unified undo entry for both tab-level and pane-level close.
    enum CloseEntry {
        case tab(TabCloseSnapshot)
        case pane(PaneCloseSnapshot)
    }

    /// Snapshot for undoing a tab close. Captures all panes including drawer children.
    struct TabCloseSnapshot {
        let tab: Tab
        /// All panes: layout panes + their drawer children.
        let panes: [Pane]
        let tabIndex: Int
    }

    /// Snapshot for undoing a single pane close (layout pane or drawer child).
    struct PaneCloseSnapshot {
        /// The pane that was closed.
        let pane: Pane
        /// Drawer child panes (non-empty only if closed pane was a layout pane with drawer children).
        let drawerChildPanes: [Pane]
        /// Tab the pane belonged to (for layout panes) or tab containing the parent pane (for drawer children).
        let tabId: UUID
        /// For layout panes: a neighbor pane ID used as insertion anchor on restore.
        /// For drawer children: the parent layout pane ID.
        /// Nil only if the pane was the sole pane in its container.
        let anchorPaneId: UUID?
        /// Split direction for re-insertion (layout panes only).
        let direction: Layout.SplitDirection
    }

    // Legacy alias for tests that reference the old name
    typealias CloseSnapshot = TabCloseSnapshot

    func snapshotForClose(tabId: UUID) -> TabCloseSnapshot? {
        guard let tabIndex = findTabIndex(tabId) else { return nil }
        let tab = tabs[tabIndex]
        var allPanes: [Pane] = []
        for paneId in tab.panes {
            guard let layoutPane = pane(paneId) else { continue }
            allPanes.append(layoutPane)
            // Drawer children are separate store entries — capture explicitly
            if let drawer = layoutPane.drawer {
                for drawerPaneId in drawer.paneIds {
                    if let drawerPane = self.pane(drawerPaneId) {
                        allPanes.append(drawerPane)
                    }
                }
            }
        }
        return TabCloseSnapshot(tab: tab, panes: allPanes, tabIndex: tabIndex)
    }

    /// Snapshot a single pane for undo. Captures the pane, its drawer children (if layout pane),
    /// and enough context to re-insert it on restore.
    func snapshotForPaneClose(paneId: UUID, inTab tabId: UUID) -> PaneCloseSnapshot? {
        guard let closedPane = pane(paneId), let tab = tab(tabId) else { return nil }

        var drawerChildPanes: [Pane] = []
        if let drawer = closedPane.drawer {
            drawerChildPanes = drawer.paneIds.compactMap { pane($0) }
        }

        // Find anchor pane for re-insertion
        let anchorPaneId: UUID?
        let direction: Layout.SplitDirection

        if closedPane.isDrawerChild {
            // Drawer child: anchor is the parent pane
            anchorPaneId = closedPane.parentPaneId
            direction = .horizontal
        } else {
            // Layout pane: find a neighbor in the tab's layout
            let layoutPaneIds = tab.paneIds.filter { $0 != paneId }
            anchorPaneId = layoutPaneIds.first
            direction = .horizontal
        }

        return PaneCloseSnapshot(
            pane: closedPane,
            drawerChildPanes: drawerChildPanes,
            tabId: tabId,
            anchorPaneId: anchorPaneId,
            direction: direction
        )
    }

    func restoreFromSnapshot(_ snapshot: TabCloseSnapshot) {
        // Re-add panes that were removed
        for pane in snapshot.panes {
            if panes[pane.id] == nil {
                panes[pane.id] = pane
            }
        }

        // Re-insert tab at original position
        let insertIndex = min(snapshot.tabIndex, tabs.count)
        tabs.insert(snapshot.tab, at: insertIndex)
        activeTabId = snapshot.tab.id

        markDirty()
    }

    func restoreFromPaneSnapshot(_ snapshot: PaneCloseSnapshot) {
        // Re-add pane to store
        panes[snapshot.pane.id] = snapshot.pane

        // Re-add drawer children to store
        for child in snapshot.drawerChildPanes {
            panes[child.id] = child
        }

        // Re-insert into layout
        if snapshot.pane.isDrawerChild {
            // Drawer child: re-add to parent's drawer
            if let parentId = snapshot.anchorPaneId {
                panes[parentId]?.withDrawer { drawer in
                    drawer.paneIds.append(snapshot.pane.id)
                    if let existingLeaf = drawer.layout.paneIds.last {
                        drawer.layout = drawer.layout.inserting(
                            paneId: snapshot.pane.id, at: existingLeaf,
                            direction: .horizontal, position: .after
                        )
                    } else {
                        drawer.layout = Layout(paneId: snapshot.pane.id)
                    }
                    drawer.activePaneId = snapshot.pane.id
                    drawer.isExpanded = true
                }
            }
        } else {
            // Layout pane: re-insert into tab layout
            if let anchor = snapshot.anchorPaneId {
                insertPane(
                    snapshot.pane.id, inTab: snapshot.tabId,
                    at: anchor, direction: snapshot.direction, position: .after
                )
            }
        }

        // Focus restored pane
        if !snapshot.pane.isDrawerChild {
            setActivePane(snapshot.pane.id, inTab: snapshot.tabId)
        }

        markDirty()
    }

    // MARK: - Private Helpers

    private func findTabIndex(_ tabId: UUID) -> Int? {
        tabs.firstIndex { $0.id == tabId }
    }

    /// Remove pane IDs from tab layouts that are not in the valid set.
    /// Prunes layout nodes, removes empty tabs, and fixes activeTabId.
    private func pruneInvalidPanes(from tabs: inout [Tab], validPaneIds: Set<UUID>, activeTabId: inout UUID?) {
        var totalPruned = 0
        var tabsRemoved = 0

        for tabIndex in tabs.indices {
            let tabId = tabs[tabIndex].id
            // Prune panes list
            tabs[tabIndex].panes.removeAll { !validPaneIds.contains($0) }

            // Prune each arrangement
            for arrIndex in tabs[tabIndex].arrangements.indices {
                let invalidIds = tabs[tabIndex].arrangements[arrIndex].layout.paneIds.filter { !validPaneIds.contains($0) }
                for paneId in invalidIds {
                    storeLogger.warning("Pruning invalid pane \(paneId) from tab \(tabId)")
                    totalPruned += 1
                    if let newLayout = tabs[tabIndex].arrangements[arrIndex].layout.removing(paneId: paneId) {
                        tabs[tabIndex].arrangements[arrIndex].layout = newLayout
                    } else {
                        tabs[tabIndex].arrangements[arrIndex].layout = Layout()
                    }
                    tabs[tabIndex].arrangements[arrIndex].visiblePaneIds.remove(paneId)
                }
            }
            // Update activePaneId if invalid
            if let activePaneId = tabs[tabIndex].activePaneId, !validPaneIds.contains(activePaneId) {
                tabs[tabIndex].activePaneId = tabs[tabIndex].activeArrangement.layout.paneIds.first
            }
        }

        // Remove empty tabs (default arrangement has empty layout)
        let beforeCount = tabs.count
        tabs.removeAll { $0.defaultArrangement.layout.isEmpty }
        tabsRemoved = beforeCount - tabs.count

        // Fix activeTabId if it was removed
        if let atId = activeTabId, !tabs.contains(where: { $0.id == atId }) {
            let newId = tabs.last?.id
            activeTabId = newId
            storeLogger.warning("Fixed stale activeTabId \(atId) → \(String(describing: newId))")
        }

        if totalPruned > 0 {
            storeLogger.warning("Pruning summary: removed \(totalPruned) pane ref(s), \(tabsRemoved) tab(s)")
        }
    }

    /// Validate and repair tab structural invariants after restore.
    /// Fixes arrangement issues, stale active IDs, pane list drift, and
    /// cross-tab pane duplicates. Logs warnings for every repair.
    private func validateTabInvariants() {
        var repairCount = 0
        var seenPaneIds = Set<UUID>()

        for tabIndex in tabs.indices {
            let tabId = tabs[tabIndex].id

            // 1. Ensure exactly one default arrangement
            let defaultCount = tabs[tabIndex].arrangements.filter(\.isDefault).count
            if defaultCount == 0 && !tabs[tabIndex].arrangements.isEmpty {
                tabs[tabIndex].arrangements[0].isDefault = true
                storeLogger.warning("Tab \(tabId): no default arrangement — marked first as default")
                repairCount += 1
            } else if defaultCount > 1 {
                var foundFirst = false
                for arrIndex in tabs[tabIndex].arrangements.indices {
                    if tabs[tabIndex].arrangements[arrIndex].isDefault {
                        if foundFirst {
                            tabs[tabIndex].arrangements[arrIndex].isDefault = false
                            repairCount += 1
                        }
                        foundFirst = true
                    }
                }
                storeLogger.warning("Tab \(tabId): \(defaultCount) default arrangements — kept first only")
            }

            // 2. Ensure activeArrangementId points to an existing arrangement
            if !tabs[tabIndex].arrangements.contains(where: { $0.id == tabs[tabIndex].activeArrangementId }) {
                tabs[tabIndex].activeArrangementId = tabs[tabIndex].defaultArrangement.id
                storeLogger.warning("Tab \(tabId): activeArrangementId was stale — reset to default")
                repairCount += 1
            }

            // 3. Sync visiblePaneIds with layout pane IDs for each arrangement
            for arrIndex in tabs[tabIndex].arrangements.indices {
                let arrLayoutPaneIds = Set(tabs[tabIndex].arrangements[arrIndex].layout.paneIds)
                let visible = tabs[tabIndex].arrangements[arrIndex].visiblePaneIds
                if visible != arrLayoutPaneIds {
                    tabs[tabIndex].arrangements[arrIndex].visiblePaneIds = arrLayoutPaneIds
                    storeLogger.warning("Tab \(tabId): arrangement \(self.tabs[tabIndex].arrangements[arrIndex].id) visiblePaneIds drifted — synced")
                    repairCount += 1
                }
            }

            // 4. Sync tab.panes with the union of all arrangement layout pane IDs
            let layoutPaneIds = Set(tabs[tabIndex].arrangements.flatMap { $0.layout.paneIds })
            let listedPaneIds = Set(tabs[tabIndex].panes)
            if layoutPaneIds != listedPaneIds {
                tabs[tabIndex].panes = Array(layoutPaneIds)
                storeLogger.warning("Tab \(tabId): panes list drifted from layouts — synced (\(listedPaneIds.count) → \(layoutPaneIds.count))")
                repairCount += 1
            }

            // 5. Ensure activePaneId is in the active arrangement
            if let apId = tabs[tabIndex].activePaneId,
               !tabs[tabIndex].activeArrangement.layout.paneIds.contains(apId) {
                tabs[tabIndex].activePaneId = tabs[tabIndex].activeArrangement.layout.paneIds.first
                storeLogger.warning("Tab \(tabId): activePaneId \(apId) not in layout — reset")
                repairCount += 1
            }

            // 6. Detect and repair cross-tab pane duplicates (a pane should be in at most one tab)
            for paneId in layoutPaneIds {
                if seenPaneIds.contains(paneId) {
                    storeLogger.warning("Pane \(paneId) appears in multiple tabs — removing from tab \(tabId)")
                    tabs[tabIndex].panes.removeAll { $0 == paneId }
                    for arrIndex in tabs[tabIndex].arrangements.indices {
                        tabs[tabIndex].arrangements[arrIndex].visiblePaneIds.remove(paneId)
                        if let newLayout = tabs[tabIndex].arrangements[arrIndex].layout.removing(paneId: paneId) {
                            tabs[tabIndex].arrangements[arrIndex].layout = newLayout
                        } else {
                            tabs[tabIndex].arrangements[arrIndex].layout = Layout()
                        }
                    }
                    repairCount += 1
                }
                seenPaneIds.insert(paneId)
            }

            // 7. Re-validate activePaneId after duplicate repair may have removed panes
            if let apId = tabs[tabIndex].activePaneId,
               !tabs[tabIndex].activeArrangement.layout.paneIds.contains(apId) {
                tabs[tabIndex].activePaneId = tabs[tabIndex].activeArrangement.layout.paneIds.first
                storeLogger.warning("Tab \(tabId): activePaneId \(apId) stale after duplicate repair — reset")
                repairCount += 1
            }
        }

        if repairCount > 0 {
            storeLogger.warning("Tab invariant validation: \(repairCount) repair(s) applied")
        }
    }
}
