import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

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

    @Test("deferral moves pending terminal custody without a claim")
    func deferralMovesPendingTerminalCustodyWithoutClaim() throws {
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

        // Act
        let deferred = registry.deferPreparedContentMount(
            paneID: paneID,
            owner: .terminal,
            generation: generation
        )

        // Assert
        #expect(deferred)
        #expect(
            registry.preparedContentMountState(for: paneID, generation: generation)
                == .deferredGeometry(owner: .terminal)
        )
        #expect(
            registry.claimPreparedContentMount(
                paneID: paneID,
                owner: .terminal,
                generation: generation
            ) == .rejected(.alreadyClaimed(.deferredGeometry(owner: .terminal)))
        )
    }

    @Test("restoring deferred custody returns it to pending and re-enables a claim")
    func restoringDeferredCustodyReturnsItToPending() throws {
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
            registry.deferPreparedContentMount(paneID: paneID, owner: .terminal, generation: generation)
        )

        // Act
        let restored = registry.restorePreparedContentMountToPending(
            paneID: paneID,
            owner: .terminal,
            generation: generation
        )

        // Assert
        #expect(restored)
        #expect(
            registry.preparedContentMountState(for: paneID, generation: generation)
                == .pending(owner: .terminal)
        )
        #expect(
            registry.claimPreparedContentMount(
                paneID: paneID,
                owner: .terminal,
                generation: generation
            ) == .accepted
        )
    }

    @Test("deferral rejects non-pending custody, an unknown pane, and a stale generation")
    func deferralRejectsNonPendingAndStaleGeneration() throws {
        // Arrange
        let generation = try makeViewRegistryContentGeneration()
        let staleGeneration = try makeViewRegistryContentGeneration()
        let mountingPane = makeViewRegistryTerminalPane()
        let mountingPaneID = PaneId(existingUUID: mountingPane.id)
        let completedPane = makeViewRegistryTerminalPane()
        let completedPaneID = PaneId(existingUUID: completedPane.id)
        let unknownPaneID = PaneId.generateUUIDv7()
        let registry = ViewRegistry()
        registry.installPreparedContentMountCohort(
            WorkspacePreparedContentMountCohort(
                generation: generation,
                terminalActivationInput: TerminalActivationInput(
                    entries: [
                        makeViewRegistryTerminalDescriptor(pane: mountingPane),
                        makeViewRegistryTerminalDescriptor(pane: completedPane),
                    ]
                ),
                nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
            )
        )
        #expect(
            registry.claimPreparedContentMount(
                paneID: mountingPaneID,
                owner: .terminal,
                generation: generation
            ) == .accepted
        )
        #expect(
            registry.claimPreparedContentMount(
                paneID: completedPaneID,
                owner: .terminal,
                generation: generation
            ) == .accepted
        )
        registry.settlePreparedContentMount(
            paneID: completedPaneID,
            owner: .terminal,
            generation: generation,
            disposition: .mounted
        )

        // Act / Assert
        #expect(
            !registry.deferPreparedContentMount(
                paneID: mountingPaneID,
                owner: .terminal,
                generation: generation
            )
        )
        #expect(
            registry.preparedContentMountState(for: mountingPaneID, generation: generation)
                == .mounting(owner: .terminal)
        )
        #expect(
            !registry.deferPreparedContentMount(
                paneID: completedPaneID,
                owner: .terminal,
                generation: generation
            )
        )
        #expect(
            registry.preparedContentMountState(for: completedPaneID, generation: generation)
                == .completed(owner: .terminal, disposition: .mounted)
        )
        #expect(
            !registry.deferPreparedContentMount(
                paneID: unknownPaneID,
                owner: .terminal,
                generation: generation
            )
        )
        #expect(registry.preparedContentMountState(for: unknownPaneID, generation: generation) == nil)
        #expect(
            !registry.deferPreparedContentMount(
                paneID: mountingPaneID,
                owner: .terminal,
                generation: staleGeneration
            )
        )
        #expect(
            registry.preparedContentMountState(for: mountingPaneID, generation: generation)
                == .mounting(owner: .terminal)
        )
    }

    @Test("creation authority is withheld while the prepared lane owns the pane")
    func creationAuthorityIsWithheldWhileThePreparedLaneOwnsThePane() throws {
        // Arrange
        let generation = try makeViewRegistryContentGeneration()
        let pendingPane = makeViewRegistryTerminalPane()
        let pendingPaneID = PaneId(existingUUID: pendingPane.id)
        let deferredPane = makeViewRegistryTerminalPane()
        let deferredPaneID = PaneId(existingUUID: deferredPane.id)
        let mountingPane = makeViewRegistryTerminalPane()
        let mountingPaneID = PaneId(existingUUID: mountingPane.id)
        let registry = ViewRegistry()
        registry.installPreparedContentMountCohort(
            WorkspacePreparedContentMountCohort(
                generation: generation,
                terminalActivationInput: TerminalActivationInput(
                    entries: [
                        makeViewRegistryTerminalDescriptor(pane: pendingPane),
                        makeViewRegistryTerminalDescriptor(pane: deferredPane),
                        makeViewRegistryTerminalDescriptor(pane: mountingPane),
                    ]
                ),
                nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
            )
        )
        #expect(
            registry.deferPreparedContentMount(
                paneID: deferredPaneID,
                owner: .terminal,
                generation: generation
            )
        )
        #expect(
            registry.claimPreparedContentMount(
                paneID: mountingPaneID,
                owner: .terminal,
                generation: generation
            ) == .accepted
        )

        // Act / Assert
        #expect(registry.terminalSurfaceCreationAuthority(for: pendingPaneID, generation: generation) == nil)
        #expect(registry.terminalSurfaceCreationAuthority(for: deferredPaneID, generation: generation) == nil)
        #expect(registry.terminalSurfaceCreationAuthority(for: mountingPaneID, generation: generation) == nil)
    }

    @Test("creation authority is released for completed and absent custody")
    func creationAuthorityIsReleasedForCompletedAndAbsentCustody() throws {
        // Arrange
        let generation = try makeViewRegistryContentGeneration()
        let staleGeneration = try makeViewRegistryContentGeneration()
        let mountedPane = makeViewRegistryTerminalPane()
        let mountedPaneID = PaneId(existingUUID: mountedPane.id)
        let failedPane = makeViewRegistryTerminalPane()
        let failedPaneID = PaneId(existingUUID: failedPane.id)
        let replacedPane = makeViewRegistryTerminalPane()
        let replacedPaneID = PaneId(existingUUID: replacedPane.id)
        let absentPaneID = PaneId.generateUUIDv7()
        let registry = ViewRegistry()
        registry.installPreparedContentMountCohort(
            WorkspacePreparedContentMountCohort(
                generation: generation,
                terminalActivationInput: TerminalActivationInput(
                    entries: [
                        makeViewRegistryTerminalDescriptor(pane: mountedPane),
                        makeViewRegistryTerminalDescriptor(pane: failedPane),
                        makeViewRegistryTerminalDescriptor(pane: replacedPane),
                    ]
                ),
                nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
            )
        )
        for paneID in [mountedPaneID, failedPaneID, replacedPaneID] {
            #expect(
                registry.claimPreparedContentMount(
                    paneID: paneID,
                    owner: .terminal,
                    generation: generation
                ) == .accepted
            )
        }
        registry.settlePreparedContentMount(
            paneID: mountedPaneID,
            owner: .terminal,
            generation: generation,
            disposition: .mounted
        )
        registry.settlePreparedContentMount(
            paneID: failedPaneID,
            owner: .terminal,
            generation: generation,
            disposition: .failed
        )
        registry.settlePreparedContentMount(
            paneID: replacedPaneID,
            owner: .terminal,
            generation: generation,
            disposition: .cancelledReplaced
        )

        // Act / Assert
        #expect(
            registry.terminalSurfaceCreationAuthority(for: mountedPaneID, generation: generation)
                == .released(mountedPaneID)
        )
        #expect(
            registry.terminalSurfaceCreationAuthority(for: failedPaneID, generation: generation)
                == .released(failedPaneID)
        )
        #expect(
            registry.terminalSurfaceCreationAuthority(for: replacedPaneID, generation: generation)
                == .released(replacedPaneID)
        )
        #expect(
            registry.terminalSurfaceCreationAuthority(for: absentPaneID, generation: generation)
                == .released(absentPaneID)
        )
        #expect(
            registry.terminalSurfaceCreationAuthority(for: mountedPaneID, generation: staleGeneration)
                == .released(mountedPaneID)
        )
    }

    @Test("deferred pane IDs list only same-generation terminal deferrals")
    func deferredPaneIDsListOnlySameGenerationTerminalDeferrals() throws {
        // Arrange
        let generation = try makeViewRegistryContentGeneration()
        let staleGeneration = try makeViewRegistryContentGeneration()
        let deferredPane = makeViewRegistryTerminalPane()
        let deferredPaneID = PaneId(existingUUID: deferredPane.id)
        let pendingPane = makeViewRegistryTerminalPane()
        let pendingPaneID = PaneId(existingUUID: pendingPane.id)
        let registry = ViewRegistry()
        registry.installPreparedContentMountCohort(
            WorkspacePreparedContentMountCohort(
                generation: generation,
                terminalActivationInput: TerminalActivationInput(
                    entries: [
                        makeViewRegistryTerminalDescriptor(pane: deferredPane),
                        makeViewRegistryTerminalDescriptor(pane: pendingPane),
                    ]
                ),
                nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
            )
        )
        #expect(
            registry.deferPreparedContentMount(
                paneID: deferredPaneID,
                owner: .terminal,
                generation: generation
            )
        )

        // Act
        let deferredPaneIDs = registry.deferredPreparedContentMountPaneIDs(
            owner: .terminal,
            generation: generation
        )
        let staleGenerationPaneIDs = registry.deferredPreparedContentMountPaneIDs(
            owner: .terminal,
            generation: staleGeneration
        )

        // Assert
        #expect(Set(deferredPaneIDs) == [deferredPaneID])
        #expect(!deferredPaneIDs.contains(pendingPaneID))
        #expect(staleGenerationPaneIDs.isEmpty)
    }
}

@MainActor
private func makeViewRegistryContentGeneration() throws -> WorkspaceContentMountGeneration {
    WorkspaceContentMountGeneration()
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
    guard case .terminal = pane.content else {
        preconditionFailure("view registry terminal fixture requires terminal content")
    }
    return TerminalActivationDescriptor(
        pane: pane,
        visibilityPriority: .activeVisible,
        hostPlacement: .tab(tabID: UUIDv7.generate())
    )
}
