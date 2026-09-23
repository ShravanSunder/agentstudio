import AgentStudioCore
import CoreGraphics
import Foundation

/// Transient state of one normal-mode drawer top-edge drag.
///
/// Owned locally by `DrawerPanelOverlay`; never published per sample. Height
/// is the anchor height minus cumulative pointer displacement in the fixed
/// `"tabContainer"` space — never the previous rendered height plus a
/// translation. When a sample lands past a size bound, the anchor rebases to
/// the displayed result so reversing direction moves the edge immediately.
struct DrawerNormalResizeSession: Equatable {
    let ownerPaneId: UUID
    /// Container height the session's pointer and height values are valid for.
    let containerHeight: CGFloat
    /// The handle gesture this session belongs to.
    let gestureID: DrawerResizeGestureID
    private(set) var anchorHeight: CGFloat
    private(set) var anchorPointerY: CGFloat
    private(set) var liveHeight: CGFloat
    /// Set when pointer-up dispatched the commit. The live height keeps
    /// displaying until the owner's committed preference reflects it, so the
    /// asynchronous workspace action cannot flash the previous height.
    private(set) var isAwaitingCommit = false
    /// Latched when the session is cancelled mid-gesture: the rest of that
    /// gesture's samples and its end are discarded.
    private(set) var isCancelled = false

    init(
        ownerPaneId: UUID,
        containerHeight: CGFloat,
        startHeight: CGFloat,
        startPointerY: CGFloat,
        gestureID: DrawerResizeGestureID
    ) {
        self.ownerPaneId = ownerPaneId
        self.containerHeight = containerHeight
        self.gestureID = gestureID
        anchorHeight = startHeight
        anchorPointerY = startPointerY
        liveHeight = startHeight
    }

    /// Applies one pointer sample. `displayedHeight` maps a requested height to
    /// the height geometry will actually display (bounds and available space).
    mutating func track(
        pointerY: CGFloat,
        displayedHeight: (_ requestedHeight: CGFloat) -> CGFloat
    ) {
        guard !isAwaitingCommit, !isCancelled else { return }
        let requestedHeight = anchorHeight - (pointerY - anchorPointerY)
        let shownHeight = displayedHeight(requestedHeight)
        if shownHeight != requestedHeight {
            anchorHeight = shownHeight
            anchorPointerY = pointerY
        }
        liveHeight = shownHeight
    }

    mutating func markAwaitingCommit() {
        isAwaitingCommit = true
    }

    mutating func cancel() {
        isCancelled = true
    }

    /// A session applies only to the owner and geometry context it began in.
    func applies(toOwner ownerPaneId: UUID, containerHeight: CGFloat) -> Bool {
        self.ownerPaneId == ownerPaneId && self.containerHeight == containerHeight
    }

    /// Owner-specific ratio committed once when the drag completes.
    var committedHeightRatio: Double? {
        guard !isCancelled, containerHeight > 0, liveHeight.isFinite else { return nil }
        return Double(liveHeight / containerHeight)
    }
}

/// Identity of one pointer gesture on the drawer resize handle, minted by the
/// handle when a gesture's first sample arrives.
struct DrawerResizeGestureID: Hashable, Sendable {
    let rawValue: UUID

    static func make() -> Self {
        Self(rawValue: UUID())
    }
}

/// Everything that can happen to the overlay's resize session.
enum DrawerResizeSessionEvent {
    case changed(gestureID: DrawerResizeGestureID, pointerY: CGFloat)
    case ended(gestureID: DrawerResizeGestureID)
    /// The handle's gesture finished or was cancelled by the system.
    case terminated(gestureID: DrawerResizeGestureID?)
    /// Owner replaced or closed, mode change, coordinate invalidation, or
    /// window deactivation.
    case cancelled
    /// The owner's committed preference changed.
    case committedPreferenceChanged
}

/// Geometry facts the overlay supplies with each event.
struct DrawerResizeSessionContext {
    let ownerPaneId: UUID
    let containerHeight: CGFloat
    /// Height currently displayed, the start height of a new gesture.
    let displayedHeight: CGFloat
    let committedHeightRatio: Double
    /// Maps a requested height to the height geometry will display.
    let displayedHeightForRequest: (_ requestedHeight: CGFloat) -> CGFloat
}

extension DrawerNormalResizeSession {
    /// Pure session transitions; `context` is required for pointer events. A cancelled gesture stays latched by its
    /// identity: its late samples and end are discarded and never restart or
    /// commit a session; only a new gesture starts a new one. Returns the next
    /// session and the ratio to commit, if any.
    static func reduce(
        _ session: Self?,
        _ event: DrawerResizeSessionEvent,
        context: DrawerResizeSessionContext? = nil
    ) -> (session: Self?, commitHeightRatio: Double?) {
        switch event {
        case .changed(let gestureID, let pointerY):
            guard let context else { return (session, nil) }
            guard var current = session, current.gestureID == gestureID else {
                var started = Self(
                    ownerPaneId: context.ownerPaneId,
                    containerHeight: context.containerHeight,
                    startHeight: context.displayedHeight,
                    startPointerY: pointerY,
                    gestureID: gestureID
                )
                started.track(pointerY: pointerY, displayedHeight: context.displayedHeightForRequest)
                return (started, nil)
            }
            guard current.applies(toOwner: context.ownerPaneId, containerHeight: context.containerHeight) else {
                current.cancel()
                return (current, nil)
            }
            current.track(pointerY: pointerY, displayedHeight: context.displayedHeightForRequest)
            return (current, nil)

        case .ended(let gestureID):
            guard let context, var current = session, current.gestureID == gestureID else { return (session, nil) }
            guard !current.isCancelled, !current.isAwaitingCommit,
                current.applies(toOwner: context.ownerPaneId, containerHeight: context.containerHeight),
                let ratio = current.committedHeightRatio.flatMap(
                    DrawerPresentationPreference.validatedNormalHeightRatio),
                ratio != context.committedHeightRatio
            else { return (current.isAwaitingCommit ? current : nil, nil) }
            current.markAwaitingCommit()
            return (current, ratio)

        case .terminated(let gestureID):
            guard let current = session, !current.isAwaitingCommit else { return (session, nil) }
            guard gestureID == nil || current.gestureID == gestureID else { return (session, nil) }
            return (nil, nil)

        case .cancelled:
            guard var current = session, !current.isAwaitingCommit else { return (nil, nil) }
            current.cancel()
            return (current, nil)

        case .committedPreferenceChanged:
            guard let current = session, current.isAwaitingCommit else { return (session, nil) }
            return (nil, nil)
        }
    }
}
