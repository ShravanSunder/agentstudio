import AgentStudioInfrastructure
import AppKit
import Foundation

package struct EditorChoiceItem: Identifiable {
    package let id: EditorTargetId
    let title: String
    let appIcon: NSImage?
    let shortcutNumber: Int

    package init(
        id: EditorTargetId,
        title: String,
        appIcon: NSImage?,
        shortcutNumber: Int
    ) {
        self.id = id
        self.title = title
        self.appIcon = appIcon
        self.shortcutNumber = shortcutNumber
    }
}
