import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace layout resize persistence gateway")
struct WorkspaceLayoutResizePersistenceGatewayTests {
    @Test("preinstall rejects and installed resize retains one base preimage")
    func installedResizeRetainsBasePreimage() throws {
        // Arrange
        let fixture = makeTabGraphLeafFixture()
        let registry = AtomRegistry()
        registry.workspaceTabGraph.replaceTabStates([fixture.tabState])
        registry.workspaceArrangementCursor.replaceCursors(
            activeArrangementIdsByTabId: [fixture.tabState.tabId: fixture.customArrangementID],
            paneCursorsByArrangementId: [:],
            drawerCursorsByKey: [:]
        )
        let runtime = WorkspacePersistenceRuntime(atomRegistry: registry)
        let splitID = fixture.tabState.arrangements[1].layout.dividerIds[0]
        let checkpoint = WorkspaceLayoutResizeCheckpoint.mainSplit(
            tabID: fixture.tabState.tabId,
            arrangementID: fixture.customArrangementID,
            splitID: splitID,
            ratio: 0.4
        )

        // Act
        let preinstall = runtime.mutationCoordinator.applyLayoutResizeCheckpoint(checkpoint)
        guard
            case .constructed(let participantSet) = runtime.snapshotParticipantFactory
                .constructCompositionParticipantSet(),
            let participant = participantSet.participants.first(where: { $0.participantID == .tabGraphs })
        else {
            Issue.record("expected tab graph participant")
            return
        }
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: runtime.revisionOwner
        )
        #expect(participant.open(lease: lease) == .opened(baseMembershipCount: 1))
        let rejected = runtime.mutationCoordinator.applyLayoutResizeCheckpoint(
            .mainSplit(
                tabID: fixture.tabState.tabId,
                arrangementID: fixture.customArrangementID,
                splitID: UUIDv7.generate(),
                ratio: 0.5
            )
        )
        let unchanged = runtime.mutationCoordinator.applyLayoutResizeCheckpoint(
            .mainSplit(
                tabID: fixture.tabState.tabId,
                arrangementID: fixture.customArrangementID,
                splitID: splitID,
                ratio: 0.7
            )
        )
        #expect(runtime.revisionOwner.committedRevision == .zero)
        let changed = runtime.mutationCoordinator.applyLayoutResizeCheckpoint(checkpoint)

        // Assert
        #expect(preinstall == .rejected(.compositionDomainNotInstalled(phase: .preinstall)))
        guard case .rejected(.planning(.missingMainSplit)) = rejected else {
            Issue.record("expected installed planning rejection")
            return
        }
        #expect(unchanged == .unchanged(revision: .zero))
        guard case .changed(let revision) = changed else {
            Issue.record("expected changed resize persistence result")
            return
        }
        #expect(revision.rawValue == 1)
        guard case .item(let item, _, _, _) = participant.inspectBaseSlot(lease: lease, slotCursor: 0) else {
            Issue.record("expected tab graph base item")
            return
        }
        #expect(item.item == .tabGraph(fixture.tabState))
        _ = participant.close(lease: lease)
    }
}
