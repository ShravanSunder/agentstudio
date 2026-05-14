import AppKit

@MainActor
final class ScrollToBottomIndicatorView: NSButton {
    weak var actionPerformer: (any TerminalSurfaceActionPerforming)?

    private(set) var hasUnreadOutput = false
    private var totalRowsWhenScrolledUp: Int?
    private(set) var currentSymbolName = "chevron.down"
    private(set) var currentTintColor: NSColor = .systemBlue

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        bezelStyle = .texturedRounded
        isBordered = false
        setSymbol(named: "chevron.down.circle")
        target = self
        action = #selector(handleClick)
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func applyScrollbarState(
        _ state: ScrollbarState,
        isEffectivelyPinnedToBottom: Bool? = nil
    ) {
        let isPinnedToBottom = isEffectivelyPinnedToBottom ?? state.isPinnedToBottom
        isHidden = isPinnedToBottom

        if isPinnedToBottom {
            totalRowsWhenScrolledUp = nil
            hasUnreadOutput = false
            setTintColor(.systemBlue)
            setSymbol(named: "chevron.down.circle")
            return
        }

        if totalRowsWhenScrolledUp == nil {
            totalRowsWhenScrolledUp = state.total
        } else if let previousTotalRows = totalRowsWhenScrolledUp, state.total > previousTotalRows {
            hasUnreadOutput = true
        }

        setTintColor(hasUnreadOutput ? .systemGreen : .systemBlue)
        setSymbol(named: hasUnreadOutput ? "chevron.down.circle.fill" : "chevron.down.circle")
    }

    private func setSymbol(named symbolName: String) {
        currentSymbolName = symbolName
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Scroll to bottom")
        contentTintColor = currentTintColor
    }

    private func setTintColor(_ color: NSColor) {
        currentTintColor = color
        contentTintColor = color
    }

    @objc private func handleClick() {
        _ = actionPerformer?.performBindingAction(.scrollToBottom)
    }
}
