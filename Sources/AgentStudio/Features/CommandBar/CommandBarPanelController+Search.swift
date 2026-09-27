import AgentStudioCore

@MainActor
extension CommandBarPanelController {
    func queryChanged(text _: String) {
        searchSequence += 1
        pendingSearchTask?.cancel()
        pendingSearchTask = nil

        guard state.isVisible else { return }
        let query = state.isNested ? state.searchQuery : state.normalizedRootQuery
        if query.isEmpty || state.currentLevel?.textEntry != nil {
            state.appliedSearchResult = nil
            return
        }

        let prepared = resultSession.prepareSearch(state: state)
        let request = SearchRequest(
            sequence: SearchRequestSequence(searchSequence),
            text: query,
            recentItemIds: state.recentItemIds.compactMap(SearchItemId.init),
            documentSet: prepared.documentSet
        )
        pendingSearchTask = Task { [weak self, searchService] in
            let answer = await searchService.search(request)
            self?.applySearchResult(answer, prepared: prepared)
        }
    }

    private func applySearchResult(_ result: SearchResultSet, prepared: CommandBarPreparedSearch) {
        guard state.isVisible, result.sequence.value == searchSequence else { return }
        guard result.generation == resultSession.currentRowGeneration else {
            let currentGeneration = resultSession.currentRowGeneration
            guard lastResubmittedGeneration != currentGeneration else { return }
            lastResubmittedGeneration = currentGeneration
            queryChanged(text: state.rawInput)
            return
        }
        guard result.outcome != .obsolete else { return }

        let prioritiesByGroup = Dictionary(
            uniqueKeysWithValues: prepared.documentSet.groups.map { ($0.id, $0.priority) }
        )
        var titleMatchesByItemId: [String: Range<Int>] = [:]
        let groups = result.groups.compactMap { resultGroup -> CommandBarItemGroup? in
            let items = resultGroup.matches.compactMap { match -> CommandBarItem? in
                guard let item = prepared.rowsById[match.itemId], isSearchItemAvailable(item) else { return nil }
                titleMatchesByItemId[item.id] = match.titleMatch
                return item
            }
            guard !items.isEmpty else { return nil }
            return CommandBarItemGroup(
                id: resultGroup.groupId,
                name: resultGroup.groupId,
                priority: prioritiesByGroup[resultGroup.groupId] ?? 0,
                items: items
            )
        }
        let displayedItems = groups.flatMap(\.items)
        resultSession.reconcileSelection(displayedItems: displayedItems, state: state)
        state.appliedSearchResult = CommandBarAppliedSearchResult(
            sequence: result.sequence,
            generation: result.generation,
            itemSnapshot: prepared.itemSnapshot,
            groups: groups,
            displayedItems: displayedItems,
            titleMatchesByItemId: titleMatchesByItemId,
            dimmedItemIds: resultSession.dimmedItemIds(in: displayedItems),
            canOpenWorktreeInCurrentTab: prepared.canOpenWorktreeInCurrentTab,
            focusedPane: prepared.focusedPane,
            commandContext: prepared.commandContext
        )
    }

    private func isSearchItemAvailable(_ item: CommandBarItem) -> Bool {
        let topology = store.repositoryTopologyAtom
        switch item.action {
        case .navigateRepo(let repositoryId):
            return topology.repo(repositoryId) != nil && !topology.isRepoUnavailable(repositoryId)
        case .worktreeAction(let presence):
            return topology.validatedAssociation(repoId: presence.repoId, worktreeId: presence.worktreeId) != nil
                && !topology.isRepoUnavailable(presence.repoId)
                && !topology.isWorktreeUnavailable(presence.worktreeId)
        case .dispatchTargeted(_, let target, let targetType) where targetType == .repo:
            return topology.repo(target) != nil && !topology.isRepoUnavailable(target)
        case .dispatchTargeted(_, let target, let targetType) where targetType == .worktree:
            guard let repository = topology.repo(containing: target) else { return false }
            return !topology.isRepoUnavailable(repository.id) && !topology.isWorktreeUnavailable(target)
        case .quickOpen(.repository(let stableKey)), .activateRecent(.repository(let stableKey)):
            guard let repository = topology.repo(stableKey: stableKey) else { return false }
            return !topology.isRepoUnavailable(repository.id)
        case .quickOpen(.worktree(let stableKey)), .activateRecent(.worktree(let stableKey)):
            guard let worktree = topology.worktree(stableKey: stableKey),
                let repository = topology.repo(containing: worktree.id)
            else { return false }
            return !topology.isRepoUnavailable(repository.id) && !topology.isWorktreeUnavailable(worktree.id)
        default:
            return true
        }
    }

    func searchContextChanged() {
        resultSession.navigationChanged()
        state.appliedSearchResult = nil
        queryChanged(text: state.rawInput)
    }

}
