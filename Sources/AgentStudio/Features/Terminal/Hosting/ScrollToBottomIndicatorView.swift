import AppKit

@MainActor
final class ScrollToBottomIndicatorView: NSButton {
    weak var actionPerformer: (any TerminalSurfaceActionPerforming)?

    private(set) var hasNewOutputForTesting = false
    private var totalRowsWhenScrolledUp: Int?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        bezelStyle = .texturedRounded
        image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Scroll to bottom")
        target = self
        action = #selector(handleClick)
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func applyScrollbarState(_ state: ScrollbarState) {
        let isPinnedToBottom = state.bottom >= state.total
        isHidden = isPinnedToBottom

        if isPinnedToBottom {
            totalRowsWhenScrolledUp = nil
            hasNewOutputForTesting = false
            image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Scroll to bottom")
            return
        }

        if totalRowsWhenScrolledUp == nil {
            totalRowsWhenScrolledUp = state.total
        } else if let previousTotalRows = totalRowsWhenScrolledUp, state.total > previousTotalRows {
            hasNewOutputForTesting = true
        }

        image = NSImage(
            systemSymbolName: hasNewOutputForTesting ? "chevron.down.circle.fill" : "chevron.down",
            accessibilityDescription: "Scroll to bottom"
        )
    }

    @objc private func handleClick() {
        _ = actionPerformer?.performBindingAction("scroll_to_bottom")
    }
}
