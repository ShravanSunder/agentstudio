import AgentStudioInfrastructure
import Foundation

extension GitWorkingDirectoryProjector {
    func isAutomaticEligible(worktreeId: UUID) -> Bool {
        automaticEligibleWorktreeIds?.contains(worktreeId) ?? true
    }

    func setAutomaticEligibleWorktrees(_ nextEligibleWorktreeIds: Set<UUID>) {
        let previousEligibleWorktreeIds =
            automaticEligibleWorktreeIds ?? Set(rootPathByWorktreeId.keys)
        guard automaticEligibleWorktreeIds != nextEligibleWorktreeIds else { return }
        automaticEligibleWorktreeIds = nextEligibleWorktreeIds

        let newlyInactiveWorktreeIds = previousEligibleWorktreeIds.subtracting(nextEligibleWorktreeIds)
        for worktreeId in newlyInactiveWorktreeIds {
            contractInactiveAutomaticState(
                worktreeId: worktreeId,
                preservesRequiredIntent: hasRequiredIntent(worktreeId: worktreeId)
            )
        }

        let newlyEligibleWorktreeIds = nextEligibleWorktreeIds.subtracting(previousEligibleWorktreeIds)
        for worktreeId in newlyEligibleWorktreeIds where registeredContext(for: worktreeId) != nil {
            scheduleAutomaticRefresh(
                worktreeId: worktreeId,
                missingBaseline: lastAcceptedStatusAtByWorktreeId[worktreeId] == nil,
                allowsPromptMissingBaseline: demandTier(for: worktreeId) != .background
            )
        }
        admitPendingWorktrees()
        rescheduleDeadlineTask()
    }

    func contractInactiveAutomaticState(
        worktreeId: UUID,
        preservesRequiredIntent: Bool
    ) {
        let hadAutomaticIntent =
            automaticRefreshDeadlineByWorktreeId[worktreeId] != nil
            || pendingVisibilityDeltaWorktreeIds.contains(worktreeId)
            || pendingByWorktreeId[worktreeId] != nil
            || tierEligibleWorktreeIds.contains(worktreeId)
            || capacityRetryWorktreeIds.contains(worktreeId)
            || openStatusBackoffWorktreeIds.contains(worktreeId)
        automaticRefreshDeadlineByWorktreeId.removeValue(forKey: worktreeId)
        pendingVisibilityDeltaWorktreeIds.remove(worktreeId)
        lastProcessedSidebarVisibleWorktreeIds.remove(worktreeId)
        if preservesRequiredIntent {
            tierEligibleWorktreeIds.insert(worktreeId)
            recordInactiveContractionTelemetry(automaticRemoved: false, requiredRetained: true)
            return
        }
        pendingByWorktreeId.removeValue(forKey: worktreeId)
        clearImmediateRefreshIntent(worktreeId: worktreeId)
        tierEligibleWorktreeIds.remove(worktreeId)
        _ = clearCapacityRetryState(worktreeId: worktreeId)
        clearStatusBackoffState(worktreeId: worktreeId)
        refreshAttribution.triggerSourceByWorktreeId.removeValue(forKey: worktreeId)
        recordInactiveContractionTelemetry(
            automaticRemoved: hadAutomaticIntent,
            requiredRetained: false
        )
    }

    package func setActivity(worktreeId: UUID, isActiveInApp: Bool) {
        if isActiveInApp {
            activeWorktreeIds.insert(worktreeId)
            scheduleAutomaticRefresh(worktreeId: worktreeId, allowsPromptMissingBaseline: true)
        } else {
            activeWorktreeIds.remove(worktreeId)
            if activePaneWorktreeId != worktreeId, !sidebarVisibleWorktreeIds.contains(worktreeId) {
                tierEligibleWorktreeIds.remove(worktreeId)
            }
        }
    }

