import Foundation

/// Dead-path quarantine: a registered worktree whose root directory has vanished
/// from disk keeps failing its git status compute (`sdk_error`) forever, burning
/// the global concurrent-status budget that live worktrees need. Instead of
/// deleting such a worktree, the projector quarantines it: the worktree is skipped
/// at admission and at periodic re-enqueue without any further per-tick stat call,
/// and it is re-armed only by an event that implies the path may have returned
/// (a file-change from the watcher, or a registration/context-change). Split from
/// the projector actor body to keep it under the type/file length caps.
extension GitWorkingDirectoryProjector {
    /// Live filesystem probe wired at the production composition root and reused by
    /// quarantine tests against real temp directories. The projector's own default
    /// is permissive so unit tests that register synthetic paths stay unaffected.
    static let liveRootPathProbe: @Sendable (URL) -> Bool = { rootPath in
        FileManager.default.fileExists(atPath: rootPath.path)
    }

    /// Quarantines any pending worktree whose root path no longer exists. Runs at
    /// the top of the admission cycle so dead worktrees never reach a drain task.
    /// Already-quarantined worktrees are excluded from the candidate set, so they
    /// incur no repeated stat calls; each dead worktree is stat-checked exactly
    /// once per admission it would otherwise have been eligible for.
    func quarantineDeadPathPendingWorktrees() {
        // Materialize candidates before mutating `pendingByWorktreeId` to avoid
        // mutating the dictionary while iterating its keys.
        let candidateWorktreeIds = pendingByWorktreeId.keys.filter { worktreeId in
            worktreeTasks[worktreeId] == nil
                && !suppressedWorktreeIds.contains(worktreeId)
                && !quarantinedWorktreeIds.contains(worktreeId)
        }
        for worktreeId in candidateWorktreeIds {
            guard let rootPath = pendingByWorktreeId[worktreeId]?.rootPath else { continue }
            guard !pathExistenceProbe(rootPath) else { continue }
            quarantineWorktreePath(worktreeId: worktreeId)
        }
    }

    /// Marks a worktree quarantined: drops its pending refresh so the pending map
    /// does not retain dead entries, and emits a single open fact.
    private func quarantineWorktreePath(worktreeId: UUID) {
        guard quarantinedWorktreeIds.insert(worktreeId).inserted else { return }
        pendingByWorktreeId.removeValue(forKey: worktreeId)
        clearImmediateRefreshIntent(worktreeId: worktreeId)
        emitPathQuarantineTelemetry(worktreeId: worktreeId, quarantined: true)
    }

    /// Event-driven re-arm gate for a file-change on a possibly-quarantined
    /// worktree. Returns whether the change should proceed into the pending map:
    /// - not quarantined: `true` (normal flow, no stat call);
    /// - quarantined and path still missing: `false` (dropped; stays quarantined,
    ///   no telemetry so a persistently-dead path emits exactly one open fact);
    /// - quarantined and path returned: clears the mark, emits the close fact, and
    ///   returns `true` so the worktree recomputes.
    func admitFileChangeAfterQuarantine(worktreeId: UUID, rootPath: URL) -> Bool {
        guard quarantinedWorktreeIds.contains(worktreeId) else { return true }
        guard pathExistenceProbe(rootPath) else { return false }
        clearQuarantineEmittingClose(worktreeId: worktreeId)
        return true
    }

    /// Clears a quarantine mark and emits the close fact. Used on the file-change
    /// re-arm path where the path was confirmed to have returned.
    private func clearQuarantineEmittingClose(worktreeId: UUID) {
        guard quarantinedWorktreeIds.remove(worktreeId) != nil else { return }
        emitPathQuarantineTelemetry(worktreeId: worktreeId, quarantined: false)
    }

    /// Silently drops a quarantine mark for lifecycle transitions (unregistration,
    /// context change) where the old path is no longer the worktree's identity, so
    /// no close fact is warranted. Mirrors the non-emitting `clearStatusBackoffState`.
    func clearQuarantineState(worktreeId: UUID) {
        quarantinedWorktreeIds.remove(worktreeId)
    }

    private func emitPathQuarantineTelemetry(worktreeId: UUID, quarantined: Bool) {
        guard let performanceTraceRecorder else { return }
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.worktree.id": .string(worktreeId.uuidString),
            "agentstudio.performance.git.path_quarantined": .bool(quarantined),
            "agentstudio.performance.git.quarantined.count": .int(quarantinedWorktreeIds.count),
            "agentstudio.performance.git.pending.count": .int(pendingByWorktreeId.count),
            "agentstudio.performance.git.running.count": .int(worktreeTasks.count),
        ]
        if quarantined {
            attributes["agentstudio.performance.git.path_quarantine.reason"] = .string("path_missing")
        }
        performanceTraceRecorder.record(.gitPathQuarantine, attributes: attributes)
    }
}
