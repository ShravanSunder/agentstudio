import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTerminal

/// SR1, SR2, SR6; Program Design item 1: the kind mapping table, including a
/// whole-inventory unavailable outcome. Real zmx's own boundary behavior
/// (a killed daemon, a refused socket, a real identity observation) is
/// proven separately in `ZmxBackendIntegrationTests` — this suite proves the
/// classification logic against a scripted `ZmxSessionRestoreProbing`.
@MainActor
@Suite("Terminal restore kind resolver")
struct TerminalRestoreKindResolverTests {
    private final class ScriptedProbe: ZmxSessionRestoreProbing, @unchecked Sendable {
        var inventory: ZmxSessionInventory = .complete([:])
        var identitiesBySessionID: [ZmxSessionID: Data] = [:]
        var identityFailureSessionIDs: Set<ZmxSessionID> = []

        func discoverSessionInventory() async -> ZmxSessionInventory { inventory }

        func observeSessionIdentity(_ sessionID: ZmxSessionID) async throws -> Data? {
            if identityFailureSessionIDs.contains(sessionID) {
                throw ZmxSessionControlTestFailure.simulated
            }
            return identitiesBySessionID[sessionID]
        }
    }

    private enum ZmxSessionControlTestFailure: Error {
        case simulated
    }

    private let enabledConfiguration = SessionConfiguration.detect(
        environment: [
            "AGENTSTUDIO_DATA_DIR": "/tmp/fake-zmx-data",
            "AGENTSTUDIO_SESSION_RESTORE": "true",
            "AGENTSTUDIO_TRACE_PROOF_TOKEN": "restore-kind-resolver-test",
            "AGENTSTUDIO_ZMX_PATH": "/usr/bin/true",
        ],
        isDebugBuild: true
    )

    @Test("an alive session with an observable identity resolves warm")
    func aliveWithObservableIdentityResolvesWarm() async throws {
        let sessionID = try restoredSessionID("as-resolver-warm")
        let pane = makePane(sessionID: sessionID)
        let probe = ScriptedProbe()
        probe.inventory = .complete([sessionID: .alive(wrapperPid: 100)])
        probe.identitiesBySessionID[sessionID] = Data([9, 9, 9])
        let resolver = makeResolver(probe: probe)

        let kinds = await resolver.resolveRestoreKinds(for: [descriptor(for: pane)])

        guard case .warm(let identity, let fallback) = kinds[PaneId(existingUUID: pane.id)] else {
            Issue.record("expected .warm, got \(String(describing: kinds[PaneId(existingUUID: pane.id)]))")
            return
        }
        #expect(identity == Data([9, 9, 9]))
        #expect(fallback.sessionID == sessionID)
    }

    @Test("an alive session whose identity can't be observed resolves unverified, never warm on the pid alone")
    func aliveWithUnobservableIdentityResolvesUnverified() async throws {
        let sessionID = try restoredSessionID("as-resolver-warm-unobservable")
        let pane = makePane(sessionID: sessionID)
        let probe = ScriptedProbe()
        probe.inventory = .complete([sessionID: .alive(wrapperPid: 100)])
        probe.identityFailureSessionIDs.insert(sessionID)
        let resolver = makeResolver(probe: probe)

        let kinds = await resolver.resolveRestoreKinds(for: [descriptor(for: pane)])

        guard case .unverified(let reason, let fallback) = kinds[PaneId(existingUUID: pane.id)] else {
            Issue.record("expected .unverified, got \(String(describing: kinds[PaneId(existingUUID: pane.id)]))")
            return
        }
        #expect(reason == .warmIdentityUnobservable)
        #expect(fallback.sessionID == sessionID)
    }

