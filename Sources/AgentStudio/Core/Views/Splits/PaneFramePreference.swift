import SwiftUI

/// Preference key that collects pane frames in the tab container coordinate space.
/// Each pane leaf reports its frame; TerminalSplitContainer reads and aggregates them
/// so the tab-level drawer overlay can position itself relative to the originating pane.
struct PaneFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Preference key for pane frames reported inside a drawer container coordinate space.
/// Kept separate from tab-level pane frames so drawer drag targeting never pollutes
/// the tab-level split overlay target map.
struct DrawerPaneFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
