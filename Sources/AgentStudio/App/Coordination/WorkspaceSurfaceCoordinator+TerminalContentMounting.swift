import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTerminal
import AppKit
import Foundation

struct MountedTerminalContent {
    let view: TerminalPaneMountView
    let surfaceID: UUID
}

enum TopologyIndependentTerminalMountFailure {
    case trustedInitialFrameUnavailable
    case startupPreparationFailed
    case surfaceCreationFailed
    case surfaceAttachmentFailed
}

enum TopologyIndependentTerminalMountResult {
    case mounted(MountedTerminalContent)
    case failed(TopologyIndependentTerminalMountFailure)
}

@MainActor
extension WorkspaceSurfaceCoordinator: PreparedTerminalMountHandling {
    /// Mount a terminal selected by a steady-state user action.
    ///
    /// Steady-state creation may enrich the terminal from current repository
    /// topology. Prepared startup activation uses the topology-independent
    /// sibling below instead.
    ///
    /// `authority` is a compile-time witness the caller must already hold
    /// (from `ViewRegistry.terminalSurfaceCreationAuthority(for:generation:)`);
    /// there is no default value, so a call site that skipped the custody
    /// question does not build.
    @discardableResult
    func mountCurrentTerminalContent(
        pane: Pane,
        initialFrame: NSRect? = nil,
        treatAsRestoredSessionStart: Bool = false,
        authority: TerminalSurfaceCreationAuthority
    ) -> NSView? {
        guard case .terminal = pane.content else {
            preconditionFailure("nonterminal pane entered the terminal content owner")
        }
        viewRegistry.ensureSlot(for: pane.id)

        let mountedView: NSView?
        if let worktreeID = pane.worktreeId,
            let repoID = pane.repoId,
            let worktree = store.repositoryTopologyAtom.worktree(worktreeID),
            let repo = store.repositoryTopologyAtom.repo(repoID)
        {
            mountedView = createView(
                for: pane,
                worktree: worktree,
                repo: repo,
                initialFrame: initialFrame,
                treatAsRestoredSessionStart: treatAsRestoredSessionStart
            )
        } else if let parentPaneID = pane.parentPaneId,
            let parentPane = store.paneAtom.pane(parentPaneID),
            let worktreeID = parentPane.worktreeId,
            let repoID = parentPane.repoId,
            let worktree = store.repositoryTopologyAtom.worktree(worktreeID),
            let repo = store.repositoryTopologyAtom.repo(repoID)
        {
            mountedView = createView(
                for: pane,
                worktree: worktree,
                repo: repo,
                initialFrame: initialFrame,
                treatAsRestoredSessionStart: treatAsRestoredSessionStart
            )
        } else {
            switch createTopologyIndependentTerminalView(
                for: pane,
                initialFrame: initialFrame,
                treatAsRestoredSessionStart: treatAsRestoredSessionStart,
                authority: authority
            ) {
            case .mounted(let mountedContent):
                mountedView = mountedContent.view
            case .failed:
                mountedView = nil
            }
        }
        guard let mountedView else { return nil }
        registerPaneFilesystemContextIfNeeded(for: pane)
        return mountedView
    }

    /// Mount a terminal from accepted composition without consulting repository
    /// topology or canonical atoms for identity, launch, or content selection.
    ///
    /// `authority` is a compile-time witness only. `PreparedTerminalMountAdmissionPort`
    /// mints and passes `.prepared(claim)` here after its own successful
    /// `pending -> mounting` claim; there is no default value.
    @discardableResult
    func mountPreparedTerminalContent(
        admission: TerminalActivationAdmission,
        initialFrame: NSRect?,
        authority: TerminalSurfaceCreationAuthority
    ) async -> TerminalActivationAttemptResult {
        let pane = admission.descriptor.pane
        guard case .terminal = pane.content else {
            preconditionFailure("nonterminal pane entered prepared terminal activation")
        }
        if pane.provider == .zmx, initialFrame == nil {
            return .failed(
                failure: .surfaceCreationFailed(code: "trusted_initial_frame_unavailable"),
                retry: .doNotRetry
            )
        }

        // SR6b (Program Design item 13): a cold pane arms its restore phase
        // and awaits the acknowledgment before its surface is ever created —
        // never an unarmed cold surface. Warm, unverified and nil kinds skip
        // this entirely; they never suspend here.
        var armedRestoreGeneration: RestoreGeneration?
        var coldStartObserver: ColdStartObserver?
        var coldStartPlan: TerminalColdRestorePlan?
        if case .cold(let plan) = admission.restoreKind {
            let generation = RestoreGenerationAllocator.allocate()
            let acknowledgment = await Ghostty.ActionRouter.armRestorePhase(
                paneID: pane.id,
                restoreGeneration: generation
            )
            guard acknowledgment == .armed else {
                return .failed(
                    failure: .surfaceCreationFailed(code: "restore_phase_unarmed"),
                    retry: .doNotRetry
                )
            }
            armedRestoreGeneration = generation

            // Program Design item 3: never a cold surface with no pending
            // startup-window observer either. Registered before the surface
            // (and the attach command that could exit fast) exists, so a
            // `showChildExited` racing registration is never missed.
            let observer = ColdStartObserver()
            Ghostty.ActionRouter.registerColdStartAttachExitObserver(paneID: pane.id, observer: observer)
            coldStartObserver = observer
            coldStartPlan = plan
        }

        viewRegistry.ensureSlot(for: pane.id)
        switch createTopologyIndependentTerminalView(
            for: pane,
            initialFrame: initialFrame,
            treatAsRestoredSessionStart: true,
            authority: authority,
            restoreKind: admission.restoreKind,
            armedRestoreGeneration: armedRestoreGeneration
        ) {
        case .mounted(let mountedContent):
            if let coldStartObserver, let coldStartPlan {
                beginObservingColdStart(paneID: pane.id, plan: coldStartPlan, observer: coldStartObserver)
            }
            return .ready(surfaceID: mountedContent.surfaceID)
        case .failed(.surfaceAttachmentFailed):
            if coldStartObserver != nil {
                Ghostty.ActionRouter.unregisterColdStartAttachExitObserver(paneID: pane.id)
            }
            return .failed(
                failure: .surfaceAttachmentFailed(code: "prepared_surface_attachment_failed"),
                retry: .retry
            )
        case .failed:
            if coldStartObserver != nil {
                Ghostty.ActionRouter.unregisterColdStartAttachExitObserver(paneID: pane.id)
            }
            return .failed(
                failure: .surfaceCreationFailed(code: "prepared_mount_failed"),
                retry: .retry
            )
        }
    }

