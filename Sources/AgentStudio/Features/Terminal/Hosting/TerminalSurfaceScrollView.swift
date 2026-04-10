import AppKit
import GhosttyKit

@MainActor
private final class TerminalSurfaceClipView: NSClipView {
    var onBoundsChanged: (() -> Void)?

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrainedBounds = super.constrainBoundsRect(proposedBounds)
        if let documentView {
            let maximumOffsetY = max(0, documentView.frame.height - constrainedBounds.height)
            constrainedBounds.origin.y = min(max(0, constrainedBounds.origin.y), maximumOffsetY)
        }
        constrainedBounds.origin.x = 0
        return constrainedBounds
    }

    override func scroll(to newOrigin: NSPoint) {
        let proposedBounds = NSRect(origin: newOrigin, size: bounds.size)
        let constrainedOrigin = constrainBoundsRect(proposedBounds).origin
        super.scroll(to: constrainedOrigin)
        onBoundsChanged?()
    }

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        super.setBoundsOrigin(newOrigin)
        onBoundsChanged?()
    }
}

@MainActor
final class TerminalSurfaceScrollView: NSView {
    private let scrollView = NSScrollView()
    private let clipView = TerminalSurfaceClipView()
    private let documentView = NSView()
    private weak var actionPerformer: (any TerminalSurfaceActionPerforming)?
    private weak var surfaceView: Ghostty.SurfaceView?
    private var lastSentRow: Int?
    private var isLiveScrolling = false
    private var isApplyingRuntimeScrollState = false
    private var previousScrollbarState: ScrollbarState?
    private var cellHeight: CGFloat = 0
    private var followBottomUntilUserScrolls = true
    private var maximumDocumentOffsetY: CGFloat {
        max(0, documentView.frame.height - scrollView.contentView.documentVisibleRect.height)
    }

    init(actionPerformer: any TerminalSurfaceActionPerforming) {
        self.actionPerformer = actionPerformer
        super.init(frame: .zero)

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .overlay
        scrollView.usesPredominantAxisScrolling = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.contentView.clipsToBounds = false
        clipView.drawsBackground = false
        clipView.documentView = documentView
        clipView.onBoundsChanged = { [weak self] in
            self?.handleBoundsDidChange()
        }
        scrollView.contentView = clipView
        scrollView.documentView = documentView

        addSubview(scrollView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func layout() {
        super.layout()

        scrollView.frame = bounds
        surfaceView?.frame.size = scrollView.bounds.size
        documentView.frame.size.width = scrollView.bounds.width

        synchronizeScrollView()
        synchronizeSurfaceFrame()
        synchronizeCoreSurface()
        updateTrackingAreas()
    }

    func embedSurfaceView(_ surfaceView: Ghostty.SurfaceView) {
        self.surfaceView?.removeFromSuperview()
        self.surfaceView = surfaceView
        documentView.addSubview(surfaceView)
        surfaceView.frame.size = scrollView.bounds.size
        needsLayout = true
        updateTrackingAreas()
    }

    func applyScrollbarState(_ state: ScrollbarState, cellHeight: CGFloat) {
        guard cellHeight > 0 else { return }
        self.cellHeight = cellHeight
        let wasPinnedToBottom = previousScrollbarState.map { isPinnedToBottom(scrollbarState: $0) } ?? true
        let isInitialState = previousScrollbarState == nil
        previousScrollbarState = state
        if isInitialState {
            followBottomUntilUserScrolls = isPinnedToBottom(scrollbarState: state)
        } else if wasPinnedToBottom {
            followBottomUntilUserScrolls = true
        }

        synchronizeScrollView()
        synchronizeSurfaceFrame()
        synchronizeCoreSurface()
    }

    var documentOffsetYForTesting: CGFloat {
        scrollView.contentView.bounds.origin.y
    }

    var maximumDocumentOffsetYForTesting: CGFloat {
        maximumDocumentOffsetY
    }

    var autohidesScrollersForTesting: Bool {
        scrollView.autohidesScrollers
    }

    var usesOverlayScrollerStyleForTesting: Bool {
        scrollView.scrollerStyle == .overlay
    }

    var documentHeightForTesting: CGFloat {
        documentView.frame.height
    }

    func simulateLiveScrollForTesting(documentOffsetY: CGFloat) {
        isLiveScrolling = true
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: documentOffsetY))
        syncTerminalRowToVisibleRect()
        isLiveScrolling = false
    }

