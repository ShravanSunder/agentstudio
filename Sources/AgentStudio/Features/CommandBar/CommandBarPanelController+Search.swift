import AgentStudioCore
import AgentStudioInfrastructure

struct CommandBarSearchMeasurement {
    let sequence: SearchRequestSequence
    let generation: SearchDocumentGeneration
    let inputAtNanoseconds: UInt64
    let submittedAtNanoseconds: UInt64
    let queryCharacterCount: Int
    var applyFinishedAtNanoseconds: UInt64?
    var outcome: String?
}

@MainActor
extension CommandBarPanelController {
    func queryChanged(text _: String, inputAtNanoseconds: UInt64? = nil) {
        let inputAt = inputAtNanoseconds ?? searchNowNanoseconds()
        recordSupersededSearch(at: inputAt)
        searchSequence += 1
        pendingSearchTask?.cancel()
        pendingSearchTask = nil

        guard state.isVisible else { return }
        let query = state.isNested ? state.searchQuery : state.normalizedRootQuery
        if state.currentLevel?.textEntry == nil {
            let prepared = resultSession.prepareSearch(state: state)
            if scheduledInstallGeneration != prepared.documentSet.generation {
                scheduledInstallGeneration = prepared.documentSet.generation
                pendingGenerationInstallTask = Task { [searchService, documentSet = prepared.documentSet] in
                    await searchService.install(documentSet)
                }
            }
        }
        if query.isEmpty || state.currentLevel?.textEntry != nil {
            state.appliedSearchResult = nil
            return
        }

        let prepared = resultSession.prepareSearch(state: state)
        let submittedAt = searchNowNanoseconds()
        let sequence = SearchRequestSequence(searchSequence)
        currentSearchMeasurement = CommandBarSearchMeasurement(
            sequence: sequence,
            generation: prepared.documentSet.generation,
            inputAtNanoseconds: inputAt,
            submittedAtNanoseconds: submittedAt,
            queryCharacterCount: query.count
        )
        let request = SearchRequest(
            sequence: sequence,
            text: query,
            recentItemIds: state.recentItemIds.compactMap(SearchItemId.init),
            documentSet: prepared.documentSet,
            submittedAtNanoseconds: submittedAt
        )
        let installTask = pendingGenerationInstallTask
        pendingSearchTask = Task { [weak self, searchService] in
            await installTask?.value
            let answer = await searchService.search(request)
            self?.applySearchResult(answer, prepared: prepared)
        }
        recordSearchStage(
            "submit",
            sequence: sequence,
            generation: prepared.documentSet.generation,
            durationNanoseconds: elapsed(from: inputAt, to: searchNowNanoseconds()),
            queryCharacterCount: query.count
        )
    }

