import Foundation
import Combine
import os.log

private let storeLogger = Logger(subsystem: "com.agentstudio", category: "WorkspaceStore")

/// Owns ALL persisted workspace state. Single source of truth.
/// All mutations go through here. Collaborators (WorkspacePersistor, ViewRegistry)
/// are internal — not peers.
@MainActor
final class WorkspaceStore: ObservableObject {

    // MARK: - Persisted State

    @Published private(set) var repos: [Repo] = []
    @Published private(set) var panes: [UUID: Pane] = [:]
    @Published private(set) var tabs: [Tab] = []
    @Published private(set) var activeTabId: UUID?

    // MARK: - Transient UI State

    @Published var draggingTabId: UUID?
    @Published var dropTargetIndex: Int?
    @Published var tabFrames: [UUID: CGRect] = [:]

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

    // MARK: - Queries

    func pane(_ id: UUID) -> Pane? {
        panes[id]
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
        provider: SessionProvider = .ghostty,
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

    func removePane(_ paneId: UUID) {
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
            }
            tabs[tabIndex].arrangements[defIdx].visiblePaneIds.insert(paneId)
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

        if let newLayout = tabs[tabIndex].arrangements[arrIndex].layout.removing(paneId: paneId) {
            tabs[tabIndex].arrangements[arrIndex].layout = newLayout
            tabs[tabIndex].arrangements[arrIndex].visiblePaneIds.remove(paneId)
            // Update active pane if removed
            if tabs[tabIndex].activePaneId == paneId {
                tabs[tabIndex].activePaneId = newLayout.paneIds.first
            }
        } else {
            // Last pane removed — signal to caller that tab is now empty.
            // Do NOT call removeTab here: let ActionExecutor handle it with undo support.
            return true
        }

        // Also remove from default arrangement if active is not default
        if !tabs[tabIndex].arrangements[arrIndex].isDefault {
            let defIdx = tabs[tabIndex].defaultArrangementIndex
            if let newDefLayout = tabs[tabIndex].arrangements[defIdx].layout.removing(paneId: paneId) {
                tabs[tabIndex].arrangements[defIdx].layout = newDefLayout
                tabs[tabIndex].arrangements[defIdx].visiblePaneIds.remove(paneId)
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

        // Clear zoom on target tab — merging changes the layout structure
        tabs[targetTabIndex].zoomedPaneId = nil

        let sourcePaneIds = tabs[sourceTabIndex].paneIds

        // Insert each source pane into target layout
        let targetArrIndex = tabs[targetTabIndex].activeArrangementIndex
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

        // Migrate legacy ghostty sessions to tmux for session persistence
        for id in panes.keys {
            if case .terminal(var termState) = panes[id]!.content, termState.provider == .ghostty {
                termState.provider = .tmux
                panes[id]!.content = .terminal(termState)
            }
        }

        // Filter out temporary panes — they are never restored
        panes = panes.filter { _, pane in
            if case .terminal(let termState) = pane.content {
                return termState.lifetime != .temporary
            }
            return true
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
        pruneInvalidPanes(from: &tabs, validPaneIds: validPaneIds)

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
        // Live `tabs` state is not mutated — only the serialized output is cleaned.
        var prunedTabs = tabs
        pruneInvalidPanes(from: &prunedTabs, validPaneIds: validPaneIds)

        let state = WorkspacePersistor.PersistableState(
            id: workspaceId,
            name: workspaceName,
            repos: repos,
            panes: persistablePanes,
            tabs: prunedTabs,
            activeTabId: activeTabId,
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

    /// Snapshot for undo close. Captures tab + panes.
    struct CloseSnapshot: Codable {
        let tab: Tab
        let panes: [Pane]
        let tabIndex: Int
    }

    func snapshotForClose(tabId: UUID) -> CloseSnapshot? {
        guard let tabIndex = findTabIndex(tabId) else { return nil }
        let tab = tabs[tabIndex]
        let tabPanes = tab.panes.compactMap { pane($0) }
        return CloseSnapshot(
            tab: tab,
            panes: tabPanes,
            tabIndex: tabIndex
        )
    }

    func restoreFromSnapshot(_ snapshot: CloseSnapshot) {
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

    // MARK: - Private Helpers

    private func findTabIndex(_ tabId: UUID) -> Int? {
        tabs.firstIndex { $0.id == tabId }
    }

    /// Remove pane IDs from tab layouts that are not in the valid set.
    /// Prunes layout nodes, removes empty tabs, and fixes activeTabId.
    private func pruneInvalidPanes(from tabs: inout [Tab], validPaneIds: Set<UUID>) {
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
        if let atId = self.activeTabId, !tabs.contains(where: { $0.id == atId }) {
            self.activeTabId = tabs.last?.id
            storeLogger.warning("Fixed stale activeTabId \(atId) → \(String(describing: self.activeTabId))")
        }

        if totalPruned > 0 {
            storeLogger.warning("Pruning summary: removed \(totalPruned) pane ref(s), \(tabsRemoved) tab(s)")
        }
    }
}
