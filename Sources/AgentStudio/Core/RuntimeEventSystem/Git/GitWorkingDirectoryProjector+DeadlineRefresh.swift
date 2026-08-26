import AgentStudioInfrastructure
import Foundation

extension GitWorkingDirectoryProjector {
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
            worktreeIds: newlyVisibleWorktreeIds.subtracting(promptlyScheduledWorktreeIds),
            outcome: .tierDeferred
        )
        if !newlyVisibleWorktreeIds.isEmpty {
            recordVisibilityAdmissionTelemetry(
                worktreeIds: newlyVisibleWorktreeIds,
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

    private func handleDeadlineWake(generation: UInt64) {
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
                guard prepareAutomaticRefreshIfCurrent(worktreeId: entry.worktreeId) else { continue }
                tierEligibleWorktreeIds.insert(entry.worktreeId)
            case .failure:
                expireStatusBackoff(worktreeId: entry.worktreeId)
            case .capacityFallback:
                expireCapacityRetry(worktreeId: entry.worktreeId)
            }
        }
        admitPendingWorktrees()
        rescheduleDeadlineTask()
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
