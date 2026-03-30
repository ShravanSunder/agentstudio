import AppKit
import SwiftUI

@MainActor
final class PersistentTabHostView: NSView {
    let tabId: UUID
    let hostingView: NSHostingView<SingleTabContent>

    var containerView: NSView { self }

    init(
        tabId: UUID,
        rootView: SingleTabContent
    ) {
        self.tabId = tabId
        self.hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }
}
