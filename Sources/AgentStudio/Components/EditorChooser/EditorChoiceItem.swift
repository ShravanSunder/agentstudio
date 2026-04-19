import AppKit
import Foundation

struct EditorChoiceItem: Identifiable {
    let id: EditorTargetId
    let title: String
    let appIcon: NSImage?
    let shortcutNumber: Int
}
