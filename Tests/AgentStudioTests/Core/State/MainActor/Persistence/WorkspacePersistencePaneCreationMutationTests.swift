import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace persistence pane creation mutation")
struct WorkspacePersistencePaneCreationMutationTests {
    @Test("accepted pane and tab creation commits every owner in one revision")
    func acceptedPaneCreationCommitsOneRevision() throws {
        // Arrange
        let atomRegistry = AtomRegistry()
        let baseline = makeBaselinePaneTabState()
        installBaseline(baseline, in: atomRegistry)
        let runtime = WorkspacePersistenceRuntime(atomRegistry: atomRegistry)
        let fixedBase = try installCompositionAndOpenFixedBase(runtime)
        let expectedFixedBaseItems: [WorkspacePersistenceSnapshotParticipantID: WorkspacePersistenceSnapshotItem] = [
            .paneGraphs: .paneGraph(baseline.paneState),
            .tabShells: .tabShell(.init(shell: baseline.shell, sortIndex: 0)),
            .activeTab: .activeTab(baseline.tabID),
            .tabGraphs: .tabGraph(baseline.graph),
            .activeArrangements: .activeArrangement(
                tabID: baseline.tabID,
                arrangementID: baseline.arrangementID
            ),
            .activePanes: .activePane(
                arrangementID: baseline.arrangementID,
                paneID: baseline.paneState.id
            ),
        ]
        for participantID in expectedFixedBaseItems.keys {
            let participant = try requireCompositionParticipant(
                participantID,
                from: fixedBase.participantSet
            )
            #expect(participant.open(lease: fixedBase.lease) == .opened(baseMembershipCount: 1))
        }
        let identities = try #require(makePersistencePaneCreationIdentities())
        let transition = try makePaneCreationTransition(
            identities: identities,
            runtime: runtime
        )

        // Act
        let result = runtime.mutationCoordinator.commitPaneCreation(transition)
        let repeatedResult = runtime.mutationCoordinator.commitPaneCreation(transition)

        // Assert
        guard case .committed(let committedRevision) = result else {
            Issue.record("expected committed pane-creation result")
            return
        }
        #expect(committedRevision.rawValue == 1)
        #expect(
            repeatedResult
                == .rejected(
                    .paneTabApplication(.paneAlreadyExists(identities.paneID.uuid))
                )
        )
        #expect(runtime.revisionOwner.committedRevision.rawValue == 1)
        #expect(atomRegistry.workspacePaneGraph.paneState(identities.paneID.uuid) == transition.paneState)
        #expect(atomRegistry.workspaceTabShell.tabShell(identities.tabID)?.id == identities.tabID)
        #expect(atomRegistry.workspaceTabShell.activeTabId == identities.tabID)
        #expect(atomRegistry.workspaceTabGraph.tabState(identities.tabID)?.tabId == identities.tabID)
        #expect(
            atomRegistry.workspaceArrangementCursor.activeArrangementId(forTab: identities.tabID)
                == identities.arrangementID
        )
        #expect(
            atomRegistry.workspaceArrangementCursor.activePaneId(forArrangement: identities.arrangementID)
                == identities.paneID.uuid
        )
        for (participantID, expectedItem) in expectedFixedBaseItems {
            let participant = try requireCompositionParticipant(
                participantID,
                from: fixedBase.participantSet
            )
            guard
                case .item(let projectedItem, _, _, _) = participant.inspectBaseSlot(
                    lease: fixedBase.lease,
                    slotCursor: 0
                )
            else {
                Issue.record("expected literal revision-zero item from \(participantID)")
                return
            }
            #expect(projectedItem.item == expectedItem)
            guard case .exhausted = participant.inspectBaseSlot(lease: fixedBase.lease, slotCursor: 1) else {
                Issue.record("expected post-base insertion exclusion from \(participantID)")
                return
            }
            _ = participant.close(lease: fixedBase.lease)
        }
        #expect(fixedBase.lease.baseRevision == .zero)
    }
}

private struct BaselinePaneTabState {
    let paneState: PaneGraphState
    let tabID: UUID
    let shell: TabShell
    let graph: TabGraphState
    let arrangementID: UUID
}

