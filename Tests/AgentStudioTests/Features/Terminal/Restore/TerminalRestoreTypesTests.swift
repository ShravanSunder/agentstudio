import AgentStudioCore
import Foundation
import Testing

@testable import AgentStudioTerminal

@Suite(.serialized)
struct TerminalRestoreTypesTests {
    @Test
    func visibleTier_sorting_prefersVisibleBeforeHidden() {
        let tiers: [VisibilityTier] = [.p1Hidden, .p0Visible]
        #expect(tiers.sorted() == [.p0Visible, .p1Hidden])
    }
}
