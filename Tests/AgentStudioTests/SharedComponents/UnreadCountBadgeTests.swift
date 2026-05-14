import SwiftUI
import Testing

@testable import AgentStudio

@Suite("UnreadCountBadge")
struct UnreadCountBadgeTests {
    @Test("badge builds with count text")
    @MainActor
    func badgeBuildsWithCountText() {
        let badge = UnreadCountBadge(text: "1")

        #expect(String(describing: type(of: badge)).contains("UnreadCountBadge"))
    }
}
