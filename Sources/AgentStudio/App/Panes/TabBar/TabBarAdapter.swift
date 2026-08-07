import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Observation

/// Lightweight display item for the tab bar.
/// Contains only what the UI needs to render — no live views or split trees.
struct TabBarItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var isSplit: Bool
    var displayTitle: String
    var activeArrangementName: String?
    var activeArrangementBadgeNumber: Int?
    var arrangementCount: Int  // total arrangements (1 = default only)
    var colorHex: String?
    var panes: [PaneVisibilityInfo]
    var zoomMode: ArrangementPanelZoomMode?
    var arrangements: [ArrangementInfo]
    var minimizedCount: Int
    var notificationDotColor: TabNotificationDotColor?
}

enum TabNotificationDotColor: Equatable {
    case red
    case amber
    case yellow
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
    var dwellTabId: UUID?
    var dwellProgress: CGFloat = 0
    var tabFrames: [UUID: CGRect] = [:]

    // MARK: - Internals

    private let store: WorkspaceStore
    private let repoCache: RepoCacheAtom
    private let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    private let notificationDotColorProvider: @MainActor ([UUID]) -> TabNotificationDotColor?
    private var isObservingManagementLayer = false
    private var isObservingTabCollection = false
    private var isReconcilingTabObservers = false
    private var nextTabObservationGeneration: UInt64 = 0
    private var tabObservationGenerationById: [UUID: UInt64] = [:]
    private var tabItemById: [UUID: TabBarItem] = [:]

    init(
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil,
        notificationDotColorProvider: @escaping @MainActor ([UUID]) -> TabNotificationDotColor? = { _ in nil }
    ) {
        self.store = store
        self.repoCache = repoCache
        self.performanceTraceRecorder = performanceTraceRecorder
        self.notificationDotColorProvider = notificationDotColorProvider
        observe()
    }

    // MARK: - Observation

    private func observe() {
        // Re-derive tabs whenever the store's observed state changes.
        // withObservationTracking fires once per registration, so we re-register
        // after each change. Task { @MainActor } satisfies @Sendable and ensures
        // we read new values (onChange has willSet semantics — old values only).
        isManagementLayerActive = atom(\.managementLayer).isActive
        observeTabCollection()
        observeManagementLayer()
    }

