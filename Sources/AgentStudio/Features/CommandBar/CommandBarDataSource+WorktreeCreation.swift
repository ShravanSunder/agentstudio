import AgentStudioCore
import Foundation

/// New Worktree drill-in: pick a source worktree, then type the branch name into a
/// text-entry level whose single Create row forks (Return) or checks out clean
/// (Option-Return) from that worktree's HEAD.
@MainActor
extension CommandBarDataSource {
    static func buildWorktreeCreationSourceLevel(
        for def: AppCommandSpec,
        store: WorkspaceStore
    ) -> CommandBarLevel {
        let items = availableRepositories(store: store).enumerated().flatMap { repoIndex, repo in
            repo.worktrees.map { worktree in
                CommandBarItem(
                    id: "target-worktree-creation-source-\(worktree.id.uuidString)",
                    title: worktree.name,
                    subtitle: repo.name,
                    icon: worktree.isMainWorktree ? .system(.starFill) : .system(.arrowTriangleBranch),
                    group: "Worktrees",
                    groupPriority: repoIndex,
                    hasChildren: true,
                    action: .navigate(worktreeCreationBranchLevel(for: def, source: worktree, repository: repo)),
                    command: def.command
                )
            }
        }
        return CommandBarLevel(
            id: "level-\(def.command.rawValue)-source",
            title: "Select Source Worktree",
            parentLabel: def.label,
            items: items
        )
    }

    /// The new worktree lands beside the repository's main checkout, so that folder's
    /// parent is where fork eligibility is asked about.
    static func worktreeCreationBranchLevel(
        for def: AppCommandSpec,
        source: Worktree,
        repository: Repo
    ) -> CommandBarLevel {
        CommandBarLevel(
            id: "level-\(def.command.rawValue)-branch-\(source.id.uuidString)",
            title: source.name,
            parentLabel: def.label,
            scopeLabel: "Worktree",
            items: [],
            textEntry: CommandBarTextEntry(
                placeholder: "Branch name...",
                forkEligibilityQuery: CommandBarForkEligibilityQuery(
                    sourceWorktreeId: source.id,
                    sourceWorktreePath: source.path,
                    destinationDirectory: repository.repoPath.standardizedFileURL.deletingLastPathComponent()
                )
            ) { input in
                [worktreeCreationRow(input: input, source: source)]
            }
        )
    }

    static func worktreeCreationRow(input: CommandBarTextEntryInput, source: Worktree) -> CommandBarItem {
        let draft = CommandBarWorktreeCreationDraft(
            sourceWorktreeId: source.id,
            branchName: WorktreeBranchName.validated(input.text),
            forkEligibility: input.forkEligibility
        )
        let forkSpec = AppCommand.forkWorktree.definition
        let cleanSpec = AppCommand.newWorktree.definition
        let text = input.text
        let title: String
        let secondaryLine: CommandBarItemSecondaryLine
        switch (draft.branchName, input.forkEligibility) {
        case (.success(let branchName), .unavailable(let reason)):
            title = branchName.rawValue
            secondaryLine = CommandBarItemSecondaryLine(
                text: "Create clean worktree — fork unavailable here: \(reason)",
                icon: cleanSpec.icon
            )
        case (.success(let branchName), _):
            title = branchName.rawValue
            // The default Return forks, so the row says what comes along.
            secondaryLine = CommandBarItemSecondaryLine(text: forkSpec.helpText, icon: forkSpec.icon)
        case (.failure(let rejection), _):
            title = text.isEmpty ? "New branch" : text
            secondaryLine = CommandBarItemSecondaryLine(text: branchNameRejectionReason(rejection), icon: nil)
        }
        return CommandBarItem(
            id: "create-worktree-\(source.id.uuidString)",
            title: title,
            subtitle: "from \(source.name)",
            secondaryLine: secondaryLine,
            icon: AppCommand.newWorktree.definition.icon,
            group: "Create",
            groupPriority: 0,
            action: .createWorktree(draft)
        )
    }

    static func branchNameRejectionReason(_ rejection: WorktreeBranchNameRejection) -> String {
        switch rejection {
        case .empty:
            "Type a branch name"
        case .tooLong(let maximumLength):
            "Branch names can be at most \(maximumLength) characters"
        case .containsWhitespaceOrControlCharacter:
            "Branch names cannot contain spaces or control characters"
        case .containsForbiddenCharacter(let character):
            "Branch names cannot contain \"\(character)\""
        case .containsForbiddenSequence(let sequence):
            "Branch names cannot contain \"\(sequence)\""
        case .invalidComponentBoundary:
            "Branch name segments cannot be empty, start with \"-\" or \".\", or end with \".\" or \".lock\""
        }
    }
}
