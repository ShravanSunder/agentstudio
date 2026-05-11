import Foundation

extension AppDelegate: ShellCommandHandling {
    func canExecute(_ command: AppCommand) -> Bool {
        switch command {
        case .clearInboxNotifications:
            canExecuteClearInboxNotificationsCommand()
        case .watchFolder, .toggleSidebar, .filterSidebar,
            .showInboxNotifications, .showWorktreeSidebar,
            .signInGitHub, .signInGoogle, .newWindow, .closeWindow,
            .showCommandBarEverything, .showCommandBarCommands, .showCommandBarPanes, .showCommandBarRepos:
            true
        default: false
        }
    }

    func execute(_ command: AppCommand) -> Bool {
        switch command {
        case .watchFolder:
            Task { await handleWatchFolderRequested() }
            return true
        case .toggleSidebar:
            mainWindowController?.toggleSidebar()
            return true
        case .filterSidebar:
            mainWindowController?.showSidebarFilter()
            return true
        case .showInboxNotifications:
            mainWindowController?.showInboxNotifications(commandBarIsKey: commandBarController.isKeyWindow)
            return true
        case .clearInboxNotifications:
            return executeClearInboxNotificationsCommand()
        case .showWorktreeSidebar:
            mainWindowController?.showWorktreeSidebar()
            return true
        case .newWindow:
            newWindow()
            return true
        case .closeWindow:
            closeWindow()
            return true
        case .showCommandBarEverything:
            showCommandBar(prefix: nil, context: "command bar")
            return true
        case .showCommandBarCommands:
            showCommandBar(prefix: ">", context: "command bar (commands)")
            return true
        case .showCommandBarPanes:
            showCommandBar(prefix: "$", context: "command bar (panes)")
            return true
        case .showCommandBarRepos:
            showCommandBar(prefix: "#", context: "command bar (repos)")
            return true
        case .signInGitHub:
            handleSignInRequested(provider: .github)
            return true
        case .signInGoogle:
            handleSignInRequested(provider: .google)
            return true
        default: return false
        }
    }

    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool {
        switch (command, targetType) {
        default: return false
        }
    }
}
