import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

/// One in-flight query belongs to the command bar session that issued it.
struct InFlightForkEligibilityQuery {
    let rootSessionGeneration: Int
    let token: UUID
    let task: Task<Void, Never>
}

struct InFlightDefaultStartPointQuery {
    let rootSessionGeneration: Int
    let token: UUID
    let task: Task<Void, Never>
}

extension CommandBarPanelController {
    func requestCreationQueriesIfNeeded(for level: CommandBarLevel) {
        switch level.creationQuery {
        case .defaultStartPoint(let repository):
            requestDefaultStartPointIfNeeded(for: repository)
        case .forkEligibility(let repository):
            requestForkPickerEligibilityIfNeeded(for: repository)
        case .worktreeEligibility(let repository, let worktree):
            requestForkPickerEligibilityIfNeeded(for: repository, worktrees: [worktree])
        case nil:
            break
        }
        if case .some(.defaultStartPoint(let repository)) = level.creationQuery,
            state.defaultStartPointByRepositoryId[repository.id] != nil
        {
            refreshCreationLevel(for: repository)
        }
        if case .some(.forkEligibility(let repository)) = level.creationQuery {
            refreshCreationLevel(for: repository)
        }
        if case .some(.worktreeEligibility(let repository, _)) = level.creationQuery {
            refreshCreationLevel(for: repository)
        }
    }

    private func requestDefaultStartPointIfNeeded(for repository: Repo) {
        let generation = state.rootSessionGeneration
        guard let defaultStartPointResolver,
            state.defaultStartPointByRepositoryId[repository.id] == nil,
            defaultStartPointQueriesByRepositoryId[repository.id]?.rootSessionGeneration != generation
        else { return }
        let token = UUIDv7.generate()
        let task = Task { @MainActor [weak self] in
            do {
                let resolution = try await defaultStartPointResolver.resolveDefaultStartPoint(
                    repositoryPath: repository.repoPath)
                guard let self, self.state.rootSessionGeneration == generation else { return }
                if self.defaultStartPointQueriesByRepositoryId[repository.id]?.token == token {
                    self.defaultStartPointQueriesByRepositoryId.removeValue(forKey: repository.id)
                }
                self.state.recordDefaultStartPoint(resolution, forRepositoryId: repository.id)
                self.refreshCreationLevel(for: repository)
            } catch {
                guard let self, self.state.rootSessionGeneration == generation else { return }
                if self.defaultStartPointQueriesByRepositoryId[repository.id]?.token == token {
                    self.defaultStartPointQueriesByRepositoryId.removeValue(forKey: repository.id)
                }
                self.state.recordDefaultStartPointQueryFailure(forRepositoryId: repository.id)
                self.refreshCreationLevel(for: repository)
            }
        }
        defaultStartPointQueriesByRepositoryId[repository.id] = InFlightDefaultStartPointQuery(
            rootSessionGeneration: generation,
            token: token,
            task: task
        )
    }

    private func requestForkPickerEligibilityIfNeeded(for repository: Repo, worktrees: [Worktree]? = nil) {
        guard let worktreeForkEligibility else { return }
        let generation = state.rootSessionGeneration
        for worktree in worktrees ?? repository.worktrees {
            guard state.forkEligibilityBySourceWorktreeId[worktree.id] == nil,
                currentSessionForkEligibilityQuery(for: worktree.id) == nil
            else { continue }
            let token = UUIDv7.generate()
            let task = Task { @MainActor [weak self] in
                let eligibility = await worktreeForkEligibility.forkEligibility(
                    sourceWorktreePath: worktree.path,
                    destinationDirectory: repository.repoPath.standardizedFileURL.deletingLastPathComponent()
                )
                guard let self else { return }
                if self.forkEligibilityQueriesBySourceWorktreeId[worktree.id]?.token == token {
                    self.forkEligibilityQueriesBySourceWorktreeId.removeValue(forKey: worktree.id)
                }
                guard self.state.rootSessionGeneration == generation else { return }
                self.state.recordForkEligibility(eligibility, forSourceWorktreeId: worktree.id)
                self.refreshCreationLevel(for: repository)
            }
            forkEligibilityQueriesBySourceWorktreeId[worktree.id] = InFlightForkEligibilityQuery(
                rootSessionGeneration: generation,
                token: token,
                task: task
            )
        }
    }

