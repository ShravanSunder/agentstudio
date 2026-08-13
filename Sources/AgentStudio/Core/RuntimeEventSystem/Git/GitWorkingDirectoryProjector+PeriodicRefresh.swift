import AgentStudioInfrastructure
import Foundation

extension GitWorkingDirectoryProjector {
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

        let uncoveredWorktreeIds = newlyVisibleWorktreeIds.filter { worktreeId in
            registeredContext(for: worktreeId) != nil
                && lastStatusEntriesByWorktreeId[worktreeId] == nil
                && pendingByWorktreeId[worktreeId] != nil
                && worktreeTasks[worktreeId] == nil
        }
        let runningVisibleCount = worktreeTasks.keys.filter {
            demandTier(for: $0) == .visibleSidebar
        }.count
        let globalAvailableSlotCount = max(
            0,
            refreshPolicy.maxConcurrentStatusComputes - worktreeTasks.count
        )
        let visibleAvailableSlotCount = max(
            0,
            refreshPolicy.visibleSidebarMaxConcurrent - runningVisibleCount
        )
        let promptAdmissionCount = min(
            uncoveredWorktreeIds.count,
            globalAvailableSlotCount,
            visibleAvailableSlotCount
        )
        let promptlyAdmittedWorktreeIds = Set(
            uncoveredWorktreeIds
                .sorted(by: { $0.uuidString < $1.uuidString })
                .prefix(promptAdmissionCount)
        )
        for worktreeId in promptlyAdmittedWorktreeIds {
            tierEligibleWorktreeIds.insert(worktreeId)
            refreshAttribution.triggerSourceByWorktreeId[worktreeId] = .visibilityChange
        }

        let tierDeferredWorktreeIds =
            newlyVisibleWorktreeIds
            .subtracting(promptlyAdmittedWorktreeIds)
        recordVisibilityAdmissionTelemetry(
            worktreeIds: promptlyAdmittedWorktreeIds,
            outcome: .admittedUncovered
        )
        recordVisibilityAdmissionTelemetry(
            worktreeIds: tierDeferredWorktreeIds,
            outcome: .tierDeferred
        )
        if !promptlyAdmittedWorktreeIds.isEmpty {
            recordVisibilityAdmissionTelemetry(
                worktreeIds: promptlyAdmittedWorktreeIds,
                outcome: .batched
            )
            admitPendingWorktrees()
        }
    }

    func startPeriodicRefreshLoopIfNeeded() {
        guard let periodicRefreshInterval, periodicRefreshInterval > .zero else { return }
        guard periodicRefreshTask == nil else { return }

        let delay = self.delay
        periodicRefreshTask = Task { [weak self, delay, periodicRefreshInterval] in
            while !Task.isCancelled {
                do {
                    try await delay.wait(periodicRefreshInterval)
                } catch is CancellationError {
                    return
                } catch {
                    Self.logger.warning(
                        "Unexpected periodic git refresh sleep failure: \(String(describing: error), privacy: .public)"
                    )
                    continue
                }
                guard !Task.isCancelled, let self else { return }
                await self.enqueuePeriodicRefreshes()
            }
        }
    }

    private func enqueuePeriodicRefreshes() {
        defer { periodicRefreshTick &+= 1 }
        guard !rootPathByWorktreeId.isEmpty else { return }
        grantPeriodicTierEligibility()

        var enqueuedWorktreeIds: [UUID] = []
        for worktreeId in rootPathByWorktreeId.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard !suppressedWorktreeIds.contains(worktreeId) else { continue }
            guard !quarantinedWorktreeIds.contains(worktreeId) else { continue }
            guard !openStatusBackoffWorktreeIds.contains(worktreeId) else { continue }
            guard pendingByWorktreeId[worktreeId] == nil else { continue }
            guard isDemandEligible(worktreeId: worktreeId) else { continue }
            guard isPeriodicRefreshDue(worktreeId: worktreeId) else { continue }
            guard let repoId = repoIdByWorktreeId[worktreeId] else { continue }
            guard let rootPath = rootPathByWorktreeId[worktreeId] else { continue }

            let nextBatchSeq = (nextPeriodicBatchSeqByWorktreeId[worktreeId] ?? 0) + 1
            nextPeriodicBatchSeqByWorktreeId[worktreeId] = nextBatchSeq
            pendingByWorktreeId[worktreeId] = FileChangeset(
                worktreeId: worktreeId,
                repoId: repoId,
                rootPath: rootPath,
                paths: [],
                containsGitInternalChanges: true,
                timestamp: envelopeClock.now,
                batchSeq: nextBatchSeq
            )
            refreshAttribution.triggerSourceByWorktreeId[worktreeId] = .periodic
            enqueuedWorktreeIds.append(worktreeId)
        }
        recordPeriodicRefreshTickTelemetry(
            enqueuedWorktreeIds: enqueuedWorktreeIds,
            registeredCount: rootPathByWorktreeId.count,
            pendingCount: pendingByWorktreeId.count,
            tick: periodicRefreshTick
        )
        admitPendingWorktrees()
    }

    private func isPeriodicRefreshDue(worktreeId: UUID) -> Bool {
        guard let lastAdmissionTick = lastPeriodicAdmissionTickByWorktreeId[worktreeId] else { return true }
        let interval = refreshPolicy.cadenceTickInterval(
            for: demandTier(for: worktreeId).cadence(in: refreshPolicy),
            unchangedResultCount: unchangedStatusResultCountByWorktreeId[worktreeId] ?? 0
        )
        return periodicRefreshTick >= lastAdmissionTick + interval
    }

    private func grantPeriodicTierEligibility() {
        if refreshPolicy.isCadenceDue(refreshPolicy.visibleSidebarCadence, tick: periodicRefreshTick) {
            grantNextVisibleSidebarStripe(candidates: sidebarVisibleWorktreeIds)
        }
        if refreshPolicy.isCadenceDue(refreshPolicy.openPaneCadence, tick: periodicRefreshTick) {
            tierEligibleWorktreeIds.formUnion(activeWorktreeIds)
        }
        let backgroundWorktreeIds = Set(rootPathByWorktreeId.keys)
            .subtracting(activeWorktreeIds)
            .subtracting(sidebarVisibleWorktreeIds)
            .subtracting(activePaneWorktreeId.map { [$0] } ?? [])
        tierEligibleWorktreeIds.formUnion(
            backgroundWorktreeIds.filter {
                refreshPolicy.isBackgroundWorktreeDue($0, tick: periodicRefreshTick)
            }
        )
    }

    func grantNextVisibleSidebarStripe(candidates: Set<UUID>) {
        let orderedCandidates = candidates.sorted(by: { $0.uuidString < $1.uuidString })
        guard !orderedCandidates.isEmpty else { return }
        let startIndex = visibleSidebarStripeCursor % orderedCandidates.count
        let stripeCount = min(refreshPolicy.visibleSidebarStripeSize, orderedCandidates.count)
        for offset in 0..<stripeCount {
            tierEligibleWorktreeIds.insert(orderedCandidates[(startIndex + offset) % orderedCandidates.count])
        }
        visibleSidebarStripeCursor = (startIndex + stripeCount) % orderedCandidates.count
    }

    func resetAdaptiveCadence(worktreeId: UUID) {
        unchangedStatusResultCountByWorktreeId.removeValue(forKey: worktreeId)
        lastPeriodicAdmissionTickByWorktreeId.removeValue(forKey: worktreeId)
    }
}
