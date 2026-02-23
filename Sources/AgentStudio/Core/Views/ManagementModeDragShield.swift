import AppKit
import Observation

/// Transparent overlay that blocks all pane interaction during management mode.
///
/// Placed as the topmost subview of ``PaneView`` (above WKWebView / Ghostty content).
///
/// ## During management mode
///
/// - ``hitTest(_:)`` returns `self` — intercepts all mouse events (clicks, hover).
/// - Registered for file/media drag types via ``DragPolicy/suppressedTypes`` —
///   absorbs them before WKWebView can show "Drop files to upload."
/// - **Not** registered for agent studio custom types — those propagate up to
///   the outer ``NSHostingView``'s SwiftUI `.onDrop` (blue drop zone overlay).
///
/// ## During normal mode
///
/// - ``hitTest(_:)`` returns `nil` — transparent to all events.
/// - No drag types registered — WKWebView receives legitimate file drops normally.
///
/// ## Dynamic registration
///
/// Registers/unregisters file/media drag types when management mode toggles,
/// using `withObservationTracking` on ``ManagementModeMonitor/isActive``.
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
        /// These are the types WKWebView registers for internally.
        static let suppressedTypes: [NSPasteboard.PasteboardType] = [
            .fileURL,
            .URL,
            .tiff,
            .png,
            .string,
            .html,
            NSPasteboard.PasteboardType("public.data"),
            NSPasteboard.PasteboardType("public.content"),
        ]
    }

    private var observationTask: Task<Void, Never>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        observeManagementMode()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Always transparent to mouse events.
        // The shield participates in drag routing via NSDraggingDestination
        // (bounds-based, independent of hitTest), not via hitTest.
        // PaneView.hitTest returning nil handles click blocking.
        return nil
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

    // MARK: - Management Mode Observation

    private func observeManagementMode() {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self] in
            withObservationTracking {
                _ = ManagementModeMonitor.shared.isActive
            } onChange: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.updateRegistration()
                    self?.observeManagementMode()
                }
            }
        }
        updateRegistration()
    }

    /// Dynamically register/unregister drag types based on management mode.
    private func updateRegistration() {
        if ManagementModeMonitor.shared.isActive {
            registerForDraggedTypes(DragPolicy.suppressedTypes)
        } else {
            unregisterDraggedTypes()
        }
    }
}
