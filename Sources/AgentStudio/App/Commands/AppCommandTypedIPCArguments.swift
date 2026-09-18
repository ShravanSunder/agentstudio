import AgentStudioCore
import AgentStudioProgrammaticControl
import Foundation

/// App-side reading of canonical typed IPC command arguments. Every accessor
/// restates identities the wire already supplied; none of them consult active
/// or focused state, so an explicit request can never silently retarget.
extension IPCCommandArguments {
    /// The one current workspace window the request names, when the variant
    /// carries one. Variants without a window are workspace-global.
    var workspaceWindowId: UUID? {
        switch self {
        case .noArguments, .repository, .standalonePane:
            nil
        case .workspaceWindow(let value): value.workspaceWindowId
        case .tab(let value): value.workspaceWindowId
        case .renamedTab(let value): value.workspaceWindowId
        case .newTab(let value): value.workspaceWindowId
        case .tabAnchor(let value): value.workspaceWindowId
        case .pane(let value): value.workspaceWindowId
        case .sourcePane(let value): value.workspaceWindowId
        case .movePaneToTab(let value): value.workspaceWindowId
        case .arrangement(let value): value.workspaceWindowId
        case .newArrangement(let value): value.workspaceWindowId
        case .renamedArrangement(let value): value.workspaceWindowId
        case .drawerParent(let value): value.workspaceWindowId
        case .drawerSourcePane(let value): value.workspaceWindowId
        case .drawerPane(let value): value.workspaceWindowId
        case .detachedDrawerPane(let value): value.workspaceWindowId
        case .directory(let value): value.workspaceWindowId
        case .worktree(let value): value.workspaceWindowId
        case .worktreeInPane(let value): value.workspaceWindowId
        case .terminalFromWorktree(let value): value.workspaceWindowId
        case .terminalFromPane(let value): value.workspaceWindowId
        case .managementFromMainPane(let value): value.workspaceWindowId
        case .managementFromDrawerPane(let value): value.workspaceWindowId
        case .floatingTerminal(let value): value.workspaceWindowId
        case .webview(let value): value.workspaceWindowId
        }
    }

    /// The durable target the variant names. It mirrors the projection's
    /// `allowedTargetKinds`, so dispatch authority and discovery cannot drift.
    var durableTarget: AppCommandDurableTarget? {
        switch self {
        case .noArguments, .workspaceWindow, .newTab, .directory, .floatingTerminal, .webview:
            nil
        case .tab(let value): .init(id: value.tabId, type: .tab)
        case .renamedTab(let value): .init(id: value.tabId, type: .tab)
        case .tabAnchor(let value): .init(id: value.anchorTabId, type: .tab)
        case .arrangement(let value): .init(id: value.tabId, type: .tab)
        case .newArrangement(let value): .init(id: value.tabId, type: .tab)
        case .renamedArrangement(let value): .init(id: value.tabId, type: .tab)
        case .movePaneToTab(let value): canonicalPaneTarget(value.sourcePaneSelector)
        case .pane(let value): canonicalPaneTarget(value.paneSelector)
        case .sourcePane(let value): canonicalPaneTarget(value.sourcePaneSelector)
        case .standalonePane(let value): canonicalPaneTarget(value.paneSelector)
        case .drawerParent(let value): canonicalPaneTarget(value.parentPaneSelector)
        case .drawerSourcePane(let value): canonicalPaneTarget(value.parentPaneSelector)
        case .drawerPane(let value): canonicalPaneTarget(value.parentPaneSelector)
        case .detachedDrawerPane(let value): canonicalPaneTarget(value.drawerPaneSelector)
        case .worktreeInPane(let value): canonicalPaneTarget(value.targetPaneSelector)
        case .terminalFromPane(let value): canonicalPaneTarget(value.sourcePaneSelector)
        case .managementFromMainPane(let value): canonicalPaneTarget(value.mainPaneSelector)
        case .managementFromDrawerPane(let value): canonicalPaneTarget(value.drawerPaneSelector)
        case .repository(let value): .init(id: value.repoId, type: .repo)
        case .worktree(let value): .init(id: value.worktreeId, type: .worktree)
        case .terminalFromWorktree(let value): .init(id: value.worktreeId, type: .worktree)
        }
    }

    private func canonicalPaneTarget(_ selector: IPCPaneSelector) -> AppCommandDurableTarget? {
        guard case .canonical(kind: .pane, id: let id) = selector.parsed else { return nil }
        return AppCommandDurableTarget(id: id, type: .pane)
    }
}

/// One durable workspace identity named by a typed command request.
struct AppCommandDurableTarget: Equatable, Sendable {
    let id: UUID
    let type: SearchItemType
}

extension AppCommandExecutionRequest {
    /// Canonical typed IPC arguments when this request came from the wire.
    var typedIPCArguments: IPCCommandArguments? {
        switch arguments {
        case .noArguments: nil
        case .typedIPC(let value): value
        }
    }
}

/// Canonical pane identity helpers shared by every owner adapting typed IPC
/// arguments. They read only what the wire supplied.
enum AppCommandTypedIPCPane {
    static func canonicalId(_ selector: IPCPaneSelector) -> UUID? {
        guard case .canonical(kind: .pane, id: let id) = selector.parsed else { return nil }
        return id
    }

    static func launchDirectory(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}
