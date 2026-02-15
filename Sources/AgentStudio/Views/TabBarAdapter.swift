import Foundation
import Combine

/// Lightweight display item for the tab bar.
/// Contains only what the UI needs to render — no live views or split trees.
struct TabBarItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var isSplit: Bool
    var displayTitle: String
    var activeArrangementName: String?  // nil when only default exists
    var arrangementCount: Int           // total arrangements (1 = default only)
}

/// Derives tab bar display state from WorkspaceStore.
/// Replaces TabBarState as the observable source for CustomTabBar.
/// Owns only transient UI state (dragging, drop targets).
@MainActor
final class TabBarAdapter: ObservableObject {

    // MARK: - Derived from WorkspaceStore

    @Published private(set) var tabs: [TabBarItem] = []
    @Published private(set) var activeTabId: UUID?

    // MARK: - Overflow Detection

    @Published var availableWidth: CGFloat = 0
    @Published private(set) var isOverflowing: Bool = false
    @Published var contentWidth: CGFloat = 0
    @Published var viewportWidth: CGFloat = 0

    static let minTabWidth: CGFloat = 100
    static let tabSpacing: CGFloat = 4
    static let tabBarPadding: CGFloat = 16

    // MARK: - Edit Mode

    @Published private(set) var isEditModeActive: Bool = false

    // MARK: - Transient UI State

    @Published var draggingTabId: UUID?
    @Published var dropTargetIndex: Int?
    @Published var tabFrames: [UUID: CGRect] = [:]

    // MARK: - Internals

    private let store: WorkspaceStore
    private var cancellables = Set<AnyCancellable>()

    init(store: WorkspaceStore) {
        self.store = store
        observe()
    }

    // MARK: - Observation

    private func observe() {
        // Re-derive tabs whenever the store's published state changes.
        // We listen to objectWillChange to catch any mutation (tabs, panes, activeTabId).
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        $availableWidth
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateOverflow()
            }
            .store(in: &cancellables)

        $contentWidth
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateOverflow()
            }
            .store(in: &cancellables)

        $viewportWidth
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateOverflow()
            }
            .store(in: &cancellables)

        ManagementModeMonitor.shared.$isActive
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                self?.isEditModeActive = isActive
            }
            .store(in: &cancellables)

        // Initial sync
        refresh()
    }

    private func refresh() {
        let storeTabs = store.tabs

        tabs = storeTabs.map { tab in
            let paneTitles = tab.paneIds.compactMap { paneId in
                store.pane(paneId)?.title
            }
            let displayTitle = paneTitles.count > 1
                ? paneTitles.joined(separator: " | ")
                : paneTitles.first ?? "Terminal"

            let activeArrangement = tab.activeArrangement
            let showArrangementName = tab.arrangements.count > 1 && !activeArrangement.isDefault

            return TabBarItem(
                id: tab.id,
                title: paneTitles.first ?? "Terminal",
                isSplit: tab.isSplit,
                displayTitle: displayTitle,
                activeArrangementName: showArrangementName ? activeArrangement.name : nil,
                arrangementCount: tab.arrangements.count
            )
        }

        activeTabId = store.activeTabId
        updateOverflow()
    }

    private func updateOverflow() {
        guard tabs.count > 0 else {
            isOverflowing = false
            return
        }

        // Prefer viewport width (from onScrollGeometryChange or ScrollView measurement),
        // fall back to availableWidth (outer container).
        let effectiveViewport = viewportWidth > 0 ? viewportWidth : availableWidth
        guard effectiveViewport > 0 else { return }

        if contentWidth > 0 {
            if isOverflowing {
                // Hysteresis: only turn off overflow when tabs fit with room for the "+" button.
                // When overflowing, "+" is hidden so contentWidth is tabs-only.
                // Require a 50px buffer before turning off to prevent oscillation.
                if contentWidth < effectiveViewport - 50 {
                    isOverflowing = false
                }
            } else {
                // Turn on overflow when scroll content exceeds viewport
                isOverflowing = contentWidth > effectiveViewport
            }
        } else {
            // Fallback: estimate-based detection before content is measured
            let tabCount = CGFloat(tabs.count)
            let totalMinWidth = tabCount * Self.minTabWidth
                + (tabCount - 1) * Self.tabSpacing
                + Self.tabBarPadding
            isOverflowing = totalMinWidth > effectiveViewport
        }
    }
}
