import Foundation
import Observation

/// AppKit presentation facts for one registered workspace window.
///
/// These facts intentionally exclude key and focus state. Key and focus rank
/// interactive work, but they do not decide whether a pane is foreground.
struct WindowPresentationFacts: Equatable, Sendable {
    let isVisible: Bool
    let isMiniaturized: Bool
    let isOccluded: Bool

    static let hidden = Self(
        isVisible: false,
        isMiniaturized: false,
        isOccluded: true
    )
}

@Observable
@MainActor
final class WindowLifecycleAtom {
    private(set) var registeredWindowIds: Set<UUID> = []
    private(set) var keyWindowId: UUID?
    private(set) var focusedWindowId: UUID?
    private var presentationFactsByWindowId: [UUID: WindowPresentationFacts] = [:]
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
        if presentationFactsByWindowId[windowId] == nil {
            presentationFactsByWindowId[windowId] = .hidden
        }
    }

    func presentationFacts(for windowId: UUID) -> WindowPresentationFacts? {
        presentationFactsByWindowId[windowId]
    }

    func recordWindowPresentation(
        _ facts: WindowPresentationFacts,
        for windowId: UUID
    ) {
        guard registeredWindowIds.contains(windowId) else { return }
        presentationFactsByWindowId[windowId] = facts
    }

    func recordWindowVisibility(_ isVisible: Bool, for windowId: UUID) {
        guard let facts = presentationFactsByWindowId[windowId] else { return }
        recordWindowPresentation(
            WindowPresentationFacts(
                isVisible: isVisible,
                isMiniaturized: facts.isMiniaturized,
                isOccluded: facts.isOccluded
            ),
            for: windowId
        )
    }

    func recordWindowMiniaturization(_ isMiniaturized: Bool, for windowId: UUID) {
        guard let facts = presentationFactsByWindowId[windowId] else { return }
        recordWindowPresentation(
            WindowPresentationFacts(
                isVisible: facts.isVisible,
                isMiniaturized: isMiniaturized,
                isOccluded: facts.isOccluded
            ),
            for: windowId
        )
    }

    func recordWindowOcclusion(_ isOccluded: Bool, for windowId: UUID) {
        guard let facts = presentationFactsByWindowId[windowId] else { return }
        recordWindowPresentation(
            WindowPresentationFacts(
                isVisible: facts.isVisible,
                isMiniaturized: facts.isMiniaturized,
                isOccluded: isOccluded
            ),
            for: windowId
        )
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
