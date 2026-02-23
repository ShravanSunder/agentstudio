import AppKit
import Observation
import os.log

private let shieldLogger = Logger(
    subsystem: "com.agentstudio", category: "DragShield"
)

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
/// ## Drag Policy
///
/// Uses an **allowlist** strategy via ``DragPolicy``:
/// - Drags containing any ``DragPolicy/allowedTypes`` pass through to SwiftUI
/// - All other drags are suppressed during management mode
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

    // MARK: - Drag Policy

    /// Defines which drag types are allowed through the shield and which are
    /// suppressed during management mode.
    ///
    /// Allowlist strategy: if a drag's pasteboard contains any ``allowedTypes``,
    /// the shield passes it through to SwiftUI `.onDrop`. All other drags are
    /// absorbed to prevent WKWebView from showing "Drop files to upload".
    ///
    /// To support a new custom drag type, add it to ``allowedTypes``.
    enum DragPolicy {
        /// Agent studio custom drag types that pass through the shield
        /// to SwiftUI `.onDrop` during management mode.
        static let allowedTypes: Set<NSPasteboard.PasteboardType> = [
            .agentStudioTabDrop,
            .agentStudioPaneDrop,
            .agentStudioNewTabDrop,
            .agentStudioTabInternal,
        ]

        /// File/media types actively suppressed during management mode.
        /// These are the types WKWebView registers for internally that trigger
        /// the "Drop files to upload" affordance.
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
        // Normal mode: transparent to all events.
        guard ManagementModeMonitor.shared.isActive else { return nil }

        // During management mode, check the drag pasteboard to decide participation.
        // Returning [] from draggingEntered does NOT cause AppKit to forward to
        // parent views — it just marks the location as "rejected." The only way to
        // let SwiftUI's .onDrop receive the drag is to return nil from hitTest so
        // AppKit skips the shield entirely and finds the hosting view.
        let pasteboardTypes = NSPasteboard(name: .drag).types ?? []
        let isAgentStudioDrag = pasteboardTypes.contains {
            DragPolicy.allowedTypes.contains($0)
        }
        if !pasteboardTypes.isEmpty {
            shieldLogger.debug(
                "[SHIELD-DIAG] hitTest: types=\(pasteboardTypes.map(\.rawValue)) agentStudio=\(isAgentStudioDrag)"
            )
        }
        return isAgentStudioDrag ? nil : self
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard ManagementModeMonitor.shared.isActive else { return [] }
        return dragOperation(for: sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard ManagementModeMonitor.shared.isActive else { return [] }
        return dragOperation(for: sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        // No visual state to clean up
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        // Absorb the drop — do nothing. File drops during management mode
        // are intentionally suppressed.
        false
    }

    // MARK: - Drag Type Resolution

    /// Returns the drag operation based on pasteboard contents.
    /// Allowed types pass through (return `[]` so AppKit forwards to SwiftUI).
    /// Everything else is suppressed (return `.generic` to claim the drag).
    private func dragOperation(for sender: any NSDraggingInfo) -> NSDragOperation {
        let pasteboardTypes = sender.draggingPasteboard.types ?? []
        let containsAllowedType = pasteboardTypes.contains { DragPolicy.allowedTypes.contains($0) }
        return containsAllowedType ? [] : .generic
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
            registerForDraggedTypes(DragPolicy.suppressedTypes)
        } else {
            unregisterDraggedTypes()
        }
    }
}