    private func observeTabCollection() {
        guard !isObservingTabCollection else { return }
        isObservingTabCollection = true
        let tabCollection = withObservationTracking {
            (
                tabIds: self.store.tabLayoutAtom.tabs.map(\.id),
                activeTabId: self.store.tabLayoutAtom.activeTabId
            )
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.isObservingTabCollection = false
                self.observeTabCollection()
            }
        }
        reconcileTabObservers(
            orderedTabIds: tabCollection.tabIds,
            activeTabId: tabCollection.activeTabId
        )
    }

    private func reconcileTabObservers(orderedTabIds: [UUID], activeTabId: UUID?) {
        let refreshClock = ContinuousClock()
        let refreshStart = refreshClock.now
        isReconcilingTabObservers = true
        defer {
            isReconcilingTabObservers = false
            publishTabsIfChanged(orderedTabIds: orderedTabIds, refreshStart: refreshStart)
        }

        let retainedTabIds = Set(orderedTabIds)
        for removedTabId in Array(tabObservationGenerationById.keys)
        where !retainedTabIds.contains(removedTabId) {
            tabObservationGenerationById.removeValue(forKey: removedTabId)
            tabItemById.removeValue(forKey: removedTabId)
        }
        for tabId in orderedTabIds where tabObservationGenerationById[tabId] == nil {
            observeTabItem(tabId)
        }

        let resolvedActiveTabId = activeTabId ?? orderedTabIds.last
        if self.activeTabId != resolvedActiveTabId {
            self.activeTabId = resolvedActiveTabId
        }
    }

    private func observeTabItem(_ tabId: UUID) {
        nextTabObservationGeneration &+= 1
        let observationGeneration = nextTabObservationGeneration
        tabObservationGenerationById[tabId] = observationGeneration
        let refreshClock = ContinuousClock()
        let refreshStart = refreshClock.now
        let item = withObservationTracking {
            self.makeTabBarItem(for: tabId)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                    self.tabObservationGenerationById[tabId] == observationGeneration
                else { return }
                self.observeTabItem(tabId)
            }
        }

        guard tabObservationGenerationById[tabId] == observationGeneration else { return }
        if let item {
            tabItemById[tabId] = item
        } else {
            tabObservationGenerationById.removeValue(forKey: tabId)
            tabItemById.removeValue(forKey: tabId)
        }
        if !isReconcilingTabObservers {
            publishTabsIfChanged(
                orderedTabIds: store.tabLayoutAtom.tabs.map(\.id),
                refreshStart: refreshStart
            )
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

    private func makeTabBarItem(for tabId: UUID) -> TabBarItem? {
        guard let tab = store.tabLayoutAtom.tab(tabId) else { return nil }
        let displayTitle = atom(\.tabDisplay).displayTitle(
            for: tab,
            workspacePane: store.paneAtom,
            workspaceRepositoryTopology: store.repositoryTopologyAtom,
            repoCache: repoCache
        )
        let activeArrangement = tab.activeArrangement
        let activeArrangementBadgeNumber = Self.activeArrangementBadgeNumber(for: tab)
        let arrangementDerived = atom(\.arrangement)
        let paneInfos = arrangementDerived.paneVisibilityItems(for: tab.id)
        let zoomPresentation = store.panePresentationAtom.zoomPresentation(forTab: tab.id)
        let zoomMode = arrangementDerived.zoomMode(for: tab.id)
        let arrangementInfos = arrangementDerived.arrangementItems(for: tab.id)
        let notificationDotColor = notificationDotColorProvider(Array(tab.allPaneIds))
        let zoomManagementTitle = zoomPresentation.flatMap { presentation in
            ZoomManagementTitle.text(
                sourceOrdinal: PaneOrdinalMap(
                    orderedPaneIds: activeArrangement.layout.paneIds
                ).ordinal(forPaneId: presentation.sourcePaneId),
                activeArrangementName: Self.activeArrangementDisplayName(for: activeArrangement)
            )
        }

        return TabBarItem(
            id: tab.id,
            title: displayTitle,
            isSplit: tab.isSplit,
            displayTitle: displayTitle,
            activeArrangementName: zoomManagementTitle
                ?? Self.activeArrangementDisplayName(for: activeArrangement),
            activeArrangementBadgeNumber: zoomPresentation == nil ? activeArrangementBadgeNumber : nil,
            arrangementCount: tab.arrangements.count,
            colorHex: tab.colorHex,
            panes: paneInfos,
            zoomMode: zoomMode,
            arrangements: arrangementInfos,
            minimizedCount: tab.activeMinimizedPaneIds.count,
            notificationDotColor: notificationDotColor
        )
    }

    private func publishTabsIfChanged(
        orderedTabIds: [UUID],
        refreshStart: ContinuousClock.Instant
    ) {
        let nextTabs = orderedTabIds.compactMap { tabItemById[$0] }
        guard tabs != nextTabs else { return }
        tabs = nextTabs
        updateOverflow()
        let clock = ContinuousClock()
        performanceTraceRecorder?.recordDuration(
            .tabBarRefresh,
            duration: refreshStart.duration(to: clock.now),
            attributes: [
                "agentstudio.performance.tabbar.tab.count": .int(tabs.count),
                "agentstudio.performance.tabbar.source_tab.count": .int(orderedTabIds.count),
                "agentstudio.performance.tabbar.pane.count": .int(tabs.reduce(0) { $0 + $1.panes.count }),
            ]
        )
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

    private static func activeArrangementDisplayName(for arrangement: PaneArrangement) -> String {
        arrangement.isDefault ? "Default" : arrangement.name
    }
}
