import AppKit
import SwiftUI
import os.log

private let controllerLogger = Logger(subsystem: "com.agentstudio", category: "CommandBarPanelController")

// MARK: - CommandBarPanelController

/// Manages the command bar panel lifecycle: show, dismiss, animate, backdrop.
/// Owns the CommandBarState and wires it to the panel.
/// All methods must be called on the main thread (enforced by AppKit caller context).
@MainActor
final class CommandBarPanelController {

    // MARK: - State

    let state = CommandBarState()

    // MARK: - Dependencies

    private let store: WorkspaceStore
    private let dispatcher: CommandDispatcher

    // MARK: - Panel

    private var panel: CommandBarPanel?
    private var backdropView: CommandBarBackdropView?

    /// The parent window the command bar is attached to.
    private weak var parentWindow: NSWindow?

    // MARK: - Initialization

    init(store: WorkspaceStore, dispatcher: CommandDispatcher) {
        self.store = store
        self.dispatcher = dispatcher
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
        let contentView = CommandBarView(
            state: state,
            store: store,
            dispatcher: dispatcher,
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )
        panel.setContent(contentView)

        // Add as child window
        parentWindow.addChildWindow(panel, ordered: .above)

        // Position panel
        panel.positionRelativeTo(parentWindow: parentWindow)

        // Initial size — will be updated by content
        panel.updateHeight(parentWindow: parentWindow)

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

        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.08
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panelToRemove.animator().alphaValue = 0
            },
            completionHandler: {
                Task { @MainActor in
                    panelToRemove.parent?.removeChildWindow(panelToRemove)
                    panelToRemove.orderOut(nil)
                    controllerLogger.debug("Command bar panel dismissed")
                }
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

        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.08
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                backdrop.animator().alphaValue = 0
            },
            completionHandler: {
                Task { @MainActor in
                    backdrop.removeFromSuperview()
                }
            })
        backdropView = nil
    }
}

// MARK: - CommandBarBackdropView

/// Semi-transparent overlay behind the command bar panel. Click to dismiss.
@MainActor
final class CommandBarBackdropView: NSView {
    private let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("CommandBarPanelController does not support NSCoder") }

    override func mouseDown(with event: NSEvent) {
        onDismiss()
    }
}
