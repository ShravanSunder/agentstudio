import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Draggable Tab Bar Container

/// Container view that wraps NSHostingView and handles drag-to-reorder for tabs.
/// Uses NSPanGestureRecognizer to detect drags while letting SwiftUI handle all other
/// interactions (clicks, close buttons, right-clicks, hover).
class DraggableTabBarHostingView: NSView, NSDraggingSource {

    // MARK: - Properties

    private var hostingView: NSHostingView<CustomTabBar>!
    weak var tabBarAdapter: TabBarAdapter?
    var onReorder: ((_ fromId: UUID, _ toIndex: Int) -> Void)?
    /// Called when a tab is clicked (mouse down + up without drag) during management mode.
    /// The pan gesture recognizer consumes mouse events, preventing SwiftUI's
    /// onTapGesture from firing. This callback forwards the click as a selection.
    var onSelect: ((_ tabId: UUID) -> Void)?
    /// Provides drag payload data (worktreeId, repoId, title) for a tab ID.
    /// Injected by the view controller to decouple from WorkspaceStore.
    var dragPayloadProvider: ((_ tabId: UUID) -> TabDragPayload?)?
    /// Planner-backed preview gate for pane drops onto the tab bar insertion row.
    /// When set, preview visibility must come from shared planner semantics.
    var canPreviewPaneDropAtIndex: ((_ payload: PaneDragPayload, _ targetTabIndex: Int) -> Bool)?
    /// Planner-backed commit hook for pane drops onto the tab bar insertion row.
    /// Returns true only when the drop was accepted and executed.
    var commitPaneDropAtIndex: ((_ payload: PaneDragPayload, _ targetTabIndex: Int) -> Bool)?

    /// Tab frames reported from SwiftUI, in SwiftUI coordinate space
    private var tabFrames: [UUID: CGRect] = [:]

    /// Currently dragging tab ID (for drag source tracking)
    private var draggingTabId: UUID?

    /// Pan gesture recognizer for drag detection
    private var panGesture: NSPanGestureRecognizer!

    /// Track the tab being dragged and the original event for drag session
    private var panStartTabId: UUID?
    private var panStartEvent: NSEvent?
    private var lastAutoSelectedTabIdForPaneDrag: UUID?

    private var managementModeObservation: Task<Void, Never>?

    isolated deinit {
        managementModeObservation?.cancel()
    }

    // MARK: - Initialization

