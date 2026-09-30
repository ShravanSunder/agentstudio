import AgentStudioTestHarness
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

/// SR2a; Program Design item 5: `beginPostAttachRecreationCheckIfNeeded`'s
/// wiring (`WorkspaceSurfaceCoordinator+TerminalContentMounting.swift`) --
/// proves the comparison against `PaneRecreationChecker`, task ownership,
/// and typed-fact delivery, without a real zmx daemon. Real
/// observe-after-attach timing against a real daemon is proven separately
/// in the E2E lane.
@MainActor
@Suite("WorkspaceSurfaceCoordinator post-attach recreation check", .serialized)
struct PostAttachRecreationCheckWiringTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    private final class ScriptedProbe: ZmxSessionRestoreProbing, @unchecked Sendable {
        var observedIdentity: Data?
        var throwsOnObserve = false

        func discoverSessionInventory() async -> ZmxSessionInventory { .complete([:]) }

        func observeSessionIdentity(_ sessionID: ZmxSessionID) async throws -> Data? {
            if throwsOnObserve { throw ScriptedProbeFailure.simulated }
            return observedIdentity
        }
    }

    private enum ScriptedProbeFailure: Error {
        case simulated
    }

    private func vocabulary() -> FactVocabulary<UUID, PaneRecreationCheckResult> {
        FactVocabulary(
            describeScope: { $0.uuidString },
            describeFact: { String(describing: $0) },
            isClosing: { _, _ in true }
        )
    }

    private func makeCoordinator() throws -> WorkspaceSurfaceCoordinator {
        let store = try makeWorkspaceJournalTestStore()
        return WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: TerminalRestoreCapturingSurfaceManager(),
            runtimeRegistry: .shared,
            windowLifecycleStore: WindowLifecycleAtom(),
            ipcLifecycle: .testUnavailable,
            bridgePaneAttendance: BridgePaneAttendanceAtom()
        )
    }

    private func makeZmxPane(sessionIDText: String) -> Pane {
        Pane(
            id: UUIDv7.generate(),
            content: .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionID: ZmxSessionID(restoring: sessionIDText)!
                )
            ),
            metadata: PaneMetadata(
                launchDirectory: URL(fileURLWithPath: "/tmp"),
                title: "Post-attach recreation check test"
            )
        )
    }

    @Test("a matching post-attach identity settles unchanged")
    func matchingIdentitySettlesUnchanged() async throws {
        // Arrange
        let coordinator = try makeCoordinator()
        let source = LocalFactSource(vocabulary: vocabulary())
        let recorder = try source.attach()
        coordinator.postAttachRecreationCheckFactSink = source.sink
        let probe = ScriptedProbe()
        let baseline = Data([1, 2, 3])
        probe.observedIdentity = baseline
        coordinator.postAttachRecreationProbe = probe
        let pane = makeZmxPane(sessionIDText: "as-post-attach-unchanged")

        // Act
        coordinator.beginPostAttachRecreationCheckIfNeeded(pane: pane, restoreKind: .warm(identity: baseline))

        // Assert
        try await recorder.expectNext(in: pane.id, .unchanged)
        #expect(coordinator.postAttachRecreationCheckTasksByPaneID[pane.id] == nil)
    }

    @Test("a different post-attach identity settles recreated")
    func differentIdentitySettlesRecreated() async throws {
        // Arrange
        let coordinator = try makeCoordinator()
        let source = LocalFactSource(vocabulary: vocabulary())
        let recorder = try source.attach()
        coordinator.postAttachRecreationCheckFactSink = source.sink
        let probe = ScriptedProbe()
        probe.observedIdentity = Data([9, 9, 9])
        coordinator.postAttachRecreationProbe = probe
        let pane = makeZmxPane(sessionIDText: "as-post-attach-recreated")

        // Act
        coordinator.beginPostAttachRecreationCheckIfNeeded(
            pane: pane, restoreKind: .warm(identity: Data([1, 2, 3])))

        // Assert
        try await recorder.expectNext(in: pane.id, .recreated)
        #expect(coordinator.postAttachRecreationCheckTasksByPaneID[pane.id] == nil)
    }

    @Test("a failed observation settles couldNotCheck, never recreated on a mere absence of proof")
    func failedObservationSettlesCouldNotCheck() async throws {
        // Arrange
        let coordinator = try makeCoordinator()
        let source = LocalFactSource(vocabulary: vocabulary())
        let recorder = try source.attach()
        coordinator.postAttachRecreationCheckFactSink = source.sink
        let probe = ScriptedProbe()
        probe.throwsOnObserve = true
        coordinator.postAttachRecreationProbe = probe
        let pane = makeZmxPane(sessionIDText: "as-post-attach-unobservable")

        // Act
        coordinator.beginPostAttachRecreationCheckIfNeeded(
            pane: pane, restoreKind: .warm(identity: Data([1, 2, 3])))

        // Assert
        try await recorder.expectNext(in: pane.id, .couldNotCheck)
    }

    @Test("an unverified pane with no baseline settles couldNotCheck even when the observation succeeds")
    func unverifiedPaneWithNoBaselineSettlesCouldNotCheck() async throws {
        // Arrange
        let coordinator = try makeCoordinator()
        let source = LocalFactSource(vocabulary: vocabulary())
        let recorder = try source.attach()
        coordinator.postAttachRecreationCheckFactSink = source.sink
        let probe = ScriptedProbe()
        probe.observedIdentity = Data([1, 2, 3])
        coordinator.postAttachRecreationProbe = probe
        let pane = makeZmxPane(sessionIDText: "as-post-attach-unverified")

        // Act
        coordinator.beginPostAttachRecreationCheckIfNeeded(
            pane: pane, restoreKind: .unverified(.warmIdentityUnobservable))

        // Assert
        try await recorder.expectNext(in: pane.id, .couldNotCheck)
    }

    @Test("a cold restore kind never starts a post-attach check")
    func coldRestoreKindNeverStartsACheck() throws {
        // Arrange
        let coordinator = try makeCoordinator()
        let pane = makeZmxPane(sessionIDText: "as-post-attach-cold")
        let plan = TerminalColdRestorePlan(
            zmxExecutable: URL(fileURLWithPath: "/usr/local/bin/zmx"),
            zmxDirectory: URL(fileURLWithPath: "/tmp/agentstudio-cold-restore-plan-test"),
            sessionID: ZmxSessionID(restoring: "as-post-attach-cold")!,
            loginShell: URL(fileURLWithPath: "/bin/zsh"),
            folderCandidates: [URL(fileURLWithPath: "/tmp")],
            notice: ColdRestoreNotice(linesByCandidateIndex: ["Restored after restart"]),
            replayFile: nil,
            resume: nil,
            attemptID: .generate()
        )

        // Act
        coordinator.beginPostAttachRecreationCheckIfNeeded(pane: pane, restoreKind: .cold(plan))

        // Assert
        #expect(coordinator.postAttachRecreationCheckTasksByPaneID.isEmpty)
    }

    @Test("a nil restore kind (steady-state mount) never starts a post-attach check")
    func nilRestoreKindNeverStartsACheck() throws {
        // Arrange
        let coordinator = try makeCoordinator()
        let pane = makeZmxPane(sessionIDText: "as-post-attach-steady-state")

        // Act
        coordinator.beginPostAttachRecreationCheckIfNeeded(pane: pane, restoreKind: nil)

        // Assert
        #expect(coordinator.postAttachRecreationCheckTasksByPaneID.isEmpty)
    }
}
