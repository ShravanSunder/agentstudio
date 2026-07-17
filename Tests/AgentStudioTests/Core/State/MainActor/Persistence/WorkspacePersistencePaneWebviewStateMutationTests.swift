import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace persistence pane webview state mutations")
struct WorkspacePersistencePaneWebviewStateMutationTests {
    @Test("preinstall webview state mutation rejects without state or revision")
    func preinstallRejects() {
        // Arrange
        let fixture = makePaneWebviewPersistenceFixture()

        // Act
        let result = fixture.runtime.mutationCoordinator.updatePaneWebviewState(
            .init(
                paneID: fixture.paneState.id,
                state: WebviewState(url: URL(string: "https://after.example")!)
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

    @Test("installed webview mutation retains one fixed-base pane and commits one revision")
    func installedMutationRetainsFixedBasePane() throws {
        // Arrange
        let fixture = makePaneWebviewPersistenceFixture()
        let installed = try installPaneWebviewParticipant(fixture.runtime)
        defer { _ = installed.participant.close(lease: installed.lease) }
        let replacementState = WebviewState(
            url: URL(string: "https://after.example")!,
            title: "After",
            showNavigation: false
        )

        // Act
        let result = fixture.runtime.mutationCoordinator.updatePaneWebviewState(
            .init(paneID: fixture.paneState.id, state: replacementState)
        )

        // Assert
        #expect(try requirePaneWebviewChangedRevision(result).rawValue == 1)
        #expect(fixture.runtime.revisionOwner.committedRevision.rawValue == 1)
        let currentState = try #require(
            fixture.atomRegistry.workspacePaneGraph.paneState(fixture.paneState.id)
        )
        #expect(currentState.content == .webview(replacementState))
        #expect(currentState.metadata == fixture.paneState.metadata)
        #expect(currentState.residency == fixture.paneState.residency)
        #expect(currentState.kind == fixture.paneState.kind)
        guard
            case .item(let projectedItem, _, _, _) = installed.participant.inspectBaseSlot(
                lease: installed.lease,
                slotCursor: 0
            )
        else {
            Issue.record("expected retained fixed-base webview pane")
            return
        }
        #expect(projectedItem.item == .paneGraph(fixture.paneState))
    }

    @Test("installed equal state and rejected panes advance no revision")
    func unchangedAndRejectedAdvanceNoRevision() throws {
        // Arrange
        let fixture = makePaneWebviewPersistenceFixture()
        let installed = try installPaneWebviewParticipant(fixture.runtime)
        defer { _ = installed.participant.close(lease: installed.lease) }
        guard case .webview(let currentWebviewState) = fixture.paneState.content else {
            Issue.record("expected webview fixture content")
            return
        }
        let missingPaneID = UUIDv7.generate()
        let terminalPaneState = makePersistenceTerminalPaneState()
        fixture.atomRegistry.workspacePaneGraph.setCanonicalPaneState(terminalPaneState)

        // Act
        let unchangedResult = fixture.runtime.mutationCoordinator.updatePaneWebviewState(
            .init(paneID: fixture.paneState.id, state: currentWebviewState)
        )
        let missingResult = fixture.runtime.mutationCoordinator.updatePaneWebviewState(
            .init(paneID: missingPaneID, state: currentWebviewState)
        )
        let wrongContentResult = fixture.runtime.mutationCoordinator.updatePaneWebviewState(
            .init(paneID: terminalPaneState.id, state: currentWebviewState)
        )

        // Assert
        #expect(unchangedResult == .unchanged(revision: .zero))
        #expect(missingResult == .rejected(.paneWebviewStatePlanning(.paneMissing(missingPaneID))))
        #expect(
            wrongContentResult
                == .rejected(
                    .paneWebviewStatePlanning(.paneContentIsNotWebview(terminalPaneState.id))
                )
        )
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
        #expect(
            fixture.atomRegistry.workspacePaneGraph.paneState(fixture.paneState.id)
                == fixture.paneState
        )
        #expect(
            fixture.atomRegistry.workspacePaneGraph.paneState(terminalPaneState.id)
                == terminalPaneState
        )
    }
}

private struct PaneWebviewPersistenceFixture {
    let atomRegistry: AtomRegistry
    let runtime: WorkspacePersistenceRuntime
    let paneState: PaneGraphState
}

private struct InstalledPaneWebviewParticipant {
    let participant: WorkspacePersistenceSnapshotParticipantSet.Participant
    let lease: WorkspaceStateSnapshotLease
}

@MainActor
private func makePaneWebviewPersistenceFixture() -> PaneWebviewPersistenceFixture {
    let atomRegistry = AtomRegistry()
    let paneState = PaneGraphState(
        pane: Pane(
            id: UUIDv7.generate(),
            content: .webview(
                WebviewState(
                    url: URL(string: "https://before.example")!,
                    title: "Before",
                    showNavigation: true
                )
            ),
            metadata: PaneMetadata(
                title: "Webview",
                facets: PaneContextFacets(cwd: URL(filePath: "/tmp/webview")),
                note: "Preserve"
            )
        )
    )
    atomRegistry.workspacePaneGraph.setCanonicalPaneState(paneState)
    return PaneWebviewPersistenceFixture(
        atomRegistry: atomRegistry,
        runtime: WorkspacePersistenceRuntime(atomRegistry: atomRegistry),
        paneState: paneState
    )
}

private func makePersistenceTerminalPaneState() -> PaneGraphState {
    PaneGraphState(
        pane: Pane(
            content: .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionID: .generateUUIDv7()
                )
            ),
            metadata: PaneMetadata(title: "Terminal")
        )
    )
}

@MainActor
private func installPaneWebviewParticipant(
    _ runtime: WorkspacePersistenceRuntime
) throws -> InstalledPaneWebviewParticipant {
    guard
        case .constructed(let participantSet) = runtime.snapshotParticipantFactory
            .constructCompositionParticipantSet(),
        let participant = participantSet.participants.first(where: { $0.participantID == .paneGraphs })
    else {
        throw PaneWebviewPersistenceTestError.installationFailed
    }
    let lease = WorkspaceStateSnapshotLease.open(
        pagerIdentity: .make(),
        revisionOwner: runtime.revisionOwner
    )
    guard participant.open(lease: lease) == .opened(baseMembershipCount: 1) else {
        throw PaneWebviewPersistenceTestError.leaseOpenFailed
    }
    return InstalledPaneWebviewParticipant(participant: participant, lease: lease)
}

private func requirePaneWebviewChangedRevision(
    _ result: WorkspacePersistenceMutationResult
) throws -> WorkspacePersistenceRevision {
    guard case .changed(let revision) = result else {
        throw PaneWebviewPersistenceTestError.expectedChangedResult
    }
    return revision
}

private enum PaneWebviewPersistenceTestError: Error {
    case expectedChangedResult
    case installationFailed
    case leaseOpenFailed
}
