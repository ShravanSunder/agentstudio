import Foundation
import Combine

/// Lightweight display item for the tab bar.
/// Contains only what the UI needs to render — no live views or split trees.
struct TabBarItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var isSplit: Bool
    var displayTitle: String
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
        // We listen to objectWillChange to catch any mutation (views, sessions, activeViewId).
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Defer to next run-loop tick so the store's properties are updated.
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            }
            .store(in: &cancellables)

        // Initial sync
        refresh()
    }

    private func refresh() {
        let storeTabs = store.activeTabs
        let sessions = store.sessions

        tabs = storeTabs.map { tab in
            let sessionTitles = tab.sessionIds.compactMap { sessionId in
                sessions.first { $0.id == sessionId }?.title
            }
            let displayTitle = sessionTitles.count > 1
                ? sessionTitles.joined(separator: " | ")
                : sessionTitles.first ?? "Terminal"

            return TabBarItem(
                id: tab.id,
                title: sessionTitles.first ?? "Terminal",
                isSplit: tab.isSplit,
                displayTitle: displayTitle
            )
        }

        activeTabId = store.activeTabId
    }
}
