import Foundation
import Observation

@Observable
@MainActor
final class WindowLifecycleAtom {
    private(set) var registeredWindowIds: Set<UUID> = []
    private(set) var keyWindowId: UUID?
    private(set) var focusedWindowId: UUID?
    // Transient window facts for launch restore. Never persisted.
    private(set) var terminalContainerBounds: CGRect = .zero
    private(set) var isLaunchLayoutSettled = false

    var isReadyForLaunchRestore: Bool {
        isLaunchLayoutSettled && !terminalContainerBounds.isEmpty
    }

    /// True only when a registered workspace window is currently key.
    /// `false` intentionally conflates "no key window", "foreign key window",
    /// and "unregistered key window" because `KeyboardOwnerDerived` only needs
    /// to distinguish workspace-vs-other ownership.
    var isWorkspaceWindowKey: Bool {
        keyWindowId.map { registeredWindowIds.contains($0) } ?? false
    }

    var preferredWorkspaceWindowId: UUID? {
        if let focusedWindowId {
            return focusedWindowId
        }
        if let keyWindowId {
            return keyWindowId
        }
        guard registeredWindowIds.count == 1 else { return nil }
        return registeredWindowIds.first
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
        guard !bounds.isEmpty else { return }
        terminalContainerBounds = bounds
        RestoreTrace.log(
            "WindowLifecycleAtom.recordTerminalContainerBounds bounds=\(NSStringFromRect(bounds)) settled=\(isLaunchLayoutSettled) ready=\(isReadyForLaunchRestore)"
        )
    }

    func recordLaunchLayoutSettled() {
        isLaunchLayoutSettled = true
        RestoreTrace.log(
            "WindowLifecycleAtom.recordLaunchLayoutSettled bounds=\(NSStringFromRect(terminalContainerBounds)) settled=\(isLaunchLayoutSettled) ready=\(isReadyForLaunchRestore)"
        )
    }
}
