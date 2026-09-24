import Foundation

/// Closed command-argument data shapes. App owns the exhaustive mapping from
/// open command identifiers to one or more of these variants.
package enum IPCCommandArgumentVariant: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case noArguments
    case workspaceWindow
    case tab
    case renamedTab
    case newTab
    case tabAnchor
    case pane
    case sourcePane
    case movePaneToTab
    case arrangement
    case newArrangement
    case renamedArrangement
    case drawerParent
    case drawerSourcePane
    case drawerPane
    case detachedDrawerPane
    case directory
    case repository
    case standalonePane
    case worktree
    case worktreeInPane
    case bridgeDocumentInPane
    case terminalFromWorktree
    case terminalFromPane
    case managementFromMainPane
    case managementFromDrawerPane
    case floatingTerminal
    case webview

    package var schema: IPCJSONSchema {
        get throws {
            switch self {
            case .noArguments:
                IPCCommandArgumentSchemas.object(kind: self)
            case .workspaceWindow:
                try IPCWorkspaceWindowCommandArguments.argumentSchema()
            case .tab:
                try IPCTabCommandArguments.argumentSchema()
            case .renamedTab:
                try IPCRenamedTabCommandArguments.argumentSchema()
            case .newTab:
                try IPCNewTabCommandArguments.argumentSchema()
            case .tabAnchor:
                try IPCTabAnchorCommandArguments.argumentSchema()
            case .pane:
                try IPCPaneCommandArguments.argumentSchema()
            case .sourcePane:
                try IPCSourcePaneCommandArguments.argumentSchema()
            case .movePaneToTab:
                try IPCMovePaneToTabCommandArguments.argumentSchema()
            case .arrangement:
                try IPCArrangementCommandArguments.argumentSchema()
            case .newArrangement:
                try IPCNewArrangementCommandArguments.argumentSchema()
            case .renamedArrangement:
                try IPCRenamedArrangementCommandArguments.argumentSchema()
            case .drawerParent:
                try IPCDrawerParentCommandArguments.argumentSchema()
            case .drawerSourcePane:
                try IPCDrawerSourcePaneCommandArguments.argumentSchema()
            case .drawerPane:
                try IPCDrawerPaneCommandArguments.argumentSchema()
            case .detachedDrawerPane:
                try IPCDetachedDrawerPaneCommandArguments.argumentSchema()
            case .directory:
                try IPCDirectoryCommandArguments.argumentSchema()
            case .repository:
                try IPCRepositoryCommandArguments.argumentSchema()
            case .standalonePane:
                try IPCStandalonePaneCommandArguments.argumentSchema()
            case .worktree:
                try IPCWorktreeCommandArguments.argumentSchema()
            case .worktreeInPane:
                try IPCWorktreeInPaneCommandArguments.argumentSchema()
            case .bridgeDocumentInPane:
                try IPCBridgeDocumentInPaneCommandArguments.argumentSchema()
            case .terminalFromWorktree:
                try IPCTerminalFromWorktreeCommandArguments.argumentSchema()
            case .terminalFromPane:
                try IPCTerminalFromPaneCommandArguments.argumentSchema()
            case .managementFromMainPane:
                try IPCManagementFromMainPaneCommandArguments.argumentSchema()
            case .managementFromDrawerPane:
                try IPCManagementFromDrawerPaneCommandArguments.argumentSchema()
            case .floatingTerminal:
                try IPCFloatingTerminalCommandArguments.argumentSchema()
            case .webview:
                try IPCWebviewCommandArguments.argumentSchema()
            }
        }
    }
}
