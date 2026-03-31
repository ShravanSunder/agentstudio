import AppKit
import Observation
import os.log

private let viewRegistryLogger = Logger(subsystem: "com.agentstudio", category: "ViewRegistry")

/// Maps pane IDs to live PaneHostView instances via per-pane observable slots.
/// Runtime only — not persisted. Collaborator of WorkspaceStore.
///
/// ## Observation contract
///
/// Each pane gets its own `@Observable PaneViewSlot`. SwiftUI views read
/// `slot(for: paneId).host` to get automatic, scoped invalidation when
/// `register()` fires. Imperative callers (PaneCoordinator, PaneTabViewController)
/// use `view(for:)` which does a plain lookup with no observation overhead.
///
/// ## Slot lifecycle
///
/// - `ensureSlot(for:)`: creates a slot proactively when a pane enters workspace structure
/// - `register(_, for:)`: sets `slot.host` — auto-invalidates SwiftUI observers
/// - `unregister(_)`: clears `slot.host = nil` — slot object survives with stable identity
/// - `removeSlot(for:)`: deletes the slot when the pane is permanently removed
///
/// Slots have pane-lifetime identity, not host-lifetime identity. This ensures
/// SwiftUI observers survive across unregister/re-register cycles (repair, undo).
@MainActor
final class ViewRegistry {
    /// Per-pane observable slot. SwiftUI views read `slot(for:).host`
    /// to get automatic, scoped invalidation when `register()` fires.
    @Observable
    final class PaneViewSlot {
        fileprivate(set) var host: PaneHostView?
    }

    #if DEBUG
        static var suppressLazyFallbackAssertionForTesting = false
    #endif

    private var slots: [UUID: PaneViewSlot] = [:]

    /// Create the slot proactively when a pane enters workspace structure.
    /// Called by PaneCoordinator before any SwiftUI body can read the slot.
    /// Idempotent — safe to call multiple times for the same paneId.
    @discardableResult
    func ensureSlot(for paneId: UUID) -> PaneViewSlot {
        if let existing = slots[paneId] {
            return existing
        }

        let newSlot = PaneViewSlot()
        slots[paneId] = newSlot
        return newSlot
    }

    /// Get the observable slot for a pane.
    /// SwiftUI views read `slot(for: paneId).host` to get per-pane observation.
    /// Falls back to lazy creation with a warning if `ensureSlot` was not called.
    func slot(for paneId: UUID) -> PaneViewSlot {
        if let existing = slots[paneId] {
            return existing
        }

        // Safety net: slot should have been created proactively via ensureSlot().
        // If we get here, the pane creation path missed the ensureSlot call.
        let message = "ViewRegistry.slot(for:) lazy fallback paneId=\(paneId) — ensureSlot was not called"
        #if DEBUG
            if !Self.suppressLazyFallbackAssertionForTesting {
                assertionFailure(message)
            }
        #endif
        viewRegistryLogger.error(
            "ViewRegistry.slot(for:) lazy fallback paneId=\(paneId.uuidString, privacy: .public) — ensureSlot was not called"
        )
        RestoreTrace.log(
            message
        )
        let newSlot = PaneViewSlot()
        slots[paneId] = newSlot
        return newSlot
    }

    /// Register a view for a pane. Automatically invalidates only
    /// SwiftUI views observing this pane's slot.
    func register(_ view: PaneHostView, for paneId: UUID) {
        ensureSlot(for: paneId).host = view
    }

    /// Unregister a view for a pane. Clears host but preserves slot identity
    /// so SwiftUI observers survive across unregister/re-register cycles.
    func unregister(_ paneId: UUID) {
        slots[paneId]?.host = nil
    }

    /// Remove the slot entirely when a pane is permanently removed from workspace structure.
    func removeSlot(for paneId: UUID) {
        slots.removeValue(forKey: paneId)
    }

    /// Get the view for a pane, if registered.
    /// Imperative callers use this — no observation tracking.
    func view(for paneId: UUID) -> PaneHostView? {
        slots[paneId]?.host
    }

    /// Get the terminal view for a pane, if it is a terminal.
    func terminalView(for paneId: UUID) -> TerminalPaneMountView? {
        guard let view = slots[paneId]?.host else { return nil }
        return view.mountedContent(as: TerminalPaneMountView.self)
    }

    /// Get the terminal status placeholder view for a pane, if it is present.
    func terminalStatusPlaceholderView(for paneId: UUID) -> TerminalStatusPlaceholderView? {
        guard let view = slots[paneId]?.host else { return nil }
        return view.mountedContent(as: TerminalPaneMountView.self)?.currentPlaceholderView
    }

    /// Get the webview for a pane, if it is a webview.
    func webviewView(for paneId: UUID) -> WebviewPaneMountView? {
        guard let view = slots[paneId]?.host else { return nil }
        return view.mountedContent(as: WebviewPaneMountView.self)
    }

    /// All registered webview pane views, keyed by pane ID.
    var allWebviewViews: [UUID: WebviewPaneMountView] {
        slots.compactMapValues { slot in
            slot.host?.mountedContent(as: WebviewPaneMountView.self)
        }
    }

    /// All registered terminal pane views, keyed by pane ID.
    var allTerminalViews: [UUID: TerminalPaneMountView] {
        slots.compactMapValues { slot in
            slot.host?.mountedContent(as: TerminalPaneMountView.self)
        }
    }

    /// All currently registered pane IDs.
    var registeredPaneIds: Set<UUID> {
        Set(slots.compactMap { $0.value.host != nil ? $0.key : nil })
    }
}
