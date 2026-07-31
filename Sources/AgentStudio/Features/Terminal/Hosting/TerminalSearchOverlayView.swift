import AgentStudioInfrastructure
import AppKit

@MainActor
final class TerminalSearchOverlayView: NSView, NSSearchFieldDelegate {
    enum NavigationDirection: Equatable {
        case next
        case previous
    }

    var onQueryChanged: ((String) -> Void)?
    var onNavigate: ((NavigationDirection) -> Void)?
    var onReturnFocusToTerminal: (() -> Void)?
    var onClose: (() -> Void)?

    private let containerView = NSVisualEffectView()
    private let searchField = NSSearchField()
    private let resultLabel = NSTextField(labelWithString: "")
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let closeButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        containerView.material = .popover
        containerView.state = .active
        containerView.blendingMode = .withinWindow
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 10
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self

        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        resultLabel.alignment = .center

        configureIconButton(
            previousButton,
            symbolName: "chevron.up",
            accessibilityLabel: "Previous Match"
        )
        previousButton.target = self
        previousButton.action = #selector(handlePrevious)

        configureIconButton(
            nextButton,
            symbolName: "chevron.down",
            accessibilityLabel: "Next Match"
        )
        nextButton.target = self
        nextButton.action = #selector(handleNext)

        configureIconButton(
            closeButton,
            symbolName: "xmark",
            accessibilityLabel: "Close Find"
        )
        closeButton.target = self
        closeButton.action = #selector(handleClose)

        containerView.addSubview(searchField)
        containerView.addSubview(resultLabel)
        containerView.addSubview(previousButton)
        containerView.addSubview(nextButton)
        containerView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            searchField.topAnchor.constraint(
                equalTo: containerView.topAnchor,
                constant: AppStyles.WorkspaceFocus.Terminal.searchOverlayContentInset
            ),
            searchField.leadingAnchor.constraint(
                equalTo: containerView.leadingAnchor,
                constant: AppStyles.WorkspaceFocus.Terminal.searchOverlayContentInset
            ),
            searchField.bottomAnchor.constraint(
                equalTo: containerView.bottomAnchor,
                constant: -AppStyles.WorkspaceFocus.Terminal.searchOverlayContentInset
            ),
            searchField.widthAnchor.constraint(
                greaterThanOrEqualToConstant:
                    AppStyles.WorkspaceFocus.Terminal.searchOverlayMinimumFieldWidth
            ),

            resultLabel.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            resultLabel.leadingAnchor.constraint(
                equalTo: searchField.trailingAnchor,
                constant: AppStyles.WorkspaceFocus.Terminal.searchOverlayResultSpacing
            ),
            resultLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),

            previousButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            previousButton.leadingAnchor.constraint(
                equalTo: resultLabel.trailingAnchor,
                constant: AppStyles.WorkspaceFocus.Terminal.searchOverlayResultSpacing
            ),

            nextButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            nextButton.leadingAnchor.constraint(
                equalTo: previousButton.trailingAnchor,
                constant: AppStyles.WorkspaceFocus.Terminal.searchOverlayControlSpacing
            ),

            closeButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            closeButton.leadingAnchor.constraint(
                equalTo: nextButton.trailingAnchor,
                constant: AppStyles.WorkspaceFocus.Terminal.searchOverlayControlSpacing
            ),
            closeButton.trailingAnchor.constraint(
                equalTo: containerView.trailingAnchor,
                constant: -AppStyles.WorkspaceFocus.Terminal.searchOverlayContentInset
            ),
        ])

        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func initializeQuery(_ query: String) {
        searchField.stringValue = query
    }

    func updateResults(totalMatches: Int?, selectedMatchIndex: Int?) {
        if let totalMatches {
            let selectedDisplayIndex = (selectedMatchIndex ?? -1) + 1
            resultLabel.stringValue = "\(max(0, selectedDisplayIndex)) of \(totalMatches)"
        } else {
            resultLabel.stringValue = ""
        }
    }

    func focusSearchField() {
        window?.makeFirstResponder(searchField)
    }

    func ownsFirstResponder(_ responder: NSResponder?) -> Bool {
        responder === searchField || responder === searchField.currentEditor()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSSearchField === searchField else {
            return
        }
        onQueryChanged?(searchField.stringValue)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard
            control === searchField,
            textView === searchField.currentEditor(),
            commandSelector == #selector(NSResponder.cancelOperation(_:))
        else {
            return false
        }

        if searchField.stringValue.isEmpty {
            onClose?()
        } else {
            onReturnFocusToTerminal?()
        }
        return true
    }

    @objc private func handlePrevious() {
        onNavigate?(.previous)
    }

    @objc private func handleNext() {
        onNavigate?(.next)
    }

    @objc private func handleClose() {
        onClose?()
    }

    private func configureIconButton(
        _ button: NSButton,
        symbolName: String,
        accessibilityLabel: String
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.title = ""
        button.bezelStyle = .texturedRounded
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.setAccessibilityLabel(accessibilityLabel)

        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityLabel
        )
        image?.setName(NSImage.Name(symbolName))
        button.image =
            image?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(
                    pointSize: AppStyles.WorkspaceFocus.Terminal.searchOverlayIconSize,
                    weight: .medium
                )
            ) ?? image

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(
                equalToConstant: AppStyles.WorkspaceFocus.Terminal.searchOverlayButtonSize
            ),
            button.heightAnchor.constraint(
                equalToConstant: AppStyles.WorkspaceFocus.Terminal.searchOverlayButtonSize
            ),
        ])
    }
}

#if DEBUG
    @MainActor
    extension TerminalSearchOverlayView {
        var resultLabelTextForTesting: String {
            resultLabel.stringValue
        }

        var interactivePointForTesting: NSPoint {
            let searchFieldFrame = searchField.frame
            return NSPoint(x: searchFieldFrame.midX, y: searchFieldFrame.midY)
        }

        func simulateQueryChangeForTesting(_ query: String) {
            searchField.stringValue = query
            onQueryChanged?(query)
        }

        func simulateNavigateForTesting(_ direction: NavigationDirection) {
            onNavigate?(direction)
        }

        func simulateCloseForTesting() {
            onClose?()
        }
    }
#endif
