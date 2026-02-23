import AppKit
import Observation

/// Manages management mode — a toggle that reveals close buttons, drag handles,
/// arrangement bar, and management borders on panes.
///
/// ## Keyboard blocking
///
/// During management mode, ALL keyboard events are consumed except:
/// - **Escape** (keyCode 53) → deactivates management mode
/// - **Cmd+E** → passes through to PaneTabViewController's event monitor for toggle
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
        if isActive {
            resignPaneFirstResponder()
        }
    }

    /// Explicitly deactivate management mode (e.g., from Escape key).
    func deactivate() {
        isActive = false
    }

    func stopMonitoring() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
    }

    // MARK: - Keyboard Blocking

    /// Monitors all keyDown events. During management mode:
    /// - Escape → deactivates management mode (consumed)
    /// - Cmd+E → passes through for toggle handling by PaneTabViewController
    /// - All other keys → consumed (prevents typing in terminal/webview)
    private func startKeyboardMonitoring() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isActive else { return event }

            // Escape → deactivate management mode
            if event.keyCode == 53 {
                self.deactivate()
                return nil
            }

            // Cmd+E → pass through for PaneTabViewController's toggle handler
            if event.modifierFlags.contains(.command),
                !event.modifierFlags.contains([.shift, .option, .control]),
                event.charactersIgnoringModifiers == "e"
            {
                return event
            }

            // All other keys → consume during management mode
            return nil
        }
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
