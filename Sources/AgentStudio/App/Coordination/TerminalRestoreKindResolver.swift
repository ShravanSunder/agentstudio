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
/// MainActor throughout except for its leaf I/O calls
/// (`probe.discoverSessionInventory()`, `probe.observeSessionIdentity(_:)`),
/// which are `@concurrent nonisolated` on `ZmxBackend` and hop off-main for
/// their own duration (SE-0461) — matching the Program Design's "What runs
/// where": the derivation itself needs no actor, only the I/O does. Every
/// `.alive` session's identity observation runs concurrently, bounded by
/// `AppPolicies.Restore.maximumConcurrentIdentityObservations`; only the
/// surrounding map/plan building (`resolveKind`, `buildColdPlan`) stays on
/// MainActor.
struct TerminalRestoreKindResolver: Sendable {
    private let sessionConfiguration: SessionConfiguration
    /// Nil when zmx couldn't be resolved at boot (`SessionConfiguration
    /// .zmxPath == nil`): there is then no backend to probe, and every
    /// zmx-provider pane simply gets no computed kind, exactly as if this
    /// resolver were never wired in (matching `TerminalRestoreRuntime
    /// .startupCommand`'s existing `nil`-kind fallback).
    private let probe: (any ZmxSessionRestoreProbing)?
    private let scrollbackStore: ScrollbackStore
    private let repositoryMainFolder: @MainActor (Pane) -> URL?

    init(
        sessionConfiguration: SessionConfiguration,
        probe: (any ZmxSessionRestoreProbing)?,
        scrollbackStore: ScrollbackStore = ScrollbackStore(),
        repositoryMainFolder: @escaping @MainActor (Pane) -> URL?
    ) {
        self.sessionConfiguration = sessionConfiguration
        self.probe = probe
        self.scrollbackStore = scrollbackStore
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
        let aliveSessionIDs: [ZmxSessionID] = zmxPanes.compactMap { entry in
            guard case .complete(let entriesBySessionID) = inventory,
                case .alive = entriesBySessionID[entry.sessionID]
            else {
                return nil
            }
            return entry.sessionID
        }
        let observedIdentitiesBySessionID = await Self.observeIdentitiesConcurrently(
            sessionIDs: aliveSessionIDs,
            probe: probe
        )

        var restoreKindsByPaneID: [PaneId: TerminalRestoreKind] = [:]
        for entry in zmxPanes {
            restoreKindsByPaneID[entry.paneID] = await resolveKind(
                pane: entry.pane,
                sessionID: entry.sessionID,
                inventory: inventory,
                zmxPath: zmxPath,
                observedIdentity: observedIdentitiesBySessionID[entry.sessionID]
            )
        }
        return restoreKindsByPaneID
    }

    /// The warm baseline's off-main fan-out (choice 1): every `.alive`
    /// session's `observeSessionIdentity` runs concurrently, bounded by
    /// `AppPolicies.Restore.maximumConcurrentIdentityObservations` so a large
    /// pane count never opens unbounded sockets at once. Not `@MainActor` —
    /// nothing here reads or writes MainActor state; only the caller's
    /// subsequent `resolveKind` mapping does.
    private static func observeIdentitiesConcurrently(
        sessionIDs: [ZmxSessionID],
        probe: any ZmxSessionRestoreProbing
    ) async -> [ZmxSessionID: Data] {
        guard !sessionIDs.isEmpty else { return [:] }
        var identitiesBySessionID: [ZmxSessionID: Data] = [:]
        var nextIndex = 0
        let concurrencyBound = min(
            AppPolicies.Restore.maximumConcurrentIdentityObservations,
            sessionIDs.count
        )
        await withTaskGroup(of: (ZmxSessionID, Data?).self) { group in
            func addNextObservation() {
                guard nextIndex < sessionIDs.count else { return }
                let sessionID = sessionIDs[nextIndex]
                nextIndex += 1
                group.addTask {
                    // A failed observation and a successful-but-empty one carry
                    // the same meaning here (`.warmIdentityUnobservable`), so
                    // `try?` collapsing the thrown case to `nil` loses nothing
                    // `resolveKind` needs.
                    let identity = try? await probe.observeSessionIdentity(sessionID)
                    return (sessionID, identity)
                }
            }
            for _ in 0..<concurrencyBound { addNextObservation() }
            while let (sessionID, identity) = await group.next() {
                if let identity {
                    identitiesBySessionID[sessionID] = identity
                }
                addNextObservation()
            }
        }
        return identitiesBySessionID
    }

    @MainActor
    private func resolveKind(
        pane: Pane,
        sessionID: ZmxSessionID,
        inventory: ZmxSessionInventory,
        zmxPath: String,
        observedIdentity: Data?
    ) async -> TerminalRestoreKind {
        let plan = await buildColdPlan(pane: pane, sessionID: sessionID, zmxPath: zmxPath)
        switch inventory {
        case .unavailable(let failure):
            return .unverified(
                .inventoryUnavailable(failure),
                fallback: plan)
        case .complete(let entriesBySessionID):
            switch entriesBySessionID[sessionID] {
            case .alive:
                guard let observedIdentity else {
                    return .unverified(
                        .warmIdentityUnobservable,
                        fallback: plan)
                }
                return .warm(
                    identity: observedIdentity,
                    fallback: plan)
            case .refused, nil:
                // Absent from a complete inventory, or refused: both are
                // proof of death (SR2), never merely unseen.
                return .cold(plan)
            case .unresponsive:
                return .unverified(
                    .sessionUnresponsive,
                    fallback: plan)
            }
        }
    }

    @MainActor
    private func buildColdPlan(pane: Pane, sessionID: ZmxSessionID, zmxPath: String) async -> TerminalColdRestorePlan {
        await TerminalColdRestorePlanBuilder.buildPlan(
            pane: pane,
            sessionID: sessionID,
            launchPaths: TerminalColdRestoreLaunchPaths(
                zmxExecutablePath: zmxPath,
                zmxDirectoryPath: sessionConfiguration.zmxDir,
                loginShellPath: SessionConfiguration.defaultShell()),
            repositoryMainFolder: repositoryMainFolder(pane),
            scrollbackStore: scrollbackStore
        )
    }
}
