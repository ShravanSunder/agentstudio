import SwiftUI

/// Preference key that collects pane frames in the tab container coordinate space.
/// Each pane leaf reports its frame so the tab-level drawer overlay can position
/// itself relative to the originating pane.
package struct PaneFramePreferenceKey: PreferenceKey {
    package static let defaultValue: [UUID: CGRect] = [:]
    package static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Preference key for pane frames reported inside a drawer container coordinate space.
/// Kept separate from tab-level pane frames so drawer drag targeting never pollutes
/// the tab-level split overlay target map.
package struct DrawerPaneFramePreferenceKey: PreferenceKey {
    package static let defaultValue: [UUID: CGRect] = [:]
    package static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