    package func setActivePaneWorktree(worktreeId: UUID?) {
        let previousActivePaneWorktreeId = activePaneWorktreeId
        activePaneWorktreeId = worktreeId
        if let previousActivePaneWorktreeId,
            previousActivePaneWorktreeId != worktreeId,
            !sidebarVisibleWorktreeIds.contains(previousActivePaneWorktreeId),
            !activeWorktreeIds.contains(previousActivePaneWorktreeId)
        {
            tierEligibleWorktreeIds.remove(previousActivePaneWorktreeId)
        }
        guard let worktreeId else { return }
        scheduleAutomaticRefresh(worktreeId: worktreeId, allowsPromptMissingBaseline: true)
    }

    package func setSidebarVisibleWorktrees(_ worktreeIds: Set<UUID>) {
        guard worktreeIds != sidebarVisibleWorktreeIds else { return }
        let noLongerVisibleWorktreeIds = sidebarVisibleWorktreeIds.subtracting(worktreeIds)
        sidebarVisibleWorktreeIds = worktreeIds
        for worktreeId in noLongerVisibleWorktreeIds
        where activePaneWorktreeId != worktreeId && !activeWorktreeIds.contains(worktreeId) {
            tierEligibleWorktreeIds.remove(worktreeId)
        }
        scheduleCoalescedVisibilityAdmission()
    }

    package func setRepositoryFactAttention(
        activePaneWorktreeId: UUID?,
        sidebarAttendedWorktreeIds: Set<UUID>,
        visibleActiveTabWorktreeIds: Set<UUID>,
        openWorktreeIds: Set<UUID>,
        warmAutomaticWorktreeIds: Set<UUID>? = nil
    ) {
        if let warmAutomaticWorktreeIds {
            setAutomaticEligibleWorktrees(warmAutomaticWorktreeIds)
        }
        let previousAttentionWorktreeIds =
            activeWorktreeIds
            .union(sidebarVisibleWorktreeIds)
            .union(self.activePaneWorktreeId.map { [$0] } ?? [])
        let nextOpenWorktreeIds = openWorktreeIds.union(visibleActiveTabWorktreeIds)
        let nextAttentionWorktreeIds =
            nextOpenWorktreeIds
            .union(sidebarAttendedWorktreeIds)
            .union(activePaneWorktreeId.map { [$0] } ?? [])
        let newlyAttendedWorktreeIds = nextAttentionWorktreeIds.subtracting(previousAttentionWorktreeIds)
        let noLongerAttendedWorktreeIds = previousAttentionWorktreeIds.subtracting(nextAttentionWorktreeIds)

        self.activePaneWorktreeId = activePaneWorktreeId
        activeWorktreeIds = nextOpenWorktreeIds
        sidebarVisibleWorktreeIds = sidebarAttendedWorktreeIds

        for worktreeId in noLongerAttendedWorktreeIds {
            tierEligibleWorktreeIds.remove(worktreeId)
        }
        for worktreeId in newlyAttendedWorktreeIds {
            scheduleAutomaticRefresh(worktreeId: worktreeId, allowsPromptMissingBaseline: true)
        }
        scheduleCoalescedVisibilityAdmission()
    }

    private enum ExactCleanRenewalDisposition {
        case renewed
        case requiresExact(GitCleanContinuityFailureReason?)
        case stale
    }

    package func waitForVisibilityAdmission() async {
        while let activeTask = visibilityAdmissionTask {
            await activeTask.value
        }
    }

