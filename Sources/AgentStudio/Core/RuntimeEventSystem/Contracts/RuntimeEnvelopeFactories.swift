import Foundation

extension SystemEnvelope {
    static func test(
        event: SystemScopedEvent,
        source: SystemSource = .builtin(.coordinator),
        seq: UInt64 = 1,
        timestamp: ContinuousClock.Instant = ContinuousClock().now,
        schemaVersion: UInt16 = RuntimeEnvelopeSchema.current,
        eventId: UUID = UUID(),
        correlationId: UUID? = nil,
        causationId: UUID? = nil,
        commandId: UUID? = nil
    ) -> Self {
        Self(
            eventId: eventId,
            source: source,
            seq: seq,
            timestamp: timestamp,
            schemaVersion: schemaVersion,
            correlationId: correlationId,
            causationId: causationId,
            commandId: commandId,
            event: event
        )
    }
}

extension WorktreeEnvelope {
    static func test(
        event: WorktreeScopedEvent,
        repoId: UUID = UUID(),
        worktreeId: UUID? = UUID(),
        source: EventSource? = nil,
        seq: UInt64 = 1,
        timestamp: ContinuousClock.Instant = ContinuousClock().now,
        schemaVersion: UInt16 = RuntimeEnvelopeSchema.current,
        eventId: UUID = UUID(),
        correlationId: UUID? = nil,
        causationId: UUID? = nil,
        commandId: UUID? = nil
    ) -> Self {
        let resolvedSource = source ?? .worktree(worktreeId ?? repoId)
        return Self(
            eventId: eventId,
            source: resolvedSource,
            seq: seq,
            timestamp: timestamp,
            schemaVersion: schemaVersion,
            correlationId: correlationId,
            causationId: causationId,
            commandId: commandId,
            repoId: repoId,
            worktreeId: worktreeId,
            event: event
        )
    }
}

extension PaneEnvelope {
    static func test(
        event: PaneRuntimeEvent,
        paneId: PaneId = PaneId(),
        paneKind: PaneContentType = .terminal,
        source: EventSource? = nil,
        seq: UInt64 = 1,
        timestamp: ContinuousClock.Instant = ContinuousClock().now,
        schemaVersion: UInt16 = RuntimeEnvelopeSchema.current,
        eventId: UUID = UUID(),
        correlationId: UUID? = nil,
        causationId: UUID? = nil,
        commandId: UUID? = nil
    ) -> Self {
        let resolvedSource = source ?? .pane(paneId)
        return Self(
            eventId: eventId,
            source: resolvedSource,
            seq: seq,
            timestamp: timestamp,
            schemaVersion: schemaVersion,
            correlationId: correlationId,
            causationId: causationId,
            commandId: commandId,
            paneId: paneId,
            paneKind: paneKind,
            event: event
        )
    }
}
