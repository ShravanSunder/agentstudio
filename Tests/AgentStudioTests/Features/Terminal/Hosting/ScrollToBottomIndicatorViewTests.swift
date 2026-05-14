import AppKit
import Testing

@testable import AgentStudio

@Suite("ScrollToBottomIndicatorView")
@MainActor
struct ScrollToBottomIndicatorViewTests {
    @Test("scroll-to-bottom indicator uses icon-only chrome")
    func scrollToBottomIndicatorUsesIconOnlyChrome() {
        let view = ScrollToBottomIndicatorView()

        #expect(view.isBordered == false)
    }

    @Test("scroll-to-bottom indicator uses thicker icon pair")
    func scrollToBottomIndicatorUsesThickerIconPair() {
        let view = ScrollToBottomIndicatorView()

        view.applyScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 200))
        #expect(view.currentSymbolName == "chevron.down.circle")
        #expect(view.currentTintColor == .systemBlue)

        view.applyScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 210))
        #expect(view.currentSymbolName == "chevron.down.circle.fill")
        #expect(view.currentTintColor == .systemGreen)
    }

    @Test("scroll-to-bottom indicator shows unread output while scrolled up")
    func scrollToBottomIndicatorShowsUnreadOutputWhileScrolledUp() {
        let view = ScrollToBottomIndicatorView()

        view.applyScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 200))
        #expect(view.isHidden == false)
        #expect(view.hasUnreadOutput == false)

        view.applyScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 210))
        #expect(view.hasUnreadOutput == true)
    }

    @Test("scroll-to-bottom indicator hides when pinned")
    func scrollToBottomIndicatorHidesWhenPinned() {
        let view = ScrollToBottomIndicatorView()

        view.applyScrollbarState(ScrollbarState(top: 160, bottom: 200, total: 200))

        #expect(view.isHidden == true)
    }

    @Test("scroll-to-bottom indicator treats sticky buffer as effectively pinned")
    func scrollToBottomIndicatorTreatsStickyBufferAsEffectivelyPinned() {
        let view = ScrollToBottomIndicatorView()

        view.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 200),
            isEffectivelyPinnedToBottom: true
        )
        #expect(view.isHidden)
        #expect(!view.hasUnreadOutput)

        view.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 210),
            isEffectivelyPinnedToBottom: true
        )
        #expect(view.isHidden)
        #expect(!view.hasUnreadOutput)
        #expect(view.currentSymbolName == "chevron.down.circle")
    }

    @Test("scroll-to-bottom indicator resets unread state after returning to bottom")
    func scrollToBottomIndicatorResetsUnreadStateAfterReturningToBottom() {
        let view = ScrollToBottomIndicatorView()

        view.applyScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 200))
        view.applyScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 210))
        #expect(view.hasUnreadOutput)

        view.applyScrollbarState(ScrollbarState(top: 170, bottom: 210, total: 210))
        #expect(view.isHidden)
        #expect(!view.hasUnreadOutput)

        view.applyScrollbarState(ScrollbarState(top: 180, bottom: 220, total: 260))
        #expect(!view.hasUnreadOutput)
    }
}
