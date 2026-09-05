import AppKit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTerminal

@MainActor
@Suite("Prepared terminal mount admission")
struct PreparedTerminalMountAdmissionPortTests {
    enum NonPendingCustodyCase: CaseIterable, CustomTestStringConvertible {
        case mounting
        case deferredGeometry
        case completed

        var testDescription: String { String(describing: self) }
    }

    @Test("claim transitions pending custody to mounting in one turn")
    func claimTransitionsPendingCustodyToMountingInOneTurn() throws {
        // Arrange
        let generation = try makePreparedTerminalTestGeneration()
        let descriptor = makePreparedTerminalTestDescriptor(pane: makePreparedTerminalTestPane())
        let paneID = descriptor.paneID
        let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let registry = ViewRegistry()
        registry.installPreparedContentMountCohort(
            WorkspacePreparedContentMountCohort(
                generation: generation,
                terminalActivationInput: TerminalActivationInput(entries: [descriptor]),
                nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
            )
        )
        let handler = RecordingPreparedTerminalMountHandler(results: [])
        let port = PreparedTerminalMountAdmissionPort(
            generation: generation,
            initialFramesByPaneID: [paneID: frame],
            viewRegistry: registry,
            mountHandler: handler,
            descriptorsByPaneID: [paneID: descriptor]
        )

        // Act
        let outcome = port.claimPreparedTerminal(
            TerminalAdmissionProposal(
                generation: generation,
                paneID: paneID,
                attempt: 1,
                appliedVisibilityRevision: TerminalVisibilityRevision(generation: generation, ordinal: 0)
            )
        )

        // Assert
        guard case .claimed(let claim) = outcome else {
            Issue.record("expected a granted claim")
            return
        }
        #expect(claim.admission.descriptor == descriptor)
        #expect(claim.admission.attempt == 1)
        #expect(
            registry.preparedContentMountState(for: paneID, generation: generation)
                == .mounting(owner: .terminal)
        )
    }

    @Test("claim is rejected for a stale generation")
    func claimIsRejectedForStaleGeneration() throws {
        // Arrange
        let generation = try makePreparedTerminalTestGeneration()
        let staleGeneration = try makePreparedTerminalTestGeneration()
        let descriptor = makePreparedTerminalTestDescriptor(pane: makePreparedTerminalTestPane())
        let paneID = descriptor.paneID
        let registry = ViewRegistry()
        registry.installPreparedContentMountCohort(
            WorkspacePreparedContentMountCohort(
                generation: generation,
                terminalActivationInput: TerminalActivationInput(entries: [descriptor]),
                nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
            )
        )
        let handler = RecordingPreparedTerminalMountHandler(results: [])
        let port = PreparedTerminalMountAdmissionPort(
            generation: generation,
            initialFramesByPaneID: [paneID: NSRect(x: 0, y: 0, width: 800, height: 600)],
            viewRegistry: registry,
            mountHandler: handler,
            descriptorsByPaneID: [paneID: descriptor]
        )

        // Act
        let outcome = port.claimPreparedTerminal(
            TerminalAdmissionProposal(
                generation: staleGeneration,
                paneID: paneID,
                attempt: 1,
                appliedVisibilityRevision: TerminalVisibilityRevision(generation: staleGeneration, ordinal: 0)
            )
        )

        // Assert
        #expect(outcome == .rejected(.staleGeneration))
        #expect(handler.admissions.isEmpty)
    }

    @Test("claim is rejected for a pane outside the cohort")
    func claimIsRejectedForPaneOutsideTheCohort() throws {
        // Arrange
        let generation = try makePreparedTerminalTestGeneration()
        let descriptor = makePreparedTerminalTestDescriptor(pane: makePreparedTerminalTestPane())
        let outsidePaneID = PaneId.generateUUIDv7()
        let registry = ViewRegistry()
        registry.installPreparedContentMountCohort(
            WorkspacePreparedContentMountCohort(
                generation: generation,
                terminalActivationInput: TerminalActivationInput(entries: [descriptor]),
                nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
            )
        )
        let handler = RecordingPreparedTerminalMountHandler(results: [])
        let port = PreparedTerminalMountAdmissionPort(
            generation: generation,
            initialFramesByPaneID: [descriptor.paneID: NSRect(x: 0, y: 0, width: 800, height: 600)],
            viewRegistry: registry,
            mountHandler: handler,
            descriptorsByPaneID: [descriptor.paneID: descriptor]
        )

        // Act
        let outcome = port.claimPreparedTerminal(
            TerminalAdmissionProposal(
                generation: generation,
                paneID: outsidePaneID,
                attempt: 1,
                appliedVisibilityRevision: TerminalVisibilityRevision(generation: generation, ordinal: 0)
            )
        )

        // Assert
        #expect(outcome == .rejected(.paneNotInCohort))
        #expect(handler.admissions.isEmpty)
    }

    @Test(
        "claim is rejected when custody is not pending",
        arguments: NonPendingCustodyCase.allCases
    )
    func claimIsRejectedWhenCustodyIsNotPending(testCase: NonPendingCustodyCase) throws {
        // Arrange
        let generation = try makePreparedTerminalTestGeneration()
        let descriptor = makePreparedTerminalTestDescriptor(pane: makePreparedTerminalTestPane())
        let paneID = descriptor.paneID
        let registry = ViewRegistry()
        registry.installPreparedContentMountCohort(
            WorkspacePreparedContentMountCohort(
                generation: generation,
                terminalActivationInput: TerminalActivationInput(entries: [descriptor]),
                nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
            )
        )
        switch testCase {
        case .mounting:
            #expect(
                registry.claimPreparedContentMount(paneID: paneID, owner: .terminal, generation: generation)
                    == .accepted
            )
        case .deferredGeometry:
            #expect(registry.deferPreparedContentMount(paneID: paneID, owner: .terminal, generation: generation))
        case .completed:
            #expect(
                registry.claimPreparedContentMount(paneID: paneID, owner: .terminal, generation: generation)
                    == .accepted
            )
            registry.settlePreparedContentMount(
                paneID: paneID,
                owner: .terminal,
                generation: generation,
                disposition: .mounted
            )
        }
        let handler = RecordingPreparedTerminalMountHandler(results: [])
        let port = PreparedTerminalMountAdmissionPort(
            generation: generation,
            initialFramesByPaneID: [paneID: NSRect(x: 0, y: 0, width: 800, height: 600)],
            viewRegistry: registry,
            mountHandler: handler,
            descriptorsByPaneID: [paneID: descriptor]
        )

        // Act
        let outcome = port.claimPreparedTerminal(
            TerminalAdmissionProposal(
                generation: generation,
                paneID: paneID,
                attempt: 1,
                appliedVisibilityRevision: TerminalVisibilityRevision(generation: generation, ordinal: 0)
            )
        )

        // Assert
        #expect(outcome == .rejected(.custodyUnavailableForClaim))
        #expect(handler.admissions.isEmpty)
    }

    @Test("claim fails closed when an eligible pane has no installed frame")
    func claimFailsClosedWhenAnEligiblePaneHasNoInstalledFrame() throws {
        // Arrange
        let generation = try makePreparedTerminalTestGeneration()
        let descriptor = makePreparedTerminalTestDescriptor(pane: makePreparedTerminalTestPane())
        let paneID = descriptor.paneID
        let registry = ViewRegistry()
        registry.installPreparedContentMountCohort(
            WorkspacePreparedContentMountCohort(
                generation: generation,
                terminalActivationInput: TerminalActivationInput(entries: [descriptor]),
                nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
            )
        )
        let handler = RecordingPreparedTerminalMountHandler(results: [])
        let port = PreparedTerminalMountAdmissionPort(
            generation: generation,
            viewRegistry: registry,
            mountHandler: handler,
            descriptorsByPaneID: [paneID: descriptor]
        )

        // Act
        let outcome = port.claimPreparedTerminal(
            TerminalAdmissionProposal(
                generation: generation,
                paneID: paneID,
                attempt: 1,
                appliedVisibilityRevision: TerminalVisibilityRevision(generation: generation, ordinal: 0)
            )
        )

        // Assert
        #expect(outcome == .rejected(.trustedFrameUnavailable))
        #expect(handler.admissions.isEmpty)
        #expect(
            registry.preparedContentMountState(for: paneID, generation: generation)
                == .pending(owner: .terminal)
        )
    }

    @Test("replaying a consumed claim performs no mount effect")
    func replayingAConsumedClaimPerformsNoMountEffect() async throws {
        // Arrange
        let generation = try makePreparedTerminalTestGeneration()
        let descriptor = makePreparedTerminalTestDescriptor(pane: makePreparedTerminalTestPane())
        let paneID = descriptor.paneID
        let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let surfaceID = UUIDv7.generate()
        let registry = ViewRegistry()
        registry.installPreparedContentMountCohort(
            WorkspacePreparedContentMountCohort(
                generation: generation,
                terminalActivationInput: TerminalActivationInput(entries: [descriptor]),
                nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
            )
        )
        let handler = RecordingPreparedTerminalMountHandler(results: [.ready(surfaceID: surfaceID)])
        let port = PreparedTerminalMountAdmissionPort(
            generation: generation,
            initialFramesByPaneID: [paneID: frame],
            viewRegistry: registry,
            mountHandler: handler,
            descriptorsByPaneID: [paneID: descriptor]
        )
        let claimOutcome = port.claimPreparedTerminal(
            TerminalAdmissionProposal(
                generation: generation,
                paneID: paneID,
                attempt: 1,
                appliedVisibilityRevision: TerminalVisibilityRevision(generation: generation, ordinal: 0)
            )
        )
        guard case .claimed(let claim) = claimOutcome else {
            Issue.record("expected a granted claim")
            return
        }

        // Act
        let first = await port.activateClaimedTerminal(claim)
        let second = await port.activateClaimedTerminal(claim)

        // Assert
        #expect(first == .attempted(.ready(surfaceID: surfaceID)))
        #expect(second == .rejected(.claimAlreadyConsumed))
        #expect(handler.admissions.count == 1)
    }

    @Test("a claim value not minted by the port is refused")
    func aClaimValueNotMintedByThePortIsRefused() async throws {
        // Arrange
        let generation = try makePreparedTerminalTestGeneration()
        let descriptor = makePreparedTerminalTestDescriptor(pane: makePreparedTerminalTestPane())
        let paneID = descriptor.paneID
        let registry = ViewRegistry()
        registry.installPreparedContentMountCohort(
            WorkspacePreparedContentMountCohort(
                generation: generation,
                terminalActivationInput: TerminalActivationInput(entries: [descriptor]),
                nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
            )
        )
        let handler = RecordingPreparedTerminalMountHandler(results: [])
        let port = PreparedTerminalMountAdmissionPort(
            generation: generation,
            initialFramesByPaneID: [paneID: NSRect(x: 0, y: 0, width: 800, height: 600)],
            viewRegistry: registry,
            mountHandler: handler,
            descriptorsByPaneID: [paneID: descriptor]
        )
        let forgedClaim = ClaimedTerminalAdmission(
            claimID: UUID(),
            admission: TerminalActivationAdmission(generation: generation, descriptor: descriptor, attempt: 1),
            acknowledgedVisibilityRevision: TerminalVisibilityRevision(generation: generation, ordinal: 0)
        )

        // Act
        let outcome = await port.activateClaimedTerminal(forgedClaim)

        // Assert
        #expect(outcome == .rejected(.claimNotIssued))
        #expect(handler.admissions.isEmpty)
    }

    @Test("attempt two reuses held custody and the same frame")
    func attemptTwoReusesHeldCustodyAndTheSameFrame() async throws {
        // Arrange
        let generation = try makePreparedTerminalTestGeneration()
        let descriptor = makePreparedTerminalTestDescriptor(pane: makePreparedTerminalTestPane())
        let paneID = descriptor.paneID
        let frame = NSRect(x: 10, y: 20, width: 900, height: 600)
        let surfaceID = UUIDv7.generate()
        let registry = ViewRegistry()
        registry.installPreparedContentMountCohort(
            WorkspacePreparedContentMountCohort(
                generation: generation,
                terminalActivationInput: TerminalActivationInput(entries: [descriptor]),
                nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
            )
        )
        let handler = RecordingPreparedTerminalMountHandler(
            results: [
                .failed(failure: .surfaceCreationFailed(code: "transient"), retry: .retry),
                .ready(surfaceID: surfaceID),
            ]
        )
        let port = PreparedTerminalMountAdmissionPort(
            generation: generation,
            initialFramesByPaneID: [paneID: frame],
            viewRegistry: registry,
            mountHandler: handler,
            descriptorsByPaneID: [paneID: descriptor]
        )
        let revision = TerminalVisibilityRevision(generation: generation, ordinal: 0)

        // Act
        let firstClaimOutcome = port.claimPreparedTerminal(
            TerminalAdmissionProposal(
                generation: generation,
                paneID: paneID,
                attempt: 1,
                appliedVisibilityRevision: revision
            )
        )
        guard case .claimed(let firstClaim) = firstClaimOutcome else {
            Issue.record("expected attempt 1 to be granted a claim")
            return
        }
        let firstActivation = await port.activateClaimedTerminal(firstClaim)
        let stateAfterFirst = registry.preparedContentMountState(for: paneID, generation: generation)

        let secondClaimOutcome = port.claimPreparedTerminal(
            TerminalAdmissionProposal(
                generation: generation,
                paneID: paneID,
                attempt: 2,
                appliedVisibilityRevision: revision
            )
        )
        guard case .claimed(let secondClaim) = secondClaimOutcome else {
            Issue.record("expected attempt 2 to be granted a claim")
            return
        }
        let secondActivation = await port.activateClaimedTerminal(secondClaim)

        // Assert
        #expect(
            firstActivation
                == .attempted(.failed(failure: .surfaceCreationFailed(code: "transient"), retry: .retry))
        )
        #expect(stateAfterFirst == .mounting(owner: .terminal))
        #expect(firstClaim.claimID != secondClaim.claimID)
        #expect(secondActivation == .attempted(.ready(surfaceID: surfaceID)))
        #expect(
            registry.preparedContentMountState(for: paneID, generation: generation)
                == .completed(owner: .terminal, disposition: .mounted)
        )
        #expect(handler.initialFrames == [frame, frame])
    }

    @Test("a proposal with a mismatched attempt is rejected")
    func aProposalWithAMismatchedAttemptIsRejected() async throws {
        // Arrange
        let generation = try makePreparedTerminalTestGeneration()
        let descriptor = makePreparedTerminalTestDescriptor(pane: makePreparedTerminalTestPane())
        let paneID = descriptor.paneID
        let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let registry = ViewRegistry()
        registry.installPreparedContentMountCohort(
            WorkspacePreparedContentMountCohort(
                generation: generation,
                terminalActivationInput: TerminalActivationInput(entries: [descriptor]),
                nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
            )
        )
        let handler = RecordingPreparedTerminalMountHandler(
            results: [.failed(failure: .surfaceCreationFailed(code: "transient"), retry: .retry)]
        )
        let port = PreparedTerminalMountAdmissionPort(
            generation: generation,
            initialFramesByPaneID: [paneID: frame],
            viewRegistry: registry,
            mountHandler: handler,
            descriptorsByPaneID: [paneID: descriptor]
        )
        let revision = TerminalVisibilityRevision(generation: generation, ordinal: 0)
        let firstClaimOutcome = port.claimPreparedTerminal(
            TerminalAdmissionProposal(
                generation: generation,
                paneID: paneID,
                attempt: 1,
                appliedVisibilityRevision: revision
            )
        )
        guard case .claimed(let firstClaim) = firstClaimOutcome else {
            Issue.record("expected attempt 1 to be granted a claim")
            return
        }
        _ = await port.activateClaimedTerminal(firstClaim)

        // Act: skip straight to attempt 3, which does not match the expected next attempt (2).
        let mismatchedOutcome = port.claimPreparedTerminal(
            TerminalAdmissionProposal(
                generation: generation,
                paneID: paneID,
                attempt: 3,
                appliedVisibilityRevision: revision
            )
        )

        // Assert
        #expect(mismatchedOutcome == .rejected(.retryClaimMismatch))
        #expect(handler.admissions.count == 1)
    }
}

