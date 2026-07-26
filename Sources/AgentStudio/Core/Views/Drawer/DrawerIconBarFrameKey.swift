import SwiftUI

/// Reports the icon bar's frame in tab-container coordinates.
///
/// The reducer retains the last non-zero value so transient SwiftUI updates do
/// not erase the exclusion zone used for drawer outside-click dismissal.
struct DrawerIconBarFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}
