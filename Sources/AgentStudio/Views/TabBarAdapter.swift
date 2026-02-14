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
    }
}
