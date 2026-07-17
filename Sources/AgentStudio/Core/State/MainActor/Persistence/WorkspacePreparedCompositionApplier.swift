import Foundation

struct WorkspaceContentMountGeneration: Hashable, Sendable {
    let id: UUID

    init(id: UUID = UUIDv7.generate()) {
        self.id = id
    }
}

struct WorkspacePreparedContentMountCohort: Equatable, Sendable {
    let generation: WorkspaceContentMountGeneration
    let terminalActivationInput: TerminalActivationInput
    let nonterminalContentMountInput: NonterminalContentMountInput
}

struct WorkspacePreparedCompositionAcceptance: Equatable, Sendable {
    let contentMountCohort: WorkspacePreparedContentMountCohort

    var terminalActivationInput: TerminalActivationInput {
        contentMountCohort.terminalActivationInput
    }

    var nonterminalContentMountInput: NonterminalContentMountInput {
        contentMountCohort.nonterminalContentMountInput
    }
}

enum WorkspacePreparedCompositionApplyFailure: Equatable, Sendable {
    case alreadyInstalled
}

enum WorkspacePreparedCompositionApplyResult: Equatable, Sendable {
    case accepted(WorkspacePreparedCompositionAcceptance)
    case failed(WorkspacePreparedCompositionApplyFailure)
}

@MainActor
struct WorkspacePreparedCompositionOwners {
    let workspaceIdentityAtom: WorkspaceIdentityAtom
    let workspaceWindowMemoryAtom: WorkspaceWindowMemoryAtom
    let workspacePaneGraphAtom: WorkspacePaneGraphAtom
    let workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom
    let workspaceTabShellAtom: WorkspaceTabShellAtom
    let workspaceTabCursorAtom: WorkspaceTabCursorAtom
    let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
}

/// Installs one previously validated workspace composition into its canonical
/// MainActor owners. The prepared value is sealed by
/// `WorkspaceCompositionPreparer`; installation therefore performs only one
/// synchronous sequence of accepted bulk replacements and cannot suspend
/// between owners.
@MainActor
final class WorkspacePreparedCompositionApplier {
    private let owners: WorkspacePreparedCompositionOwners
    private var hasInstalledComposition = false

    init(owners: WorkspacePreparedCompositionOwners) {
        self.owners = owners
    }

    func apply(
        _ prepared: PreparedWorkspaceComposition
    ) -> WorkspacePreparedCompositionApplyResult {
        guard !hasInstalledComposition else {
            return .failed(.alreadyInstalled)
        }

        owners.workspaceIdentityAtom.replaceIdentity(
            workspaceId: prepared.identity.workspaceID,
            workspaceName: prepared.identity.workspaceName,
            createdAt: prepared.identity.createdAt
        )
        owners.workspaceWindowMemoryAtom.replaceWindowMemory(
            sidebarWidth: prepared.windowMemory.sidebarWidth,
            windowFrame: prepared.windowMemory.windowFrame
        )
        owners.workspacePaneGraphAtom.replacePaneStates(prepared.paneGraph.replacement)
        owners.workspaceDrawerCursorAtom.replaceExpandedDrawer(prepared.expandedDrawerID)
        owners.workspaceTabShellAtom.replaceTabShells(prepared.tabShells.shells)
        owners.workspaceTabCursorAtom.replaceActiveTab(prepared.activeTabID)
        owners.workspaceTabGraphAtom.replaceTabStates(prepared.tabGraph.states)
        owners.workspaceArrangementCursorAtom.replaceCursors(
            activeArrangementIdsByTabId: prepared.arrangementCursors.activeArrangementIDsByTabID,
            paneCursorsByArrangementId: prepared.arrangementCursors.paneCursorsByArrangementID,
            drawerCursorsByKey: prepared.arrangementCursors.drawerCursorsByKey
        )
        hasInstalledComposition = true

        return .accepted(
            WorkspacePreparedCompositionAcceptance(
                contentMountCohort: WorkspacePreparedContentMountCohort(
                    generation: WorkspaceContentMountGeneration(),
                    terminalActivationInput: prepared.terminalActivationInput,
                    nonterminalContentMountInput: prepared.nonterminalContentMountInput
                )
            )
        )
    }
}
