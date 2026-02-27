import Foundation

enum PaneRuntimeEventBus {
    static let shared = EventBus<PaneEventEnvelope>()
}

enum AppEvent: Sendable {
    case newTabRequested
    case closeTabRequested
    case undoCloseTabRequested
    case selectTabAtIndex(index: Int)
    case selectTabById(tabId: UUID, paneId: UUID?)
    case addRepoRequested
    case addFolderRequested
    case refreshWorktreesRequested
    case openWorktreeRequested(worktreeId: UUID)
    case terminalProcessTerminated(worktreeId: UUID?, exitCode: Int32?)
    case extractPaneRequested(tabId: UUID, paneId: UUID, targetTabIndex: Int?)
    case movePaneToTabRequested(paneId: UUID, sourceTabId: UUID?, targetTabId: UUID)
    case openWorktreeInPaneRequested(worktreeId: UUID)
    case openWebviewRequested
    case signInRequested(provider: String)
    case repairSurfaceRequested(paneId: UUID)
    case toggleSidebarRequested
    case filterSidebarRequested
    case openNewTerminalRequested(worktreeId: UUID)
    case refocusTerminalRequested
    case showCommandBarRepos
    case worktreeBellRang(paneId: UUID)
    case managementModeChanged(isActive: Bool)
}

enum AppEventBus {
    static let shared = EventBus<AppEvent>()
}

enum GhosttyEventSignal: Sendable {
    case newWindowRequested
    case closeSurface(surfaceViewId: ObjectIdentifier, processAlive: Bool)
    case rendererHealthUpdated(surfaceViewId: ObjectIdentifier, isHealthy: Bool)
    case workingDirectoryUpdated(surfaceViewId: ObjectIdentifier, rawPwd: String?)
}

enum GhosttyEventBus {
    static let shared = EventBus<GhosttyEventSignal>()
}

@inline(__always)
func postAppEvent(_ event: AppEvent) {
    Task { await AppEventBus.shared.post(event) }
}

@inline(__always)
func postGhosttyEvent(_ event: GhosttyEventSignal) {
    Task { await GhosttyEventBus.shared.post(event) }
}