    @Test("N live sessions, exceeding the concurrency bound, all resolve warm with their own identity")
    func manyLiveSessionsAllResolveWarm() async throws {
        // Exceeds AppPolicies.Restore.maximumConcurrentIdentityObservations
        // (4), so the bounded task group must refill from its backlog at
        // least once rather than only ever running its first wave.
        let sessionCount = 6
        let probe = ScriptedProbe()
        var panesBySessionID: [ZmxSessionID: Pane] = [:]
        var descriptors: [TerminalActivationDescriptor] = []
        var inventoryEntries: [ZmxSessionID: ZmxInventoryEntry] = [:]
        for index in 0..<sessionCount {
            let sessionID = try restoredSessionID("as-resolver-concurrent-\(index)")
            let pane = makePane(sessionID: sessionID)
            panesBySessionID[sessionID] = pane
            descriptors.append(descriptor(for: pane))
            inventoryEntries[sessionID] = .alive(wrapperPid: Int32(100 + index))
            probe.identitiesBySessionID[sessionID] = Data([UInt8(index)])
        }
        probe.inventory = .complete(inventoryEntries)
        let resolver = makeResolver(probe: probe)

        let kinds = await resolver.resolveRestoreKinds(for: descriptors)

        #expect(kinds.count == sessionCount)
        for (sessionID, pane) in panesBySessionID {
            guard case .warm(let identity, let fallback) = kinds[PaneId(existingUUID: pane.id)] else {
                Issue.record(
                    "expected .warm for session \(sessionID), got \(String(describing: kinds[PaneId(existingUUID: pane.id)]))"
                )
                continue
            }
            #expect(identity == probe.identitiesBySessionID[sessionID])
            #expect(fallback.sessionID == sessionID)
        }
    }

    @Test("a refused session resolves cold")
    func refusedResolvesCold() async throws {
        let sessionID = try restoredSessionID("as-resolver-refused")
        let pane = makePane(sessionID: sessionID)
        let probe = ScriptedProbe()
        probe.inventory = .complete([sessionID: .refused])
        let resolver = makeResolver(probe: probe)

        let kinds = await resolver.resolveRestoreKinds(for: [descriptor(for: pane)])

        guard case .cold(let plan) = kinds[PaneId(existingUUID: pane.id)] else {
            Issue.record("expected .cold, got \(String(describing: kinds[PaneId(existingUUID: pane.id)]))")
            return
        }
        #expect(plan.sessionID == sessionID)
    }

    @Test("a session absent from a complete inventory resolves cold, exactly like refused")
    func absentFromCompleteInventoryResolvesCold() async throws {
        let sessionID = try restoredSessionID("as-resolver-absent")
        let pane = makePane(sessionID: sessionID)
        let probe = ScriptedProbe()
        probe.inventory = .complete([:])
        let resolver = makeResolver(probe: probe)

        let kinds = await resolver.resolveRestoreKinds(for: [descriptor(for: pane)])

        guard case .cold = kinds[PaneId(existingUUID: pane.id)] else {
            Issue.record("expected .cold, got \(String(describing: kinds[PaneId(existingUUID: pane.id)]))")
            return
        }
    }

    @Test("an unresponsive session resolves unverified, never cold or warm")
    func unresponsiveResolvesUnverified() async throws {
        let sessionID = try restoredSessionID("as-resolver-unresponsive")
        let pane = makePane(sessionID: sessionID)
        let probe = ScriptedProbe()
        probe.inventory = .complete([sessionID: .unresponsive])
        let resolver = makeResolver(probe: probe)

        let kinds = await resolver.resolveRestoreKinds(for: [descriptor(for: pane)])

        guard case .unverified(let reason, let fallback) = kinds[PaneId(existingUUID: pane.id)] else {
            Issue.record("expected .unverified, got \(String(describing: kinds[PaneId(existingUUID: pane.id)]))")
            return
        }
        #expect(reason == .sessionUnresponsive)
        #expect(fallback.sessionID == sessionID)
    }

