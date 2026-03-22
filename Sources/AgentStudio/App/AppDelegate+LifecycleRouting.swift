import AppKit
import os.log

private let appDelegateLifecycleLogger = Logger(subsystem: "com.agentstudio", category: "AppDelegate")

@MainActor
extension AppDelegate {
    func applicationDidBecomeActive(_ notification: Notification) {
        applicationLifecycleMonitor.handleApplicationDidBecomeActive()
    }

    func applicationDidResignActive(_ notification: Notification) {
        applicationLifecycleMonitor.handleApplicationDidResignActive()
    }

    func applicationWillTerminate(_ notification: Notification) {
        applicationLifecycleMonitor.handleApplicationWillTerminate { [weak self] in
            guard
                let splitViewController = self?.mainWindowController?.window?.contentViewController
                    as? MainSplitViewController
            else { return }
            splitViewController.savePersistentUIState()
        }
    }

    func wireLifecycleConsumers() {
        Ghostty.bindApplicationLifecycleStore(appLifecycleStore)
        paneTabViewController()?.setAppLifecycleStore(appLifecycleStore)
    }

    func paneTabViewController() -> PaneTabViewController? {
        guard
            let splitViewController = mainWindowController?.window?.contentViewController
                as? MainSplitViewController,
            splitViewController.splitViewItems.count > 1,
            let paneTabViewController = splitViewController.splitViewItems[1].viewController
                as? PaneTabViewController
        else { return nil }

        return paneTabViewController
    }

    func handleRefreshWorktreesRequested() async {
        guard !store.watchedPaths.isEmpty else { return }
        _ = await watchedFolderCommands.refreshWatchedFolders(store.watchedPaths.map(\.path))
        paneCoordinator.syncFilesystemRootsAndActivity()
    }

    @objc func showCommandBarRepos() {
        appDelegateLifecycleLogger.info("showCommandBarRepos triggered")
        guard let window = NSApp.keyWindow ?? mainWindowController?.window else {
            appDelegateLifecycleLogger.warning("No window available for command bar (repos)")
            return
        }
        commandBarController.show(prefix: "#", parentWindow: window)
    }

    func showRepoCommandBar() {
        showCommandBarRepos()
    }

    func refreshWorktrees() {
        Task { await handleRefreshWorktreesRequested() }
    }

    func refocusActivePane() {
        mainWindowController?.refocusActivePane()
    }
}
