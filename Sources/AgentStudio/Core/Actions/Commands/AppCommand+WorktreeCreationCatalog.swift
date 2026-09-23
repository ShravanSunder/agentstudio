extension AppCommand {
    /// The single command-bar entry for worktree creation. Its source-worktree level
    /// ends in one Create row whose Return modifier picks this clean checkout or a fork.
    func newWorktreeDefinition() -> AppCommandSpec {
        worktreeDefinition(
            label: "New Worktree...",
            icon: .octicon(.gitWorktree),
            helpText: "Create a worktree on a new branch from a worktree's HEAD, checked out clean",
            surfacePolicy: .exposed([.commandBar])
        )
    }

    /// Reached only through the New Worktree Create row's Return modifier, so it is a
    /// distinct identity without a second root command-bar row.
    func forkWorktreeDefinition() -> AppCommandSpec {
        worktreeDefinition(
            label: "Fork Worktree...",
            icon: .octicon(.repoClone),
            helpText: "Fork a worktree with its uncommitted, untracked, and ignored files",
            surfacePolicy: .notPresented
        )
    }
}
