import AppKit
import SwiftUI

// MARK: - Pasteboard Type

extension NSPasteboard.PasteboardType {
    // Use a simple string identifier instead of UTType to avoid Info.plist requirement
    static let agentStudioTab = NSPasteboard.PasteboardType("com.agentstudio.tab.internal")
}

// MARK: - Draggable Tab Bar Container

/// Container view that wraps NSHostingView and handles drag-to-reorder for tabs.
/// Uses composition instead of subclassing to avoid NSHostingView's sealed NSDraggingSource methods.
class DraggableTabBarHostingView: NSView, NSDraggingSource {

    // MARK: - Properties

    private var hostingView: NSHostingView<CustomTabBar>!
    weak var tabBarState: TabBarState?
    var onReorder: ((_ fromId: UUID, _ toIndex: Int) -> Void)?

    /// Tab frames reported from SwiftUI, in SwiftUI coordinate space
    private var tabFrames: [UUID: CGRect] = [:]

    /// Currently dragging tab ID (for drag source tracking)
    private var draggingTabId: UUID?

    /// Track mouse down for drag detection
    private var mouseDownPoint: NSPoint?
    private var mouseDownTabId: UUID?
    private let minimumDragDistance: CGFloat = 5.0

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
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Register as drag destination
        registerForDraggedTypes([.agentStudioTab])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    func configure(state: TabBarState, onReorder: @escaping (UUID, Int) -> Void) {
        self.tabBarState = state
        self.onReorder = onReorder
    }

    func updateTabFrames(_ frames: [UUID: CGRect]) {
        tabFrames.merge(frames) { _, new in new }
    }

    /// Get current tab frames, preferring local cache but falling back to TabBarState
    private var currentTabFrames: [UUID: CGRect] {
        if !tabFrames.isEmpty {
            return tabFrames
        }
        // Fall back to TabBarState frames (set directly by SwiftUI)
        return tabBarState?.tabFrames ?? [:]
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
        guard let state = tabBarState, !state.tabs.isEmpty else { return nil }

        let swiftUIPoint = CGPoint(x: point.x, y: bounds.height - point.y)
        let frames = currentTabFrames

        // Sort tabs by their x position
        let sortedTabs = state.tabs.enumerated().compactMap { index, tab -> (index: Int, frame: CGRect)? in
            guard let frame = frames[tab.id] else { return nil }
            return (index, frame)
        }.sorted { $0.frame.minX < $1.frame.minX }

        // Find insertion point based on midpoint
        for item in sortedTabs {
            let midX = item.frame.midX
            if swiftUIPoint.x < midX {
                return item.index
            }
        }

        // Past the last tab
        return state.tabs.count
    }

    // MARK: - View Hit Testing

    /// Claim tab areas for drag handling. When we return `self`, we own the full
    /// mouse event sequence—forwarding to subviews causes infinite loops.
    /// See docs/architecture/app_architecture.md for details.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        let frames = currentTabFrames

        if !frames.isEmpty && tabAtPoint(localPoint) != nil {
            return self
        }
        return super.hitTest(point)
    }

    // MARK: - Mouse Events (Drag Initiation)

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Check if clicking on a tab - track for potential drag
        if let tabId = tabAtPoint(point) {
            mouseDownPoint = point
            mouseDownTabId = tabId
            // We handle this ourselves - DO NOT forward to hostingView (causes infinite loop)
            return
        }

        mouseDownPoint = nil
        mouseDownTabId = nil
        // If we get here, hitTest should have returned hostingView, not us
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Check if we should start a drag
        if let startPoint = mouseDownPoint,
           let tabId = mouseDownTabId,
           draggingTabId == nil {
            let distance = hypot(point.x - startPoint.x, point.y - startPoint.y)
            if distance >= minimumDragDistance {
                debugLog("[DraggableTabBar] Starting drag after \(String(format: "%.1f", distance))px movement")
                mouseDownPoint = nil
                mouseDownTabId = nil
                startDrag(tabId: tabId, at: point, event: event)
                return
            }
        }

        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        // If we were tracking a tab click (not a drag), select the tab now
        if let tabId = mouseDownTabId {
            // Find the tab and select it
            if let state = tabBarState,
               state.tabs.contains(where: { $0.id == tabId }) {
                state.activeTabId = tabId
                // Post notification for the controller to switch terminal
                NotificationCenter.default.post(
                    name: .selectTabById,
                    object: nil,
                    userInfo: ["tabId": tabId]
                )
            }
        }

        // Clear tracking state
        mouseDownPoint = nil
        mouseDownTabId = nil
        super.mouseUp(with: event)
    }

    // MARK: - Drag Initiation

    private func startDrag(tabId: UUID, at point: NSPoint, event: NSEvent) {
        draggingTabId = tabId

        // Update state to show drag visual immediately
        tabBarState?.draggingTabId = tabId

        // Create pasteboard item
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(tabId.uuidString, forType: .agentStudioTab)

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
        if let tab = tabBarState?.tabs.first(where: { $0.id == tabId }) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.white
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

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        // State already set in startDrag
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // Cleanup
        DispatchQueue.main.async { [weak self] in
            self?.tabBarState?.draggingTabId = nil
            self?.tabBarState?.dropTargetIndex = nil
            self?.draggingTabId = nil
        }
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.types?.contains(.agentStudioTab) == true else {
            return []
        }

        updateDropTarget(for: sender)
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDropTarget(for: sender)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        DispatchQueue.main.async { [weak self] in
            self?.tabBarState?.dropTargetIndex = nil
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let idString = sender.draggingPasteboard.string(forType: .agentStudioTab),
              let tabId = UUID(uuidString: idString),
              let targetIndex = tabBarState?.dropTargetIndex else {
            return false
        }

        // Execute reorder
        onReorder?(tabId, targetIndex)

        return true
    }

    private func updateDropTarget(for sender: NSDraggingInfo) {
        let point = convert(sender.draggingLocation, from: nil)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let index = self.dropIndexAtPoint(point) {
                // Don't highlight if dropping in same position
                if let draggingId = self.draggingTabId,
                   let currentIndex = self.tabBarState?.tabs.firstIndex(where: { $0.id == draggingId }),
                   (index == currentIndex || index == currentIndex + 1) {
                    self.tabBarState?.dropTargetIndex = nil
                } else {
                    self.tabBarState?.dropTargetIndex = index
                }
            } else {
                self.tabBarState?.dropTargetIndex = nil
            }
        }
    }
}
