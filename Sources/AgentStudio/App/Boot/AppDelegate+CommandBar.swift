import AppKit

extension AppDelegate {
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
}
