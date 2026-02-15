import AppKit
import Combine

/// Manages edit mode — a toggle that reveals close buttons, drag handles,
/// arrangement bar, and management borders on panes.
/// Toggled via Cmd+Opt+A (command pipeline) or the tab bar button.
/// Escape key deactivates when active.
@MainActor
final class ManagementModeMonitor: ObservableObject {
    static let shared = ManagementModeMonitor()

    /// Whether edit mode is currently active
    @Published private(set) var isActive: Bool = false

    private var escapeMonitor: Any?

    private init() {
        startEscapeMonitoring()
    }

    // MARK: - Public API

    /// Toggle edit mode on/off.
    func toggle() {
        isActive.toggle()
    }

    /// Explicitly deactivate edit mode (e.g., from Escape key).
    func deactivate() {
        isActive = false
    }

    // MARK: - Escape Key Listener

    private func startEscapeMonitoring() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isActive else { return event }
            // keyCode 53 = Escape
            if event.keyCode == 53 {
                self.deactivate()
                return nil // consume the event
            }
            return event
        }
    }

    func stopMonitoring() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }
}
