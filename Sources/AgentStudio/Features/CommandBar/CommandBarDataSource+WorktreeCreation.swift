import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

@MainActor
extension CommandBarDataSource {
    static func buildWorktreeCreationRepoLevel(
        for def: AppCommandSpec,
        store: WorkspaceStore
    ) -> CommandBarLevel {
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        let focusedRepoId = atom(\.workspaceFocusedPane).resolve(
            workspaceTab: workspaceTab,
            workspacePane: store.paneAtom,
            requestedOwner: atom(\.workspaceFocusOwner).owner
        )?.repoId
        let available = availableRepositories(store: store)
        var repositories: [Repo] = []
        if let focused = available.first(where: { $0.id == focusedRepoId }) {
            repositories.append(focused)
        }
        for repository in available where repository.id != focusedRepoId {
            repositories.append(repository)
        }
        return CommandBarLevel(
            id: "level-newWorktree-repos",
            title: "Select Repository",
            parentLabel: def.label,
            items: repositories.map { repository in
                CommandBarItem(
                    id: "target-newWorktree-repo-\(repository.id.uuidString)",
                    title: repository.name,
                    icon: .system(.folder),
                    group: "Repositories",
                    groupPriority: 0,
                    hasChildren: true,
                    action: .navigate(worktreeCreationMenuLevel(repository: repository)),
                    command: def.command
                )
            }
        )
    }

    static func worktreeCreationMenuLevel(
        repository: Repo,
        defaultStartPoint: WorktreeDefaultStartPoint? = nil,
        defaultQueryFailed: Bool = false
    ) -> CommandBarLevel {
        let defaultSpec = AppCommand.newWorktreeFromDefault.definition
        let forkSpec = AppCommand.forkWorktree.definition
        let defaultDisplay: String
        let defaultEnabled: Bool
        switch defaultStartPoint {
        case .resolved(let displayRef, _):
            defaultDisplay = displayRef
            defaultEnabled = true
        case .noDefaultBranch:
            defaultDisplay = "no default branch"
            defaultEnabled = false
        case nil:
            defaultDisplay = defaultQueryFailed ? "Unable to read default branch" : "Checking default branch…"
            defaultEnabled = false
        }
        return CommandBarLevel(
            id: "level-newWorktree-menu-\(repository.id.uuidString)",
            title: AppCommand.newWorktree.definition.label,
            parentLabel: repository.name,
            scopeLabel: "Repository",
            items: [
                CommandBarItem(
                    id: "newWorktree-default-\(repository.id.uuidString)",
                    title: defaultSpec.label,
                    subtitle: defaultDisplay,
                    icon: defaultSpec.icon,
                    group: "Create",
                    groupPriority: 0,
                    hasChildren: true,
                    action: .navigate(
                        worktreeCreationBranchLevel(
                            repository: repository,
                            kind: .fromDefault,
                            source: nil,
                            sourceDisplay: defaultDisplay
                        )),
                    command: defaultSpec.command,
                    isEnabled: defaultEnabled
                ),
                CommandBarItem(
                    id: "newWorktree-fork-\(repository.id.uuidString)",
                    title: forkSpec.label,
                    icon: forkSpec.icon,
                    group: "Create",
                    groupPriority: 0,
                    hasChildren: true,
                    action: .navigate(worktreeCreationForkPickerLevel(repository: repository)),
                    command: forkSpec.command,
                    isEnabled: !repository.worktrees.isEmpty
                ),
            ],
            creationQuery: .defaultStartPoint(repository)
        )
    }

