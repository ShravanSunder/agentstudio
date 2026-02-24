import AppKit
import Observation

extension Notification.Name {
    static let managementModeDidChange = Notification.Name("ManagementModeDidChange")
}

/// Manages management mode — a toggle that reveals close buttons, drag handles,
/// arrangement bar, and management borders on panes.
///
/// ## Keyboard blocking
///
/// During management mode, keyDown events are routed as:
/// - **Escape** (keyCode 53) → deactivates management mode
/// - **Any Command shortcut** → passes through to app/window handlers (menu, command pipeline)
/// - **Everything else** → consumed so pane content cannot type/interact
///
/// On activation, first responder is resigned from the key window so terminal
/// cursors stop blinking and pane content doesn't appear to accept input.
///
/// ## Toggling
///
/// Toggled via Cmd+E (command pipeline) or the toolbar/tab bar button.
@MainActor
@Observable
final class ManagementModeMonitor {
    static let shared = ManagementModeMonitor()

    /// Whether management mode is currently active
    private(set) var isActive: Bool = false

    private var keyboardMonitor: Any?

    private init() {
        startKeyboardMonitoring()
    }

    // MARK: - Public API

    /// Toggle management mode on/off.
    func toggle() {
        isActive.toggle()
        NotificationCenter.default.post(name: .managementModeDidChange, object: isActive)
        if isActive {
            resignPaneFirstResponder()
        }
    }

    /// Explicitly deactivate management mode (e.g., from Escape key).
    func deactivate() {
        let wasActive = isActive
        isActive = false
        if wasActive {
            NotificationCenter.default.post(name: .managementModeDidChange, object: false)
        }
    }

    func stopMonitoring() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
    }

    // MARK: - Keyboard Blocking

    /// Monitors all keyDown events. During management mode:
    /// - Escape → deactivate + consume
    /// - Any Command shortcut → pass through to app/window handlers
    /// - All other keys → consume (prevents typing in terminal/webview)
    private func startKeyboardMonitoring() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isActive else { return event }

            switch self.keyDownDecision(
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers
            ) {
            case .deactivateAndConsume:
                self.deactivate()
                return nil
            case .passThrough:
                return event
            case .consume:
                return nil
            }
        }
    }

    // MARK: - Key Policy

    enum KeyDownDecision: Equatable {
        case deactivateAndConsume
        case passThrough
        case consume
    }

    func keyDownDecision(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        charactersIgnoringModifiers _: String?
    ) -> KeyDownDecision {
        if keyCode == 53 {
            return .deactivateAndConsume
        }

        let normalizedModifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        if normalizedModifiers.contains(.command) {
            return .passThrough
        }

        return .consume
    }

    // MARK: - First Responder Management

    /// Resign first responder from the key window's content to prevent
    /// terminal cursors from blinking and pane content from appearing active.
    private func resignPaneFirstResponder() {
        guard let app: NSApplication = NSApp,
            let window = app.keyWindow
        else { return }
        window.makeFirstResponder(window.contentView)
    }
}
