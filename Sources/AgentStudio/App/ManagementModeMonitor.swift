import AppKit
import Combine

/// Monitors Opt+Cmd (Option + Command) modifier keys to toggle management mode.
/// Management mode reveals close buttons, enables drag-and-drop for panes/tabs,
/// and shows management borders on panes.
/// Note: Ctrl+click = right-click on macOS, so Ctrl is avoided.
@MainActor
final class ManagementModeMonitor: ObservableObject {
    static let shared = ManagementModeMonitor()

    /// Whether management mode is currently active (Opt+Cmd held)
    @Published private(set) var isActive: Bool = false

    /// The required modifier flags for management mode
    static let requiredModifiers: NSEvent.ModifierFlags = [.option, .command]

    private var flagsMonitor: Any?

    private init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    private func startMonitoring() {
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    nonisolated func stopMonitoring() {
        MainActor.assumeIsolated {
            if let monitor = flagsMonitor {
                NSEvent.removeMonitor(monitor)
                flagsMonitor = nil
            }
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let newValue = flags.contains(Self.requiredModifiers)
        if isActive != newValue {
            isActive = newValue
        }
    }
}
