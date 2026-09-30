import AgentStudioCore
import Foundation

/// `package` (not `private`), matching `GhosttyTerminalActivityInputBinding`'s
/// own reasoning: a dedicated test suite constructs a fresh instance to
/// prove the routing mechanic in isolation, without touching the shared
/// global singleton below.
///
/// SR5; Program Design item 3, "the surface's command exits before
/// handoff, including while discovering": Ghostty's `showChildExited`
/// action is the one event-driven fact present whether the attach client
/// dies during discovery or after (`GhosttyActionRouter+StartupTracing
/// .swift`'s `scheduleChildExitedStartupTrace` already resolves the pane
/// for its own trace call; this binding is fed through that same
/// resolution, not a second lookup).
@MainActor
package final class ColdStartAttachExitBinding {
    private var observersByPaneID: [UUID: ColdStartObserver] = [:]

    package init() {}

    /// Registered when a cold pane's startup window begins (alongside
    /// arming its restore phase), before the surface that runs the attach
    /// command is created — a `showChildExited` that races registration
    /// would otherwise be missed.
    package func register(paneID: UUID, observer: ColdStartObserver) {
        observersByPaneID[paneID] = observer
    }

    /// Unregistered once the window settles or the pane is torn down, so a
    /// later, unrelated pane reusing the same slot never reaches a stale
    /// observer.
    package func unregister(paneID: UUID) {
        observersByPaneID.removeValue(forKey: paneID)
    }

    package func reportAttachClientExited(paneID: UUID) {
        guard let observer = observersByPaneID[paneID] else { return }
        Task { await observer.reportAttachClientExited() }
    }
}

@MainActor private let coldStartAttachExitBinding = ColdStartAttachExitBinding()

extension Ghostty.ActionRouter {
    @MainActor
    package static func registerColdStartAttachExitObserver(paneID: UUID, observer: ColdStartObserver) {
        coldStartAttachExitBinding.register(paneID: paneID, observer: observer)
    }

    @MainActor
    package static func unregisterColdStartAttachExitObserver(paneID: UUID) {
        coldStartAttachExitBinding.unregister(paneID: paneID)
    }

    @MainActor
    static func reportColdStartAttachClientExited(paneID: UUID) {
        coldStartAttachExitBinding.reportAttachClientExited(paneID: paneID)
    }
}