    init(rootView: CustomTabBar) {
        super.init(frame: .zero)

        hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.sizingOptions = [.preferredContentSize]
        hostingView.safeAreaRegions = []
        addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Register as drag destination for internal reorder, tab drop, and pane drop
        registerForDraggedTypes([.agentStudioTabInternal, .agentStudioTabDrop, .agentStudioPaneDrop])

        // Set up pan gesture recognizer for drag detection.
        // Disabled by default — only enabled when management mode (Cmd+Opt) is active.
        // This prevents the recognizer from interfering with SwiftUI's onTapGesture
        // on tab pills, which was causing intermittent missed clicks.
        panGesture = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delaysPrimaryMouseButtonEvents = false
        panGesture.isEnabled = ManagementModeMonitor.shared.isActive
        addGestureRecognizer(panGesture)
        observeManagementMode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func observeManagementMode() {
        managementModeObservation?.cancel()
        managementModeObservation = Task { @MainActor [weak self] in
            withObservationTracking {
                _ = ManagementModeMonitor.shared.isActive
            } onChange: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.updateManagementModeState()
                    self?.observeManagementMode()
                }
            }
        }
        updateManagementModeState()
    }

    private func updateManagementModeState() {
        panGesture.isEnabled = ManagementModeMonitor.shared.isActive
        if !ManagementModeMonitor.shared.isActive {
            // Clean up any in-flight drag state when leaving management mode
            panStartTabId = nil
            panStartEvent = nil
            if draggingTabId != nil {
                draggingTabId = nil
                tabBarAdapter?.draggingTabId = nil
                tabBarAdapter?.dropTargetIndex = nil
            }
        }
    }

    // MARK: - Setup

    func configure(adapter: TabBarAdapter, onReorder: @escaping (UUID, Int) -> Void) {
        self.tabBarAdapter = adapter
        self.onReorder = onReorder
    }

    func updateTabFrames(_ frames: [UUID: CGRect]) {
        tabFrames.merge(frames) { _, new in new }
    }

    /// Get current tab frames, preferring local cache but falling back to TabBarAdapter
    private var currentTabFrames: [UUID: CGRect] {
        if !tabFrames.isEmpty {
            return tabFrames
        }
        // Fall back to TabBarAdapter frames (set directly by SwiftUI)
        return tabBarAdapter?.tabFrames ?? [:]
    }

    // MARK: - Hit Testing

    /// Find which tab is at the given point (in NSView coordinates)
    private func tabAtPoint(_ point: NSPoint) -> UUID? {
        // Convert to SwiftUI coordinate space (flipped Y)
        let swiftUIPoint = CGPoint(x: point.x, y: bounds.height - point.y)

        let frames = currentTabFrames

        for (tabId, frame) in frames {
            if frame.contains(swiftUIPoint) {
                return tabId
            }
        }
        return nil
    }

    /// Find the insertion index for a drop at the given point
    private func dropIndexAtPoint(_ point: NSPoint) -> Int? {
        guard let adapter = tabBarAdapter, !adapter.tabs.isEmpty else { return nil }
        let orderedTabIds = adapter.tabs.map(\.id)
        return Self.paneDropInsertionIndex(
            dropPoint: point,
            boundsHeight: bounds.height,
            tabFrames: currentTabFrames,
            orderedTabIds: orderedTabIds
        )
    }

    /// Shared insertion-index resolver used by tab-bar drag preview and drop commit.
    /// Returning nil means the pointer is outside the tab row and no insertion marker
    /// should be shown.
    nonisolated static func paneDropInsertionIndex(
        dropPoint: NSPoint,
        boundsHeight: CGFloat,
        tabFrames: [UUID: CGRect],
        orderedTabIds: [UUID]
    ) -> Int? {
        guard !orderedTabIds.isEmpty else { return nil }

        let swiftUIPoint = CGPoint(x: dropPoint.x, y: boundsHeight - dropPoint.y)
        let sortedTabs = orderedTabIds.enumerated().compactMap { index, tabId -> (index: Int, frame: CGRect)? in
            guard let frame = tabFrames[tabId] else { return nil }
            return (index: index, frame: frame)
        }.sorted { $0.frame.minX < $1.frame.minX }
        guard !sortedTabs.isEmpty else { return nil }

        let verticalMinY = sortedTabs.map(\.frame.minY).min() ?? 0
        let verticalMaxY = sortedTabs.map(\.frame.maxY).max() ?? 0
        guard swiftUIPoint.y >= verticalMinY, swiftUIPoint.y <= verticalMaxY else {
            return nil
        }

        // Find insertion point based on midpoint
        for item in sortedTabs {
            let midX = item.frame.midX
            if swiftUIPoint.x < midX {
                return item.index
            }
        }

        // Past the last tab
        return orderedTabIds.count
    }

    private func clearDropTargetIndicator() {
        tabBarAdapter?.dropTargetIndex = nil
        lastAutoSelectedTabIdForPaneDrag = nil
    }

    // MARK: - Pan Gesture Handler

    @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
        // No runtime guard needed — pan gesture is controlled via isEnabled toggle.
        // This avoids consuming mouse events and interfering with SwiftUI's onTapGesture.
        let location = gesture.location(in: self)

        switch gesture.state {
        case .began:
            // Check if pan started on a tab
            if let tabId = tabAtPoint(location) {
                panStartTabId = tabId
                panStartEvent = NSApp.currentEvent
            }

        case .changed:
            // Start drag session once we have enough movement
            if let tabId = panStartTabId, draggingTabId == nil {
                guard let event = panStartEvent ?? NSApp.currentEvent else {
                    panStartTabId = nil
                    panStartEvent = nil
                    return
                }
                startDrag(tabId: tabId, at: location, event: event)
                panStartTabId = nil
                panStartEvent = nil
            }

        case .ended, .cancelled:
            // If pan ended with no drag started, this was a click — forward as tab selection.
            // The pan gesture consumes the mouse-down, preventing SwiftUI's onTapGesture.
            if let tabId = panStartTabId, draggingTabId == nil {
                onSelect?(tabId)
            }
            panStartTabId = nil
            panStartEvent = nil

        default:
            break
        }
    }

    // MARK: - Drag Initiation

    private func startDrag(tabId: UUID, at point: NSPoint, event: NSEvent) {
        draggingTabId = tabId

        // Update adapter to show drag visual immediately
        tabBarAdapter?.draggingTabId = tabId

        // Create pasteboard item with both formats
        let pasteboardItem = NSPasteboardItem()

        // Internal format for tab bar reordering
        pasteboardItem.setString(tabId.uuidString, forType: .agentStudioTabInternal)

        // SwiftUI-compatible format for terminal split drops
        if let payload = dragPayloadProvider?(tabId) {
            if let payloadData = try? JSONEncoder().encode(payload) {
                pasteboardItem.setData(payloadData, forType: .agentStudioTabDrop)
            }
        }

        // Create dragging item
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)

        // Set drag image
        if let frame = currentTabFrames[tabId] {
            let nsFrame = NSRect(
                x: frame.minX,
                y: bounds.height - frame.maxY,  // Flip Y back to NSView
                width: frame.width,
                height: frame.height
            )
            let image = createDragImage(for: tabId, frame: nsFrame)
            draggingItem.setDraggingFrame(nsFrame, contents: image)
        }

        // Start drag session
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func createDragImage(for tabId: UUID, frame: NSRect) -> NSImage {
        let image = NSImage(size: frame.size)
        image.lockFocus()

        // Draw pill background
        let pillRect = NSRect(origin: .zero, size: frame.size)
        let path = NSBezierPath(roundedRect: pillRect, xRadius: 8, yRadius: 8)
        NSColor.white.withAlphaComponent(0.15).setFill()
        path.fill()

        // Draw border
        NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 1.5
        path.stroke()

        // Draw tab title
        if let tab = tabBarAdapter?.tabs.first(where: { $0.id == tabId }) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.white,
            ]
            let title = tab.title as NSString
            let titleSize = title.size(withAttributes: attrs)
            let titlePoint = NSPoint(
                x: (frame.width - titleSize.width) / 2,
                y: (frame.height - titleSize.height) / 2
            )
            title.draw(at: titlePoint, withAttributes: attrs)
        }

        image.unlockFocus()
        return image
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation
    {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        // State already set in startDrag
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // Cleanup
        Task { @MainActor [weak self] in
            self?.tabBarAdapter?.draggingTabId = nil
            self?.tabBarAdapter?.dropTargetIndex = nil
            self?.draggingTabId = nil
        }
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let types = sender.draggingPasteboard.types ?? []
        guard types.contains(.agentStudioTabInternal) || types.contains(.agentStudioPaneDrop) else {
            return []
        }

        let dropPoint = convert(sender.draggingLocation, from: nil)
        if types.contains(.agentStudioPaneDrop),
            !paneDropIsAllowedInTabBar(sender.draggingPasteboard, at: dropPoint)
        {
            clearDropTargetIndicator()
            return []
        }

        // Reject drags when management mode exited mid-drag.
        // Pane drags start only from management mode affordances.
        if (types.contains(.agentStudioTabInternal) || types.contains(.agentStudioPaneDrop))
            && !ManagementModeMonitor.shared.isActive
        {
            return []
        }

        updateDropTarget(for: sender)
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let types = sender.draggingPasteboard.types ?? []

        let dropPoint = convert(sender.draggingLocation, from: nil)
        if types.contains(.agentStudioPaneDrop),
            !paneDropIsAllowedInTabBar(sender.draggingPasteboard, at: dropPoint)
        {
            clearDropTargetIndicator()
            return []
        }

        // Reject drags when management mode exited mid-drag
        if (types.contains(.agentStudioTabInternal) || types.contains(.agentStudioPaneDrop))
            && !ManagementModeMonitor.shared.isActive
        {
            Task { @MainActor [weak self] in
                self?.tabBarAdapter?.dropTargetIndex = nil
            }
            return []
        }

        if types.contains(.agentStudioPaneDrop) {
            if let hoveredTabId = tabAtPoint(dropPoint),
                hoveredTabId != lastAutoSelectedTabIdForPaneDrag
            {
                lastAutoSelectedTabIdForPaneDrag = hoveredTabId
                onSelect?(hoveredTabId)
            }
        }

        updateDropTarget(for: sender)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        clearDropTargetIndicator()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { clearDropTargetIndicator() }
        let pasteboard = sender.draggingPasteboard

        // Handle internal tab reorder (only when management mode is still active)
        if let idString = pasteboard.string(forType: .agentStudioTabInternal),
            let tabId = UUID(uuidString: idString),
            let targetIndex = tabBarAdapter?.dropTargetIndex,
            ManagementModeMonitor.shared.isActive
        {
            onReorder?(tabId, targetIndex)
            return true
        }

        // Handle pane drop:
        // - Always use insertion index semantics on the tab row
        // - Create/move to a new tab at the insertion target
        if let paneData = pasteboard.data(forType: .agentStudioPaneDrop),
            let payload = try? JSONDecoder().decode(PaneDragPayload.self, from: paneData)
        {
            let dropPoint = convert(sender.draggingLocation, from: nil)
            let targetTabIndex = dropIndexAtPoint(dropPoint)
            guard let targetTabIndex else {
                return false
            }

            // Planner-backed path when the controller provides hooks.
            if let commitPaneDropAtIndex {
                return commitPaneDropAtIndex(payload, targetTabIndex)
            }

            // Backwards-compatible fallback for call sites that have not yet
            // migrated to planner-backed callbacks.
            if !Self.allowsTabBarInsertion(for: payload) {
                return false
            }
            postAppEvent(
                .extractPaneRequested(
                    tabId: payload.tabId,
                    paneId: payload.paneId,
                    targetTabIndex: targetTabIndex
                )
            )
            return true
        }

        return false
    }

    private func paneDropIsAllowedInTabBar(_ pasteboard: NSPasteboard, at dropPoint: NSPoint) -> Bool {
        guard let paneData = pasteboard.data(forType: .agentStudioPaneDrop),
            let payload = try? JSONDecoder().decode(PaneDragPayload.self, from: paneData)
        else {
            return false
        }

        guard let targetTabIndex = dropIndexAtPoint(dropPoint) else {
            return false
        }

        if let canPreviewPaneDropAtIndex {
            return canPreviewPaneDropAtIndex(payload, targetTabIndex)
        }

        return Self.allowsTabBarInsertion(for: payload)
    }

    nonisolated static func allowsTabBarInsertion(for payload: PaneDragPayload) -> Bool {
        // Drawer child panes are constrained to their parent drawer and cannot
        // be moved into top-level tabs.
        payload.drawerParentPaneId == nil
    }

    private func updateDropTarget(for sender: NSDraggingInfo) {
        let point = convert(sender.draggingLocation, from: nil)
        if let index = dropIndexAtPoint(point) {
            // Don't highlight if dropping in same position.
            if let draggingId = draggingTabId,
                let currentIndex = tabBarAdapter?.tabs.firstIndex(where: { $0.id == draggingId }),
                index == currentIndex || index == currentIndex + 1
            {
                tabBarAdapter?.dropTargetIndex = nil
            } else {
                tabBarAdapter?.dropTargetIndex = index
            }
        } else {
            tabBarAdapter?.dropTargetIndex = nil
        }
    }
}
