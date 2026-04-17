import AppKit
import GhosttyKit

@MainActor
private final class TerminalSurfaceClipView: NSClipView {
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
    }

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        let proposedBounds = NSRect(origin: newOrigin, size: bounds.size)
        let constrainedOrigin = constrainBoundsRect(proposedBounds).origin
        super.setBoundsOrigin(constrainedOrigin)
    }
}

@MainActor
final class TerminalSurfaceScrollView: NSView {
    let scrollView = NSScrollView()
    private let clipView = TerminalSurfaceClipView()
    let documentView = NSView()
    private weak var actionPerformer: (any TerminalSurfaceActionPerforming)?
    private weak var surfaceView: Ghostty.SurfaceView?
    private weak var hostStateSource: (any TerminalSurfaceHostStateSource)?
    nonisolated(unsafe) private var notificationObservers: [NSObjectProtocol] = []
    private var lastSentRow: Int?
    private var isLiveScrolling = false
    private var previousScrollbarState: ScrollbarState?
    private var cellHeight: CGFloat = 0
    private var maximumDocumentOffsetY: CGFloat {
        max(0, documentView.frame.height - scrollView.contentView.documentVisibleRect.height)
    }

    init(actionPerformer: any TerminalSurfaceActionPerforming) {
        self.actionPerformer = actionPerformer
        super.init(frame: .zero)

        scrollView.hasVerticalScroller = false
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
        scrollView.contentView = clipView
        scrollView.documentView = documentView
        scrollView.contentView.postsBoundsChangedNotifications = true

        addSubview(scrollView)

        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { [weak self] in
                    self?.handleScrollChange()
                }
            })
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSScrollView.willStartLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { [weak self] in
                    self?.isLiveScrolling = true
                }
            })
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSScrollView.didEndLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { [weak self] in
                    self?.isLiveScrolling = false
                }
            })
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSScrollView.didLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { [weak self] in
                    self?.handleLiveScroll()
                }
            })
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                if Thread.isMainThread {
                    MainActor.assumeIsolated {
                        self.handleScrollerStyleChange()
                    }
                } else {
                    Task { @MainActor [weak self] in
                        self?.handleScrollerStyleChange()
                    }
                }
            })
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    func bindHostStateSource(_ hostStateSource: any TerminalSurfaceHostStateSource) {
        self.hostStateSource?.onHostScrollbarStateChanged = nil
        self.hostStateSource = hostStateSource
        synchronizeAppearance()
        hostStateSource.onHostScrollbarStateChanged = { [weak self] _ in
            guard let self else { return }
            self.synchronizeAppearance()
            self.synchronizeScrollView()
            self.synchronizeSurfaceFrame()
        }
    }

    func embedSurfaceView(_ surfaceView: Ghostty.SurfaceView) {
        self.surfaceView?.removeFromSuperview()
        self.surfaceView = surfaceView
        bindHostStateSource(surfaceView)
        documentView.addSubview(surfaceView)
        surfaceView.frame.size = scrollView.bounds.size
        needsLayout = true
        synchronizeAppearance()
        updateTrackingAreas()
    }

    func applyScrollbarState(_ state: ScrollbarState, cellHeight: CGFloat) {
        guard cellHeight > 0 else { return }
        self.cellHeight = cellHeight
        previousScrollbarState = state

        synchronizeScrollView()
        synchronizeSurfaceFrame()
    }

    private func handleScrollChange() {
        synchronizeSurfaceFrame()
    }

    private func handleLiveScroll() {
        let effectiveCellHeight = currentCellHeight()
        guard let state = currentScrollbarState(), effectiveCellHeight > 0 else { return }

        let visibleRect = scrollView.contentView.documentVisibleRect
        let documentHeight = documentView.frame.height
        let offsetFromTop = max(0, documentHeight - visibleRect.origin.y - visibleRect.height)
        let maximumTopRow = max(0, state.total - state.visibleRowCount)
        let row = max(0, min(Int(offsetFromTop / effectiveCellHeight), maximumTopRow))
        guard row != lastSentRow else { return }
        lastSentRow = row
        _ = actionPerformer?.performBindingAction(.scrollToRow(row))
    }

    private func synchronizeScrollView() {
        documentView.frame.size.height = documentHeight()

        guard let state = currentScrollbarState() else {
            scrollView.reflectScrolledClipView(scrollView.contentView)
            return
        }

        if !isLiveScrolling {
            let offsetY = runtimeDocumentOffsetY(for: state)
            scrollView.contentView.scroll(to: CGPoint(x: 0, y: offsetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
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

    private func synchronizeAppearance() {
        guard let hostStateSource else { return }
        scrollView.hasVerticalScroller = hostStateSource.hostConfigSnapshot.scrollbarPolicy != .never
        let hasLightBackground = hostStateSource.hostConfigSnapshot.backgroundColor.isLightColor
        scrollView.appearance = NSAppearance(named: hasLightBackground ? .aqua : .darkAqua)
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
        let effectiveCellHeight = currentCellHeight()
        guard effectiveCellHeight > 0, let state = currentScrollbarState() else { return contentHeight }

        let documentGridHeight = CGFloat(state.total) * effectiveCellHeight
        let padding = contentHeight - (CGFloat(state.visibleRowCount) * effectiveCellHeight)
        return max(contentHeight, documentGridHeight + padding)
    }

    private func runtimeDocumentOffsetY(for state: ScrollbarState) -> CGFloat {
        let offsetY = CGFloat(state.total - state.top - state.visibleRowCount) * currentCellHeight()
        return min(max(0, offsetY), maximumDocumentOffsetY)
    }

    private func currentScrollbarState() -> ScrollbarState? {
        hostStateSource?.hostScrollbarState ?? previousScrollbarState
    }

    private func currentCellHeight() -> CGFloat {
        if let reportedCellHeight = hostStateSource?.reportedCellSize?.height, reportedCellHeight > 0 {
            return reportedCellHeight
        }
        return cellHeight
    }

    private func handleScrollerStyleChange() {
        scrollView.scrollerStyle = .overlay
        synchronizeCoreSurface()
    }

    override func mouseMoved(with event: NSEvent) {
        guard NSScroller.preferredScrollerStyle == .legacy else { return }
        scrollView.flashScrollers()
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