    @Test("a whole-inventory unavailable outcome makes every pane unverified")
    func wholeInventoryUnavailableMakesEveryPaneUnverified() async throws {
        let firstSessionID = try restoredSessionID("as-resolver-unavailable-one")
        let secondSessionID = try restoredSessionID("as-resolver-unavailable-two")
        let firstPane = makePane(sessionID: firstSessionID)
        let secondPane = makePane(sessionID: secondSessionID)
        let probe = ScriptedProbe()
        probe.inventory = .unavailable(.timedOut)
        let resolver = makeResolver(probe: probe)

        let kinds = await resolver.resolveRestoreKinds(for: [
            descriptor(for: firstPane),
            descriptor(for: secondPane),
        ])

        #expect(kinds.count == 2)
        let expectedSessionIDs = Set([firstSessionID, secondSessionID])
        for kind in kinds.values {
            guard case .unverified(let reason, let fallback) = kind else {
                Issue.record("expected .unverified, got \(kind)")
                continue
            }
            #expect(reason == .inventoryUnavailable(.timedOut))
            #expect(expectedSessionIDs.contains(fallback.sessionID))
        }
    }

    @Test("a drawer pane follows exactly the same classification rules as a main pane (SR6)")
    func drawerPaneFollowsTheSameRules() async throws {
        let sessionID = try restoredSessionID("as-resolver-drawer-refused")
        let pane = makePane(sessionID: sessionID)
        let probe = ScriptedProbe()
        probe.inventory = .complete([sessionID: .refused])
        let resolver = makeResolver(probe: probe)
        let drawerDescriptor = TerminalActivationDescriptor(
            pane: pane,
            visibilityPriority: .activeVisible,
            hostPlacement: .drawer(tabID: UUID(), parentPaneID: PaneId(existingUUID: UUID()), drawerID: UUID())
        )

        let kinds = await resolver.resolveRestoreKinds(for: [drawerDescriptor])

        guard case .cold(let plan) = kinds[PaneId(existingUUID: pane.id)] else {
            Issue.record("expected .cold, got \(String(describing: kinds[PaneId(existingUUID: pane.id)]))")
            return
        }
        #expect(plan.sessionID == sessionID)
    }

    @Test("a non-zmx pane never gets a computed restore kind")
    func nonZmxPaneNeverGetsAComputedKind() async throws {
        let probe = ScriptedProbe()
        probe.inventory = .complete([:])
        let resolver = makeResolver(probe: probe)
        let nonZmxPane = Pane(
            content: .terminal(
                TerminalState(provider: .ghostty, lifetime: .temporary, zmxSessionID: .generateUUIDv7())),
            metadata: PaneMetadata(title: "Ghostty")
        )

        let kinds = await resolver.resolveRestoreKinds(for: [descriptor(for: nonZmxPane)])

        #expect(kinds.isEmpty)
    }

    @Test("no probe wired (zmx unresolved at boot) resolves no kinds at all")
    func noProbeResolvesNoKinds() async throws {
        let sessionID = try restoredSessionID("as-resolver-no-probe")
        let pane = makePane(sessionID: sessionID)
        let resolver = TerminalRestoreKindResolver(
            sessionConfiguration: enabledConfiguration,
            probe: nil,
            repositoryMainFolder: { _ in nil }
        )

        let kinds = await resolver.resolveRestoreKinds(for: [descriptor(for: pane)])

        #expect(kinds.isEmpty)
    }

    // MARK: - Helpers

    private func restoredSessionID(_ storedText: String) throws -> ZmxSessionID {
        try #require(ZmxSessionID(restoring: storedText))
    }

    private func makeResolver(probe: ScriptedProbe) -> TerminalRestoreKindResolver {
        TerminalRestoreKindResolver(
            sessionConfiguration: enabledConfiguration,
            probe: probe,
            repositoryMainFolder: { _ in nil }
        )
    }

    private func makePane(sessionID: ZmxSessionID) -> Pane {
        Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: sessionID)),
            metadata: PaneMetadata(launchDirectory: URL(filePath: "/tmp"), title: "Terminal")
        )
    }

    private func descriptor(for pane: Pane) -> TerminalActivationDescriptor {
        TerminalActivationDescriptor(
            pane: pane,
            visibilityPriority: .activeVisible,
            hostPlacement: .tab(tabID: UUID())
        )
    }
}
