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
    @Published private(set) var sessions: [TerminalSession] = []
    @Published private(set) var views: [ViewDefinition] = []
    @Published private(set) var activeViewId: UUID?

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

    var activeView: ViewDefinition? {
        views.first { $0.id == activeViewId }
    }

    var activeTabs: [Tab] {
        activeView?.tabs ?? []
    }

    var activeTabId: UUID? {
        activeView?.activeTabId
    }

    /// All sessions visible in the active view.
    var activeSessionIds: Set<UUID> {
        Set(activeView?.allSessionIds ?? [])
    }

    /// Is a worktree active (has any session)?
    func isWorktreeActive(_ worktreeId: UUID) -> Bool {
        sessions.contains { $0.worktreeId == worktreeId }
    }

    /// Count of sessions for a worktree.
    func sessionCount(for worktreeId: UUID) -> Int {
        sessions.filter { $0.worktreeId == worktreeId }.count
    }

    // MARK: - Queries

    func session(_ id: UUID) -> TerminalSession? {
        sessions.first { $0.id == id }
    }

    func tab(_ id: UUID) -> Tab? {
        activeView?.tabs.first { $0.id == id }
    }

    func tabContaining(sessionId: UUID) -> Tab? {
        activeView?.tabs.first { $0.sessionIds.contains(sessionId) }
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

    func sessions(for worktreeId: UUID) -> [TerminalSession] {
        sessions.filter { $0.worktreeId == worktreeId }
    }

    // MARK: - Session Mutations

    @discardableResult
    func createSession(
        source: TerminalSource,
        title: String = "Terminal",
        provider: SessionProvider = .ghostty,
        lifetime: SessionLifetime = .persistent,
        residency: SessionResidency = .active
    ) -> TerminalSession {
        let session = TerminalSession(
            source: source,
            title: title,
            provider: provider,
            lifetime: lifetime,
            residency: residency
        )
        sessions.append(session)
        markDirty()
        return session
    }

    func removeSession(_ sessionId: UUID) {
        sessions.removeAll { $0.id == sessionId }

        // Remove from all view layouts
        for viewIndex in views.indices {
            for tabIndex in views[viewIndex].tabs.indices {
                if let newLayout = views[viewIndex].tabs[tabIndex].layout.removing(sessionId: sessionId) {
                    views[viewIndex].tabs[tabIndex].layout = newLayout
                    // Update activeSessionId if it was the removed session
                    if views[viewIndex].tabs[tabIndex].activeSessionId == sessionId {
                        views[viewIndex].tabs[tabIndex].activeSessionId = newLayout.sessionIds.first
                    }
                } else {
                    // Layout became empty — mark tab for removal
                    views[viewIndex].tabs[tabIndex].layout = Layout()
                }
            }
            // Remove empty tabs
            views[viewIndex].tabs.removeAll { $0.layout.isEmpty }
            // Fix activeTabId if it was removed
            if let activeTabId = views[viewIndex].activeTabId,
               !views[viewIndex].tabs.contains(where: { $0.id == activeTabId }) {
                views[viewIndex].activeTabId = views[viewIndex].tabs.last?.id
            }
        }
        markDirty()
    }

    func updateSessionTitle(_ sessionId: UUID, title: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else {
            storeLogger.warning("updateSessionTitle: session \(sessionId) not found")
            return
        }
        sessions[index].title = title
        markDirty()
    }

    func updateSessionCWD(_ sessionId: UUID, cwd: URL?) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else {
            storeLogger.warning("updateSessionCWD: session \(sessionId) not found")
            return
        }
        guard sessions[index].lastKnownCWD != cwd else { return }
        sessions[index].lastKnownCWD = cwd
        markDirty()
    }

    func updateSessionAgent(_ sessionId: UUID, agent: AgentType?) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else {
            storeLogger.warning("updateSessionAgent: session \(sessionId) not found")
            return
        }
        sessions[index].agent = agent
        markDirty()
    }

    func setResidency(_ residency: SessionResidency, for sessionId: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else {
            storeLogger.warning("setResidency: session \(sessionId) not found")
            return
        }
        sessions[index].residency = residency
        markDirty()
    }

    // MARK: - View Mutations

    func switchView(_ viewId: UUID) {
        guard views.contains(where: { $0.id == viewId }) else {
            storeLogger.warning("switchView: view \(viewId) not found")
            return
        }
        activeViewId = viewId
        markDirty()
    }

    @discardableResult
    func createView(name: String, kind: ViewKind) -> ViewDefinition {
        let view = ViewDefinition(name: name, kind: kind)
        views.append(view)
        markDirty()
        return view
    }

    func deleteView(_ viewId: UUID) {
        // Cannot delete main view
        guard views.first(where: { $0.id == viewId })?.kind != .main else { return }
        views.removeAll { $0.id == viewId }
        if activeViewId == viewId {
            activeViewId = views.first(where: { $0.kind == .main })?.id
        }
        markDirty()
    }

    @discardableResult
    func saveCurrentViewAs(name: String) -> ViewDefinition? {
        guard let current = activeView else { return nil }
        let snapshot = ViewDefinition(
            name: name,
            kind: .saved,
            tabs: current.tabs,
            activeTabId: current.activeTabId
        )
        views.append(snapshot)
        markDirty()
        return snapshot
    }

    // MARK: - Tab Mutations (within active view)

    func appendTab(_ tab: Tab) {
        guard let viewIndex = activeViewIndex else {
            storeLogger.warning("appendTab: no active view")
            return
        }
        views[viewIndex].tabs.append(tab)
        views[viewIndex].activeTabId = tab.id
        markDirty()
    }

    func removeTab(_ tabId: UUID) {
        guard let viewIndex = activeViewIndex else {
            storeLogger.warning("removeTab: no active view")
            return
        }
        views[viewIndex].tabs.removeAll { $0.id == tabId }
        if views[viewIndex].activeTabId == tabId {
            views[viewIndex].activeTabId = views[viewIndex].tabs.last?.id
        }
        markDirty()
    }

    func insertTab(_ tab: Tab, at index: Int) {
        guard let viewIndex = activeViewIndex else {
            storeLogger.warning("insertTab: no active view")
            return
        }
        let clampedIndex = min(index, views[viewIndex].tabs.count)
        views[viewIndex].tabs.insert(tab, at: clampedIndex)
        markDirty()
    }

    func moveTab(fromId: UUID, toIndex: Int) {
        guard let viewIndex = activeViewIndex else {
            storeLogger.warning("moveTab: no active view")
            return
        }
        guard let fromIndex = views[viewIndex].tabs.firstIndex(where: { $0.id == fromId }) else {
            storeLogger.warning("moveTab: tab \(fromId) not found")
            return
        }
        let tab = views[viewIndex].tabs.remove(at: fromIndex)
        // After removal, indices shift left. Adjust toIndex to compensate.
        let adjustedIndex = toIndex > fromIndex ? toIndex - 1 : toIndex
        let clampedIndex = max(0, min(adjustedIndex, views[viewIndex].tabs.count))
        views[viewIndex].tabs.insert(tab, at: clampedIndex)
        markDirty()
    }

    /// Move a tab by a relative delta. Clamps at boundaries (no cyclic wrap),
    /// matching Ghostty's TerminalController.onMoveTab behavior.
    func moveTabByDelta(tabId: UUID, delta: Int) {
        guard let viewIndex = activeViewIndex else {
            storeLogger.warning("moveTabByDelta: no active view")
            return
        }
        guard let fromIndex = views[viewIndex].tabs.firstIndex(where: { $0.id == tabId }) else {
            storeLogger.warning("moveTabByDelta: tab \(tabId) not found")
            return
        }
        let count = views[viewIndex].tabs.count
        guard count > 1 else { return }

        // Clamp at boundaries — matches Ghostty's behavior.
        // Guard against Int.min overflow: -Int.min is undefined, treat as max leftward move.
        let finalIndex: Int
        if delta < 0 {
            let magnitude = delta == Int.min ? Int.max : -delta
            finalIndex = fromIndex - min(fromIndex, magnitude)
        } else {
            let remaining = count - 1 - fromIndex
            finalIndex = fromIndex + min(remaining, delta)
        }
        guard finalIndex != fromIndex else { return }

        let tab = views[viewIndex].tabs.remove(at: fromIndex)
        views[viewIndex].tabs.insert(tab, at: finalIndex)
        markDirty()
    }

    func setActiveTab(_ tabId: UUID?) {
        guard let viewIndex = activeViewIndex else {
            storeLogger.warning("setActiveTab: no active view")
            return
        }
        views[viewIndex].activeTabId = tabId
        markDirty()
    }

    // MARK: - Layout Mutations (within a tab in the active view)

    func insertSession(
        _ sessionId: UUID,
        inTab tabId: UUID,
        at targetSessionId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position
    ) {
        guard let (viewIndex, tabIndex) = findTab(tabId) else { return }
        // Clear zoom on new split — user needs to see all panes
        views[viewIndex].tabs[tabIndex].zoomedSessionId = nil
        views[viewIndex].tabs[tabIndex].layout = views[viewIndex].tabs[tabIndex].layout
            .inserting(sessionId: sessionId, at: targetSessionId, direction: direction, position: position)
        markDirty()
    }

    func removeSessionFromLayout(_ sessionId: UUID, inTab tabId: UUID) {
        guard let (viewIndex, tabIndex) = findTab(tabId) else { return }
        // Clear zoom if the zoomed session is being removed
        if views[viewIndex].tabs[tabIndex].zoomedSessionId == sessionId {
            views[viewIndex].tabs[tabIndex].zoomedSessionId = nil
        }
        if let newLayout = views[viewIndex].tabs[tabIndex].layout.removing(sessionId: sessionId) {
            views[viewIndex].tabs[tabIndex].layout = newLayout
            // Update active session if removed
            if views[viewIndex].tabs[tabIndex].activeSessionId == sessionId {
                views[viewIndex].tabs[tabIndex].activeSessionId = newLayout.sessionIds.first
            }
        } else {
            // Last session removed — close tab
            removeTab(tabId)
        }
        markDirty()
    }

    func resizePane(tabId: UUID, splitId: UUID, ratio: Double) {
        guard let (viewIndex, tabIndex) = findTab(tabId) else { return }
        views[viewIndex].tabs[tabIndex].layout = views[viewIndex].tabs[tabIndex].layout
            .resizing(splitId: splitId, ratio: ratio)
        markDirty()
    }

    func equalizePanes(tabId: UUID) {
        guard let (viewIndex, tabIndex) = findTab(tabId) else { return }
        views[viewIndex].tabs[tabIndex].layout = views[viewIndex].tabs[tabIndex].layout.equalized()
        markDirty()
    }

    func setActiveSession(_ sessionId: UUID?, inTab tabId: UUID) {
        guard let (viewIndex, tabIndex) = findTab(tabId) else { return }
        views[viewIndex].tabs[tabIndex].activeSessionId = sessionId
        markDirty()
    }

    // MARK: - Zoom

    func toggleZoom(sessionId: UUID, inTab tabId: UUID) {
        guard let (viewIndex, tabIndex) = findTab(tabId) else { return }
        if views[viewIndex].tabs[tabIndex].zoomedSessionId == sessionId {
            views[viewIndex].tabs[tabIndex].zoomedSessionId = nil
        } else if views[viewIndex].tabs[tabIndex].layout.contains(sessionId) {
            views[viewIndex].tabs[tabIndex].zoomedSessionId = sessionId
        }
        // Do NOT markDirty() — zoom is transient, not persisted
    }

    // MARK: - Keyboard Resize

    func resizePaneByDelta(tabId: UUID, paneId: UUID, direction: SplitResizeDirection, amount: UInt16) {
        guard let (viewIndex, tabIndex) = findTab(tabId) else { return }
        let tab = views[viewIndex].tabs[tabIndex]

        // No-op while zoomed — no visual feedback for resize
        guard tab.zoomedSessionId == nil else {
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

        views[viewIndex].tabs[tabIndex].layout = views[viewIndex].tabs[tabIndex].layout
            .resizing(splitId: splitId, ratio: newRatio)
        markDirty()
    }

    // MARK: - Compound Operations

    /// Break a split tab into individual tabs, one per session.
    func breakUpTab(_ tabId: UUID) -> [Tab] {
        guard let (viewIndex, tabIndex) = findTab(tabId) else { return [] }
        let sessionIds = views[viewIndex].tabs[tabIndex].sessionIds
        guard sessionIds.count > 1 else { return [] }

        // Clear zoom — tab is being decomposed
        views[viewIndex].tabs[tabIndex].zoomedSessionId = nil

        // Remove original tab
        views[viewIndex].tabs.remove(at: tabIndex)

        // Create individual tabs
        var newTabs: [Tab] = []
        for sessionId in sessionIds {
            let tab = Tab(sessionId: sessionId)
            newTabs.append(tab)
        }

        // Insert at original position
        let insertIndex = min(tabIndex, views[viewIndex].tabs.count)
        views[viewIndex].tabs.insert(contentsOf: newTabs, at: insertIndex)
        views[viewIndex].activeTabId = newTabs.first?.id

        markDirty()
        return newTabs
    }

    /// Extract a session from a tab into its own new tab.
    func extractSession(_ sessionId: UUID, fromTab tabId: UUID) -> Tab? {
        guard let (viewIndex, tabIndex) = findTab(tabId) else { return nil }
        guard views[viewIndex].tabs[tabIndex].sessionIds.count > 1 else { return nil }

        // Clear zoom if extracting the zoomed session
        if views[viewIndex].tabs[tabIndex].zoomedSessionId == sessionId {
            views[viewIndex].tabs[tabIndex].zoomedSessionId = nil
        }

        // Remove session from source tab
        if let newLayout = views[viewIndex].tabs[tabIndex].layout.removing(sessionId: sessionId) {
            views[viewIndex].tabs[tabIndex].layout = newLayout
            if views[viewIndex].tabs[tabIndex].activeSessionId == sessionId {
                views[viewIndex].tabs[tabIndex].activeSessionId = newLayout.sessionIds.first
            }
        }

        // Create new tab
        let newTab = Tab(sessionId: sessionId)
        let insertIndex = tabIndex + 1
        views[viewIndex].tabs.insert(newTab, at: min(insertIndex, views[viewIndex].tabs.count))
        views[viewIndex].activeTabId = newTab.id

        markDirty()
        return newTab
    }

    /// Merge all sessions from source tab into target tab's layout.
    func mergeTab(
        sourceId: UUID,
        intoTarget targetId: UUID,
        at targetSessionId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position
    ) {
        guard let viewIndex = activeViewIndex else { return }
        guard let sourceTabIndex = views[viewIndex].tabs.firstIndex(where: { $0.id == sourceId }),
              let targetTabIndex = views[viewIndex].tabs.firstIndex(where: { $0.id == targetId }) else { return }

        // Clear zoom on target tab — merging changes the layout structure
        views[viewIndex].tabs[targetTabIndex].zoomedSessionId = nil

        let sourceSessionIds = views[viewIndex].tabs[sourceTabIndex].sessionIds

        // Insert each source session into target layout
        var currentTarget = targetSessionId
        for sessionId in sourceSessionIds {
            views[viewIndex].tabs[targetTabIndex].layout = views[viewIndex].tabs[targetTabIndex].layout
                .inserting(sessionId: sessionId, at: currentTarget, direction: direction, position: position)
            currentTarget = sessionId
        }

        // Remove source tab
        views[viewIndex].tabs.remove(at: sourceTabIndex)

        // Fix activeTabId
        views[viewIndex].activeTabId = targetId

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
        // worktrees that match by path. Sessions reference worktreeId, so changing
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
            sessions = state.sessions
            views = state.views
            activeViewId = state.activeViewId
            sidebarWidth = state.sidebarWidth
            windowFrame = state.windowFrame
            createdAt = state.createdAt
            updatedAt = state.updatedAt
            storeLogger.info("Restored workspace '\(state.name)' with \(state.sessions.count) session(s), \(state.views.count) view(s)")
        } else if persistor.hasWorkspaceFiles() {
            storeLogger.error("Workspace files exist on disk but failed to load — starting with empty state.")
        } else {
            storeLogger.info("No workspace files found — first launch")
        }

        // Filter out temporary sessions — they are never restored
        sessions.removeAll { $0.lifetime == .temporary }

        // Remove sessions whose worktree no longer exists (deleted between launches)
        let validWorktreeIds = Set(repos.flatMap(\.worktrees).map(\.id))
        sessions.removeAll { session in
            if let wid = session.worktreeId, !validWorktreeIds.contains(wid) {
                storeLogger.warning("Removing session \(session.id) — worktree \(wid) no longer exists")
                return true
            }
            return false
        }

        // Prune views: remove dangling session IDs from layouts
        let validSessionIds = Set(sessions.map(\.id))
        pruneInvalidSessions(from: &views, validSessionIds: validSessionIds)

        // Ensure main view exists
        ensureMainView()
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

        // Filter out temporary sessions — they are never persisted
        let persistableSessions = sessions.filter { $0.lifetime != .temporary }
        let validSessionIds = Set(persistableSessions.map(\.id))

        // Prune views: remove temporary session IDs from layouts in the PERSISTED COPY.
        // Live `views` state is not mutated — only the serialized output is cleaned.
        var prunedViews = views
        pruneInvalidSessions(from: &prunedViews, validSessionIds: validSessionIds)

        let state = WorkspacePersistor.PersistableState(
            id: workspaceId,
            name: workspaceName,
            repos: repos,
            sessions: persistableSessions,
            views: prunedViews,
            activeViewId: activeViewId,
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

    /// Snapshot for undo close. Captures tab + sessions + view context.
    struct CloseSnapshot: Codable {
        let tab: Tab
        let sessions: [TerminalSession]
        let viewId: UUID
        let tabIndex: Int
    }

    func snapshotForClose(tabId: UUID) -> CloseSnapshot? {
        guard let viewIndex = activeViewIndex,
              let tabIndex = views[viewIndex].tabs.firstIndex(where: { $0.id == tabId }) else {
            return nil
        }
        let tab = views[viewIndex].tabs[tabIndex]
        let tabSessions = tab.sessionIds.compactMap { session($0) }
        return CloseSnapshot(
            tab: tab,
            sessions: tabSessions,
            viewId: views[viewIndex].id,
            tabIndex: tabIndex
        )
    }

    func restoreFromSnapshot(_ snapshot: CloseSnapshot) {
        // Re-add sessions that were removed
        for session in snapshot.sessions {
            if !sessions.contains(where: { $0.id == session.id }) {
                sessions.append(session)
            }
        }

        // Re-insert tab at original position in the correct view
        if let viewIndex = views.firstIndex(where: { $0.id == snapshot.viewId }) {
            let insertIndex = min(snapshot.tabIndex, views[viewIndex].tabs.count)
            views[viewIndex].tabs.insert(snapshot.tab, at: insertIndex)
            views[viewIndex].activeTabId = snapshot.tab.id
        } else if let viewIndex = activeViewIndex {
            // Fallback to active view
            views[viewIndex].tabs.append(snapshot.tab)
            views[viewIndex].activeTabId = snapshot.tab.id
        }

        markDirty()
    }

    // MARK: - Private Helpers

    private var activeViewIndex: Int? {
        views.firstIndex { $0.id == activeViewId }
    }

    private func findTab(_ tabId: UUID) -> (viewIndex: Int, tabIndex: Int)? {
        guard let viewIndex = activeViewIndex else { return nil }
        guard let tabIndex = views[viewIndex].tabs.firstIndex(where: { $0.id == tabId }) else { return nil }
        return (viewIndex, tabIndex)
    }

    /// Remove session IDs from view layouts that are not in the valid set.
    /// Follows the same pattern as `removeSession()` — prunes layout nodes,
    /// removes empty tabs, and fixes activeTabId pointers.
    private func pruneInvalidSessions(from views: inout [ViewDefinition], validSessionIds: Set<UUID>) {
        var totalPruned = 0
        var tabsRemoved = 0

        for viewIndex in views.indices {
            let viewName = views[viewIndex].name
            for tabIndex in views[viewIndex].tabs.indices {
                let tabId = views[viewIndex].tabs[tabIndex].id
                let invalidIds = views[viewIndex].tabs[tabIndex].sessionIds.filter { !validSessionIds.contains($0) }
                for sessionId in invalidIds {
                    storeLogger.warning("Pruning invalid session \(sessionId) from view '\(viewName)' tab \(tabId)")
                    totalPruned += 1
                    if let newLayout = views[viewIndex].tabs[tabIndex].layout.removing(sessionId: sessionId) {
                        views[viewIndex].tabs[tabIndex].layout = newLayout
                        if views[viewIndex].tabs[tabIndex].activeSessionId == sessionId {
                            views[viewIndex].tabs[tabIndex].activeSessionId = newLayout.sessionIds.first
                        }
                    } else {
                        // Layout became empty — mark tab for removal
                        views[viewIndex].tabs[tabIndex].layout = Layout()
                    }
                }
            }
            // Remove empty tabs
            let beforeCount = views[viewIndex].tabs.count
            views[viewIndex].tabs.removeAll { $0.layout.isEmpty }
            let removed = beforeCount - views[viewIndex].tabs.count
            if removed > 0 {
                storeLogger.warning("Removed \(removed) empty tab(s) from view '\(viewName)' after pruning")
                tabsRemoved += removed
            }
            // Fix activeTabId if it was removed
            if let activeTabId = views[viewIndex].activeTabId,
               !views[viewIndex].tabs.contains(where: { $0.id == activeTabId }) {
                let newActiveId = views[viewIndex].tabs.last?.id
                storeLogger.warning("Fixed stale activeTabId \(activeTabId) → \(String(describing: newActiveId)) in view '\(viewName)'")
                views[viewIndex].activeTabId = newActiveId
            }
        }

        if totalPruned > 0 {
            storeLogger.warning("Pruning summary: removed \(totalPruned) session ref(s), \(tabsRemoved) tab(s)")
        }
    }

    /// Ensure the main view always exists.
    private func ensureMainView() {
        if !views.contains(where: { $0.kind == .main }) {
            let mainView = ViewDefinition(name: "Main", kind: .main)
            views.insert(mainView, at: 0)
            activeViewId = mainView.id
        }
        if activeViewId == nil {
            activeViewId = views.first(where: { $0.kind == .main })?.id
        }
    }
}
