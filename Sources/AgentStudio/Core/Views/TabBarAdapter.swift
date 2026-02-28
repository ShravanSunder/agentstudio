import Foundation
import Observation

/// Pane info exposed to the tab bar for arrangement panel display.
struct TabBarPaneInfo: Identifiable, Equatable {
    let id: UUID
    var title: String
    var isMinimized: Bool
}

/// Arrangement info exposed to the tab bar for arrangement panel display.
struct TabBarArrangementInfo: Identifiable, Equatable {
    let id: UUID
    var name: String
    var isDefault: Bool
    var isActive: Bool
}

/// Lightweight display item for the tab bar.
/// Contains only what the UI needs to render — no live views or split trees.
struct TabBarItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var isSplit: Bool
    var displayTitle: String
    var activeArrangementName: String?  // nil when only default exists
    var arrangementCount: Int  // total arrangements (1 = default only)
    var panes: [TabBarPaneInfo]
    var arrangements: [TabBarArrangementInfo]
    var minimizedCount: Int
}

/// Derives tab bar display state from WorkspaceStore.
/// Replaces TabBarState as the observable source for CustomTabBar.
/// Owns only transient UI state (dragging, drop targets).
@MainActor
@Observable
final class TabBarAdapter {

    // MARK: - Derived from WorkspaceStore

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

    // MARK: - Management Mode

    private(set) var isManagementModeActive: Bool = false

    // MARK: - Transient UI State

    var draggingTabId: UUID?
    var dropTargetIndex: Int?
    var tabFrames: [UUID: CGRect] = [:]

    // MARK: - Internals

    private let store: WorkspaceStore
    private var isObservingManagementMode = false
    private var isObservingStore = false

    init(store: WorkspaceStore) {
        self.store = store
        observe()
    }

    // MARK: - Observation

    private func observe() {
        // Re-derive tabs whenever the store's observed state changes.
        // withObservationTracking fires once per registration, so we re-register
        // after each change. Task { @MainActor } satisfies @Sendable and ensures
        // we read new values (onChange has willSet semantics — old values only).
        isManagementModeActive = ManagementModeMonitor.shared.isActive
        observeStore()
        observeManagementMode()

        // Initial sync
        refresh()
    }

    /// Bridge @Observable store → adapter via withObservationTracking.
    /// Fires once per registration; re-registers after each change.
    private func observeStore() {
        guard !isObservingStore else { return }
        isObservingStore = true
        withObservationTracking {
            // Touch the store properties we derive state from.
            // @Observable tracks these accesses and fires onChange when any mutate.
            _ = self.store.tabs
            _ = self.store.activeTabId
            _ = self.store.panes
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.isObservingStore = false
                self.refresh()
                self.observeStore()
            }
        }
    }

    private func observeManagementMode() {
        guard !isObservingManagementMode else { return }
        isObservingManagementMode = true
        withObservationTracking {
            // Track only reads; writes stay in onChange.
            _ = ManagementModeMonitor.shared.isActive
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObservingManagementMode = false
                self.isManagementModeActive = ManagementModeMonitor.shared.isActive
                self.observeManagementMode()
            }
        }
    }

    private func refresh() {
        let storeTabs = store.tabs

        tabs = storeTabs.map { tab in
            let paneTitles = tab.paneIds.map { paneDisplayTitle(for: $0) }
            let displayTitle =
                paneTitles.count > 1
                ? paneTitles.joined(separator: " | ")
                : paneTitles.first ?? "Terminal"

            let activeArrangement = tab.activeArrangement
            let showArrangementName = tab.arrangements.count > 1 && !activeArrangement.isDefault

            let paneInfos: [TabBarPaneInfo] = tab.paneIds.map { paneId in
                TabBarPaneInfo(
                    id: paneId,
                    title: paneDisplayTitle(for: paneId),
                    isMinimized: tab.minimizedPaneIds.contains(paneId)
                )
            }

            let arrangementInfos: [TabBarArrangementInfo] = tab.arrangements.map { arr in
                TabBarArrangementInfo(
                    id: arr.id,
                    name: arr.name,
                    isDefault: arr.isDefault,
                    isActive: arr.id == tab.activeArrangementId
                )
            }

            return TabBarItem(
                id: tab.id,
                title: paneTitles.first ?? "Terminal",
                isSplit: tab.isSplit,
                displayTitle: displayTitle,
                activeArrangementName: showArrangementName ? activeArrangement.name : nil,
                arrangementCount: tab.arrangements.count,
                panes: paneInfos,
                arrangements: arrangementInfos,
                minimizedCount: tab.minimizedPaneIds.count
            )
        }

        if let storeActiveTabId = store.activeTabId {
            activeTabId = storeActiveTabId
        } else {
            // Defensive UI fallback for transient restore/repair windows where tabs
            // exist but activeTabId has not been recomputed yet.
            activeTabId = tabs.last?.id
        }
        updateOverflow()
    }

    private func paneDisplayTitle(for paneId: UUID) -> String {
        guard let pane = store.pane(paneId) else { return "Terminal" }
        let rawTitle = pane.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let isGenericTitle =
            rawTitle.isEmpty || rawTitle.localizedCaseInsensitiveCompare("Terminal") == .orderedSame
            || rawTitle.localizedCaseInsensitiveCompare("Drawer") == .orderedSame

        if isGenericTitle,
            let cwdName = pane.metadata.cwd?.lastPathComponent,
            !cwdName.isEmpty
        {
            return cwdName
        }

        return rawTitle.isEmpty ? "Terminal" : rawTitle
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
}