@MainActor
private func installBaseline(_ baseline: BaselinePaneTabState, in atomRegistry: AtomRegistry) {
    atomRegistry.workspacePaneGraph.setCanonicalPaneState(baseline.paneState)
    atomRegistry.workspaceTabShell.insertTabShell(baseline.shell, at: 0)
    atomRegistry.workspaceTabGraph.insertTabState(baseline.graph, at: 0)
    atomRegistry.workspaceArrangementCursor.insertActiveArrangementId(
        baseline.arrangementID,
        forTab: baseline.tabID
    )
    atomRegistry.workspaceArrangementCursor.insertPaneCursor(
        .init(activePaneId: baseline.paneState.id),
        forArrangement: baseline.arrangementID
    )
    atomRegistry.workspaceTabCursor.replaceActiveTab(baseline.tabID)
}

private func makeBaselinePaneTabState() -> BaselinePaneTabState {
    let paneID = UUIDv7.generate()
    let tabID = UUIDv7.generate()
    let arrangementID = UUIDv7.generate()
    let paneState = PaneGraphState(
        pane: Pane(
            id: paneID,
            content: .terminal(.init(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())),
            metadata: PaneMetadata(title: "Baseline")
        )
    )
    let arrangement = PaneArrangementGraphState(
        id: arrangementID,
        name: "Default",
        isDefault: true,
        layout: Layout(paneId: paneID),
        minimizedPaneIds: [],
        showsMinimizedPanes: false,
        drawerViews: [:]
    )
    return BaselinePaneTabState(
        paneState: paneState,
        tabID: tabID,
        shell: TabShell(id: tabID, name: "Baseline"),
        graph: TabGraphState(
            tabId: tabID,
            allPaneIds: [paneID],
            arrangements: [arrangement]
        ),
        arrangementID: arrangementID
    )
}

@MainActor
private func makePaneCreationTransition(
    identities: WorkspaceNewPaneTabIDs,
    runtime: WorkspacePersistenceRuntime
) throws -> WorkspacePaneCreationTransition {
    let contextCapture = WorkspacePaneCreationContextBuilder(
        workspacePaneGraphAtom: runtime.atomOwners.workspacePaneGraph,
        workspaceTabShellAtom: runtime.atomOwners.workspaceTabShell,
        workspaceTabGraphAtom: runtime.atomOwners.workspaceTabGraph,
        workspaceArrangementCursorAtom: runtime.atomOwners.workspaceArrangementCursor
    ).capture(identities: identities)
    guard case .captured(let context) = contextCapture else {
        throw WorkspacePersistencePaneCreationMutationTestError.contextRejected
    }
    let decision = WorkspacePaneCreationTransitionDecider.decide(
        request: WorkspacePaneCreationRequest(
            identities: identities,
            content: .webview(WebviewState(url: URL(string: "https://example.com")!)),
            metadata: PaneMetadata(title: "Web"),
            residency: .active,
            tabName: "Web"
        ),
        context: context
    )
    guard case .changed(let transition) = decision else {
        throw WorkspacePersistencePaneCreationMutationTestError.transitionRejected
    }
    return transition
}

@MainActor
private func installCompositionAndOpenFixedBase(
    _ runtime: WorkspacePersistenceRuntime
) throws -> (
    participantSet: WorkspacePersistenceSnapshotParticipantSet,
    lease: WorkspaceStateSnapshotLease
) {
    guard
        case .constructed(let participantSet) = runtime.snapshotParticipantFactory
            .constructCompositionParticipantSet()
    else {
        throw WorkspacePersistencePaneCreationMutationTestError.compositionInstallationFailed
    }
    let lease = WorkspaceStateSnapshotLease.open(
        pagerIdentity: .make(),
        revisionOwner: runtime.revisionOwner
    )
    return (participantSet, lease)
}

@MainActor
private func requireCompositionParticipant(
    _ participantID: WorkspacePersistenceSnapshotParticipantID,
    from participantSet: WorkspacePersistenceSnapshotParticipantSet
) throws -> WorkspacePersistenceSnapshotParticipantSet.Participant {
    guard let participant = participantSet.participants.first(where: { $0.participantID == participantID }) else {
        throw WorkspacePersistencePaneCreationMutationTestError.participantMissing(participantID)
    }
    return participant
}

private func makePersistencePaneCreationIdentities() -> WorkspaceNewPaneTabIDs? {
    guard
        case .validated(let identities) = WorkspaceNewPaneTabIDs.prepare(
            paneID: UUIDv7.generate(),
            drawerID: UUIDv7.generate(),
            tabID: UUIDv7.generate(),
            arrangementID: UUIDv7.generate()
        )
    else { return nil }
    return identities
}

private enum WorkspacePersistencePaneCreationMutationTestError: Error {
    case compositionInstallationFailed
    case contextRejected
    case participantMissing(WorkspacePersistenceSnapshotParticipantID)
    case transitionRejected
}
