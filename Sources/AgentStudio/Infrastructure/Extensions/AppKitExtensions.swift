import AppKit
import UniformTypeIdentifiers

extension NSPasteboard.PasteboardType {
    // Internal tab reordering within tab bar
    static let agentStudioTabInternal = NSPasteboard.PasteboardType("com.agentstudio.tab.internal")

    // For SwiftUI drop compatibility (matches UTType.agentStudioTab)
    static let agentStudioTabDrop = NSPasteboard.PasteboardType(UTType.agentStudioTab.identifier)

    // For pane drag-to-tab-bar (extract pane to new tab)
    static let agentStudioPaneDrop = NSPasteboard.PasteboardType(UTType.agentStudioPane.identifier)
}

extension NSToolbarItem.Identifier {
    static let managementMode = NSToolbarItem.Identifier("managementMode")
    static let addRepo = NSToolbarItem.Identifier("addRepo")
    static let addFolder = NSToolbarItem.Identifier("addFolder")
}
