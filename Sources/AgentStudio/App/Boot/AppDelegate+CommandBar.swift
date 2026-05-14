import AppKit

extension AppDelegate {
    func showCommandBar(prefix: String?, context: String) {
        appLogger.info("showCommandBar context=\(context, privacy: .public)")
        guard let window = NSApp.keyWindow ?? mainWindowController?.window else {
            appLogger.warning("No window available for \(context, privacy: .public)")
            return
        }

        let owner = KeyboardOwner.current(
            windowLifecycle: windowLifecycleStore,
            managementLayer: atomStore.managementLayer,
            uiState: uiState
        )
        if let prefix {
            commandBarController.show(prefix: prefix, parentWindow: window)
        } else {
            let scope = CommandBarState.defaultScope(for: owner)
            commandBarController.show(defaultRootScope: scope, parentWindow: window)
        }
    }
}
