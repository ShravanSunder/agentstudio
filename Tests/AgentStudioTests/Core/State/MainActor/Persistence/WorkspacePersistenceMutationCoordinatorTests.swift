import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspacePersistenceMutationCoordinator")
struct WorkspacePersistenceMutationCoordinatorTests {
    @Test("window-memory mutation rejects before composition installation")
    func windowMemoryMutationRejectsBeforeCompositionInstallation() {
        // Arrange
        let runtime = WorkspacePersistenceRuntime(atomRegistry: AtomRegistry())

        // Act
        let result = runtime.mutationCoordinator.setSidebarWidth(333)

        // Assert
        #expect(
            result
                == .rejected(
                    .compositionDomainNotInstalled(phase: .preinstall)
                )
        )
        #expect(runtime.revisionOwner.committedRevision == .zero)
        #expect(runtime.atomOwners.workspaceWindowMemory.sidebarWidth == 250)
    }

    @Test("installed sidebar mutation retains literal aggregate preimage at fixed revision")
    func installedSidebarMutationRetainsLiteralAggregatePreimage() throws {
        // Arrange
        let originalFrame = CGRect(x: 13, y: 21, width: 987, height: 654)
        let atomRegistry = AtomRegistry()
        atomRegistry.workspaceWindowMemory.replaceWindowMemory(
            sidebarWidth: 280,
            windowFrame: originalFrame
        )
        let runtime = WorkspacePersistenceRuntime(atomRegistry: atomRegistry)
        let participant = try installAndOpenWindowMemoryParticipant(runtime: runtime)

        // Act
        let result = runtime.mutationCoordinator.setSidebarWidth(333)

        // Assert
        guard case .changed(let committedRevision) = result else {
            Issue.record("expected installed sidebar mutation to change")
            return
        }
        #expect(committedRevision.rawValue == 1)
        #expect(runtime.revisionOwner.committedRevision.rawValue == 1)
        #expect(atomRegistry.workspaceWindowMemory.sidebarWidth == 333)
        #expect(atomRegistry.workspaceWindowMemory.windowFrame == originalFrame)
        guard
            case .item(let projectedItem, _, _, _) = participant.participant.inspectBaseSlot(
                lease: participant.lease,
                slotCursor: 0
            )
        else {
            Issue.record("expected retained aggregate window-memory preimage")
            return
        }
        #expect(participant.lease.baseRevision == .zero)
        #expect(
            projectedItem.item
                == .windowMemory(
                    .init(sidebarWidth: 280, windowFrame: originalFrame)
                )
        )
        _ = participant.participant.close(lease: participant.lease)
    }

    @Test("equal installed sidebar repeat is unchanged without another revision")
    func equalInstalledSidebarRepeatIsUnchanged() throws {
        // Arrange
        let runtime = WorkspacePersistenceRuntime(atomRegistry: AtomRegistry())
        let participant = try installAndOpenWindowMemoryParticipant(runtime: runtime)

        let firstResult = runtime.mutationCoordinator.setSidebarWidth(300)

        // Act
        let repeatedResult = runtime.mutationCoordinator.setSidebarWidth(300)

        // Assert
        guard case .changed(let firstRevision) = firstResult else {
            Issue.record("expected first installed sidebar mutation to change")
            return
        }
        #expect(firstRevision.rawValue == 1)
        #expect(repeatedResult == .unchanged(revision: firstRevision))
        #expect(runtime.revisionOwner.committedRevision == firstRevision)
        guard
            case .item = participant.participant.inspectBaseSlot(
                lease: participant.lease,
                slotCursor: 0
            )
        else {
            Issue.record("expected unchanged base window-memory slot")
            return
        }
        #expect(participant.lease.baseRevision == .zero)
        _ = participant.participant.close(lease: participant.lease)
    }

    @Test("installed frame mutation captures preimage and advances one revision")
    func installedFrameMutationCapturesPreimageAndAdvancesOneRevision() throws {
        // Arrange
        let atomRegistry = AtomRegistry()
        atomRegistry.workspaceWindowMemory.setSidebarWidth(321)
        let runtime = WorkspacePersistenceRuntime(atomRegistry: atomRegistry)
        let participant = try installAndOpenWindowMemoryParticipant(runtime: runtime)
        let newFrame = CGRect(x: 34, y: 55, width: 800, height: 600)

        // Act
        let result = runtime.mutationCoordinator.setWindowFrame(newFrame)

        // Assert
        guard case .changed(let committedRevision) = result else {
            Issue.record("expected installed frame mutation to change")
            return
        }
        #expect(committedRevision.rawValue == 1)
        #expect(runtime.revisionOwner.committedRevision.rawValue == 1)
        #expect(atomRegistry.workspaceWindowMemory.windowFrame == newFrame)
        guard
            case .item(let projectedItem, _, _, _) = participant.participant.inspectBaseSlot(
                lease: participant.lease,
                slotCursor: 0
            )
        else {
            Issue.record("expected retained frame-mutation preimage")
            return
        }
        #expect(
            projectedItem.item
                == .windowMemory(.init(sidebarWidth: 321, windowFrame: nil))
        )
        _ = participant.participant.close(lease: participant.lease)
    }
}

@MainActor
private func installAndOpenWindowMemoryParticipant(
    runtime: WorkspacePersistenceRuntime
) throws -> (
    participant: WorkspacePersistenceSnapshotParticipantSet.Participant,
    lease: WorkspaceStateSnapshotLease
) {
    guard
        case .constructed(let participantSet) = runtime.snapshotParticipantFactory
            .constructCompositionParticipantSet(),
        let participant = participantSet.participants.first(where: {
            $0.participantID == .workspaceWindowMemory
        })
    else {
        Issue.record("expected installed composition window-memory participant")
        throw WorkspacePersistenceMutationCoordinatorTestError.compositionInstallationFailed
    }
    let lease = WorkspaceStateSnapshotLease.open(
        pagerIdentity: .make(),
        revisionOwner: runtime.revisionOwner
    )
    guard case .opened(baseMembershipCount: 1) = participant.open(lease: lease) else {
        Issue.record("expected window-memory participant lease to open")
        throw WorkspacePersistenceMutationCoordinatorTestError.leaseOpenFailed
    }
    return (participant, lease)
}

private enum WorkspacePersistenceMutationCoordinatorTestError: Error {
    case compositionInstallationFailed
    case leaseOpenFailed
}
