import AgentStudioInfrastructure
import Foundation
import Observation

/// AppKit presentation facts for one registered workspace window.
///
/// These facts intentionally exclude key and focus state. Key and focus rank
/// interactive work, but they do not decide whether a pane is foreground.
package struct WindowPresentationFacts: Equatable, Sendable {
    package let isVisible: Bool
    package let isMiniaturized: Bool
    package let isOccluded: Bool

    package init(isVisible: Bool, isMiniaturized: Bool, isOccluded: Bool) {
        self.isVisible = isVisible
        self.isMiniaturized = isMiniaturized
        self.isOccluded = isOccluded
    }

    package static let hidden = Self(
        isVisible: false,
        isMiniaturized: false,
        isOccluded: true
    )
}

package enum FirstInteractiveFrameSource: String, Equatable, Sendable {
    case presented
    case occludedFallback = "occluded_fallback"
}

@Observable
@MainActor
package final class WindowLifecycleAtom {
    package private(set) var registeredWindowIds: Set<UUID> = []
    package private(set) var keyWindowId: UUID?
    package private(set) var focusedWindowId: UUID?
    private var presentationFactsByWindowId: [UUID: WindowPresentationFacts] = [:]
    // Transient window facts for launch restore. Never persisted.
    package private(set) var terminalContainerBounds: CGRect = .zero
    package private(set) var isLaunchLayoutSettled = false
    /// App-owned usable-frame proxy. This is not a Ghostty renderer-present fact.
    package private(set) var didPublishFirstInteractiveFrame = false
    package private(set) var firstInteractiveFrameSource: FirstInteractiveFrameSource?
    private var firstInteractiveFrameWaiters: [CheckedContinuation<Void, Never>] = []

    package var isReadyForLaunchRestore: Bool {
        isLaunchLayoutSettled && !terminalContainerBounds.isEmpty
    }

    package init() {}

    /// True only when a registered workspace window is currently key.
    /// `false` intentionally conflates "no key window", "foreign key window",
    /// and "unregistered key window" because `KeyboardOwnerDerived` only needs
    /// to distinguish workspace-vs-other ownership.
    var isWorkspaceWindowKey: Bool {
        keyWindowId.map { registeredWindowIds.contains($0) } ?? false
    }

    package var preferredWorkspaceWindowId: UUID? {
        if let focusedWindowId {
            return focusedWindowId
        }
        if let keyWindowId {
            return keyWindowId
        }
        guard registeredWindowIds.count == 1 else { return nil }
        return registeredWindowIds.first
    }

    package func recordWindowRegistered(_ windowId: UUID) {
        registeredWindowIds.insert(windowId)
        if presentationFactsByWindowId[windowId] == nil {
            presentationFactsByWindowId[windowId] = .hidden
        }
    }

    package func presentationFacts(for windowId: UUID) -> WindowPresentationFacts? {
        presentationFactsByWindowId[windowId]
    }

    package func recordWindowPresentation(
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

    package func recordWindowBecameKey(_ windowId: UUID) {
        keyWindowId = windowId
        focusedWindowId = windowId
    }

    package func recordWindowResignedKey(_ windowId: UUID) {
        guard keyWindowId == windowId else { return }
        keyWindowId = nil
    }

    package func recordWindowBecameFocused(_ windowId: UUID) {
        focusedWindowId = windowId
    }

    package func recordWindowResignedFocused(_ windowId: UUID) {
        guard focusedWindowId == windowId else { return }
        focusedWindowId = nil
    }

    package func recordTerminalContainerBounds(_ bounds: CGRect) {
        guard !bounds.isEmpty else { return }
        terminalContainerBounds = bounds
        RestoreTrace.log(
            "WindowLifecycleAtom.recordTerminalContainerBounds bounds=\(NSStringFromRect(bounds)) settled=\(isLaunchLayoutSettled) ready=\(isReadyForLaunchRestore)"
        )
    }

    package func recordLaunchLayoutSettled() {
        isLaunchLayoutSettled = true
        RestoreTrace.log(
            "WindowLifecycleAtom.recordLaunchLayoutSettled bounds=\(NSStringFromRect(terminalContainerBounds)) settled=\(isLaunchLayoutSettled) ready=\(isReadyForLaunchRestore)"
        )
    }

    @discardableResult
    package func recordFirstInteractiveFramePublished(source: FirstInteractiveFrameSource) -> Bool {
        guard !didPublishFirstInteractiveFrame else { return false }
        didPublishFirstInteractiveFrame = true
        firstInteractiveFrameSource = source
        let waiters = firstInteractiveFrameWaiters
        firstInteractiveFrameWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        return true
    }

    package func waitUntilFirstInteractiveFramePublished() async {
        guard !didPublishFirstInteractiveFrame else { return }
        await withCheckedContinuation { continuation in
            firstInteractiveFrameWaiters.append(continuation)
        }
    }
}
