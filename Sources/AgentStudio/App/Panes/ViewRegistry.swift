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
/// - `retireSlot(for:)`: tombstones the slot during close transitions so readers can finish
/// - `finalizeRetiredSlotRemoval(for:)`: deletes a tombstoned slot once no surface renders it
/// - `removeSlot(for:)`: deletes the slot immediately for non-transition removal
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

        var slotPaneIdsForTesting: Set<UUID> {
            Set(slots.keys)
        }
    #endif

    private var slots: [UUID: PaneViewSlot] = [:]
    private var retiredPaneIds: Set<UUID> = []
    private var renderedIdsBySurface: [String: Set<UUID>] = [:]
    private(set) var isInitialRestorePending = false

    /// Mark the launch window where restored pane slots may exist before hosts are recreated.
    ///
    /// Startup seeds slots before SwiftUI tab hosts render, then mounts hosts later once
    /// the terminal container has reliable bounds. A nil host is expected during that window.
    func beginInitialRestore() {
        isInitialRestorePending = true
    }

    /// Mark that launch restore has either completed or found no panes to restore.
    func completeInitialRestore() {
        isInitialRestorePending = false
    }

    /// Create the slot proactively when a pane enters workspace structure.
    /// Called by PaneCoordinator before any SwiftUI body can read the slot.
    /// Idempotent — safe to call multiple times for the same paneId.
    @discardableResult
    func ensureSlot(for paneId: UUID) -> PaneViewSlot {
        if let existing = slots[paneId] {
            retiredPaneIds.remove(paneId)
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

    /// Tombstone a slot for close transitions. The slot remains readable while
    /// any registered render surface still reports the pane ID; otherwise it is
    /// finalized immediately.
    func retireSlot(for paneId: UUID) {
        guard let slot = slots[paneId] else { return }

        slot.host = nil
        retiredPaneIds.insert(paneId)
        finalizeRetiredSlotsNotRenderedByAnySurface()
    }

    /// True when the slot is tombstoned for a close/removal transition and must
    /// remain readable until every registered surface stops rendering the pane id.
    func isRetired(for paneId: UUID) -> Bool {
        retiredPaneIds.contains(paneId)
    }

    /// Delete a tombstoned slot once its close transition is fully absent from rendered surfaces.
    func finalizeRetiredSlotRemoval(for paneId: UUID) {
        guard retiredPaneIds.remove(paneId) != nil else { return }
        slots.removeValue(forKey: paneId)
    }

    /// Remove the slot entirely for non-transition removal paths.
    func removeSlot(for paneId: UUID) {
        retiredPaneIds.remove(paneId)
        slots.removeValue(forKey: paneId)
    }

    /// Report the complete set of pane IDs currently rendered by a stable surface.
    func surfaceRenderedIds(_ surfaceId: String, ids: Set<UUID>) {
        renderedIdsBySurface[surfaceId] = ids
        finalizeRetiredSlotsNotRenderedByAnySurface()
    }

    /// Remove a surface from the rendered-union projection.
    func unregisterSurface(_ surfaceId: String) {
        renderedIdsBySurface.removeValue(forKey: surfaceId)
        finalizeRetiredSlotsNotRenderedByAnySurface()
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

    #if DEBUG
        func peekSlotForTesting(_ paneId: UUID) -> PaneViewSlot? {
            slots[paneId]
        }

        func isRetiredForTesting(_ paneId: UUID) -> Bool {
            isRetired(for: paneId)
        }
    #endif

    private func finalizeRetiredSlotsNotRenderedByAnySurface() {
        guard !retiredPaneIds.isEmpty else { return }

        let renderedPaneIds = renderedIdsBySurface.values.reduce(into: Set<UUID>()) { union, ids in
            union.formUnion(ids)
        }
        let removablePaneIds = retiredPaneIds.subtracting(renderedPaneIds)
        for paneId in removablePaneIds {
            finalizeRetiredSlotRemoval(for: paneId)
        }
    }
}
