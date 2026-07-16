import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("View registry prepared content ownership")
struct ViewRegistryPreparedContentMountTests {
    @Test("one accepted cohort assigns each pane to exactly one owner")
    func acceptedCohortAssignsEachPaneToExactlyOneOwner() throws {
        // Arrange
        let generation = try makeViewRegistryContentGeneration()
        let terminalPane = makeViewRegistryTerminalPane()
        let webviewPane = makeViewRegistryWebviewPane()
        let cohort = WorkspacePreparedContentMountCohort(
            generation: generation,
            terminalActivationInput: TerminalActivationInput(
                entries: [makeViewRegistryTerminalDescriptor(pane: terminalPane)]
            ),
            nonterminalContentMountInput: NonterminalContentMountInput(
                entries: [
                    NonterminalContentMountDescriptor(
                        content: .webview(webviewPane),
                        visibilityPriority: .visible,
                        hostPlacement: .tab(tabID: UUIDv7.generate())
                    )
                ]
            )
        )
        let registry = ViewRegistry()

        // Act
        registry.installPreparedContentMountCohort(cohort)

        // Assert
        #expect(
            registry.preparedContentMountState(
                for: PaneId(existingUUID: terminalPane.id),
                generation: generation
            ) == .pending(owner: .terminal)
        )
        #expect(
            registry.preparedContentMountState(
                for: PaneId(existingUUID: webviewPane.id),
                generation: generation
            ) == .pending(owner: .nonterminal)
        )
    }

    @Test("wrong lane, duplicate claim, and stale generation are rejected")
    func invalidClaimsAreRejected() throws {
        // Arrange
        let generation = try makeViewRegistryContentGeneration()
        let staleGeneration = try makeViewRegistryContentGeneration()
        let terminalPane = makeViewRegistryTerminalPane()
        let terminalPaneID = PaneId(existingUUID: terminalPane.id)
        let cohort = WorkspacePreparedContentMountCohort(
            generation: generation,
            terminalActivationInput: TerminalActivationInput(
                entries: [makeViewRegistryTerminalDescriptor(pane: terminalPane)]
            ),
            nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
        )
        let registry = ViewRegistry()
        registry.installPreparedContentMountCohort(cohort)

        // Act / Assert
        #expect(
            registry.claimPreparedContentMount(
                paneID: terminalPaneID,
                owner: .nonterminal,
                generation: generation
            ) == .rejected(.wrongOwner(expected: .terminal))
        )
        #expect(
            registry.claimPreparedContentMount(
                paneID: terminalPaneID,
                owner: .terminal,
                generation: staleGeneration
            ) == .rejected(.staleGeneration)
        )
        #expect(
            registry.claimPreparedContentMount(
                paneID: terminalPaneID,
                owner: .terminal,
                generation: generation
            ) == .accepted
        )
        #expect(
            registry.claimPreparedContentMount(
                paneID: terminalPaneID,
                owner: .terminal,
                generation: generation
            ) == .rejected(.alreadyClaimed(.mounting(owner: .terminal)))
        )
    }

    @Test("settlement records one terminal outcome for the claimed generation")
    func settlementRecordsOneOutcomeForClaimedGeneration() throws {
        // Arrange
        let generation = try makeViewRegistryContentGeneration()
        let pane = makeViewRegistryTerminalPane()
        let paneID = PaneId(existingUUID: pane.id)
        let registry = ViewRegistry()
        registry.installPreparedContentMountCohort(
            WorkspacePreparedContentMountCohort(
                generation: generation,
                terminalActivationInput: TerminalActivationInput(
                    entries: [makeViewRegistryTerminalDescriptor(pane: pane)]
                ),
                nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
            )
        )
        #expect(
            registry.claimPreparedContentMount(
                paneID: paneID,
                owner: .terminal,
                generation: generation
            ) == .accepted
        )

        // Act
        registry.settlePreparedContentMount(
            paneID: paneID,
            owner: .terminal,
            generation: generation,
            disposition: .mounted
        )

        // Assert
        #expect(
            registry.preparedContentMountState(for: paneID, generation: generation)
                == .completed(owner: .terminal, disposition: .mounted)
        )
    }
}

@MainActor
private func makeViewRegistryContentGeneration() throws -> WorkspaceContentMountGeneration {
    let revisionOwner = WorkspacePersistenceRevisionOwner()
    let revision = try revisionOwner.performSynchronousTransaction { preparation in
        preparation.commit { preparation.transaction.proposedRevision }
    }
    return WorkspaceContentMountGeneration(
        processGeneration: revisionOwner.processGeneration,
        revision: revision
    )
}

private func makeViewRegistryTerminalPane() -> Pane {
    Pane(
        id: UUIDv7.generate(),
        content: .terminal(
            TerminalState(
                provider: .zmx,
                lifetime: .persistent,
                zmxSessionID: .generateUUIDv7()
            )
        ),
        metadata: PaneMetadata(
            launchDirectory: URL(filePath: "/tmp/view-registry-terminal"),
            title: "Terminal"
        )
    )
}

private func makeViewRegistryWebviewPane() -> Pane {
    Pane(
        id: UUIDv7.generate(),
        content: .webview(
            WebviewState(
                url: URL(filePath: "/tmp/view-registry-webview"),
                title: "Webview",
                showNavigation: false
            )
        ),
        metadata: PaneMetadata(title: "Webview")
    )
}

private func makeViewRegistryTerminalDescriptor(pane: Pane) -> TerminalActivationDescriptor {
    guard case .terminal(let state) = pane.content else {
        preconditionFailure("view registry terminal fixture requires terminal content")
    }
    return TerminalActivationDescriptor(
        pane: pane,
        zmxSessionID: state.zmxSessionID,
        provider: .zmx,
        launchConfiguration: TerminalActivationLaunchConfiguration(
            launchDirectory: .stored(URL(filePath: "/tmp/view-registry-terminal")),
            executionBackend: .local,
            lifetime: .persistent,
            displayTitle: "Terminal"
        ),
        visibilityPriority: .activeVisible,
        hostPlacement: .tab(tabID: UUIDv7.generate())
    )
}