    /// Program Design item 4 ("Staggered starts"): the existing single-worker
    /// activation drain (`TerminalActivationScheduler`,
    /// `restoreMaximumConcurrentAdmissions == 1`) already starts cold panes
    /// one at a time, visible first — a separate start slot would only
    /// stall every other queued pane behind a blocked cold one, since that
    /// worker cannot skip a candidate and come back to it. A dedicated start
    /// limit is added only if a future measurement shows it's needed.
    /// Runs detached from `mountPreparedTerminalContent`'s own return so a
    /// slow or pending window never delays activation settlement. Owned by
    /// `coldStartObservationTasksByPaneID` so retirement and coordinator
    /// teardown can cancel it, and a test can await its outcome fact instead
    /// of idling.
    /// Not `private`: a dedicated test suite calls this directly with a
    /// scripted `ColdStartObserverSyscalls` to prove the task-ownership and
    /// fact-sink wiring without needing surface creation to succeed (see
    /// `WorkspaceSurfaceCoordinatorColdStartObservationTests`).
    func beginObservingColdStart(
        paneID: UUID,
        plan: TerminalColdRestorePlan,
        observer: ColdStartObserver
    ) {
        let observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome: ColdStartOutcome
            if let bootID = try? await WorkspaceUndoJournalClock.current().bootID {
                let socketPath = plan.zmxDirectory.appending(path: plan.sessionID.rawValue).path
                outcome = await observer.observeColdStart(
                    zmxDirectory: plan.zmxDirectory,
                    socketPath: socketPath,
                    bootID: bootID,
                    attemptID: plan.attemptID
                )
            } else {
                outcome = .unobservable(.identityUnverifiable)
            }
            Ghostty.ActionRouter.unregisterColdStartAttachExitObserver(paneID: paneID)
            self.coldStartObservationTasksByPaneID.removeValue(forKey: paneID)
            self.handleColdStartOutcome(outcome, paneID: paneID)
        }
        coldStartObservationTasksByPaneID[paneID] = observationTask
    }

    /// SR5: the specific failure reason still needs the existing
    /// overlay-owner wiring (Program Design item 3's "existing placeholder
    /// and overlay owner"); `.unobservable` never reaches the person at all
    /// ("the reason goes to telemetry only" — `RestoreTrace.log` here is
    /// this restore code path's own established local-diagnostic channel,
    /// gated behind `AGENTSTUDIO_RESTORE_TRACE`, not OTLP). The fact sink
    /// runs after the task above already removed itself from the dictionary
    /// (`docs/specs/2026-09-28-typed-fact-test-harness`) — no suspension
    /// between the outcome settling and a test observing it.
    private func handleColdStartOutcome(_ outcome: ColdStartOutcome, paneID: UUID) {
        switch outcome {
        case .handedOff:
            RestoreTrace.log("coldStart handedOff pane=\(paneID)")
        case .failed(let failure):
            RestoreTrace.log("coldStart failed pane=\(paneID) failure=\(failure)")
        case .unobservable(let reason):
            RestoreTrace.log("coldStart unobservable pane=\(paneID) reason=\(reason)")
        }
        coldStartObservationFactSink?(paneID, outcome)
    }
}