    private func refreshCreationLevel(for repository: Repo) {
        for level in state.navigationStack {
            refreshCreationLevel(level, for: repository)
        }
    }

    private func refreshCreationLevel(_ level: CommandBarLevel, for repository: Repo) {
        switch level.creationQuery {
        case .defaultStartPoint(let queriedRepository) where queriedRepository.id == repository.id:
            break
        case .forkEligibility(let queriedRepository) where queriedRepository.id == repository.id:
            break
        case .worktreeEligibility(let queriedRepository, _) where queriedRepository.id == repository.id:
            break
        default:
            return
        }
        guard let currentRepository = CommandBarDataSource.availableRepository(repository, store: store) else {
            replaceCreationLevelWithoutActions(level)
            return
        }
        switch level.creationQuery {
        case .defaultStartPoint(let queriedRepository) where queriedRepository.id == repository.id:
            state.replaceLevel(
                CommandBarDataSource.worktreeCreationMenuLevel(
                    repository: currentRepository,
                    defaultStartPoint: state.defaultStartPointByRepositoryId[repository.id],
                    defaultQueryFailed: state.defaultStartPointQueryFailures.contains(repository.id)
                ))
        case .forkEligibility(let queriedRepository) where queriedRepository.id == repository.id:
            let eligibility = state.forkEligibilityBySourceWorktreeId
            let focusedWorktreeId = focusedWorktreeId(in: currentRepository)
            state.replaceLevel(
                CommandBarDataSource.worktreeCreationForkPickerLevel(
                    repository: currentRepository,
                    eligibilityByWorktreeId: eligibility,
                    focusedWorktreeId: focusedWorktreeId
                ))
        case .worktreeEligibility(let queriedRepository, let worktree) where queriedRepository.id == repository.id:
            guard let currentWorktree = currentRepository.worktrees.first(where: { $0.id == worktree.id }) else {
                replaceCreationLevelWithoutActions(level)
                return
            }
            let presence = CommandBarDataSource.buildWorktreePresence(
                worktree: currentWorktree,
                repo: currentRepository,
                store: store
            )
            state.replaceLevel(
                CommandBarDataSource.buildWorktreeActionsLevel(
                    worktree: currentWorktree,
                    presence: presence,
                    canOpenInCurrentTab: canOpenWorktreeInCurrentTab,
                    dispatcher: dispatcher,
                    repository: currentRepository,
                    forkEligibility: state.forkEligibilityBySourceWorktreeId[currentWorktree.id]
                ))
        default:
            break
        }
    }

    private func replaceCreationLevelWithoutActions(_ level: CommandBarLevel) {
        state.replaceLevel(
            CommandBarLevel(
                id: level.id,
                title: level.title,
                parentLabel: level.parentLabel,
                scopeLabel: level.scopeLabel,
                breadcrumbIcon: level.breadcrumbIcon,
                items: [],
                creationQuery: level.creationQuery
            ))
    }

    private func focusedWorktreeId(in repository: Repo) -> UUID? {
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        let focusedPane = atom(\.workspaceFocusedPane).resolve(
            workspaceTab: workspaceTab,
            workspacePane: store.paneAtom,
            requestedOwner: atom(\.workspaceFocusOwner).owner
        )
        guard focusedPane?.repoId == repository.id else { return nil }
        return focusedPane?.worktreeId
    }

    private func currentSessionForkEligibilityQuery(for sourceWorktreeId: UUID) -> InFlightForkEligibilityQuery? {
        guard let query = forkEligibilityQueriesBySourceWorktreeId[sourceWorktreeId],
            query.rootSessionGeneration == state.rootSessionGeneration
        else { return nil }
        return query
    }
}
