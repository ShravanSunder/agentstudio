import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTerminal
import Foundation

/// Decides SR1/SR2/SR6's restore kind (E4) for every zmx-provider pane in
/// one mount, before terminal activation runs (Program Design item 1). Built
/// once at boot (`AppDelegate+WorkspaceBoot.swift`) and injected into
/// `WorkspacePreparedContentMountCoordinator`, whose `mount()` awaits
/// `resolveRestoreKinds(for:)` before its terminal lane activates.
///
/// Bridges Core (`ZmxSessionInventory`, `ZmxSessionRestoreProbing`) and
/// Features (`TerminalRestoreKind`) — neither module may import the other,
/// so this classification belongs at the App layer, where both are already
/// visible.
///
/// Not `@MainActor`: called from `mount()` (MainActor), it runs on
/// MainActor throughout except for its two leaf I/O calls
/// (`probe.discoverSessionInventory()`, `probe.observeSessionIdentity(_:)`),
/// which are `@concurrent nonisolated` on `ZmxBackend` and hop off-main for
/// their own duration (SE-0461) — matching the Program Design's "What runs
/// where": the derivation itself needs no actor, only the I/O does.
struct TerminalRestoreKindResolver: Sendable {
    private let sessionConfiguration: SessionConfiguration
    /// Nil when zmx couldn't be resolved at boot (`SessionConfiguration
    /// .zmxPath == nil`): there is then no backend to probe, and every
    /// zmx-provider pane simply gets no computed kind, exactly as if this
    /// resolver were never wired in (matching `TerminalRestoreRuntime
    /// .startupCommand`'s existing `nil`-kind fallback).
    private let probe: (any ZmxSessionRestoreProbing)?
    private let repositoryMainFolder: @MainActor (Pane) -> URL?

    init(
        sessionConfiguration: SessionConfiguration,
        probe: (any ZmxSessionRestoreProbing)?,
        repositoryMainFolder: @escaping @MainActor (Pane) -> URL?
    ) {
        self.sessionConfiguration = sessionConfiguration
        self.probe = probe
        self.repositoryMainFolder = repositoryMainFolder
    }

    @MainActor
    func resolveRestoreKinds(
        for descriptors: [TerminalActivationDescriptor]
    ) async -> [PaneId: TerminalRestoreKind] {
        guard sessionConfiguration.isOperational, let zmxPath = sessionConfiguration.zmxPath, let probe else {
            return [:]
        }
        let zmxPanes: [(paneID: PaneId, pane: Pane, sessionID: ZmxSessionID)] = descriptors.compactMap { descriptor in
            guard descriptor.pane.provider == .zmx, let sessionID = descriptor.pane.terminalState?.zmxSessionID else {
                return nil
            }
            return (descriptor.paneID, descriptor.pane, sessionID)
        }
        guard !zmxPanes.isEmpty else { return [:] }

        let inventory = await probe.discoverSessionInventory()
        var restoreKindsByPaneID: [PaneId: TerminalRestoreKind] = [:]
        for entry in zmxPanes {
            restoreKindsByPaneID[entry.paneID] = await resolveKind(
                pane: entry.pane,
                sessionID: entry.sessionID,
                inventory: inventory,
                zmxPath: zmxPath,
                probe: probe
            )
        }
        return restoreKindsByPaneID
    }

    @MainActor
    private func resolveKind(
        pane: Pane,
        sessionID: ZmxSessionID,
        inventory: ZmxSessionInventory,
        zmxPath: String,
        probe: any ZmxSessionRestoreProbing
    ) async -> TerminalRestoreKind {
        switch inventory {
        case .unavailable(let failure):
            return .unverified(.inventoryUnavailable(failure))
        case .complete(let entriesBySessionID):
            switch entriesBySessionID[sessionID] {
            case .alive:
                return await resolveWarmOrUnverified(sessionID: sessionID, probe: probe)
            case .refused, nil:
                // Absent from a complete inventory, or refused: both are
                // proof of death (SR2), never merely unseen.
                return .cold(buildColdPlan(pane: pane, sessionID: sessionID, zmxPath: zmxPath))
            case .unresponsive:
                return .unverified(.sessionUnresponsive)
            }
        }
    }

    private func resolveWarmOrUnverified(
        sessionID: ZmxSessionID,
        probe: any ZmxSessionRestoreProbing
    ) async -> TerminalRestoreKind {
        do {
            guard let identity = try await probe.observeSessionIdentity(sessionID) else {
                return .unverified(.warmIdentityUnobservable)
            }
            return .warm(identity: identity)
        } catch {
            return .unverified(.warmIdentityUnobservable)
        }
    }

    @MainActor
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
