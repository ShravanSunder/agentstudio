import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Pasteboard Type

extension NSPasteboard.PasteboardType {
    // Internal tab reordering within tab bar
    static let agentStudioTabInternal = NSPasteboard.PasteboardType("com.agentstudio.tab.internal")

    // For SwiftUI drop compatibility (matches UTType.agentStudioTab)
    static let agentStudioTabDrop = NSPasteboard.PasteboardType(UTType.agentStudioTab.identifier)

    // For pane drag-to-tab-bar (extract pane to new tab)
    static let agentStudioPaneDrop = NSPasteboard.PasteboardType(UTType.agentStudioPane.identifier)
}

// MARK: - Draggable Tab Bar Container

/// Container view that wraps NSHostingView and handles drag-to-reorder for tabs.
/// Uses NSPanGestureRecognizer to detect drags while letting SwiftUI handle all other
/// interactions (clicks, close buttons, right-clicks, hover).
class DraggableTabBarHostingView: NSView, NSDraggingSource {

    // MARK: - Properties

    private var hostingView: NSHostingView<CustomTabBar>!
    weak var tabBarState: TabBarState?
    var onReorder: ((_ fromId: UUID, _ toIndex: Int) -> Void)?

    /// Tab frames reported from SwiftUI, in SwiftUI coordinate space
    private var tabFrames: [UUID: CGRect] = [:]

    /// Currently dragging tab ID (for drag source tracking)
    private var draggingTabId: UUID?

    /// Pan gesture recognizer for drag detection
    private var panGesture: NSPanGestureRecognizer!

    /// Track the tab being dragged and the original event for drag session
    private var panStartTabId: UUID?
    private var panStartEvent: NSEvent?

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

        // Register as drag destination for internal reorder, tab drop, and pane drop
        registerForDraggedTypes([.agentStudioTabInternal, .agentStudioTabDrop, .agentStudioPaneDrop])

        // Set up pan gesture recognizer for drag detection
        panGesture = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delaysPrimaryMouseButtonEvents = false
        addGestureRecognizer(panGesture)
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

    // MARK: - Pan Gesture Handler

    @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
        // Tab drag requires management mode (Ctrl+Opt held)
        guard ManagementModeMonitor.shared.isActive else {
            gesture.state = .cancelled
            return
        }

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
                startDrag(tabId: tabId, at: location, event: panStartEvent ?? NSApp.currentEvent!)
                panStartTabId = nil
                panStartEvent = nil
            }

        case .ended, .cancelled:
            panStartTabId = nil
            panStartEvent = nil

        default:
            break
        }
    }

    // MARK: - Drag Initiation

    private func startDrag(tabId: UUID, at point: NSPoint, event: NSEvent) {
        draggingTabId = tabId

        // Update state to show drag visual immediately
        tabBarState?.draggingTabId = tabId

        // Create pasteboard item with both formats
        let pasteboardItem = NSPasteboardItem()

        // Internal format for tab bar reordering
        pasteboardItem.setString(tabId.uuidString, forType: .agentStudioTabInternal)

        // SwiftUI-compatible format for terminal split drops
        if let tab = tabBarState?.tabs.first(where: { $0.id == tabId }) {
            let payload = TabDragPayload(
                tabId: tabId,
                worktreeId: tab.primaryWorktreeId,
                repoId: tab.primaryRepoId,
                title: tab.title
            )
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
        let types = sender.draggingPasteboard.types ?? []
        guard types.contains(.agentStudioTabInternal) || types.contains(.agentStudioPaneDrop) else {
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
        let pasteboard = sender.draggingPasteboard

        // Handle internal tab reorder
        if let idString = pasteboard.string(forType: .agentStudioTabInternal),
           let tabId = UUID(uuidString: idString),
           let targetIndex = tabBarState?.dropTargetIndex {
            onReorder?(tabId, targetIndex)
            return true
        }

        // Handle pane drop → extract pane to new tab
        if let paneData = pasteboard.data(forType: .agentStudioPaneDrop),
           let payload = try? JSONDecoder().decode(PaneDragPayload.self, from: paneData) {
            NotificationCenter.default.post(
                name: .extractPaneRequested,
                object: nil,
                userInfo: [
                    "tabId": payload.tabId,
                    "paneId": payload.paneId
                ]
            )
            return true
        }

        return false
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
