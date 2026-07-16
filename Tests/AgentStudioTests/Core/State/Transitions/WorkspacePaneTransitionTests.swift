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
}

private func makePaneTransitionState(
    paneID: UUID = UUIDv7.generate(),
    title: String
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
            metadata: PaneMetadata(title: title)
        )
    )
}

extension Array {
    fileprivate var onlyElement: Element? {
        count == 1 ? self[0] : nil
    }
}
