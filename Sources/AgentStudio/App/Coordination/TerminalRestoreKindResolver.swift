import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTerminal
import Foundation

/// Decides SR1/SR2/SR6's restore kind (E4) for every zmx-provider pane in
/// one mount, before terminal activation runs (Program Design item 1).
/// Bridges Core (`ZmxSessionInventory`, `ZmxSessionRestoreProbing`) and
/// Features (`TerminalRestoreKind`) — neither module may import the other,
/// so this classification belongs at the App layer, where both are already
/// visible.
///
/// App joins Core's inventory and Terminal's plan vocabulary. Classification
/// streams off-main through `classifyRestoreKinds` (`@concurrent
/// nonisolated`, amended 2026-10-01, A1 review): descriptor filtering, the
/// per-pane identity observation, kind mapping and fallback-plan
/// construction all run there, matching the Program Design's "What runs
/// where" — inventory -> restore kind, observation -> classification, and
/// resume evidence all stay off-main. The MainActor allowance at PD:464 is
/// for pure command choice (`TerminalRestoreRuntime`'s own switch over an
/// already-decided kind), not this classification. `resolveRestoreKinds` is
/// the existing whole-map reader that collects that same stream.
struct TerminalRestoreKindResolver: Sendable {
    private let sessionConfiguration: SessionConfiguration
    /// Nil when zmx couldn't be resolved at boot (`SessionConfiguration
    /// .zmxPath == nil`): there is then no backend to probe, and every
    /// zmx-provider pane simply gets no computed kind, exactly as if this
    /// resolver were never wired in (matching `TerminalRestoreRuntime
    /// .startupCommand`'s existing `nil`-kind fallback).
    private let probe: (any ZmxSessionRestoreProbing)?
    private let repositoryMainFolder: @Sendable (Pane) -> URL?

    init(
        sessionConfiguration: SessionConfiguration,
        probe: (any ZmxSessionRestoreProbing)?,
        repositoryMainFolder: @escaping @Sendable (Pane) -> URL?
    ) {
        self.sessionConfiguration = sessionConfiguration
        self.probe = probe
        self.repositoryMainFolder = repositoryMainFolder
    }

    /// `observeDerivationExecutionContext` (test technique amendment, Lead
    /// 2026-10-01; A1 advisor review): a no-op in production, called as the
    /// first statement here so a test can record this call's real execution
    /// context (e.g. `Thread.isMainThread`) as a structural, deterministic
    /// fact instead of racing it against other MainActor work — the repo's
    /// own rule against a verdict that depends on machine speed. Since this
    /// whole function is `@concurrent nonisolated`, recording here proves
    /// the same off-main guarantee for every call, including the per-pane
    /// fan-out `classifyRestoreKinds` performs underneath it.
    @concurrent nonisolated func resolveRestoreKinds(
        for descriptors: [TerminalActivationDescriptor],
        observeDerivationExecutionContext: @Sendable () -> Void = {}
    ) async -> [PaneId: TerminalRestoreKind] {
        observeDerivationExecutionContext()
        let (stream, continuation) = AsyncStream.makeStream(
            of: (PaneId, TerminalRestoreKind).self, bufferingPolicy: .unbounded)
        async let classification: Void = classifyRestoreKinds(for: descriptors) { paneID, kind in
            continuation.yield((paneID, kind))
        }
        // The producer is joined before closing the collector stream.
        await classification
        continuation.finish()
        var result: [PaneId: TerminalRestoreKind] = [:]
        for await (paneID, kind) in stream { result[paneID] = kind }
        return result
    }

    /// The streaming entry: publishes each pane's restore kind as soon as
    /// its own classification settles, instead of waiting for the whole
    /// batch. `resolveRestoreKinds` above collects this same stream into a
    /// map for callers that still want the old whole-map shape.
    @concurrent nonisolated func classifyRestoreKinds(
        for descriptors: [TerminalActivationDescriptor],
        publish: @Sendable (PaneId, TerminalRestoreKind) async -> Void
    ) async {
        guard sessionConfiguration.isOperational, let zmxPath = sessionConfiguration.zmxPath, let probe else { return }
        let entries = descriptors.compactMap { descriptor -> (PaneId, Pane, ZmxSessionID)? in
            guard descriptor.pane.provider == .zmx, let sessionID = descriptor.pane.terminalState?.zmxSessionID else {
                return nil
            }
            return (descriptor.paneID, descriptor.pane, sessionID)
        }
        guard !entries.isEmpty else { return }
        let inventory = await probe.discoverSessionInventory()
        await withTaskGroup(of: (PaneId, TerminalRestoreKind).self) { group in
            var nextIndex = 0
            func addNextClassification() {
                guard nextIndex < entries.count else { return }
                let (paneID, pane, sessionID) = entries[nextIndex]
                nextIndex += 1
                group.addTask {
                    let identity: Data?
                    if case .complete(let sessions) = inventory, case .alive = sessions[sessionID] {
                        identity = try? await probe.observeSessionIdentity(sessionID)
                    } else {
                        identity = nil
                    }
                    return (
                        paneID,
                        resolveKind(
                            pane: pane, sessionID: sessionID, inventory: inventory,
                            zmxPath: zmxPath, observedIdentity: identity)
                    )
                }
            }
            for _ in 0..<min(entries.count, AppPolicies.Restore.maximumConcurrentIdentityObservations) {
                addNextClassification()
            }
            while let (paneID, kind) = await group.next() {
                await publish(paneID, kind)
                addNextClassification()
            }
        }
    }

    private func resolveKind(
        pane: Pane,
        sessionID: ZmxSessionID,
        inventory: ZmxSessionInventory,
        zmxPath: String,
        observedIdentity: Data?
    ) -> TerminalRestoreKind {
        switch inventory {
        case .unavailable(let failure):
            return .unverified(
                .inventoryUnavailable(failure),
                fallback: buildColdPlan(pane: pane, sessionID: sessionID, zmxPath: zmxPath))
        case .complete(let entriesBySessionID):
            switch entriesBySessionID[sessionID] {
            case .alive:
                guard let observedIdentity else {
                    return .unverified(
                        .warmIdentityUnobservable,
                        fallback: buildColdPlan(pane: pane, sessionID: sessionID, zmxPath: zmxPath))
                }
                return .warm(
                    identity: observedIdentity,
                    fallback: buildColdPlan(pane: pane, sessionID: sessionID, zmxPath: zmxPath))
            case .refused, nil:
                // Absent from a complete inventory, or refused: both are
                // proof of death (SR2), never merely unseen.
                return .cold(buildColdPlan(pane: pane, sessionID: sessionID, zmxPath: zmxPath))
            case .unresponsive:
                return .unverified(
                    .sessionUnresponsive,
                    fallback: buildColdPlan(pane: pane, sessionID: sessionID, zmxPath: zmxPath))
            }
        }
    }

    private func buildColdPlan(pane: Pane, sessionID: ZmxSessionID, zmxPath: String) -> TerminalColdRestorePlan {
        TerminalColdRestorePlanBuilder.buildPlan(
            pane: pane,
            sessionID: sessionID,
            zmxExecutablePath: zmxPath,
            zmxDirectoryPath: sessionConfiguration.zmxDir,
            loginShellPath: SessionConfiguration.defaultShell(),
            repositoryMainFolder: repositoryMainFolder(pane)
        )
    }
}
