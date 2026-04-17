import Foundation
import Observation

/// Lightweight display item for the tab bar.
/// Contains only what the UI needs to render — no live views or split trees.
struct TabBarItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var isSplit: Bool
    var displayTitle: String
    var activeArrangementName: String?  // nil when only default exists
    var activeArrangementBadgeNumber: Int?
    var arrangementCount: Int  // total arrangements (1 = default only)
    var panes: [PaneVisibilityInfo]
    var arrangements: [ArrangementInfo]
    var minimizedCount: Int
}

/// Derives tab bar display state from the workspace atoms.
/// Replaces TabBarState as the observable source for CustomTabBar.
/// Owns only transient UI state (dragging, drop targets).
@MainActor
@Observable
final class TabBarAdapter {

    // MARK: - Derived From Workspace Atoms

    private(set) var tabs: [TabBarItem] = []
    private(set) var activeTabId: UUID?

    // MARK: - Overflow Detection

    var availableWidth: CGFloat = 0 {
        didSet {
            guard oldValue != availableWidth else { return }
            updateOverflow()
        }
    }
    private(set) var isOverflowing: Bool = false
    var contentWidth: CGFloat = 0 {
        didSet {
            guard oldValue != contentWidth else { return }
            updateOverflow()
        }
    }
    var viewportWidth: CGFloat = 0 {
        didSet {
            guard oldValue != viewportWidth else { return }
            updateOverflow()
        }
    }

    static let minTabWidth: CGFloat = 220
    static let tabSpacing: CGFloat = 4
    static let tabBarPadding: CGFloat = 16
    static let hysteresisBuffer: CGFloat = 50

    // MARK: - Management Layer

    private(set) var isManagementLayerActive: Bool = false

    // MARK: - Transient UI State

    var draggingTabId: UUID?
    var dropTargetIndex: Int?
    var tabFrames: [UUID: CGRect] = [:]

    // MARK: - Internals

    private let store: WorkspaceStore
    private let repoCache: RepoCacheAtom
    private var isObservingManagementLayer = false
    private var isObservingStore = false

    init(store: WorkspaceStore, repoCache: RepoCacheAtom) {
        self.store = store
        self.repoCache = repoCache
        observe()
    }

    // MARK: - Observation

    private func observe() {
        // Re-derive tabs whenever the store's observed state changes.
        // withObservationTracking fires once per registration, so we re-register
        // after each change. Task { @MainActor } satisfies @Sendable and ensures
        // we read new values (onChange has willSet semantics — old values only).
        isManagementLayerActive = atom(\.managementLayer).isActive
        observeStore()
        observeManagementLayer()

        // Initial sync
        refresh()
    }

