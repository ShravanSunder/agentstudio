import Foundation

/// Admission policy for pending status computes: decides which pending
/// worktrees get the bounded compute slots each cycle. The reserved lane
/// serves the active-pane worktree first, then the oldest-stale background
/// worktrees, so foreground panes cannot starve behind a large background
/// fleet. Split from the projector actor body to keep it under the
/// type/file length caps.
extension GitWorkingDirectoryProjector {
    func admitPendingWorktrees() {
        guard !isShuttingDown else { return }
        quarantineDeadPathPendingWorktrees()
        let availableSlots = refreshPolicy.maxConcurrentStatusComputes - worktreeTasks.count
        guard availableSlots > 0 else { return }

        let eligibleWorktreeIds = pendingByWorktreeId.keys.filter { worktreeId in
            worktreeTasks[worktreeId] == nil
                && !suppressedWorktreeIds.contains(worktreeId)
                && !quarantinedWorktreeIds.contains(worktreeId)
                && !capacityRetryWorktreeIds.contains(worktreeId)
        }
        guard !eligibleWorktreeIds.isEmpty else { return }

        var admittedWorktreeIds: [UUID] = []
        let reservedSlotCount = min(refreshPolicy.oldestStaleReservedSlots, availableSlots)
        if reservedSlotCount > 0 {
            if let activePaneWorktreeId, eligibleWorktreeIds.contains(activePaneWorktreeId) {
                admittedWorktreeIds.append(activePaneWorktreeId)
            }
            let remainingReservedSlotCount = reservedSlotCount - admittedWorktreeIds.count
            if remainingReservedSlotCount > 0 {
                admittedWorktreeIds.append(
                    contentsOf:
                        eligibleWorktreeIds
                        .filter { priorityKey(for: $0) == 3 }
                        .sorted(by: sortPendingWorktreeByStaleness)
                        .prefix(remainingReservedSlotCount)
                )
            }
        }

        let remainingSlotCount = availableSlots - admittedWorktreeIds.count
        if remainingSlotCount > 0 {
            let alreadyAdmitted = Set(admittedWorktreeIds)
            admittedWorktreeIds.append(
                contentsOf:
                    eligibleWorktreeIds
                    .filter { !alreadyAdmitted.contains($0) }
                    .sorted(by: sortPendingWorktreeByPriority)
                    .prefix(remainingSlotCount)
            )
        }

        for worktreeId in admittedWorktreeIds {
            startDrainTask(worktreeId: worktreeId)
        }
        guard !admittedWorktreeIds.isEmpty else { return }
        recordGitAdmissionTelemetry(
            admittedWorktreeIds: admittedWorktreeIds,
            availableSlots: availableSlots
        )
    }

    private func sortPendingWorktreeByPriority(_ lhs: UUID, _ rhs: UUID) -> Bool {
        let lhsPriority = priorityKey(for: lhs)
        let rhsPriority = priorityKey(for: rhs)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        return lhs.uuidString < rhs.uuidString
    }

    private func sortPendingWorktreeByStaleness(_ lhs: UUID, _ rhs: UUID) -> Bool {
        guard let lhsChangeset = pendingByWorktreeId[lhs] else { return false }
        guard let rhsChangeset = pendingByWorktreeId[rhs] else { return true }
        if lhsChangeset.timestamp != rhsChangeset.timestamp {
            return lhsChangeset.timestamp < rhsChangeset.timestamp
        }
        if lhsChangeset.batchSeq != rhsChangeset.batchSeq {
            return lhsChangeset.batchSeq < rhsChangeset.batchSeq
        }
        return lhs.uuidString < rhs.uuidString
    }

    private func priorityKey(for worktreeId: UUID) -> Int {
        if activePaneWorktreeId == worktreeId {
            return 0
        }
        if sidebarVisibleWorktreeIds.contains(worktreeId) {
            return 1
        }
        if activeWorktreeIds.contains(worktreeId) {
            return 2
        }
        return 3
    }
}
