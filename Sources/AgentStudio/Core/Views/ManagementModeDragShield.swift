import AppKit
import Observation

/// Transparent overlay that suppresses standard file/media drag types during
/// management mode, preventing WKWebView-backed panes from showing
/// "Drop files to upload" when panes/tabs are dragged over them.
///
/// ## Architecture
///
/// Follows the **single-owner-per-drag-type** principle:
/// - This shield owns file/media types (suppression targets)
/// - Parent SwiftUI `.onDrop` owns agent studio custom types (tab/pane drops)
/// - Type sets are disjoint — no collision, no interception conflict
///
/// ## Placement
///
/// Added as the topmost subview of `PaneView.swiftUIContainer`.
///
/// ## hitTest behavior
///
/// - **Management mode ON:** returns `self` — participates in drag routing,
///   blocks file/media drags from reaching WKWebView beneath.
/// - **Management mode OFF:** returns `nil` — transparent to all events,
///   WKWebView can receive legitimate file drops normally.
///
/// ## Dynamic registration
///
/// Registers for file/media drag types when management mode activates,
/// unregisters when it deactivates. Uses `withObservationTracking` on
/// `ManagementModeMonitor.shared.isActive` (same pattern as
/// `DraggableTabBarHostingView` and `TabBarAdapter`).
@MainActor
final class ManagementModeDragShield: NSView {

    /// File/media types to suppress during management mode.
    /// These are the types WKWebView registers for internally that trigger
    /// the "Drop files to upload" affordance. Agent studio custom types
    /// (`.agentStudioTab`, `.agentStudioPane`, etc.) are intentionally
    /// excluded — the parent `.onDrop` handles those.
    private static let suppressionTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        .tiff,
        .png,
        .string,
        .html,
        NSPasteboard.PasteboardType("public.data"),
        NSPasteboard.PasteboardType("public.content"),
    ]

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
        // During management mode: return self so we participate in drag routing.
        // During normal mode: return nil so we're transparent to all events.
        ManagementModeMonitor.shared.isActive ? self : nil
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard ManagementModeMonitor.shared.isActive else { return [] }
        // Accept the drag to prevent WKWebView from seeing it.
        // Return .generic rather than .move to avoid implying the drop will do something.
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
        // Absorb the drop — do nothing. File drops during management mode
        // are intentionally suppressed.
        false
    }

    // MARK: - Management Mode Observation

    /// Observes ManagementModeMonitor.shared.isActive using the same
    /// recursive withObservationTracking pattern as DraggableTabBarHostingView
    /// and TabBarAdapter.
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
            registerForDraggedTypes(Self.suppressionTypes)
        } else {
            unregisterDraggedTypes()
        }
    }
}
