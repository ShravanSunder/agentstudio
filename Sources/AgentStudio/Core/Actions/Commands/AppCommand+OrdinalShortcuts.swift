import Foundation

extension AppCommand {
    private static let tabSelectionShortcuts: [AppShortcut] = [
        .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
        .selectTab6, .selectTab7, .selectTab8, .selectTab9,
    ]

    private static let paneFocusShortcuts: [AppShortcut] = [
        .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
        .focusPane6, .focusPane7, .focusPane8, .focusPane9,
    ]

    static func selectTabShortcut(index: Int) -> AppShortcut {
        ordinalShortcut(index: index, shortcuts: tabSelectionShortcuts, label: "tab selection")
    }

    static func focusPaneShortcut(index: Int) -> AppShortcut {
        ordinalShortcut(index: index, shortcuts: paneFocusShortcuts, label: "pane focus")
    }

    private static func ordinalShortcut(
        index: Int,
        shortcuts: [AppShortcut],
        label: String
    ) -> AppShortcut {
        guard shortcuts.indices.contains(index - 1) else {
            preconditionFailure("Unsupported \(label) shortcut index \(index)")
        }
        return shortcuts[index - 1]
    }
}