    func scheduleCoalescedVisibilityAdmission() {
        if visibilityAdmissionTask != nil {
            recordVisibilityAdmissionTelemetry(
                worktreeIds: pendingVisibilityDeltaWorktreeIds,
                outcome: .superseded
            )
        }
        visibilityAdmissionTask?.cancel()
        pendingVisibilityDeltaWorktreeIds =
            sidebarVisibleWorktreeIds
            .subtracting(lastProcessedSidebarVisibleWorktreeIds)
            .filter(isAutomaticEligible(worktreeId:))

        let delay = self.delay
        let coalescingWindow = AppPolicies.GitRefresh.visibilityChangeCoalescingWindow
        visibilityAdmissionTask = Task { [weak self, delay, coalescingWindow] in
            do {
                try await delay.wait(coalescingWindow)
            } catch is CancellationError {
                return
            } catch {
                Self.logger.warning(
                    "Unexpected visibility-admission sleep failure: \(String(describing: error), privacy: .public)"
                )
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applyCoalescedVisibilityAdmission()
        }
    }

    private func applyCoalescedVisibilityAdmission() {
        visibilityAdmissionTask = nil
        let newlyVisibleWorktreeIds =
            sidebarVisibleWorktreeIds
            .subtracting(lastProcessedSidebarVisibleWorktreeIds)
            .filter(isAutomaticEligible(worktreeId:))
        lastProcessedSidebarVisibleWorktreeIds = sidebarVisibleWorktreeIds
        pendingVisibilityDeltaWorktreeIds.removeAll(keepingCapacity: false)

        let uncoveredWorktreeIds = Set(
            newlyVisibleWorktreeIds.filter { worktreeId in
                registeredContext(for: worktreeId) != nil
                    && lastAcceptedStatusAtByWorktreeId[worktreeId] == nil
            })
        let runningVisibleCount = admittedDemandTierByWorktreeId.values.filter { $0 == .visibleSidebar }.count
        let promptAdmissionCount = min(
            uncoveredWorktreeIds.count,
            max(0, refreshPolicy.maxConcurrentStatusComputes - worktreeTasks.count),
            max(0, refreshPolicy.visibleSidebarMaxConcurrent - runningVisibleCount)
        )
        let promptlyScheduledWorktreeIds = Set(
            uncoveredWorktreeIds
                .sorted(by: { $0.uuidString < $1.uuidString })
                .prefix(promptAdmissionCount)
        )
        for worktreeId in newlyVisibleWorktreeIds {
            refreshAttribution.triggerSourceByWorktreeId[worktreeId] = .visibilityChange
            scheduleAutomaticRefresh(
                worktreeId: worktreeId,
                missingBaseline: uncoveredWorktreeIds.contains(worktreeId),
                allowsPromptMissingBaseline: promptlyScheduledWorktreeIds.contains(worktreeId)
            )
        }
        recordVisibilityAdmissionTelemetry(
            worktreeIds: promptlyScheduledWorktreeIds,
            outcome: .admittedUncovered
        )
        recordVisibilityAdmissionTelemetry(
            worktreeIds: Set(newlyVisibleWorktreeIds).subtracting(promptlyScheduledWorktreeIds),
            outcome: .tierDeferred
        )
        if !newlyVisibleWorktreeIds.isEmpty {
            recordVisibilityAdmissionTelemetry(
                worktreeIds: Set(newlyVisibleWorktreeIds),
                outcome: .batched
            )
        }
    }

    func rescheduleDeadlineTask() {
        deadlineTaskGeneration &+= 1
        let generation = deadlineTaskGeneration
        deadlineTask?.cancel()
        deadlineTask = nil
        recordLogicalDebtSnapshotIfChanged()
        guard !isShuttingDown, let earliestDeadline = earliestRefreshDeadline else { return }

        let deadlineClock = self.deadlineClock
        deadlineTask = Task { [weak self, deadlineClock] in
            do {
                try await deadlineClock.sleep(until: earliestDeadline)
            } catch is CancellationError {
                return
            } catch {
                Self.logger.warning(
                    "Unexpected Git deadline sleep failure: \(String(describing: error), privacy: .public)"
                )
                return
            }
            guard !Task.isCancelled else { return }
            await self?.handleDeadlineWake(generation: generation)
        }
    }

    private var earliestRefreshDeadline: Duration? {
        while let first = deadlineQueue.first {
            guard isCurrentDeadline(first) else {
                deadlineQueue.removeFirst()
                continue
            }
            return first.deadline
        }
        return nil
    }

    private func handleDeadlineWake(generation: UInt64) async {
        guard generation == deadlineTaskGeneration, !isShuttingDown else { return }
        deadlineTask = nil
        let now = deadlineClock.now

        while let entry = deadlineQueue.first, entry.deadline <= now {
            deadlineQueue.removeFirst()
            guard isCurrentDeadline(entry) else { continue }
            switch entry.kind {
            case .automatic:
                automaticRefreshDeadlineByWorktreeId.removeValue(forKey: entry.worktreeId)
                guard admitAutomaticRefreshAfterQuarantine(worktreeId: entry.worktreeId) else { continue }
                switch await renewExactCleanAuthorityIfCurrent(
                    worktreeId: entry.worktreeId,
                    deadlineGeneration: generation
                ) {
                case .renewed, .stale:
                    continue
                case .requiresExact(let uncertaintyReason):
                    let admitted = prepareAutomaticRefreshIfCurrent(worktreeId: entry.worktreeId)
                    if let uncertaintyReason {
                        recordContinuityUncertaintyTelemetry(uncertaintyReason)
                        recordExactFallbackTelemetry(admitted: admitted)
                    }
                    guard admitted else { continue }
                    tierEligibleWorktreeIds.insert(entry.worktreeId)
                    continue
                }
            case .failure:
                expireStatusBackoff(worktreeId: entry.worktreeId)
            case .capacityFallback:
                expireCapacityRetry(worktreeId: entry.worktreeId)
            }
        }
        admitPendingWorktrees()
        rescheduleDeadlineTask()
    }

    private func renewExactCleanAuthorityIfCurrent(
        worktreeId: UUID,
        deadlineGeneration: UInt64
    ) async -> ExactCleanRenewalDisposition {
        guard !isShuttingDown,
            pendingByWorktreeId[worktreeId] == nil,
            !explicitRefreshWorktreeIds.contains(worktreeId),
            let context = registeredContext(for: worktreeId),
            let authority = exactCleanAuthorityByWorktreeId[worktreeId],
            let exactCleanProvider = gitWorkingTreeProvider as? any GitExactCleanStatusProviding
        else {
            return .requiresExact(nil)
        }

        let renewal = await exactCleanProvider.renewExactCleanAuthority(authority)
        guard !Task.isCancelled,
            !isShuttingDown,
            deadlineTaskGeneration == deadlineGeneration,
            registeredContext(for: worktreeId) == context,
            exactCleanAuthorityByWorktreeId[worktreeId] == authority,
            pendingByWorktreeId[worktreeId] == nil,
            !explicitRefreshWorktreeIds.contains(worktreeId)
        else {
            return .stale
        }

        switch renewal {
        case .renewed(let renewedAuthority):
            exactCleanAuthorityByWorktreeId[worktreeId] = renewedAuthority
            let acceptedAt = deadlineClock.now
            lastAcceptedStatusAtByWorktreeId[worktreeId] = acceptedAt
            lastAcceptedLineDetailAtByWorktreeId[worktreeId] = acceptedAt
            unchangedStatusResultCountByWorktreeId[worktreeId, default: 0] += 1
            scheduleAutomaticRefresh(worktreeId: worktreeId)
            recordExactCleanContinuityRenewedTelemetry()
            return .renewed
        case .requiresExact(let reason):
            exactCleanAuthorityByWorktreeId.removeValue(forKey: worktreeId)
            return .requiresExact(reason)
        }
    }

    func setRefreshDeadline(
        _ deadline: Duration,
        kind: GitRefreshDeadlineKind,
        worktreeId: UUID
    ) {
        switch kind {
        case .automatic:
            guard automaticRefreshDeadlineByWorktreeId[worktreeId] != deadline else { return }
            automaticRefreshDeadlineByWorktreeId[worktreeId] = deadline
        case .failure:
            guard statusFailureDeadlineByWorktreeId[worktreeId] != deadline else { return }
            statusFailureDeadlineByWorktreeId[worktreeId] = deadline
        case .capacityFallback:
            guard capacityFallbackDeadlineByWorktreeId[worktreeId] != deadline else { return }
            capacityFallbackDeadlineByWorktreeId[worktreeId] = deadline
        }
        deadlineQueue.insert(
            GitRefreshDeadlineEntry(deadline: deadline, kind: kind, worktreeId: worktreeId)
        )
    }

    private func isCurrentDeadline(_ entry: GitRefreshDeadlineEntry) -> Bool {
        switch entry.kind {
        case .automatic:
            automaticRefreshDeadlineByWorktreeId[entry.worktreeId] == entry.deadline
        case .failure:
            statusFailureDeadlineByWorktreeId[entry.worktreeId] == entry.deadline
        case .capacityFallback:
            capacityFallbackDeadlineByWorktreeId[entry.worktreeId] == entry.deadline
        }
    }

    @discardableResult
    private func prepareAutomaticRefreshIfCurrent(worktreeId: UUID) -> Bool {
        guard isAutomaticEligible(worktreeId: worktreeId) else { return false }
        guard !suppressedWorktreeIds.contains(worktreeId) else { return false }
        guard !quarantinedWorktreeIds.contains(worktreeId) else { return false }
        guard !openStatusBackoffWorktreeIds.contains(worktreeId) else { return false }
        guard let context = registeredContext(for: worktreeId) else { return false }
        var createdPeriodicIntent = false
        if pendingByWorktreeId[worktreeId] == nil {
            let nextBatchSeq = (nextPeriodicBatchSeqByWorktreeId[worktreeId] ?? 0) + 1
            nextPeriodicBatchSeqByWorktreeId[worktreeId] = nextBatchSeq
            pendingByWorktreeId[worktreeId] = FileChangeset(
                worktreeId: worktreeId,
                repoId: context.repoId,
                rootPath: context.rootPath,
                paths: [],
                containsGitInternalChanges: true,
                timestamp: envelopeClock.now,
                batchSeq: nextBatchSeq
            )
            createdPeriodicIntent = true
        }
        if createdPeriodicIntent {
            refreshAttribution.triggerSourceByWorktreeId[worktreeId] = .periodic
        }
        return true
    }

    func scheduleAutomaticRefresh(
        worktreeId: UUID,
        missingBaseline: Bool = false,
        allowsPromptMissingBaseline: Bool = false
    ) {
        guard registeredContext(for: worktreeId) != nil else { return }
        guard isAutomaticEligible(worktreeId: worktreeId) else {
            automaticRefreshDeadlineByWorktreeId.removeValue(forKey: worktreeId)
            rescheduleDeadlineTask()
            return
        }
        if missingBaseline || lastAcceptedStatusAtByWorktreeId[worktreeId] == nil,
            allowsPromptMissingBaseline
        {
            automaticRefreshDeadlineByWorktreeId.removeValue(forKey: worktreeId)
            if prepareAutomaticRefreshIfCurrent(worktreeId: worktreeId) {
                immediateRefreshWorktreeIds.insert(worktreeId)
                tierEligibleWorktreeIds.insert(worktreeId)
                admitPendingWorktrees()
            }
            rescheduleDeadlineTask()
            return
        }
        let now = deadlineClock.now
        let tier = demandTier(for: worktreeId)
        let candidate: Duration
        if missingBaseline || lastAcceptedStatusAtByWorktreeId[worktreeId] == nil {
            candidate =
                tier == .activePane || allowsPromptMissingBaseline
                ? now
                : now
                    + refreshPolicy.registrationPhaseDelay(
                        for: worktreeId,
                        cadence: tier.cadence(in: refreshPolicy)
                    )
        } else {
            let cadence = refreshPolicy.adaptiveCadence(
                base: tier.cadence(in: refreshPolicy),
                unchangedResultCount: unchangedStatusResultCountByWorktreeId[worktreeId] ?? 0
            )
            let statusAcceptedAt = lastAcceptedStatusAtByWorktreeId[worktreeId] ?? now
            let lastStart = lastAutomaticStartAtByWorktreeId[worktreeId] ?? statusAcceptedAt
            let lastCompletion = lastAutomaticCompletionAtByWorktreeId[worktreeId] ?? statusAcceptedAt
            let dutyGap = refreshPolicy.automaticDutyGap(
                for: lastAutomaticDutyByWorktreeId[worktreeId] ?? .zero
            )
            let statusDeadline = max(lastStart + cadence, lastCompletion + dutyGap)
            let detailDeadline =
                lastAcceptedLineDetailAtByWorktreeId[worktreeId].map {
                    $0 + refreshPolicy.lineDetailFreshnessInterval
                } ?? now
            candidate = min(statusDeadline, detailDeadline)
        }
        if let existing = automaticRefreshDeadlineByWorktreeId[worktreeId] {
            setRefreshDeadline(min(existing, candidate), kind: .automatic, worktreeId: worktreeId)
        } else {
            setRefreshDeadline(candidate, kind: .automatic, worktreeId: worktreeId)
        }
        rescheduleDeadlineTask()
    }

    func recordAutomaticAdmission(worktreeId: UUID, isExplicit: Bool) {
        automaticRefreshDeadlineByWorktreeId.removeValue(forKey: worktreeId)
        guard !isExplicit else { return }
        let start = deadlineClock.now
        lastAutomaticStartAtByWorktreeId[worktreeId] = start
        if requiresAutomaticStartPacing(worktreeId: worktreeId, isExplicit: false) {
            nextAutomaticStartAt = max(
                nextAutomaticStartAt,
                start + refreshPolicy.minimumAutomaticStartInterval
            )
        }
    }

    func recordAutomaticCompletion(worktreeId: UUID, duty: Duration) {
        let completion = deadlineClock.now
        lastAcceptedStatusAtByWorktreeId[worktreeId] = completion
        lastAutomaticCompletionAtByWorktreeId[worktreeId] = completion
        lastAutomaticDutyByWorktreeId[worktreeId] = duty
        if isPacedAutomaticTrigger(
            refreshAttribution.admittedTriggerSourceByWorktreeId[worktreeId],
            tier: admittedDemandTierByWorktreeId[worktreeId] ?? demandTier(for: worktreeId)
        ) {
            nextAutomaticStartAt = max(
                nextAutomaticStartAt,
                completion + refreshPolicy.automaticDutyGap(for: duty)
            )
        }
        scheduleAutomaticRefresh(worktreeId: worktreeId)
    }

    func requiresAutomaticStartPacing(worktreeId: UUID, isExplicit: Bool) -> Bool {
        guard !isExplicit, refreshPolicy.minimumAutomaticStartInterval > .zero else {
            return false
        }
        return isPacedAutomaticTrigger(
            refreshAttribution.triggerSourceByWorktreeId[worktreeId],
            tier: demandTier(for: worktreeId)
        )
    }

    private func isPacedAutomaticTrigger(
        _ triggerSource: GitRefreshTriggerSource?,
        tier: GitDemandTier
    ) -> Bool {
        switch triggerSource ?? .registration {
        case .registration, .periodic, .visibilityChange, .retry:
            true
        case .filesystemChange, .remoteReferenceRefresh:
            tier != .activePane
        }
    }

    func resetAdaptiveCadence(worktreeId: UUID) {
        unchangedStatusResultCountByWorktreeId.removeValue(forKey: worktreeId)
    }
}
