import AppKit
import SwiftUI
import os.log

private let controllerLogger = Logger(subsystem: "com.agentstudio", category: "CommandBarPanelController")

// MARK: - CommandBarPanelController

/// Manages the command bar panel lifecycle: show, dismiss, animate, backdrop.
/// Owns the CommandBarState and wires it to the panel.
/// All methods must be called on the main thread (enforced by AppKit caller context).
final class CommandBarPanelController {

    // MARK: - State

    let state = CommandBarState()

    // MARK: - Panel

    private var panel: CommandBarPanel?
    private var backdropView: CommandBarBackdropView?

    /// The parent window the command bar is attached to.
    private weak var parentWindow: NSWindow?

    // MARK: - Initialization

    init() {
        state.loadRecents()
    }

    // MARK: - Show / Dismiss

    /// Show the command bar. If already visible with a different prefix, switch in-place.
    /// If already visible with the same prefix (or no prefix), dismiss (toggle behavior).
    func show(prefix: String? = nil, parentWindow: NSWindow) {
        self.parentWindow = parentWindow

        if state.isVisible {
            // Toggle: same prefix → dismiss; different prefix → switch in-place
            let currentPrefix = state.activePrefix
            let requestedPrefix = prefix

            if currentPrefix == requestedPrefix {
                dismiss()
                return
            } else {
                state.switchPrefix(requestedPrefix ?? "")
                return
            }
        }

        // Create panel and backdrop
        state.show(prefix: prefix)
        presentPanel(parentWindow: parentWindow)
    }

    /// Dismiss the command bar and clean up.
    func dismiss() {
        guard state.isVisible else { return }

        state.dismiss()
        dismissPanel()
    }

    // MARK: - Panel Presentation

    private func presentPanel(parentWindow: NSWindow) {
        let panel = CommandBarPanel()
        self.panel = panel

        // Wire Escape key through controller dismiss lifecycle
        panel.onDismiss = { [weak self] in
            self?.dismiss()
        }

        // Set SwiftUI content
        let contentView = CommandBarContentView(state: state, onDismiss: { [weak self] in
            self?.dismiss()
        })
        panel.setContent(contentView)

        // Add as child window
        parentWindow.addChildWindow(panel, ordered: .above)

        // Position panel
        panel.positionRelativeTo(parentWindow: parentWindow)

        // Initial size — will be updated by content
        panel.updateHeight(300, parentWindow: parentWindow)

        // Show backdrop
        showBackdrop(on: parentWindow)

        // Animate in
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        })

        controllerLogger.debug("Command bar panel presented")
    }

    private func dismissPanel() {
        guard let panel else { return }

        // Animate out — capture panel locally to avoid actor-isolation issues in completion
        let panelToRemove = panel
        self.panel = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panelToRemove.animator().alphaValue = 0
        }, completionHandler: {
            panelToRemove.parent?.removeChildWindow(panelToRemove)
            panelToRemove.orderOut(nil)
            controllerLogger.debug("Command bar panel dismissed")
        })

        // Remove backdrop
        hideBackdrop()

        // Return focus to parent window
        parentWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Backdrop

    private func showBackdrop(on window: NSWindow) {
        guard let contentView = window.contentView else { return }

        let backdrop = CommandBarBackdropView(onDismiss: { [weak self] in
            self?.dismiss()
        })
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        backdrop.alphaValue = 0
        contentView.addSubview(backdrop, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: contentView.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        self.backdropView = backdrop

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            backdrop.animator().alphaValue = 1
        }
    }

    private func hideBackdrop() {
        guard let backdrop = backdropView else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            backdrop.animator().alphaValue = 0
        }, completionHandler: {
            backdrop.removeFromSuperview()
        })
        backdropView = nil
    }
}

// MARK: - CommandBarBackdropView

/// Semi-transparent overlay behind the command bar panel. Click to dismiss.
final class CommandBarBackdropView: NSView {
    private let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        onDismiss()
    }
}

// MARK: - CommandBarContentView (temporary placeholder)

/// Placeholder SwiftUI view for the command bar content.
/// Will be replaced with full implementation in Phase 3.
private struct CommandBarContentView: View {
    @Bindable var state: CommandBarState
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Search field placeholder
            HStack(spacing: 10) {
                Image(systemName: state.scopeIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.35))
                    .frame(width: 16, height: 16)

                TextField(state.placeholder, text: $state.rawInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .onSubmit {
                        // TODO: Phase 4 — execute selected item
                    }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)

            Divider()
                .opacity(0.3)

            // Results placeholder
            VStack(spacing: 8) {
                Text("Command bar ready")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.5))

                Text("Scope: \(scopeLabel)")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.3))

                if !state.searchQuery.isEmpty {
                    Text("Query: \"\(state.searchQuery)\"")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.3))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)

            Divider()
                .opacity(0.3)

            // Footer placeholder
            HStack(spacing: 16) {
                footerHint("↵", "Open")
                footerHint("↑↓", "Navigate")
                footerHint("esc", "Dismiss")
            }
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
        }
        .frame(width: 540)
    }

    private var scopeLabel: String {
        switch state.activeScope {
        case .everything: return "Everything"
        case .commands: return "Commands"
        case .panes: return "Panes"
        }
    }

    private func footerHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
            Text(label)
                .font(.system(size: 11))
        }
        .foregroundStyle(.primary.opacity(0.3))
    }
}