    static func worktreeCreationForkPickerLevel(
        repository: Repo,
        eligibilityByWorktreeId: [UUID: WorktreeForkEligibility] = [:],
        focusedWorktreeId: UUID? = nil
    ) -> CommandBarLevel {
        var worktrees: [Worktree] = []
        var includedWorktreeIds: Set<UUID> = []
        if let focused = repository.worktrees.first(where: { $0.id == focusedWorktreeId }) {
            worktrees.append(focused)
            _ = includedWorktreeIds.insert(focused.id)
        }
        if let main = repository.worktrees.first(where: { $0.isMainWorktree && $0.id != focusedWorktreeId }) {
            worktrees.append(main)
            _ = includedWorktreeIds.insert(main.id)
        }
        for worktree in repository.worktrees {
            if includedWorktreeIds.insert(worktree.id).inserted {
                worktrees.append(worktree)
            }
        }
        return CommandBarLevel(
            id: "level-newWorktree-fork-\(repository.id.uuidString)",
            title: "Fork Worktree",
            parentLabel: repository.name,
            items: worktrees.map { worktree in
                let eligibility = eligibilityByWorktreeId[worktree.id]
                let reason: String?
                if case .unavailable(let unavailableReason) = eligibility {
                    reason = unavailableReason
                } else if eligibility == nil {
                    reason = "Checking fork availability…"
                } else {
                    reason = nil
                }
                return CommandBarItem(
                    id: "newWorktree-fork-source-\(worktree.id.uuidString)",
                    title: worktree.name,
                    subtitle: reason ?? repository.name,
                    icon: worktree.isMainWorktree ? .system(.starFill) : .system(.arrowTriangleBranch),
                    group: "Worktrees",
                    groupPriority: 0,
                    hasChildren: true,
                    action: .navigate(
                        worktreeCreationBranchLevel(
                            repository: repository,
                            kind: .fork,
                            source: worktree,
                            sourceDisplay: worktree.name
                        )),
                    command: .forkWorktree,
                    isEnabled: reason == nil
                )
            },
            creationQuery: .forkEligibility(repository)
        )
    }

    static func worktreeCreationBranchLevel(
        repository: Repo,
        kind: WorktreeCreationKind,
        source: Worktree?,
        sourceDisplay: String
    ) -> CommandBarLevel {
        let targetId = source?.id ?? repository.id
        return CommandBarLevel(
            id: "level-newWorktree-branch-\(targetId.uuidString)",
            title: kind == .fork
                ? LocalActionSpec.forkThisWorktree.actionSpec.label
                : AppCommand.newWorktreeFromDefault.definition.label,
            parentLabel: source?.name ?? repository.name,
            scopeLabel: kind == .fork ? "Worktree" : "Repository",
            items: [],
            textEntry: CommandBarTextEntry(placeholder: "Branch name...") { input in
                [
                    worktreeCreationRow(
                        input: input,
                        repository: repository,
                        kind: kind,
                        targetId: targetId,
                        sourceDisplay: sourceDisplay
                    )
                ]
            }
        )
    }

    static func worktreeCreationRow(
        input: CommandBarTextEntryInput,
        repository: Repo,
        kind: WorktreeCreationKind,
        targetId: UUID,
        sourceDisplay: String
    ) -> CommandBarItem {
        let branchName = WorktreeBranchName.validated(input.text)
        let draft = CommandBarWorktreeCreationDraft(kind: kind, targetId: targetId, branchName: branchName)
        let title: String
        let secondaryLine: CommandBarItemSecondaryLine
        switch branchName {
        case .success(let name):
            title = "Create \(name.rawValue)"
            let slug = WorktreeDestinationPolicy.folderSlug(for: name) ?? name.rawValue
            secondaryLine = CommandBarItemSecondaryLine(
                text: "→ \(repository.repoPath.lastPathComponent).\(slug)",
                icon: kind.command.definition.icon
            )
        case .failure(let rejection):
            title = input.text.isEmpty ? "Create" : input.text
            secondaryLine = CommandBarItemSecondaryLine(text: branchNameRejectionReason(rejection), icon: nil)
        }
        return CommandBarItem(
            id: "create-worktree-\(targetId.uuidString)",
            title: title,
            subtitle: "from \(sourceDisplay)",
            secondaryLine: secondaryLine,
            icon: kind.command.definition.icon,
            group: "Create",
            groupPriority: 0,
            action: .createWorktree(draft),
            command: kind.command
        )
    }

    static func branchNameRejectionReason(_ rejection: WorktreeBranchNameRejection) -> String {
        switch rejection {
        case .empty: "Type a branch name"
        case .tooLong(let maximumLength): "Branch names can be at most \(maximumLength) characters"
        case .containsWhitespaceOrControlCharacter: "Branch names cannot contain spaces or control characters"
        case .containsForbiddenCharacter(let character): "Branch names cannot contain \"\(character)\""
        case .containsForbiddenSequence(let sequence): "Branch names cannot contain \"\(sequence)\""
        case .invalidComponentBoundary:
            "Branch name segments cannot be empty, start with \"-\" or \".\", or end with \".\" or \".lock\""
        }
    }
}
