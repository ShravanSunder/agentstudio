import AppKit

/// Transparent overlay that suppresses file/media drag types during management mode,
/// preventing WKWebView-backed panes from showing "Drop files to upload."
///
/// Placed as the topmost subview of ``PaneView`` (above WKWebView / Ghostty content).
///
/// ## Architecture: single-owner-per-drag-type
///
/// - **Shield owns** file/media suppression: `.fileURL`, `.URL`, `.tiff`, `.png`, `.string`, `.html`.
/// - **Parent `.onDrop` owns** agent studio custom types: tab/pane/newTab drops.
/// - Type sets are **disjoint** — no collision, no interception conflict.
///
/// ## hitTest behavior
///
/// Always returns `nil` — transparent to mouse events (clicks, hover).
/// ``PaneView/hitTest(_:)`` handles click blocking by returning `nil` during management mode.
/// NSDraggingDestination routing is **frame-based** (independent of hitTest), so the shield
/// still receives drag callbacks for its registered types.
///
/// ## Dynamic registration
///
/// Registers/unregisters file/media drag types when management mode toggles
/// via typed `AppEventBus` events from ``ManagementModeMonitor``.
/// Also notifies the parent ``PaneView`` to apply content-level interaction changes
/// (e.g., CSS `pointer-events: none` for WKWebView).
@MainActor
final class ManagementModeDragShield: NSView {

    // MARK: - Drag Policy

    /// Drag type classification for the shield.
    ///
    /// **Allowlist strategy:** agent studio custom types pass through to SwiftUI
    /// `.onDrop`. All other types are suppressed during management mode.
    ///
    /// To support a new custom drag type, add it to ``allowedTypes``.
    enum DragPolicy {
        /// Agent studio custom drag types that must pass through the shield.
        static let allowedTypes: Set<NSPasteboard.PasteboardType> = [
            .agentStudioTabDrop,
            .agentStudioPaneDrop,
            .agentStudioNewTabDrop,
            .agentStudioTabInternal,
        ]

        /// File/media types suppressed during management mode.
        /// These are the narrow types WKWebView registers for internally.
        ///
        /// **Critical:** Do NOT add supertypes like `public.data` or `public.content` —
        /// they match agent studio CodableRepresentation payloads and would intercept
        /// pane/tab drags, breaking SwiftUI's `.onDrop` on the parent hosting view.
        static let suppressedTypes: [NSPasteboard.PasteboardType] = [
            .fileURL,
            .URL,
            .tiff,
            .png,
            .string,
            .html,
        ]
    }

    private var managementModeTask: Task<Void, Never>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        subscribeToManagementModeEvents()
        updateRegistration()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    isolated deinit {
        managementModeTask?.cancel()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        // Ensure parent pane receives the current interaction state when the shield
        // is first attached. Without this, panes created while management mode is
        // already active could miss content interaction suppression.
        updateRegistration()
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Always transparent to mouse events.
        // The shield participates in drag routing via NSDraggingDestination
        // (bounds-based, independent of hitTest), not via hitTest.
        // PaneView.hitTest returning nil handles click blocking.
        nil
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard ManagementModeMonitor.shared.isActive else { return [] }
        // Accept the drag to prevent WKWebView from seeing it.
        return .generic
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard ManagementModeMonitor.shared.isActive else { return [] }
        return .generic
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        // No visual state to clean up
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        // Absorb the drop — do nothing.
        false
    }

    // MARK: - Management Mode Events

    private func subscribeToManagementModeEvents() {
        managementModeTask?.cancel()
        managementModeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = await AppEventBus.shared.subscribe()
            for await event in stream {
                if Task.isCancelled { break }
                guard case .managementModeChanged = event else { continue }
                self.updateRegistration()
            }
        }
    }

    /// Dynamically register/unregister drag types based on management mode.
    /// Also notifies the parent PaneView to apply content-level interaction changes.
    private func updateRegistration() {
        let isActive = ManagementModeMonitor.shared.isActive
        if isActive {
            registerForDraggedTypes(DragPolicy.suppressedTypes)
        } else {
            unregisterDraggedTypes()
        }
        // Notify parent PaneView for content-level interaction suppression
        // (e.g., WKWebView pointer-events:none, Ghostty mouse tracking).
        (superview as? PaneView)?.setContentInteractionEnabled(!isActive)
    }
}
