import Foundation
import Combine
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
    var arrangementCount: Int           // total arrangements (1 = default only)
    var panes: [TabBarPaneInfo]
    var arrangements: [TabBarArrangementInfo]
    var minimizedCount: Int
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

    static let minTabWidth: CGFloat = 220
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
        // Re-derive tabs whenever the store's observed state changes.
        // withObservationTracking fires once per registration, so we re-register
        // after each change. Task { @MainActor } satisfies @Sendable and ensures
        // we read new values (onChange has willSet semantics — old values only).
        observeStore()

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

    /// Bridge @Observable store → ObservableObject adapter via withObservationTracking.
    /// Fires once per registration; re-registers after each change.
    private func observeStore() {
        withObservationTracking {
            // Touch the store properties we derive state from.
            // @Observable tracks these accesses and fires onChange when any mutate.
            _ = self.store.tabs
            _ = self.store.activeTabId
            _ = self.store.panes
        } onChange: {
            Task { @MainActor [weak self] in
                self?.refresh()
                self?.observeStore()
            }
        }
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

            let paneInfos: [TabBarPaneInfo] = tab.paneIds.map { paneId in
                TabBarPaneInfo(
                    id: paneId,
                    title: store.pane(paneId)?.title ?? "Terminal",
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

        // Overflow when tabs at min width can't fit in the viewport.
        let tabCount = CGFloat(tabs.count)
        let totalMinWidth = tabCount * Self.minTabWidth
            + (tabCount - 1) * Self.tabSpacing
            + Self.tabBarPadding
        isOverflowing = totalMinWidth > effectiveViewport
    }
}
