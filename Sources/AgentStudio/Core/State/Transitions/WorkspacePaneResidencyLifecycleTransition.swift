import Foundation

struct WorkspaceBackgroundPaneRequest: Equatable, Sendable {
    let paneID: UUID
}

struct WorkspaceReactivatePaneRequest: Equatable, Sendable {
    let paneID: UUID
    let targetTabID: UUID
    let targetPaneID: UUID
    let direction: Layout.SplitDirection
    let position: Layout.Position
    let sizingMode: DropSizingMode
}

enum WorkspacePaneResidencyPaneWitness: Equatable, Sendable {
    case missing
    case present(PaneGraphState)
}

enum WorkspacePaneResidencyTabOwnershipWitness: Equatable, Sendable {
    case absent
    case owned(WorkspaceIndexedTabGraphState)
    case multiple([UUID])
}

enum WorkspacePaneResidencyDrawerSelection: Equatable, Sendable {
    case noSelection
    case selected(UUID)
}

enum WorkspacePaneResidencyDrawerCursorWitness: Equatable, Sendable {
    case missing
    case present(WorkspacePaneResidencyDrawerSelection)
}

struct WorkspacePaneResidencyTabCursorSnapshot: Equatable, Sendable {
    let activeArrangement: WorkspaceActiveArrangementSelection
    let activePanesByArrangementID: [UUID: WorkspaceActivePaneCursorWitness]
    let activeDrawerChildrenByKey: [ArrangementDrawerCursorKey: WorkspacePaneResidencyDrawerCursorWitness]
    let zoom: WorkspaceZoomSelection
}

enum WorkspaceBackgroundTabRemovalContext: Equatable, Sendable {
    case notRequired
    case current(tabShells: [TabShell], activeTab: WorkspaceTabCursorSelection)
}

struct WorkspaceBackgroundedDrawerPayload: Equatable, Sendable {
    let drawerID: UUID
    let viewsByArrangementID: [UUID: DrawerView]
}

enum WorkspaceRetainedDrawerPayloadWitness: Equatable, Sendable {
    case absent
    case present(WorkspaceBackgroundedDrawerPayload)
}

struct WorkspaceBackgroundPanePlanningContext: Equatable, Sendable {
    let pane: WorkspacePaneResidencyPaneWitness
    let declaredDrawerChildrenByID: [UUID: PaneGraphState]
    let ownershipByPaneID: [UUID: WorkspacePaneResidencyTabOwnershipWitness]
    let tabCursors: WorkspacePaneResidencyTabCursorSnapshot
    let tabRemoval: WorkspaceBackgroundTabRemovalContext
    let retainedDrawerPayload: WorkspaceRetainedDrawerPayloadWitness
}

enum WorkspaceTargetTabWitness: Equatable, Sendable {
    case missing
    case present(WorkspaceIndexedTabGraphState)
}

struct WorkspaceReactivatePanePlanningContext: Equatable, Sendable {
    let pane: WorkspacePaneResidencyPaneWitness
    let declaredDrawerChildrenByID: [UUID: PaneGraphState]
    let ownershipByPaneID: [UUID: WorkspacePaneResidencyTabOwnershipWitness]
    let targetTab: WorkspaceTargetTabWitness
    let targetTabCursors: WorkspacePaneResidencyTabCursorSnapshot
    let retainedDrawerPayload: WorkspaceRetainedDrawerPayloadWitness
}

struct WorkspacePaneResidencyPaneReplacement: Equatable, Sendable {
    let paneID: UUID
    let previous: PaneGraphState
    let replacement: PaneGraphState
}

enum WorkspacePaneResidencyTabGraphMutation: Equatable, Sendable {
    case replace(previous: WorkspaceIndexedTabGraphState, replacement: WorkspaceIndexedTabGraphState)
    case remove(WorkspaceIndexedTabGraphState)
}

enum WorkspacePaneResidencyTabShellMutation: Equatable, Sendable {
    case notRead
    case remove(removed: WorkspaceIndexedTabShell, shiftedSuffix: [WorkspaceIndexedTabShell])
}

struct WorkspacePaneResidencyFamilyOwnershipWitness: Equatable, Sendable {
    let paneID: UUID
    let expected: WorkspacePaneResidencyTabOwnershipWitness
}

enum WorkspacePaneResidencyTabCursorMutation: Equatable, Sendable {
    case notRead
    case witness(WorkspaceTabCursorSelection)
    case replace(WorkspaceTabCursorReplacement)
}

enum WorkspacePaneResidencyActiveArrangementMutation: Equatable, Sendable {
    case witness(tabID: UUID, expected: WorkspaceActiveArrangementSelection)
    case remove(tabID: UUID, previous: UUID)
}

enum WorkspacePaneResidencyActivePaneMutation: Equatable, Sendable {
    case witness(arrangementID: UUID, expected: WorkspaceActivePaneCursorWitness)
    case replace(
        arrangementID: UUID,
        previous: WorkspaceActivePaneCursorWitness,
        replacement: WorkspacePaneSelection
    )
    case remove(arrangementID: UUID, previous: WorkspaceActivePaneCursorWitness)
}

enum WorkspacePaneResidencyActiveDrawerMutation: Equatable, Sendable {
    case witness(key: ArrangementDrawerCursorKey, expected: WorkspacePaneResidencyDrawerCursorWitness)
    case insert(
        key: ArrangementDrawerCursorKey,
        expected: WorkspacePaneResidencyDrawerCursorWitness,
        replacement: WorkspacePaneResidencyDrawerSelection
    )
    case replace(
        key: ArrangementDrawerCursorKey,
        previous: WorkspacePaneResidencyDrawerCursorWitness,
        replacement: WorkspacePaneResidencyDrawerSelection
    )
    case remove(key: ArrangementDrawerCursorKey, previous: WorkspacePaneResidencyDrawerCursorWitness)
}

