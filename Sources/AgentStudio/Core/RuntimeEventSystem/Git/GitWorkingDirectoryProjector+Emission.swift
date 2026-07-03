import Foundation

/// Envelope emission for derived git facts: sequences, posts to the runtime
/// bus, and records delivery telemetry. Split from the projector actor body
/// to keep it under the type/file length caps.
extension GitWorkingDirectoryProjector {
    func emitGitWorkingDirectoryEvent(
        worktreeId: UUID,
        repoId: UUID,
        event: GitWorkingDirectoryEvent
    ) async {
        nextEnvelopeSequence += 1
        let envelope = RuntimeEnvelope.worktree(
            WorktreeEnvelope(
                source: .system(.builtin(.gitWorkingDirectoryProjector)),
                seq: nextEnvelopeSequence,
                timestamp: envelopeClock.now,
                repoId: repoId,
                worktreeId: worktreeId,
                event: .gitWorkingDirectory(event)
            )
        )

        let droppedCount = (await runtimeBus.post(envelope)).droppedCount
        if droppedCount > 0 {
            Self.logger.warning(
                "Git projector event delivery dropped for \(droppedCount, privacy: .public) subscriber(s); seq=\(self.nextEnvelopeSequence, privacy: .public)"
            )
        }
        performanceTraceRecorder?.record(
            .gitEventPosted,
            attributes: [
                "agentstudio.performance.git.event_posted.count": .int(1),
                "agentstudio.performance.git.dropped_subscriber.count": .int(droppedCount),
            ]
        )
        Self.logger.debug("Posted git projector event for worktree \(worktreeId.uuidString, privacy: .public)")
    }
}
