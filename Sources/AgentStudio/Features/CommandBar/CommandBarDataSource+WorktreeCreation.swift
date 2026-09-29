import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioWorktreeOperations
import Foundation

@MainActor
extension CommandBarDataSource {
    static func buildWorktreeCreationRepoLevel(
        for def: AppCommandSpec,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom
    ) -> CommandBarLevel {
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        let focusedPane = atom(\.workspaceFocusedPane).resolve(
            workspaceTab: workspaceTab,
            workspacePane: store.paneAtom,
            requestedOwner: atom(\.workspaceFocusOwner).owner
        )
        let focusedRepoId = focusedPane?.repoId
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
                    action: .navigate(
                        worktreeCreationMenuLevel(
                            repository: repository,
                            store: store,
                            repoCache: repoCache,
                            focusedWorktreeId: repository.id == focusedRepoId ? focusedPane?.worktreeId : nil)),
                    command: def.command
                )
            }
        )
    }

    static func worktreeCreationMenuLevel(
        repository: Repo,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        defaultStartPoint: WorktreeDefaultStartPoint? = nil,
        defaultQueryFailed: Bool = false,
        branchNames: [String]? = nil,
        branchListingFailed: Bool = false,
        eligibilityByWorktreeId: [UUID: WorktreeForkEligibility] = [:],
        focusedWorktreeId: UUID? = nil
    ) -> CommandBarLevel {
        let defaultSpec = AppCommand.newWorktreeFromDefault.definition
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
        let forkItems = orderedForkSources(repository: repository, focusedWorktreeId: focusedWorktreeId)
            .map { worktree in
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
                    group: "FORK A WORKTREE",
                    groupPriority: 0,
                    hasChildren: true,
                    action: .navigate(
                        worktreeCreationBranchLevel(
                            repository: repository,
                            kind: .fork,
                            source: worktree,
                            sourceDisplay: worktree.name)),
                    command: .forkWorktree,
                    isEnabled: reason == nil)
            }
        let defaultBranchName = defaultBranchName(from: defaultStartPoint)
        let recentBranchNames = recentBranchNames(
            repository: repository, store: store, repoCache: repoCache, excluding: defaultBranchName)
        let defaultItem = CommandBarItem(
            id: "newWorktree-default-\(repository.id.uuidString)",
            title: defaultSpec.label,
            subtitle: defaultDisplay,
            icon: defaultSpec.icon,
            group: "FROM A BRANCH",
            groupPriority: 1,
            hasChildren: true,
            action: .navigate(
                worktreeCreationBranchLevel(
                    repository: repository,
                    kind: .fromDefault,
                    source: nil,
                    sourceDisplay: defaultDisplay)),
            command: defaultSpec.command,
            isEnabled: defaultEnabled)
        var branchItems =
            [defaultItem]
            + recentBranchNames.map { branchName in
                worktreeCreationFromBranchItem(branchName, repository: repository)
            }
        if branchListingFailed {
            branchItems.append(
                CommandBarItem(
                    id: "newWorktree-branch-list-error-\(repository.id.uuidString)",
                    title: "Unable to list branches",
                    icon: AppCommand.newWorktreeFromBranch.definition.icon,
                    group: "FROM A BRANCH",
                    groupPriority: 1,
                    action: .custom({}),
                    isEnabled: false
                ))
        }
        let recentBranchSet = Set(recentBranchNames)
        let searchOnlyItems = (branchNames ?? [])
            .filter { $0 != defaultBranchName && !recentBranchSet.contains($0) }
            .map { worktreeCreationFromBranchItem($0, repository: repository) }
        return CommandBarLevel(
            id: "level-newWorktree-menu-\(repository.id.uuidString)",
            title: AppCommand.newWorktree.definition.label,
            parentLabel: repository.name,
            scopeLabel: "Repository",
            items: forkItems + branchItems,
            searchOnlyItems: searchOnlyItems,
            creationQuery: .branchListing(repository)
        )
    }

    private static func orderedForkSources(
        repository: Repo,
        focusedWorktreeId: UUID?
    ) -> [Worktree] {
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
        return worktrees
    }

    private static func recentBranchNames(
        repository: Repo,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        excluding defaultBranchName: String?
    ) -> [String] {
        var includedBranchNames: Set<String> = []
        return resolvedRecentWorktrees(store: store)
            .compactMap { _, recentRepository, worktree in
                guard recentRepository.id == repository.id,
                    let branchName = repoCache.worktreeEnrichment(for: worktree.id)?.branch,
                    !branchName.isEmpty,
                    branchName != defaultBranchName,
                    includedBranchNames.insert(branchName).inserted
                else { return nil }
                return branchName
            }
            .prefix(5)
            .map(\.self)
    }

    private static func defaultBranchName(from startPoint: WorktreeDefaultStartPoint?) -> String? {
        guard case .resolved(let displayRef, let referenceName) = startPoint else { return nil }
        if referenceName.hasPrefix("refs/heads/") {
            return String(referenceName.dropFirst("refs/heads/".count))
        }
        if referenceName.hasPrefix("refs/remotes/") {
            return referenceName.split(separator: "/").dropFirst(3).joined(separator: "/")
        }
        return displayRef
    }

    private static func worktreeCreationFromBranchItem(
        _ branchName: String,
        repository: Repo
    ) -> CommandBarItem {
        let branchSpec = AppCommand.newWorktreeFromBranch.definition
        return CommandBarItem(
            id: "newWorktree-from-branch-\(repository.id.uuidString)-\(branchName)",
            title: branchName,
            icon: branchSpec.icon,
            group: "FROM A BRANCH",
            groupPriority: 1,
            hasChildren: true,
            action: .navigate(
                worktreeCreationBranchLevel(
                    repository: repository,
                    kind: .fromBranch(referenceName: "refs/heads/\(branchName)"),
                    source: nil,
                    sourceDisplay: branchName)),
            command: branchSpec.command)
    }

    static func worktreeCreationBranchLevel(
        repository: Repo,
        kind: WorktreeCreationKind,
        source: Worktree?,
        sourceDisplay: String
    ) -> CommandBarLevel {
        let targetId = source?.id ?? repository.id
        let levelTitle: String =
            switch kind {
            case .fromDefault: AppCommand.newWorktreeFromDefault.definition.label
            case .fromBranch: "From \(sourceDisplay)"
            case .fork: LocalActionSpec.forkThisWorktree.actionSpec.label
            }
        return CommandBarLevel(
            id: "level-newWorktree-branch-\(targetId.uuidString)",
            title: levelTitle,
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
            let slug = WorktreeDestinationNaming.folderSlug(for: name) ?? name.rawValue
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
