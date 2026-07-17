import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace pane residency lifecycle owner")
struct WorkspacePaneResidencyLifecycleOwnerTests {
    @Test("double background preserves the original payload and revision")
    func doubleBackgroundPreservesPayload() throws {
        // Arrange
        let fixture = try makePaneResidencyLifecycleOwnerFixture()

        // Act
        let first = fixture.runtime.paneResidencyLifecycleOwner.backgroundPane(
            .init(paneID: fixture.residency.parent.id)
        )
        let firstPayload = fixture.runtime.paneResidencyLifecycleOwner.retainedDrawerPayload(
            forPane: fixture.residency.parent.id
        )
        let second = fixture.runtime.paneResidencyLifecycleOwner.backgroundPane(
            .init(paneID: fixture.residency.parent.id)
        )

        // Assert
        guard case .changed(let firstRevision) = first else {
            Issue.record("expected first background to change")
            return
        }
        #expect(firstRevision.rawValue == 1)
        guard case .present = firstPayload else {
            Issue.record("expected retained drawer payload")
            return
        }
        #expect(second == .unchanged(revision: firstRevision))
        #expect(
            fixture.runtime.paneResidencyLifecycleOwner.retainedDrawerPayload(
                forPane: fixture.residency.parent.id
            ) == firstPayload
        )
        #expect(fixture.runtime.revisionOwner.committedRevision == firstRevision)
    }

    @Test("rejected reactivation preserves payload and produces no mount")
    func rejectedReactivationPreservesPayload() throws {
        // Arrange
        let fixture = try makePaneResidencyLifecycleOwnerFixture()
        _ = fixture.runtime.paneResidencyLifecycleOwner.backgroundPane(
            .init(paneID: fixture.residency.parent.id)
        )
        let retainedPayload = fixture.runtime.paneResidencyLifecycleOwner.retainedDrawerPayload(
            forPane: fixture.residency.parent.id
        )
        let missingTabID = UUIDv7.generate()
        var request = fixture.residency.reactivateRequest()
        request = .init(
            paneID: request.paneID,
            targetTabID: missingTabID,
            targetPaneID: request.targetPaneID,
            direction: request.direction,
            position: request.position,
            sizingMode: request.sizingMode
        )

        // Act
        let result = fixture.runtime.paneResidencyLifecycleOwner.reactivatePane(request)

        // Assert
        #expect(result == .rejected(.planning(.targetTabMissing(missingTabID))))
        #expect(
            fixture.runtime.paneResidencyLifecycleOwner.retainedDrawerPayload(
                forPane: fixture.residency.parent.id
            ) == retainedPayload
        )
        #expect(fixture.runtime.revisionOwner.committedRevision.rawValue == 1)
    }

    @Test("successful reactivation consumes once and emits one mount intent")
    func successfulReactivationConsumesOnce() throws {
        // Arrange
        let fixture = try makePaneResidencyLifecycleOwnerFixture()
        _ = fixture.runtime.paneResidencyLifecycleOwner.backgroundPane(
            .init(paneID: fixture.residency.parent.id)
        )

        // Act
        let first = fixture.runtime.paneResidencyLifecycleOwner.reactivatePane(
            fixture.residency.reactivateRequest()
        )
        let second = fixture.runtime.paneResidencyLifecycleOwner.reactivatePane(
            fixture.residency.reactivateRequest()
        )

        // Assert
        guard case .changed(let revision, let mountIntent) = first else {
            Issue.record("expected successful reactivation")
            return
        }
        #expect(revision.rawValue == 2)
        #expect(mountIntent.paneID == fixture.residency.parent.id)
        #expect(second == .unchanged(revision: revision))
        #expect(
            fixture.runtime.paneResidencyLifecycleOwner.retainedDrawerPayload(
                forPane: fixture.residency.parent.id
            ) == .absent
        )
        #expect(fixture.runtime.revisionOwner.committedRevision == revision)
    }

    @Test("background without drawer children stores no stale payload")
    func emptyDrawerStoresAbsentPayload() throws {
        // Arrange
        let fixture = try makePaneResidencyLifecycleOwnerFixture(hasDrawerChildren: false)

        // Act
        let first = fixture.runtime.paneResidencyLifecycleOwner.backgroundPane(
            .init(paneID: fixture.residency.parent.id)
        )
        let second = fixture.runtime.paneResidencyLifecycleOwner.backgroundPane(
            .init(paneID: fixture.residency.parent.id)
        )

        // Assert
        guard case .changed(let revision) = first else {
            Issue.record("expected empty-drawer background to change")
            return
        }
        #expect(second == .unchanged(revision: revision))
        #expect(
            fixture.runtime.paneResidencyLifecycleOwner.retainedDrawerPayload(
                forPane: fixture.residency.parent.id
            ) == .absent
        )
    }
}

