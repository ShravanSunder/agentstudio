import Foundation
import Testing

@testable import AgentStudio

@Suite("RuntimeEnvelope legacy bridge")
struct RuntimeEnvelopeLegacyBridgeTests {
    @Test("fromLegacy routes worktreeRegistered to system topology envelope")
    func fromLegacyRoutesWorktreeRegisteredToSystemEnvelope() {
        let worktreeId = UUID()
        let repoId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/repo-\(UUID().uuidString)")
        let legacy = PaneEventEnvelope(
            source: .system(.builtin(.filesystemWatcher)),
            sourceFacets: PaneContextFacets(repoId: repoId, worktreeId: worktreeId, cwd: rootPath),
            paneKind: nil,
            seq: 1,
            commandId: nil,
            correlationId: nil,
            timestamp: ContinuousClock().now,
            epoch: 0,
            event: .filesystem(.worktreeRegistered(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath))
        )

        let bridged = RuntimeEnvelope.fromLegacy(legacy)
        guard case .system(let systemEnvelope) = bridged else {
            Issue.record("Expected system envelope")
            return
        }
        guard case .topology(.worktreeRegistered(let mappedWorktreeId, let mappedRepoId, let mappedRootPath)) = systemEnvelope.event else {
            Issue.record("Expected worktreeRegistered topology event")
            return
        }
        #expect(mappedWorktreeId == worktreeId)
        #expect(mappedRepoId == repoId)
        #expect(mappedRootPath == rootPath)
    }

    @Test("system topology worktree lifecycle round-trips to legacy filesystem event")
    func roundTripSystemTopologyWorktreeLifecycle() {
        let worktreeId = UUID()
        let repoId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/repo-\(UUID().uuidString)")

        let runtime = RuntimeEnvelope.system(
            SystemEnvelope.test(
                event: .topology(.worktreeRegistered(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)),
                source: .builtin(.filesystemWatcher),
                seq: 7
            )
        )

        guard let legacy = runtime.toLegacy() else {
            Issue.record("Expected topology worktreeRegistered to bridge to legacy")
            return
        }

        guard case .filesystem(.worktreeRegistered(let legacyWorktreeId, let legacyRepoId, let legacyRootPath)) = legacy.event else {
            Issue.record("Expected legacy worktreeRegistered event")
            return
        }
        #expect(legacyWorktreeId == worktreeId)
        #expect(legacyRepoId == repoId)
        #expect(legacyRootPath == rootPath)
        #expect(legacy.source == .system(.builtin(.filesystemWatcher)))
    }

    @Test("pane envelope round-trip preserves identity fields")
    func roundTripPaneEnvelope() {
        let paneId = PaneId()
        let eventId = UUID()
        let runtime = RuntimeEnvelope.pane(
            PaneEnvelope.test(
                event: .terminal(.bellRang),
                paneId: paneId,
                paneKind: .terminal,
                source: .pane(paneId),
                seq: 11,
                eventId: eventId
            )
        )

        guard let legacy = runtime.toLegacy() else {
            Issue.record("Expected pane envelope to bridge to legacy")
            return
        }
        let bridgedBack = RuntimeEnvelope.fromLegacy(legacy)
        guard case .pane(let paneEnvelope) = bridgedBack else {
            Issue.record("Expected pane envelope after round-trip")
            return
        }
        #expect(paneEnvelope.paneId == paneId)
        #expect(paneEnvelope.eventId == eventId)
        #expect(paneEnvelope.seq == 11)
    }

    @Test("fromLegacy uses deterministic eventId fallback for missing repoId in worktree-scoped security event")
    func deterministicRepoFallbackUsesEventId() {
        let eventId = UUID()
        let legacy = PaneEventEnvelope(
            eventId: eventId,
            source: .pane(PaneId()),
            sourceFacets: .empty,
            paneKind: .terminal,
            seq: 3,
            commandId: nil,
            correlationId: nil,
            timestamp: ContinuousClock().now,
            epoch: 0,
            event: .security(.sandboxStopped(reason: "test"))
        )

        let bridged = RuntimeEnvelope.fromLegacy(legacy)
        guard case .worktree(let worktreeEnvelope) = bridged else {
            Issue.record("Expected worktree envelope for security event")
            return
        }
        #expect(worktreeEnvelope.repoId == eventId)
    }
}

