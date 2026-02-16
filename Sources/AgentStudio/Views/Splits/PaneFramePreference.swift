import SwiftUI

/// Preference key that collects pane frames in the tab container coordinate space.
/// Each pane leaf reports its frame; TerminalSplitContainer reads and aggregates them
/// so the tab-level drawer overlay can position itself relative to the originating pane.
struct PaneFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