private struct PaneResidencyLifecycleOwnerFixture {
    let runtime: WorkspacePersistenceRuntime
    let residency: PaneResidencyFixture
}

private enum PaneResidencyLifecycleOwnerTestError: Error {
    case participantInstallationFailed
}

@MainActor
private func makePaneResidencyLifecycleOwnerFixture(
    hasDrawerChildren: Bool = true
) throws -> PaneResidencyLifecycleOwnerFixture {
    let residency = lifecycleResidencyFixture(hasDrawerChildren: hasDrawerChildren)
    let atomRegistry = AtomRegistry()
    for paneState in [residency.parent] + residency.children + [residency.otherPane] {
        atomRegistry.workspacePaneGraph.setCanonicalPaneState(paneState)
    }
    atomRegistry.workspaceTabShell.replaceTabShells([
        TabShell(id: residency.tabID, name: "Target")
    ])
    atomRegistry.workspaceTabCursor.replaceActiveTab(residency.tabID)
    atomRegistry.workspaceTabGraph.replaceTabStates([residency.tabState])
    atomRegistry.workspaceArrangementCursor.replaceCursors(
        activeArrangementIdsByTabId: [residency.tabID: residency.arrangementIDs[0]],
        paneCursorsByArrangementId: residency.cursors.activePanesByArrangementID.mapValues { witness in
            guard case .present(let selection) = witness else {
                return ArrangementPaneCursorState(activePaneId: nil)
            }
            switch selection {
            case .noSelection: return ArrangementPaneCursorState(activePaneId: nil)
            case .selected(let paneID): return ArrangementPaneCursorState(activePaneId: paneID)
            }
        },
        drawerCursorsByKey: residency.cursors.activeDrawerChildrenByKey.compactMapValues { witness in
            guard case .present(let selection) = witness else { return nil }
            switch selection {
            case .noSelection: return ArrangementDrawerCursorState(activeChildId: nil)
            case .selected(let childID): return ArrangementDrawerCursorState(activeChildId: childID)
            }
        }
    )
    atomRegistry.workspacePanePresentation.setZoomedPaneId(
        residency.parent.id,
        forTab: residency.tabID
    )
    let runtime = WorkspacePersistenceRuntime(atomRegistry: atomRegistry)
    guard case .constructed = runtime.snapshotParticipantFactory.constructCompositionParticipantSet()
    else {
        throw PaneResidencyLifecycleOwnerTestError.participantInstallationFailed
    }
    return .init(runtime: runtime, residency: residency)
}

private func lifecycleResidencyFixture(
    hasDrawerChildren: Bool
) -> PaneResidencyFixture {
    let base = makeResidencyFixture()
    guard !hasDrawerChildren else { return base }
    var parent = base.parent
    guard case .layout(var drawer) = parent.kind else {
        preconditionFailure("residency fixture parent must own a drawer")
    }
    drawer.paneIds = []
    parent.kind = .layout(drawer: drawer)
    var tabState = base.tabState
    let removedChildIDs = Set(base.children.map(\.id))
    tabState.allPaneIds.removeAll { removedChildIDs.contains($0) }
    for arrangementIndex in tabState.arrangements.indices {
        tabState.arrangements[arrangementIndex].drawerViews = [:]
    }
    let owner = WorkspacePaneResidencyTabOwnershipWitness.owned(
        .init(index: 0, state: tabState)
    )
    return PaneResidencyFixture(
        parent: parent,
        children: [],
        otherPane: base.otherPane,
        drawerID: base.drawerID,
        tabID: base.tabID,
        arrangementIDs: base.arrangementIDs,
        tabState: tabState,
        ownership: owner,
        ownershipByPaneID: [parent.id: owner],
        childStatesByID: [:],
        cursors: .init(
            activeArrangement: base.cursors.activeArrangement,
            activePanesByArrangementID: base.cursors.activePanesByArrangementID,
            activeDrawerChildrenByKey: [:],
            zoom: base.cursors.zoom
        )
    )
}
