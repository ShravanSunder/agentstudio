import Foundation

// MARK: - Notification Names

extension Notification.Name {
    // Tab management
    static let newTabRequested = Notification.Name("newTabRequested")
    static let closeTabRequested = Notification.Name("closeTabRequested")
    static let undoCloseTabRequested = Notification.Name("undoCloseTabRequested")
    static let selectTabAtIndex = Notification.Name("selectTabAtIndex")
    static let selectTabById = Notification.Name("selectTabById")

    // Repo management
    static let addRepoRequested = Notification.Name("addRepoRequested")
    static let refreshWorktreesRequested = Notification.Name("refreshWorktreesRequested")

    // Terminal management
    static let openWorktreeRequested = Notification.Name("openWorktreeRequested")
    static let terminalProcessTerminated = Notification.Name("terminalProcessTerminated")

    // Pane management
    static let extractPaneRequested = Notification.Name("extractPaneRequested")

    // Webview management
    static let openWebviewRequested = Notification.Name("openWebviewRequested")
    static let signInRequested = Notification.Name("signInRequested")

    // Surface repair
    static let repairSurfaceRequested = Notification.Name("repairSurfaceRequested")

    // Sidebar management
    static let toggleSidebarRequested = Notification.Name("toggleSidebarRequested")
    static let filterSidebarRequested = Notification.Name("filterSidebarRequested")
    static let openNewTerminalRequested = Notification.Name("openNewTerminalRequested")

    // Focus management
    static let refocusTerminalRequested = Notification.Name("refocusTerminalRequested")
}
