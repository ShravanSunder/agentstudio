import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct TerminalRestoreTypesTests {
    @Test
    func hiddenRestorePolicy_usesExistingSessionsOnlyBehavior() {
        let config = SessionConfiguration.resolved(environment: [:], zmxPath: nil)

        #expect(config.shouldRestoreHiddenPane(hasExistingSession: true))
        #expect(!config.shouldRestoreHiddenPane(hasExistingSession: false))
    }

    @Test
    func visibleTier_sorting_prefersVisibleBeforeHidden() {
        let tiers: [VisibilityTier] = [.p1Hidden, .p0Visible]
        #expect(tiers.sorted() == [.p0Visible, .p1Hidden])
    }
}
