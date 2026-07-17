import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace persistence pane context mutations")
struct WorkspacePersistencePaneContextMutationTests {
    @Test("preinstall pane context mutation rejects without state or revision")
    func preinstallRejects() {
        // Arrange
        let fixture = makePaneContextPersistenceFixture()

        // Act
        let result = fixture.runtime.mutationCoordinator.updatePaneContext(
            .init(
                paneID: fixture.paneState.id,
                cwd: URL(filePath: "/tmp/after"),
                resolvedContext: .unresolved
            )
        )

        // Assert
        #expect(result == .rejected(.compositionDomainNotInstalled(phase: .preinstall)))
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
        #expect(
            fixture.atomRegistry.workspacePaneGraph.paneState(fixture.paneState.id)
                == fixture.paneState
        )
    }

    @Test("installed pane context mutation captures one fixed-base pane and commits one revision")
    func installedMutationCapturesFixedBasePane() throws {
        // Arrange
        let fixture = makePaneContextPersistenceFixture()
        let installed = try installPaneContextParticipant(fixture.runtime)
        defer { _ = installed.participant.close(lease: installed.lease) }
        let replacementRepoID = UUIDv7.generate()
        let replacementWorktreeID = UUIDv7.generate()
        let request = WorkspacePaneContextUpdateRequest(
            paneID: fixture.paneState.id,
            cwd: URL(filePath: "/tmp/after"),
            resolvedContext: .resolved(
                repoID: replacementRepoID,
                worktreeID: replacementWorktreeID
            )
        )

        // Act
        let result = fixture.runtime.mutationCoordinator.updatePaneContext(request)

        // Assert
        #expect(try requirePaneContextChangedRevision(result).rawValue == 1)
        #expect(fixture.runtime.revisionOwner.committedRevision.rawValue == 1)
        let currentState = try #require(
            fixture.atomRegistry.workspacePaneGraph.paneState(fixture.paneState.id)
        )
        #expect(currentState.metadata.facets.cwd == request.cwd)
        #expect(currentState.metadata.facets.repoId == replacementRepoID)
        #expect(currentState.metadata.facets.worktreeId == replacementWorktreeID)
        guard
            case .item(let projectedItem, _, _, _) = installed.participant.inspectBaseSlot(
                lease: installed.lease,
                slotCursor: 0
            )
        else {
            Issue.record("expected retained fixed-base pane context")
            return
        }
        #expect(projectedItem.item == .paneGraph(fixture.paneState))
    }

    @Test("installed equal context and missing pane advance no revision")
    func unchangedAndMissingAdvanceNoRevision() throws {
        // Arrange
        let fixture = makePaneContextPersistenceFixture()
        let installed = try installPaneContextParticipant(fixture.runtime)
        defer { _ = installed.participant.close(lease: installed.lease) }
        let currentFacets = fixture.paneState.metadata.facets
        let currentRepoID = try #require(currentFacets.repoId)
        let currentWorktreeID = try #require(currentFacets.worktreeId)
        let missingPaneID = UUIDv7.generate()

        // Act
        let unchangedResult = fixture.runtime.mutationCoordinator.updatePaneContext(
            .init(
                paneID: fixture.paneState.id,
                cwd: currentFacets.cwd,
                resolvedContext: .resolved(
                    repoID: currentRepoID,
                    worktreeID: currentWorktreeID
                )
            )
        )
        let missingResult = fixture.runtime.mutationCoordinator.updatePaneContext(
            .init(paneID: missingPaneID, cwd: nil, resolvedContext: .unresolved)
        )

        // Assert
        #expect(unchangedResult == .unchanged(revision: .zero))
        #expect(missingResult == .rejected(.paneContextPlanning(.paneMissing(missingPaneID))))
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
        #expect(
            fixture.atomRegistry.workspacePaneGraph.paneState(fixture.paneState.id)
                == fixture.paneState
        )
    }
}

private struct PaneContextPersistenceFixture {
    let atomRegistry: AtomRegistry
    let runtime: WorkspacePersistenceRuntime
    let paneState: PaneGraphState
}

private struct InstalledPaneContextParticipant {
    let participant: WorkspacePersistenceSnapshotParticipantSet.Participant
    let lease: WorkspaceStateSnapshotLease
}

@MainActor
private func makePaneContextPersistenceFixture() -> PaneContextPersistenceFixture {
    let atomRegistry = AtomRegistry()
    let paneState = PaneGraphState(
        pane: Pane(
            id: UUIDv7.generate(),
            content: .webview(WebviewState(url: URL(string: "https://example.com")!)),
            metadata: PaneMetadata(
                title: "Context",
                facets: PaneContextFacets(
                    repoId: UUIDv7.generate(),
                    worktreeId: UUIDv7.generate(),
                    cwd: URL(filePath: "/tmp/before")
                )
            )
        )
    )
    atomRegistry.workspacePaneGraph.setCanonicalPaneState(paneState)
    return PaneContextPersistenceFixture(
        atomRegistry: atomRegistry,
        runtime: WorkspacePersistenceRuntime(atomRegistry: atomRegistry),
        paneState: paneState
    )
}

@MainActor
private func installPaneContextParticipant(
    _ runtime: WorkspacePersistenceRuntime
) throws -> InstalledPaneContextParticipant {
    guard
        case .constructed(let participantSet) = runtime.snapshotParticipantFactory
            .constructCompositionParticipantSet(),
        let participant = participantSet.participants.first(where: { $0.participantID == .paneGraphs })
    else {
        throw WorkspacePersistencePaneContextMutationTestError.installationFailed
    }
    let lease = WorkspaceStateSnapshotLease.open(
        pagerIdentity: .make(),
        revisionOwner: runtime.revisionOwner
    )
    guard participant.open(lease: lease) == .opened(baseMembershipCount: 1) else {
        throw WorkspacePersistencePaneContextMutationTestError.leaseOpenFailed
    }
    return InstalledPaneContextParticipant(participant: participant, lease: lease)
}

private func requirePaneContextChangedRevision(
    _ result: WorkspacePersistenceMutationResult
) throws -> WorkspacePersistenceRevision {
    guard case .changed(let revision) = result else {
        throw WorkspacePersistencePaneContextMutationTestError.expectedChangedResult
    }
    return revision
}

private enum WorkspacePersistencePaneContextMutationTestError: Error {
    case expectedChangedResult
    case installationFailed
    case leaseOpenFailed
}
