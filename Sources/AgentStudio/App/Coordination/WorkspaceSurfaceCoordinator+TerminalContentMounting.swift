import AgentStudioCore
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
        if case .cold = admission.restoreKind {
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
            return .ready(surfaceID: mountedContent.surfaceID)
        case .failed(.surfaceAttachmentFailed):
            return .failed(
                failure: .surfaceAttachmentFailed(code: "prepared_surface_attachment_failed"),
                retry: .retry
            )
        case .failed:
            return .failed(
                failure: .surfaceCreationFailed(code: "prepared_mount_failed"),
                retry: .retry
            )
        }
    }
}