    /// Bridge @Observable store → adapter via withObservationTracking.
    /// Fires once per registration; re-registers after each change.
    private func observeStore() {
        guard !isObservingStore else { return }
        isObservingStore = true
        withObservationTracking {
            _ = self.store.tabLayoutAtom.tabs
            _ = self.store.tabLayoutAtom.activeTabId
            _ = self.store.paneAtom.panes
            _ = self.repoCache.worktreeEnrichmentByWorktreeId
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.isObservingStore = false
                self.refresh()
                self.observeStore()
            }
        }
    }

    private func observeManagementLayer() {
        guard !isObservingManagementLayer else { return }
        isObservingManagementLayer = true
        withObservationTracking {
            // Track only reads; writes stay in onChange.
            _ = atom(\.managementLayer).isActive
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObservingManagementLayer = false
                self.isManagementLayerActive = atom(\.managementLayer).isActive
                self.observeManagementLayer()
            }
        }
    }

    private func refresh() {
        let tabLayout = store.tabLayoutAtom
        let storeTabs = tabLayout.tabs

        tabs = storeTabs.map { tab in
            let displayTitle = atom(\.tabDisplay).displayTitle(
                for: tab,
                workspacePane: store.paneAtom,
                workspaceRepositoryTopology: store.repositoryTopologyAtom,
                repoCache: repoCache
            )
            let dragTitle = displayTitle

            let activeArrangement = tab.activeArrangement
            let showArrangementName = tab.arrangements.count > 1 && !activeArrangement.isDefault
            let activeArrangementBadgeNumber = Self.activeArrangementBadgeNumber(for: tab)

            let arrangementDerived = atom(\.arrangement)
            let paneInfos = arrangementDerived.paneVisibilityItems(for: tab.id)
            let arrangementInfos = arrangementDerived.arrangementItems(for: tab.id)

            return TabBarItem(
                id: tab.id,
                title: dragTitle,
                isSplit: tab.isSplit,
                displayTitle: displayTitle,
                activeArrangementName: showArrangementName ? activeArrangement.name : nil,
                activeArrangementBadgeNumber: activeArrangementBadgeNumber,
                arrangementCount: tab.arrangements.count,
                panes: paneInfos,
                arrangements: arrangementInfos,
                minimizedCount: tab.activeMinimizedPaneIds.count
            )
        }

        if let storeActiveTabId = tabLayout.activeTabId {
            activeTabId = storeActiveTabId
        } else {
            // Defensive UI fallback for transient restore/repair windows where tabs
            // exist but activeTabId has not been recomputed yet.
            activeTabId = tabs.last?.id
        }
        updateOverflow()
    }

    private func paneDisplayTitle(for paneId: UUID) -> String {
        guard let pane = store.paneAtom.pane(paneId) else {
            return "Terminal"
        }

        let rawTitle = pane.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultLabel = rawTitle.isEmpty ? "Terminal" : rawTitle

        if let worktreeId = pane.worktreeId,
            let repoId = pane.repoId,
            let repo = store.repositoryTopologyAtom.repo(repoId),
            let worktree = store.repositoryTopologyAtom.worktree(worktreeId)
        {
            let repoName = pane.metadata.repoName ?? repo.name
            let branchName = atom(\.paneDisplay).resolvedBranchName(
                worktree: worktree,
                enrichment: repoCache.worktreeEnrichmentByWorktreeId[worktree.id]
            )
            return "\(repoName) | \(branchName) | \(worktree.path.lastPathComponent)"
        }

        if let cwdFolderName = pane.metadata.cwd?.lastPathComponent,
            !cwdFolderName.isEmpty
        {
            return cwdFolderName
        }

        return defaultLabel
    }

    private func updateOverflow() {
        guard !tabs.isEmpty else {
            isOverflowing = false
            return
        }

        // Prefer viewport width (from onScrollGeometryChange or ScrollView measurement),
        // fall back to availableWidth (outer container).
        let effectiveViewport = viewportWidth > 0 ? viewportWidth : availableWidth
        guard effectiveViewport > 0 else { return }

        // Content-width-based overflow: use actual measured content width when available.
        if contentWidth > 0 {
            if isOverflowing {
                // Hysteresis: only turn off overflow when content width drops
                // well below the viewport to prevent oscillation.
                isOverflowing = contentWidth > (effectiveViewport - Self.hysteresisBuffer)
            } else {
                isOverflowing = contentWidth > effectiveViewport
            }
            return
        }

        // Fallback: estimate overflow from tab count when content width isn't measured yet.
        let tabCount = CGFloat(tabs.count)
        let totalMinWidth =
            tabCount * Self.minTabWidth
            + (tabCount - 1) * Self.tabSpacing
            + Self.tabBarPadding
        isOverflowing = totalMinWidth > effectiveViewport
    }

    private static func activeArrangementBadgeNumber(for tab: Tab) -> Int? {
        let customArrangements = tab.arrangements.filter { !$0.isDefault }
        guard let index = customArrangements.firstIndex(where: { $0.id == tab.activeArrangementId }) else {
            return nil
        }
        return index + 1
    }
}
