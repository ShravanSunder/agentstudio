import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace pane transitions")
struct WorkspacePaneTransitionTests {
    @Test("title planner produces one exact replacement without mutating its input")
    func titlePlannerProducesExactReplacement() throws {
        // Arrange
        let originalState = makePaneTransitionState(title: "Before")
        let request = WorkspacePaneTitleUpdateRequest(
            paneID: originalState.id,
            title: "After"
        )

        // Act
        let decision = WorkspacePaneTitleTransitionPlanner.plan(
            request,
            currentPaneState: originalState
        )

        // Assert
        guard case .changed(let transition) = decision else {
            Issue.record("expected one changed title transition")
            return
        }
        let replacement = try #require(transition.replacements.onlyElement)
        #expect(replacement.paneID == originalState.id)
        #expect(replacement.expectedCurrentState == originalState)
        #expect(replacement.replacementState.metadata.title == "After")
        #expect(replacement.replacementState.id == originalState.id)
        #expect(originalState.metadata.title == "Before")
    }

    @Test("title planner returns strict unchanged and missing decisions")
    func titlePlannerReturnsUnchangedAndMissingDecisions() {
        // Arrange
        let originalState = makePaneTransitionState(title: "Same")
        let missingPaneID = UUIDv7.generate()

        // Act / Assert
        #expect(
            WorkspacePaneTitleTransitionPlanner.plan(
                WorkspacePaneTitleUpdateRequest(
                    paneID: originalState.id,
                    title: "Same"
                ),
                currentPaneState: originalState
            ) == .unchanged
        )
        #expect(
            WorkspacePaneTitleTransitionPlanner.plan(
                WorkspacePaneTitleUpdateRequest(
                    paneID: missingPaneID,
                    title: "Missing"
                ),
                currentPaneState: nil
            ) == .rejected(.paneMissing(missingPaneID))
        )
    }

    @Test("metadata planner applies strict title and normalized note updates without changing unrelated state")
    func metadataPlannerAppliesTitleAndNormalizedNoteUpdates() throws {
        // Arrange
        let originalState = makePaneTransitionState(
            title: "Before",
            note: "Original note",
            facets: PaneContextFacets(
                repoId: UUIDv7.generate(),
                worktreeId: UUIDv7.generate(),
                cwd: URL(filePath: "/tmp/original")
            )
        )

        // Act
        let titleDecision = WorkspacePaneMetadataTransitionPlanner.plan(
            WorkspacePaneMetadataUpdateRequest(
                paneID: originalState.id,
                update: .title("After")
            ),
            currentPaneState: originalState
        )
        let noteDecision = WorkspacePaneMetadataTransitionPlanner.plan(
            WorkspacePaneMetadataUpdateRequest(
                paneID: originalState.id,
                update: .note(.set("  Ship after verification  "))
            ),
            currentPaneState: originalState
        )

        // Assert
        guard case .changed(let titleTransition) = titleDecision,
            case .changed(let noteTransition) = noteDecision
        else {
            Issue.record("expected changed metadata transitions")
            return
        }
        let titleReplacement = try #require(titleTransition.replacements.onlyElement)
        let noteReplacement = try #require(noteTransition.replacements.onlyElement)
        #expect(titleReplacement.expectedCurrentState == originalState)
        #expect(titleReplacement.replacementState.metadata.title == "After")
        #expect(titleReplacement.replacementState.metadata.note == "Original note")
        #expect(titleReplacement.replacementState.metadata.facets == originalState.metadata.facets)
        #expect(noteReplacement.expectedCurrentState == originalState)
        #expect(noteReplacement.replacementState.metadata.note == "Ship after verification")
        #expect(noteReplacement.replacementState.metadata.title == "Before")
        #expect(noteReplacement.replacementState.metadata.facets == originalState.metadata.facets)
        #expect(originalState.metadata.title == "Before")
        #expect(originalState.metadata.note == "Original note")
    }

    @Test("metadata planner applies explicit note clear")
    func metadataPlannerAppliesExplicitNoteClear() throws {
        // Arrange
        let originalState = makePaneTransitionState(title: "Pane", note: "Remove me")

        // Act
        let decision = WorkspacePaneMetadataTransitionPlanner.plan(
            WorkspacePaneMetadataUpdateRequest(
                paneID: originalState.id,
                update: .note(.clear)
            ),
            currentPaneState: originalState
        )

        // Assert
        guard case .changed(let transition) = decision else {
            Issue.record("expected explicit note clear to change")
            return
        }
        let replacement = try #require(transition.replacements.onlyElement)
        #expect(replacement.expectedCurrentState == originalState)
        #expect(replacement.replacementState.metadata.note == nil)
        #expect(replacement.replacementState.metadata.title == originalState.metadata.title)
        #expect(replacement.replacementState.content == originalState.content)
        #expect(replacement.replacementState.residency == originalState.residency)
        #expect(replacement.replacementState.kind == originalState.kind)
    }

    @Test("metadata planner returns semantic no-ops after normalization")
    func metadataPlannerReturnsSemanticNoOps() {
        // Arrange
        let originalState = makePaneTransitionState(
            title: "Same",
            note: "Ship it"
        )

        // Act / Assert
        #expect(
            WorkspacePaneMetadataTransitionPlanner.plan(
                .init(paneID: originalState.id, update: .title("Same")),
                currentPaneState: originalState
            ) == .unchanged
        )
        #expect(
            WorkspacePaneMetadataTransitionPlanner.plan(
                .init(paneID: originalState.id, update: .note(.set("  Ship it  "))),
                currentPaneState: originalState
            ) == .unchanged
        )
    }

    @Test("metadata planner rejects missing and mismatched keyed pane identity")
    func metadataPlannerRejectsMissingAndMismatchedIdentity() {
        // Arrange
        let requestedPaneID = UUIDv7.generate()
        let foreignState = makePaneTransitionState(title: "Foreign")

        // Act / Assert
        #expect(
            WorkspacePaneMetadataTransitionPlanner.plan(
                .init(paneID: requestedPaneID, update: .note(.clear)),
                currentPaneState: nil
            ) == .rejected(.paneMissing(requestedPaneID))
        )
        #expect(
            WorkspacePaneMetadataTransitionPlanner.plan(
                .init(
                    paneID: requestedPaneID,
                    update: .title("Foreign")
                ),
                currentPaneState: foreignState
            )
                == .rejected(
                    .paneIdentityMismatch(
                        requestedPaneID: requestedPaneID,
                        currentPaneID: foreignState.id
                    )
                )
        )
    }

}

private func makePaneTransitionState(
    paneID: UUID = UUIDv7.generate(),
    title: String,
    note: String? = nil,
    facets: PaneContextFacets = .empty
) -> PaneGraphState {
    PaneGraphState(
        pane: Pane(
            id: paneID,
            content: .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionID: .generateUUIDv7()
                )
            ),
            metadata: PaneMetadata(title: title, facets: facets, note: note)
        )
    )
}

extension Array {
    fileprivate var onlyElement: Element? {
        count == 1 ? self[0] : nil
    }
}
