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
        #expect(view.hasUnreadOutputForTesting == false)

        view.applyScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 210))
        #expect(view.hasUnreadOutputForTesting == true)
    }

    @Test("scroll-to-bottom indicator hides when pinned")
    func scrollToBottomIndicatorHidesWhenPinned() {
        let view = ScrollToBottomIndicatorView()

        view.applyScrollbarState(ScrollbarState(top: 160, bottom: 200, total: 200))

        #expect(view.isHidden == true)
    }

    @Test("scroll-to-bottom indicator resets unread state after returning to bottom")
    func scrollToBottomIndicatorResetsUnreadStateAfterReturningToBottom() {
        let view = ScrollToBottomIndicatorView()

        view.applyScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 200))
        view.applyScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 210))
        #expect(view.hasUnreadOutputForTesting)

        view.applyScrollbarState(ScrollbarState(top: 170, bottom: 210, total: 210))
        #expect(view.isHidden)
        #expect(!view.hasUnreadOutputForTesting)

        view.applyScrollbarState(ScrollbarState(top: 180, bottom: 220, total: 260))
        #expect(!view.hasUnreadOutputForTesting)
    }
}
