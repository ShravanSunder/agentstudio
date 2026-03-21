import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct TerminalRestoreTypesTests {
    @Test
    func backgroundRestorePolicy_defaultsToExistingSessionsOnly() {
        #expect(SessionConfiguration.detect().backgroundRestorePolicy == .existingSessionsOnly)
    }

    @Test
    func visibleTier_sorting_prefersVisibleBeforeHidden() {
        let tiers: [VisibilityTier] = [.p1Hidden, .p0Visible]
        #expect(tiers.sorted() == [.p0Visible, .p1Hidden])
    }
}
