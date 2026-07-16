import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace pane creation gateway")
struct WorkspacePaneCreationGatewayTests {
    @Test("installed gateway creates one canonical pane and tab at one revision")
    func installedGatewayCreatesPaneAndTab() throws {
        // Arrange
        let atomRegistry = AtomRegistry()
        let runtime = WorkspacePersistenceRuntime(atomRegistry: atomRegistry)
        guard case .constructed = runtime.snapshotParticipantFactory.constructCompositionParticipantSet() else {
            Issue.record("expected composition participant installation")
            return
        }
        let request = try makeGatewayRequest()

        // Act
        let result = runtime.paneCreationGateway.create(request)

        // Assert
        guard case .created(let creation) = result else {
            Issue.record("expected committed pane creation")
            return
        }
        #expect(creation.pane.id == request.identities.paneID.uuid)
        #expect(creation.tabID == request.identities.tabID)
        #expect(creation.revision.rawValue == 1)
        #expect(runtime.revisionOwner.committedRevision == creation.revision)
        #expect(
            atomRegistry.workspacePaneGraph.paneState(creation.pane.id)?
                .pane(isDrawerExpanded: false) == creation.pane
        )
        #expect(atomRegistry.workspaceTabShell.tabShell(creation.tabID)?.id == creation.tabID)
        #expect(atomRegistry.workspaceTabShell.activeTabId == creation.tabID)
        #expect(atomRegistry.workspaceTabGraph.tabState(creation.tabID)?.tabId == creation.tabID)
    }

    @Test("gateway rejects preinstall persistence without mutating canonical state")
    func gatewayRejectsBeforeCompositionInstallation() throws {
        // Arrange
        let atomRegistry = AtomRegistry()
        let runtime = WorkspacePersistenceRuntime(atomRegistry: atomRegistry)
        let request = try makeGatewayRequest()

        // Act
        let result = runtime.paneCreationGateway.create(request)

        // Assert
        #expect(
            result
                == .rejected(
                    .persistence(
                        .compositionDomainNotInstalled(phase: .preinstall)
                    )
                )
        )
        #expect(runtime.revisionOwner.committedRevision == .zero)
        #expect(atomRegistry.workspacePaneGraph.paneState(request.identities.paneID.uuid) == nil)
        #expect(atomRegistry.workspaceTabShell.tabShell(request.identities.tabID) == nil)
    }

    @Test("gateway reports owner divergence before opening a persistence transaction")
    func gatewayRejectsMisalignedTabOwners() throws {
        // Arrange
        let atomRegistry = AtomRegistry()
        let unmatchedTabID = UUIDv7.generate()
        atomRegistry.workspaceTabShell.insertTabShell(
            TabShell(id: unmatchedTabID, name: "Unmatched"),
            at: 0
        )
        let runtime = WorkspacePersistenceRuntime(atomRegistry: atomRegistry)
        let request = try makeGatewayRequest()

        // Act
        let result = runtime.paneCreationGateway.create(request)

        // Assert
        #expect(
            result
                == .rejected(
                    .context(
                        .tabOwnerAlignment(
                            .tabOwnerCountMismatch(shellCount: 1, graphCount: 0)
                        )
                    )
                )
        )
        #expect(runtime.revisionOwner.committedRevision == .zero)
        #expect(atomRegistry.workspacePaneGraph.paneState(request.identities.paneID.uuid) == nil)
    }
}

private func makeGatewayRequest() throws -> WorkspacePaneCreationRequest {
    let identities: WorkspaceNewPaneTabIDs
    switch WorkspaceNewPaneTabIDs.prepare(
        paneID: UUIDv7.generate(),
        drawerID: UUIDv7.generate(),
        tabID: UUIDv7.generate(),
        arrangementID: UUIDv7.generate()
    ) {
    case .validated(let validatedIdentities):
        identities = validatedIdentities
    case .rejected(let rejection):
        throw WorkspacePaneCreationGatewayTestError.identity(rejection)
    }
    return WorkspacePaneCreationRequest(
        identities: identities,
        content: .webview(
            WebviewState(
                url: URL(string: "https://example.com/gateway")!,
                showNavigation: true
            )
        ),
        metadata: PaneMetadata(title: "example.com"),
        residency: .active,
        tabName: "example.com"
    )
}

private enum WorkspacePaneCreationGatewayTestError: Error {
    case identity(WorkspaceNewPaneTabIDRejection)
}
