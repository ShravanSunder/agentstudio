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
        managementModeMonitor?.stopMonitoring()
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
        let watchedPaths = store.repositoryTopologyAtom.watchedPaths
        guard !watchedPaths.isEmpty else { return }
        _ = await watchedFolderCommands.refreshWatchedFolders(watchedPaths.map(\.path))
        paneCoordinator.syncFilesystemRootsAndActivity()
    }

    @objc func showCommandBarRepos() {
        CommandDispatcher.shared.dispatch(.showCommandBarRepos)
    }

    func showRepoCommandBar() {
        CommandDispatcher.shared.dispatch(.showCommandBarRepos)
    }

    func refreshWorktrees() {
        Task { await handleRefreshWorktreesRequested() }
    }

    func refocusActivePane() {
        mainWindowController?.refocusActivePane()
    }
}
