import Testing

@testable import AgentStudio

@Suite("Ghostty event routing coverage")
@MainActor
struct GhosttyEventRoutingCoverageTests {
    @Test("every known Ghostty action tag has one explicit routing decision")
    func everyKnownGhosttyActionTag_hasExplicitRoutingDecision() {
        let accountedTags =
            Ghostty.ActionRouter.explicitlyRoutedTags
            .union(Ghostty.ActionRouter.deferredTags)
            .union(Ghostty.ActionRouter.interceptedTags)

        #expect(accountedTags == Set(GhosttyActionTag.allCases))
    }
}
