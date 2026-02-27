import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct DragSessionStateTests {

    @Test
    func test_armedSessionRetainsCandidatePayloadAndTarget() {
        let payload = SplitDropPayload(kind: .newTerminal)
        let target = PaneDropTarget(paneId: UUID(), zone: .left)
        let candidate = DragSessionCandidate(payload: payload, target: target)
        let state = DragSessionState.armed(candidate: candidate)

        guard case .armed(let storedCandidate) = state else {
            Issue.record("Expected armed state")
            return
        }

        #expect(storedCandidate == candidate)
    }

    @Test
    func test_committingSessionRetainsCandidate() {
        let payload = SplitDropPayload(kind: .existingTab(tabId: UUID()))
        let target = PaneDropTarget(paneId: UUID(), zone: .right)
        let candidate = DragSessionCandidate(payload: payload, target: target)
        let state = DragSessionState.committing(candidate: candidate)

        guard case .committing(let storedCandidate) = state else {
            Issue.record("Expected committing state")
            return
        }

        #expect(storedCandidate.target == target)
    }
}
