import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import AppKit

extension AppDelegate: AgentStudioIPCUIPresenting {
    func showCommandBar(prefix: String?, context: String) {
        appLogger.info("showCommandBar context=\(context, privacy: .public)")
        guard
            let window = Self.commandBarPresentationWindow(
                keyWindow: NSApp.keyWindow,
                fallbackWindow: mainWindowController?.window
            )
        else {
            appLogger.warning("No window available for \(context, privacy: .public)")
            return
        }
        guard let workspaceWindowId = windowLifecycleStore.preferredWorkspaceWindowId else {
            appLogger.warning("No workspace window available for \(context, privacy: .public)")
            return
        }

        let owner = KeyboardOwner.current(
            windowLifecycle: windowLifecycleStore,
            managementLayer: atomStore.managementLayer,
            uiState: uiState
        )
        if let prefix {
            commandBarController.show(prefix: prefix, parentWindow: window, workspaceWindowId: workspaceWindowId)
        } else {
            let scope = CommandBarState.defaultScope(for: owner)
            commandBarController.show(
                defaultRootScope: scope,
                parentWindow: window,
                workspaceWindowId: workspaceWindowId
            )
        }
    }

    static func commandBarPresentationWindow(keyWindow: NSWindow?, fallbackWindow: NSWindow?) -> NSWindow? {
        keyWindow?.parent ?? keyWindow ?? fallbackWindow
    }

    func presentCommandBar(scope: IPCCommandBarScope) throws -> IPCCommandBarOpenResult {
        guard
            let window = Self.commandBarPresentationWindow(
                keyWindow: NSApp.keyWindow,
                fallbackWindow: mainWindowController?.window
            )
        else {
            throw AppIPCUIPresentationError(reason: .noActiveWindow)
        }
        guard let workspaceWindowId = windowLifecycleStore.preferredWorkspaceWindowId else {
            throw AppIPCUIPresentationError(reason: .noActiveWindow)
        }

        switch scope {
        case .everything:
            commandBarController.show(
                defaultRootScope: .everything,
                parentWindow: window,
                workspaceWindowId: workspaceWindowId
            )
        case .commands:
            commandBarController.show(prefix: ">", parentWindow: window, workspaceWindowId: workspaceWindowId)
        case .panes:
            commandBarController.show(prefix: "$", parentWindow: window, workspaceWindowId: workspaceWindowId)
        case .repos:
            commandBarController.show(prefix: "#", parentWindow: window, workspaceWindowId: workspaceWindowId)
        }

        return IPCCommandBarOpenResult(workspaceWindowId: workspaceWindowId, scope: scope, correlationId: nil)
    }
}