    func simulateSurfaceWheelScrollForTesting(deltaY: CGFloat) {
        let currentOffsetY = scrollView.contentView.bounds.origin.y
        let nextOffsetY = max(0, currentOffsetY + deltaY)
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: nextOffsetY))
        syncTerminalRowToVisibleRect()
    }

    func handleSurfaceScrollWheel(_ event: NSEvent) {
        isLiveScrolling = true
        scrollView.scrollWheel(with: event)
        isLiveScrolling = false
    }

    private func handleBoundsDidChange() {
        let currentOffsetY = scrollView.contentView.bounds.origin.y
        let clampedOffsetY = min(max(0, currentOffsetY), maximumDocumentOffsetY)
        if currentOffsetY != clampedOffsetY {
            isApplyingRuntimeScrollState = true
            scrollView.contentView.scroll(to: CGPoint(x: 0, y: clampedOffsetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isApplyingRuntimeScrollState = false
        }

        synchronizeSurfaceFrame()
        synchronizeCoreSurface()
        guard !isApplyingRuntimeScrollState else { return }
        if currentOffsetY != maximumDocumentOffsetY {
            followBottomUntilUserScrolls = false
        } else if maximumDocumentOffsetY == 0 || clampedOffsetY == maximumDocumentOffsetY {
            followBottomUntilUserScrolls = true
        }
        syncTerminalRowToVisibleRect()
    }

    private func syncTerminalRowToVisibleRect() {
        guard let state = previousScrollbarState, cellHeight > 0 else { return }

        let visibleRect = scrollView.contentView.documentVisibleRect
        let documentHeight = documentView.frame.height
        let offsetFromTop = max(0, documentHeight - visibleRect.origin.y - visibleRect.height)
        let visibleRowCount = max(0, state.bottom - state.top)
        let maximumTopRow = max(0, state.total - visibleRowCount)
        let row = max(0, min(Int(offsetFromTop / cellHeight), maximumTopRow))
        guard row != lastSentRow else { return }
        lastSentRow = row
        _ = actionPerformer?.performBindingAction("scroll_to_row:\(row)")
    }

    private func synchronizeScrollView() {
        documentView.frame.size.height = documentHeight()

        guard let state = previousScrollbarState else {
            scrollView.reflectScrolledClipView(scrollView.contentView)
            return
        }

        if !isLiveScrolling && followBottomUntilUserScrolls {
            let offsetY = runtimeDocumentOffsetY(for: state)
            isApplyingRuntimeScrollState = true
            scrollView.contentView.scroll(to: CGPoint(x: 0, y: offsetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isApplyingRuntimeScrollState = false
            lastSentRow = state.top
        } else {
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func synchronizeSurfaceFrame() {
        guard let surfaceView else { return }
        let visibleRect = scrollView.contentView.documentVisibleRect
        surfaceView.frame.origin = visibleRect.origin
    }

    private func synchronizeCoreSurface() {
        guard let surfaceView else { return }
        let width = scrollView.contentSize.width
        let height = surfaceView.frame.height
        guard width > 0, height > 0 else { return }
        surfaceView.sizeDidChange(NSSize(width: width, height: height), source: "scrollWrapper")
    }

    private func documentHeight() -> CGFloat {
        let contentHeight = scrollView.contentSize.height
        guard cellHeight > 0, let state = previousScrollbarState else { return contentHeight }

        let visibleRowCount = max(0, state.bottom - state.top)
        let documentGridHeight = CGFloat(state.total) * cellHeight
        let padding = contentHeight - (CGFloat(visibleRowCount) * cellHeight)
        return max(contentHeight, documentGridHeight + padding)
    }

    private func runtimeDocumentOffsetY(for state: ScrollbarState) -> CGFloat {
        let visibleRowCount = max(0, state.bottom - state.top)
        let offsetY = CGFloat(state.total - state.top - visibleRowCount) * cellHeight
        return min(max(0, offsetY), maximumDocumentOffsetY)
    }

    private func isPinnedToBottom(scrollbarState: ScrollbarState) -> Bool {
        scrollbarState.bottom >= scrollbarState.total
    }

    override func mouseMoved(with event: NSEvent) {
        scrollView.flashScrollers()
        super.mouseMoved(with: event)
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        super.updateTrackingAreas()

        guard let verticalScroller = scrollView.verticalScroller else { return }
        addTrackingArea(
            NSTrackingArea(
                rect: convert(verticalScroller.bounds, from: verticalScroller),
                options: [
                    .mouseMoved,
                    .activeInKeyWindow,
                ],
                owner: self,
                userInfo: nil
            ))
    }
}
