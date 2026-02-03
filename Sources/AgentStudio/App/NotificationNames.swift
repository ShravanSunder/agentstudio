import Foundation

// MARK: - Notification Names

extension Notification.Name {
    // Tab management
    static let newTabRequested = Notification.Name("newTabRequested")
    static let closeTabRequested = Notification.Name("closeTabRequested")
    static let selectTabAtIndex = Notification.Name("selectTabAtIndex")

    // Project management
    static let addProjectRequested = Notification.Name("addProjectRequested")
    static let refreshWorktreesRequested = Notification.Name("refreshWorktreesRequested")

    // Terminal management
    static let openWorktreeRequested = Notification.Name("openWorktreeRequested")
    static let terminalProcessTerminated = Notification.Name("terminalProcessTerminated")

    // Sidebar management
    static let toggleSidebarRequested = Notification.Name("toggleSidebarRequested")
}
