import AppKit

final class CodeViewerPaneView: PaneView {
    private let state: CodeViewerState
    private let initialText: String?
    private let scrollView = NSScrollView()
    private let textView = NSTextView()

    init(paneId: UUID, state: CodeViewerState, initialText: String? = nil) {
        self.state = state
        self.initialText = initialText
        super.init(paneId: paneId)
        setupCodeViewerSurface()
        loadFileContents()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    private func setupCodeViewerSurface() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindPanel = true
        textView.allowsUndo = false
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false

        scrollView.documentView = textView
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func loadFileContents() {
        if let initialText {
            textView.string = initialText
            if let scrollToLine = state.scrollToLine {
                scrollToLineNumber(scrollToLine)
            }
            return
        }

        do {
            textView.string = try String(contentsOf: state.filePath, encoding: .utf8)
            if let scrollToLine = state.scrollToLine {
                scrollToLineNumber(scrollToLine)
            }
        } catch {
            textView.string = "Unable to load file: \(state.filePath.path)"
        }
    }

    private func scrollToLineNumber(_ targetLine: Int) {
        guard targetLine > 0 else { return }

        let text = textView.string as NSString
        var currentLine = 1
        var location = 0

        while currentLine < targetLine, location < text.length {
            let searchRange = NSRange(location: location, length: text.length - location)
            let newlineRange = text.range(of: "\n", options: [], range: searchRange)
            if newlineRange.location == NSNotFound {
                break
            }
            location = newlineRange.location + newlineRange.length
            currentLine += 1
        }

        let selectionRange = NSRange(location: location, length: 0)
        textView.setSelectedRange(selectionRange)
        textView.scrollRangeToVisible(selectionRange)
    }
}
