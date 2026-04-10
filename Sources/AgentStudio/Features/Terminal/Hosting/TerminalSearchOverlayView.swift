import AppKit

@MainActor
final class TerminalSearchOverlayView: NSView {
    enum NavigationDirection: Equatable {
        case next
        case previous
    }

    var onQueryChanged: ((String) -> Void)?
    var onNavigate: ((NavigationDirection) -> Void)?
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
        searchField.target = self
        searchField.action = #selector(handleSearchFieldChange)

        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        resultLabel.alignment = .center

        previousButton.translatesAutoresizingMaskIntoConstraints = false
        previousButton.title = "Prev"
        previousButton.target = self
        previousButton.action = #selector(handlePrevious)
        previousButton.bezelStyle = .texturedRounded

        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.title = "Next"
        nextButton.target = self
        nextButton.action = #selector(handleNext)
        nextButton.bezelStyle = .texturedRounded

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.title = "Close"
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.bezelStyle = .texturedRounded

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

            searchField.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            searchField.widthAnchor.constraint(equalToConstant: 180),

            resultLabel.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            resultLabel.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 8),
            resultLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),

            previousButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            previousButton.leadingAnchor.constraint(equalTo: resultLabel.trailingAnchor, constant: 8),

            nextButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            nextButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 6),

            closeButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            closeButton.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10),
            closeButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func update(query: String, totalMatches: Int?, selectedMatchIndex: Int?) {
        searchField.stringValue = query
        if let totalMatches {
            let selectedDisplayIndex = (selectedMatchIndex ?? -1) + 1
            resultLabel.stringValue = "\(max(0, selectedDisplayIndex)) of \(totalMatches)"
        } else {
            resultLabel.stringValue = ""
        }
    }

    @objc private func handleSearchFieldChange() {
        onQueryChanged?(searchField.stringValue)
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
