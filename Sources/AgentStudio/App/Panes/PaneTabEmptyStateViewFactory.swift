import AppKit

@MainActor
enum PaneTabEmptyStateViewFactory {
    static func make(target: AnyObject, addRepoAction: Selector, addFolderAction: Selector) -> NSView {
        let container = NSView()
        container.wantsLayer = true

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 20
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // Icon with gradient background
        let iconContainer = NSView()
        iconContainer.wantsLayer = true
        iconContainer.layer?.cornerRadius = 20
        iconContainer.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Terminal")
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 36, weight: .medium)
        iconView.contentTintColor = .controlAccentColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)

        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 80),
            iconContainer.heightAnchor.constraint(equalToConstant: 80),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
        ])

        let titleLabel = NSTextField(labelWithString: "Welcome to AgentStudio")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .labelColor

        let subtitleLabel = NSTextField(
            wrappingLabelWithString:
                "Manage your AI agent worktrees with integrated terminal sessions.\nDouble-click a worktree to open a terminal."
        )
        subtitleLabel.font = NSFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 3

        let hintLabel = NSTextField(labelWithString: "Tip: Add Folder scans and imports all repos at once")
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor

        let addRepoButton = NSButton(title: "Add Repo...", target: target, action: addRepoAction)
        addRepoButton.bezelStyle = .rounded
        addRepoButton.controlSize = .large

        let addFolderButton = NSButton(title: "Add Folder...", target: target, action: addFolderAction)
        addFolderButton.bezelStyle = .rounded
        addFolderButton.controlSize = .large
        addFolderButton.bezelColor = .systemTeal
        addFolderButton.keyEquivalent = "\r"

        let buttonStack = NSStackView(views: [addRepoButton, addFolderButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 10
        buttonStack.alignment = .centerY

        stackView.addArrangedSubview(iconContainer)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.addArrangedSubview(buttonStack)
        stackView.addArrangedSubview(hintLabel)

        stackView.setCustomSpacing(24, after: iconContainer)
        stackView.setCustomSpacing(8, after: titleLabel)
        stackView.setCustomSpacing(24, after: subtitleLabel)
        stackView.setCustomSpacing(12, after: buttonStack)

        container.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            subtitleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 400),
        ])

        return container
    }
}