enum WorkspacePaneResidencyZoomMutation: Equatable, Sendable {
    case witness(tabID: UUID, expected: WorkspaceZoomSelection)
    case clear(tabID: UUID, previous: UUID)
}

enum WorkspacePaneResidencyRuntimeEffect: Equatable, Sendable {
    case replaceRetainedDrawerPayload(
        paneID: UUID,
        replacement: WorkspaceRetainedDrawerPayloadWitness
    )
    case consumeRetainedDrawerPayloadAndMount(paneID: UUID)
}

struct WorkspacePaneResidencyRuntimePayloadTransition: Equatable, Sendable {
    let expected: WorkspaceRetainedDrawerPayloadWitness
    let effect: WorkspacePaneResidencyRuntimeEffect
}

struct WorkspaceBackgroundPaneTransition: Equatable, Sendable {
    let paneReplacements: [WorkspacePaneResidencyPaneReplacement]
    let familyOwnership: [WorkspacePaneResidencyFamilyOwnershipWitness]
    let tabGraph: WorkspacePaneResidencyTabGraphMutation
    let tabShell: WorkspacePaneResidencyTabShellMutation
    let tabCursor: WorkspacePaneResidencyTabCursorMutation
    let activeArrangements: [WorkspacePaneResidencyActiveArrangementMutation]
    let activePanes: [WorkspacePaneResidencyActivePaneMutation]
    let activeDrawerChildren: [WorkspacePaneResidencyActiveDrawerMutation]
    let zoom: WorkspacePaneResidencyZoomMutation
    let runtimePayload: WorkspacePaneResidencyRuntimePayloadTransition
}

struct WorkspaceReactivatePaneTransition: Equatable, Sendable {
    let paneReplacements: [WorkspacePaneResidencyPaneReplacement]
    let familyOwnership: [WorkspacePaneResidencyFamilyOwnershipWitness]
    let tabGraph: WorkspacePaneResidencyTabGraphMutation
    let activeArrangements: [WorkspacePaneResidencyActiveArrangementMutation]
    let activePanes: [WorkspacePaneResidencyActivePaneMutation]
    let activeDrawerChildren: [WorkspacePaneResidencyActiveDrawerMutation]
    let zoom: WorkspacePaneResidencyZoomMutation
    let runtimePayload: WorkspacePaneResidencyRuntimePayloadTransition
}

enum WorkspacePaneResidencyLifecycleTransition: Equatable, Sendable {
    case background(WorkspaceBackgroundPaneTransition)
    case reactivate(WorkspaceReactivatePaneTransition)
}

enum WorkspacePaneResidencyLifecycleRejection: Equatable, Sendable {
    case activeArrangementMissing(UUID)
    case activeArrangementNotInTab(tabID: UUID, arrangementID: UUID)
    case childIdentityMismatch(expected: UUID, actual: UUID)
    case childMissing(UUID)
    case childParentMismatch(childID: UUID, expectedParentID: UUID, actualParentID: UUID?)
    case childResidencyMismatch(childID: UUID, expected: SessionResidency, actual: SessionResidency)
    case drawerChildPane(UUID)
    case drawerCursorMissing(ArrangementDrawerCursorKey)
    case drawerCursorSelectionInvalid(ArrangementDrawerCursorKey)
    case invalidPaneResidency(paneID: UUID, actual: SessionResidency)
    case layoutInsertionRejected(tabID: UUID, targetPaneID: UUID)
    case paneAlreadyOwnedByTab(paneID: UUID, tabID: UUID)
    case paneIdentityMismatch(expected: UUID, actual: UUID)
    case paneMissing(UUID)
    case paneNotOwnedByTab(UUID)
    case paneOwnedByMultipleTabs(paneID: UUID, tabIDs: [UUID])
    case paneOwnershipWitnessMissing(UUID)
    case paneOwnerMismatch(paneID: UUID, expectedTabID: UUID, actualTabID: UUID?)
    case paneSelectionInvalid(arrangementID: UUID)
    case retainedDrawerPayloadMismatch(expectedDrawerID: UUID, actualDrawerID: UUID)
    case retainedDrawerPayloadInvalidMembership(arrangementID: UUID, expected: [UUID], actual: [UUID])
    case retainedDrawerPayloadInvalidMinimized(arrangementID: UUID, invalidPaneIDs: Set<UUID>)
    case retainedDrawerPayloadInvalidActiveChild(arrangementID: UUID, activeChildID: UUID?)
    case tabCursorInvalid(UUID)
    case tabRemovalContextMissing(UUID)
    case tabRemovalContextUnexpected(UUID)
    case tabShellMissing(UUID)
    case targetPaneMissing(tabID: UUID, paneID: UUID)
    case targetTabMissing(UUID)
}

enum WorkspaceBackgroundPaneTransitionDecision: Equatable, Sendable {
    case changed(WorkspacePaneResidencyLifecycleTransition)
    case unchanged
    case rejected(WorkspacePaneResidencyLifecycleRejection)
}

enum WorkspaceReactivatePaneTransitionDecision: Equatable, Sendable {
    case changed(WorkspacePaneResidencyLifecycleTransition)
    case unchanged
    case rejected(WorkspacePaneResidencyLifecycleRejection)
}
