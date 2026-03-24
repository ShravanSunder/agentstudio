import Foundation
import Observation

@Observable
@MainActor
final class WindowLifecycleStore {
    private(set) var registeredWindowIds: Set<UUID> = []
    private(set) var keyWindowId: UUID?
    private(set) var focusedWindowId: UUID?
    // Transient window facts for launch restore. Never persisted.
    private(set) var terminalContainerBounds: CGRect = .zero
    private(set) var isLaunchLayoutSettled = false

    var isReadyForLaunchRestore: Bool {
        isLaunchLayoutSettled && !terminalContainerBounds.isEmpty
    }

    func recordWindowRegistered(_ windowId: UUID) {
        registeredWindowIds.insert(windowId)
    }

    func recordWindowBecameKey(_ windowId: UUID) {
        keyWindowId = windowId
        focusedWindowId = windowId
    }

    func recordWindowResignedKey(_ windowId: UUID) {
        guard keyWindowId == windowId else { return }
        keyWindowId = nil
    }

    func recordWindowBecameFocused(_ windowId: UUID) {
        focusedWindowId = windowId
    }

    func recordWindowResignedFocused(_ windowId: UUID) {
        guard focusedWindowId == windowId else { return }
        focusedWindowId = nil
    }

    func recordTerminalContainerBounds(_ bounds: CGRect) {
        terminalContainerBounds = bounds
    }

    func recordLaunchLayoutSettled() {
        isLaunchLayoutSettled = true
    }
}
