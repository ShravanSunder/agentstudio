import Testing

@testable import AgentStudio

@Suite(.serialized)
struct PaneDropPlannerMatrixTests {
    @Test("fixture covers movement matrix rows")
    func fixtureCoversMovementMatrixRows() {
        #expect(!PaneValidationMatrixFixture.cases.isEmpty)
        #expect(PaneValidationMatrixFixture.cases.count >= 11)
    }

    @Test("planner matrix cases enforce expected decisions")
    func plannerMatrixCases() {
        for testCase in PaneValidationMatrixFixture.cases {
            let decision = PaneDropPlanner.previewDecision(
                payload: testCase.payload,
                destination: testCase.destination,
                state: testCase.state
            )
            #expect(
                decision == testCase.expectedDecision,
                "Unexpected decision for case: \(testCase.name)"
            )
        }
    }
}
