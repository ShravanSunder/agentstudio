import Foundation
import Observation

struct EditorChooserState: Equatable {
    var openForPaneId: UUID?
    var bookmarkedEditorId: EditorTargetId?
}

@MainActor
@Observable
final class UIStateAtom {
    private(set) var filterText: String = ""
    private(set) var isFilterVisible: Bool = false
    private(set) var showMinimizedBars: Bool = true
    private(set) var sidebarCollapsed: Bool = false
    private(set) var sidebarSurface: SidebarSurface = .repos
    private(set) var sidebarHasFocus: Bool = false
    private(set) var editorChooserState: EditorChooserState = .init()
    private(set) var availableEditorTargets: [ExternalEditorTarget] = []

    func setFilterText(_ text: String) {
        filterText = text
    }

    func setFilterVisible(_ isVisible: Bool) {
        isFilterVisible = isVisible
    }

    func setShowMinimizedBars(_ show: Bool) {
        showMinimizedBars = show
    }

    func setSidebarCollapsed(_ isCollapsed: Bool) {
        sidebarCollapsed = isCollapsed
    }

    func setSidebarSurface(_ surface: SidebarSurface) {
        sidebarSurface = surface
    }

    func setSidebarHasFocus(_ hasFocus: Bool) {
        sidebarHasFocus = hasFocus
    }

    func setBookmarkedEditor(_ editorId: EditorTargetId?) {
        editorChooserState.bookmarkedEditorId = editorId
    }

    func setOpenEditorPane(_ paneId: UUID?) {
        editorChooserState.openForPaneId = paneId
    }

    func setAvailableEditorTargets(_ targets: [ExternalEditorTarget]) {
        availableEditorTargets = targets
    }

    func hydrate(
        filterText: String,
        isFilterVisible: Bool,
        showMinimizedBars: Bool = true,
        sidebarCollapsed: Bool = false,
        sidebarSurface: SidebarSurface = .repos,
        editorChooserState: EditorChooserState = .init()
    ) {
        self.filterText = filterText
        self.isFilterVisible = isFilterVisible
        self.showMinimizedBars = showMinimizedBars
        self.sidebarCollapsed = sidebarCollapsed
        self.sidebarSurface = sidebarSurface
        self.sidebarHasFocus = false
        self.editorChooserState = editorChooserState
        self.availableEditorTargets = []
        // The open chooser belongs to the current live pane tree only, not persisted state.
        self.editorChooserState.openForPaneId = nil
    }

    func clear() {
        filterText = ""
        isFilterVisible = false
        showMinimizedBars = true
        sidebarCollapsed = false
        sidebarSurface = .repos
        sidebarHasFocus = false
        editorChooserState = .init()
        availableEditorTargets = []
    }
}
