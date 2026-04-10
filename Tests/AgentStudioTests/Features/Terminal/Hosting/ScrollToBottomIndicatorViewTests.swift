import AppKit
import Testing

@testable import AgentStudio

@Suite("ScrollToBottomIndicatorView")
@MainActor
struct ScrollToBottomIndicatorViewTests {
    @Test("scroll-to-bottom indicator shows unread output while scrolled up")
    func scrollToBottomIndicatorShowsUnreadOutputWhileScrolledUp() {
        let view = ScrollToBottomIndicatorView()

        view.applyScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 200))
        #expect(view.isHidden == false)
        #expect(view.hasNewOutputForTesting == false)

        view.applyScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 210))
        #expect(view.hasNewOutputForTesting == true)
    }

    @Test("scroll-to-bottom indicator hides when pinned")
    func scrollToBottomIndicatorHidesWhenPinned() {
        let view = ScrollToBottomIndicatorView()

        view.applyScrollbarState(ScrollbarState(top: 160, bottom: 200, total: 200))

        #expect(view.isHidden == true)
    }
}
