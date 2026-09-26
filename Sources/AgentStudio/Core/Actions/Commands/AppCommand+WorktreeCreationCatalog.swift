extension AppCommand {
    func newWorktreeDefinition() -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            label: "New Worktree",
            icon: .octicon(.gitWorktree),
            helpText: "Choose a repository and create a new worktree",
            surfacePolicy: .exposed([.commandBar]),
            targeting: .contextualAndTargeted([.repo], preferredInvocation: .targetSelection),
            commandBarGroupName: "Repo",
            commandBarGroupPriority: CommandBarGroupPriority.repo
        )
    }

    func newWorktreeFromDefaultDefinition() -> AppCommandSpec {
        worktreeDefinition(
            label: "From Default",
            icon: .octicon(.gitWorktree),
            helpText: "Create a new worktree from the repository's default branch",
            surfacePolicy: .notPresented,
            targetTypes: [.repo]
        )
    }

    func forkWorktreeDefinition() -> AppCommandSpec {
        worktreeDefinition(
            label: "Fork…",
            icon: .octicon(.repoClone),
            helpText: "Fork a worktree with its uncommitted, untracked, and ignored files",
            surfacePolicy: .notPresented
        )
    }
}
