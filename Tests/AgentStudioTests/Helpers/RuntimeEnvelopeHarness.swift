import Foundation

@testable import AgentStudio

struct SystemEventRecord {
    let source: SystemSource
    let event: SystemScopedEvent
    let eventId: UUID
    let seq: UInt64
}

struct WorktreeEventRecord {
    let source: EventSource
    let event: WorktreeScopedEvent
    let eventId: UUID
    let seq: UInt64
    let repoId: UUID
    let worktreeId: UUID?
}

struct PaneEventRecord {
    let source: EventSource
    let event: PaneRuntimeEvent
    let eventId: UUID
    let seq: UInt64
    let paneId: PaneId
}

enum RuntimeEnvelopeHarness {
    static func topologyEnvelope(
        event: TopologyEvent,
        source: SystemSource = .builtin(.filesystemWatcher),
        seq: UInt64 = 1,
        eventId: UUID = UUID()
    ) -> RuntimeEnvelope {
        .system(
            SystemEnvelope.test(
                event: .topology(event),
                source: source,
                seq: seq,
                eventId: eventId
            )
        )
    }

    static func filesystemEnvelope(
        event: FilesystemEvent,
        repoId: UUID = UUID(),
        worktreeId: UUID? = UUID(),
        source: EventSource = .system(.builtin(.filesystemWatcher)),
        seq: UInt64 = 1,
        eventId: UUID = UUID()
    ) -> RuntimeEnvelope {
        .worktree(
            WorktreeEnvelope.test(
                event: .filesystem(event),
                repoId: repoId,
                worktreeId: worktreeId,
                source: source,
                seq: seq,
                eventId: eventId
            )
        )
    }

    static func gitEnvelope(
        event: GitWorkingDirectoryEvent,
        repoId: UUID = UUID(),
        worktreeId: UUID? = UUID(),
        source: EventSource = .system(.builtin(.gitWorkingDirectoryProjector)),
        seq: UInt64 = 1,
        eventId: UUID = UUID()
    ) -> RuntimeEnvelope {
        .worktree(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(event),
                repoId: repoId,
                worktreeId: worktreeId,
                source: source,
                seq: seq,
                eventId: eventId
            )
        )
    }

    static func forgeEnvelope(
        event: ForgeEvent,
        repoId: UUID = UUID(),
        worktreeId: UUID? = UUID(),
        source: EventSource = .system(.service(.gitForge(provider: "github"))),
        seq: UInt64 = 1,
        eventId: UUID = UUID()
    ) -> RuntimeEnvelope {
        .worktree(
            WorktreeEnvelope.test(
                event: .forge(event),
                repoId: repoId,
                worktreeId: worktreeId,
                source: source,
                seq: seq,
                eventId: eventId
            )
        )
    }

    static func paneEnvelope(
        event: PaneRuntimeEvent,
        paneId: PaneId = PaneId(),
        source: EventSource? = nil,
        seq: UInt64 = 1,
        eventId: UUID = UUID()
    ) -> RuntimeEnvelope {
        .pane(
            PaneEnvelope.test(
                event: event,
                paneId: paneId,
                source: source,
                seq: seq,
                eventId: eventId
            )
        )
    }

    static func systemEvents(from envelopes: [RuntimeEnvelope]) -> [SystemEventRecord] {
        envelopes.compactMap { envelope in
            guard case .system(let systemEnvelope) = envelope else { return nil }
            return SystemEventRecord(
                source: systemEnvelope.source,
                event: systemEnvelope.event,
                eventId: systemEnvelope.eventId,
                seq: systemEnvelope.seq
            )
        }
    }

    static func worktreeEvents(from envelopes: [RuntimeEnvelope]) -> [WorktreeEventRecord] {
        envelopes.compactMap { envelope in
            guard case .worktree(let worktreeEnvelope) = envelope else { return nil }
            return WorktreeEventRecord(
                source: worktreeEnvelope.source,
                event: worktreeEnvelope.event,
                eventId: worktreeEnvelope.eventId,
                seq: worktreeEnvelope.seq,
                repoId: worktreeEnvelope.repoId,
                worktreeId: worktreeEnvelope.worktreeId
            )
        }
    }

    static func paneEvents(from envelopes: [RuntimeEnvelope]) -> [PaneEventRecord] {
        envelopes.compactMap { envelope in
            guard case .pane(let paneEnvelope) = envelope else { return nil }
            return PaneEventRecord(
                source: paneEnvelope.source,
                event: paneEnvelope.event,
                eventId: paneEnvelope.eventId,
                seq: paneEnvelope.seq,
                paneId: paneEnvelope.paneId
            )
        }
    }
}