    private func applySearchResult(_ result: SearchResultSet, prepared: CommandBarPreparedSearch) {
        let applyStarted = searchNowNanoseconds()
        guard state.isVisible, result.sequence.value == searchSequence else { return }
        guard result.generation == resultSession.currentRowGeneration else {
            recordSearchOutcome("obsolete", result: result)
            currentSearchMeasurement = nil
            let currentGeneration = resultSession.currentRowGeneration
            guard lastResubmittedGeneration != currentGeneration else { return }
            lastResubmittedGeneration = currentGeneration
            queryChanged(text: state.rawInput)
            return
        }
        guard result.outcome != .obsolete else {
            recordSearchOutcome("obsolete", result: result)
            currentSearchMeasurement = nil
            return
        }
        if let actorFinished = result.actorFinishedAtNanoseconds {
            recordSearchStage(
                "wait_for_main",
                sequence: result.sequence,
                generation: result.generation,
                durationNanoseconds: elapsed(from: actorFinished, to: applyStarted)
            )
        }

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
        let applyFinished = searchNowNanoseconds()
        let outcome = result.outcome == .answered ? "answered" : "degraded"
        recordSearchStage(
            "apply",
            sequence: result.sequence,
            generation: result.generation,
            durationNanoseconds: elapsed(from: applyStarted, to: applyFinished),
            outcome: outcome,
            resultCount: displayedItems.count
        )
        if currentSearchMeasurement?.sequence == result.sequence {
            currentSearchMeasurement?.applyFinishedAtNanoseconds = applyFinished
            currentSearchMeasurement?.outcome = outcome
        }
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

    func acknowledgeResultPublished(
        sequence: SearchRequestSequence,
        generation: SearchDocumentGeneration
    ) {
        guard state.appliedSearchResult?.sequence == sequence,
            state.appliedSearchResult?.generation == generation
        else { return }
        let publication = CommandBarPublicationIdentity(sequence: sequence, generation: generation)
        guard lastAcknowledgedPublication != publication else { return }
        lastAcknowledgedPublication = publication
        guard let measurement = currentSearchMeasurement,
            measurement.sequence == sequence,
            measurement.generation == generation,
            let applyFinished = measurement.applyFinishedAtNanoseconds
        else { return }
        let publishedAt = searchNowNanoseconds()
        recordSearchStage(
            "publication",
            sequence: sequence,
            generation: generation,
            durationNanoseconds: elapsed(from: applyFinished, to: publishedAt),
            outcome: measurement.outcome
        )
        recordSearchStage(
            "end_to_end",
            sequence: sequence,
            generation: generation,
            durationNanoseconds: elapsed(from: measurement.inputAtNanoseconds, to: publishedAt),
            outcome: measurement.outcome,
            queryCharacterCount: measurement.queryCharacterCount,
            resultCount: state.appliedSearchResult?.displayedItems.count
        )
        if let invalidatedAt = resultSession.consumeTopologyInvalidation(for: generation) {
            let freshnessStarted = max(invalidatedAt, measurement.submittedAtNanoseconds)
            recordSearchStage(
                "freshness",
                sequence: sequence,
                generation: generation,
                durationNanoseconds: elapsed(from: freshnessStarted, to: publishedAt)
            )
        }
        currentSearchMeasurement = nil
    }

    func recordSupersededSearch(at nowNanoseconds: UInt64) {
        guard let measurement = currentSearchMeasurement else { return }
        recordSearchStage(
            "outcome",
            sequence: measurement.sequence,
            generation: measurement.generation,
            durationNanoseconds: elapsed(from: measurement.inputAtNanoseconds, to: nowNanoseconds),
            outcome: "superseded"
        )
        currentSearchMeasurement = nil
    }

    private func recordSearchOutcome(_ outcome: String, result: SearchResultSet) {
        recordSearchStage(
            "outcome",
            sequence: result.sequence,
            generation: result.generation,
            durationNanoseconds: 0,
            outcome: outcome
        )
    }

    private func recordSearchStage(
        _ stage: String,
        sequence: SearchRequestSequence,
        generation: SearchDocumentGeneration,
        durationNanoseconds: UInt64,
        outcome: String? = nil,
        queryCharacterCount: Int? = nil,
        resultCount: Int? = nil
    ) {
        guard let performanceTraceRecorder else { return }
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.performance.commandbar.search.stage": .string(stage),
            "agentstudio.performance.commandbar.search.sequence": .int(Int(clamping: sequence.value)),
            "agentstudio.performance.commandbar.search.generation": .int(Int(clamping: generation.value)),
        ]
        if let outcome {
            attributes["agentstudio.performance.commandbar.search.outcome"] = .string(outcome)
        }
        if let queryCharacterCount {
            attributes["agentstudio.performance.commandbar.query_character.count"] = .int(queryCharacterCount)
        }
        if let resultCount {
            attributes["agentstudio.performance.commandbar.result.count"] = .int(resultCount)
        }
        performanceTraceRecorder.recordDuration(
            .commandBarSearch,
            duration: .nanoseconds(Int64(clamping: durationNanoseconds)),
            attributes: attributes
        )
    }

    private func elapsed(from start: UInt64, to end: UInt64) -> UInt64 {
        end >= start ? end - start : 0
    }
}
