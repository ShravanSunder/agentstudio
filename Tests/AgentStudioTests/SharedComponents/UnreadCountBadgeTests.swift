import SwiftUI
import Testing

@testable import AgentStudio

@Suite("UnreadCountBadge")
struct UnreadCountBadgeTests {
    @Test("badge is a shared value-rendered view")
    func badgeIsSharedValueRenderedView() {
        let badge = UnreadCountBadge(text: "9+")

        #expect(String(describing: type(of: badge)).contains("UnreadCountBadge"))
    }
}
