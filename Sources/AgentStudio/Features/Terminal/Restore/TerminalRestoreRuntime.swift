import Foundation

@MainActor
struct TerminalRestoreRuntime {
    let sessionConfiguration: SessionConfiguration

    func shouldStartHiddenRestore(
        policy: BackgroundRestorePolicy,
        hasExistingSession: Bool
    ) -> Bool {
        TerminalRestoreScheduler.shouldStartHiddenRestore(
            policy: policy,
            hasExistingSession: hasExistingSession
        )
    }

    func zmxAttachCommand(
        pane: Pane,
        worktree: Worktree,
        repo: Repo
    ) -> String? {
        guard let zmxPath = sessionConfiguration.zmxPath else { return nil }

        let sessionId: String
        if let parentPaneId = pane.parentPaneId {
            sessionId = ZmxBackend.drawerSessionId(
                parentPaneId: parentPaneId,
                drawerPaneId: pane.id
            )
        } else {
            sessionId = ZmxBackend.sessionId(
                repoStableKey: repo.stableKey,
                worktreeStableKey: worktree.stableKey,
                paneId: pane.id
            )
        }

        return ZmxBackend.buildAttachCommand(
            zmxPath: zmxPath,
            sessionId: sessionId,
            shell: SessionConfiguration.defaultShell()
        )
    }
}
