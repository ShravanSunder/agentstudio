import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTerminal
import Foundation

/// App joins Core's inventory and Terminal's plan vocabulary. Classification
/// streams off-main; the existing whole-map reader collects that same stream.
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

    @concurrent nonisolated func resolveRestoreKinds(
        for descriptors: [TerminalActivationDescriptor]
    ) async -> [PaneId: TerminalRestoreKind] {
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
