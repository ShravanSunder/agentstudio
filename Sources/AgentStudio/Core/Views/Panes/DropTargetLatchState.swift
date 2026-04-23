import AppKit
import Foundation

struct DropTargetLatchState {
    /// Determines whether a latched drop target should be cleared.
    /// We clear when drag interaction is no longer active (all buttons released)
    /// or when the app loses focus and cannot continue receiving drag updates.
    static func shouldClearTarget(appIsActive: Bool, pressedMouseButtons: Int) -> Bool {
        !appIsActive || pressedMouseButtons == 0
    }
}