@MainActor
private final class RecordingPreparedTerminalMountHandler: PreparedTerminalMountHandling {
    private var results: [TerminalActivationAttemptResult]
    private(set) var admissions: [TerminalActivationAdmission] = []
    private(set) var initialFrames: [NSRect?] = []

    init(results: [TerminalActivationAttemptResult]) {
        self.results = results
    }

    func mountPreparedTerminalContent(
        admission: TerminalActivationAdmission,
        initialFrame: NSRect?
    ) -> TerminalActivationAttemptResult {
        admissions.append(admission)
        initialFrames.append(initialFrame)
        return results.removeFirst()
    }
}

@MainActor
private func makePreparedTerminalTestGeneration() throws -> WorkspaceContentMountGeneration {
    WorkspaceContentMountGeneration()
}

private func makePreparedTerminalTestPane() -> Pane {
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
            launchDirectory: URL(filePath: "/tmp/prepared-terminal-admission"),
            title: "Prepared Terminal"
        )
    )
}

private func makePreparedTerminalTestDescriptor(pane: Pane) -> TerminalActivationDescriptor {
    guard case .terminal = pane.content else {
        preconditionFailure("prepared terminal test requires terminal content")
    }
    return TerminalActivationDescriptor(
        pane: pane,
        visibilityPriority: .activeVisible,
        hostPlacement: .tab(tabID: UUIDv7.generate())
    )
}
