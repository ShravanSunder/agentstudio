import AppKit
import UniformTypeIdentifiers

extension NSPasteboard.PasteboardType {
    // Internal tab reordering within tab bar
    package static let agentStudioTabInternal = NSPasteboard.PasteboardType("com.agentstudio.tab.internal")

    // For SwiftUI drop compatibility (matches UTType.agentStudioTab)
    package static let agentStudioTabDrop = NSPasteboard.PasteboardType(UTType.agentStudioTab.identifier)

    // For pane drag-to-tab-bar (extract pane to new tab)
    package static let agentStudioPaneDrop = NSPasteboard.PasteboardType(UTType.agentStudioPane.identifier)

    // For new-tab drag from tab bar (matches UTType.agentStudioNewTab)
    package static let agentStudioNewTabDrop = NSPasteboard.PasteboardType(UTType.agentStudioNewTab.identifier)
}

extension NSToolbarItem.Identifier {
    package static let managementLayer = NSToolbarItem.Identifier("managementLayer")
    package static let watchFolder = NSToolbarItem.Identifier("watchFolder")
}
