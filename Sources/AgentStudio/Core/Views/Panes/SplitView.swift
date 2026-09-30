import AgentStudioInfrastructure
import SwiftUI

private struct SplitViewLayoutPublicationKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct InteractionPerformanceProbeEnvironmentKey: EnvironmentKey {
    static let defaultValue: AgentStudioInteractionPerformanceProbe? = nil
}

extension EnvironmentValues {
    package var agentStudioInteractionPerformanceProbe: AgentStudioInteractionPerformanceProbe? {
        get { self[InteractionPerformanceProbeEnvironmentKey.self] }
        set { self[InteractionPerformanceProbeEnvironmentKey.self] = newValue }
    }
}

/// The two child rectangles of a split, in the split's own coordinate space.
package struct SplitViewRegions: Equatable, Sendable {
    package let left: CGRect
    package let right: CGRect
}

/// Pure split arithmetic shared by `SplitView` paint and callers that must
/// predict the same regions without a SwiftUI pass (drawer bootstrap
/// geometry for Pane Zoom).
package enum SplitViewRegionLayout {
    /// Visible divider gap between the two split regions.
    package static let dividerGapSize: CGFloat = 2

    package static func regions(
        direction: SplitViewDirection,
        size: CGSize,
        split: CGFloat,
        reservesDividerSpace: Bool,
        resizeIncrements: NSSize = .init(width: 1, height: 1)
    ) -> SplitViewRegions {
        var left = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        var right = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        switch direction {
        case .horizontal:
            left.size.width *= split
            if reservesDividerSpace {
                left.size.width -= dividerGapSize / 2
            }
            left.size.width -= left.size.width.truncatingRemainder(dividingBy: resizeIncrements.width)
            right.origin.x += left.size.width
            if reservesDividerSpace {
                right.origin.x += dividerGapSize / 2
            }
            right.size.width -= right.origin.x

        case .vertical:
            left.size.height *= split
            if reservesDividerSpace {
                left.size.height -= dividerGapSize / 2
            }
            left.size.height -= left.size.height.truncatingRemainder(dividingBy: resizeIncrements.height)
            right.origin.y += left.size.height
            if reservesDividerSpace {
                right.origin.y += dividerGapSize / 2
            }
            right.size.height -= right.origin.y
        }
        return SplitViewRegions(left: left, right: right)
    }
}

/// A split view shows a left and right (or top and bottom) view with a divider in the middle for resizing.
/// The terminology "left" and "right" is always used but for vertical splits "left" is "top" and "right" is "bottom".
///
/// Adapted from Ghostty's SplitView implementation.
package struct SplitView<L: View, R: View>: View {
    /// Direction of the split
    let direction: SplitViewDirection

    /// Minimum increment (in points) that this split can be resized by
    let resizeIncrements: NSSize

    /// The left and right views to render
    let left: L
    let right: R

    /// Called when the divider is double-tapped to equalize splits
    let onEqualize: () -> Void

    /// Whether the divider and its resize interaction are currently visible.
    let showsDivider: Bool

    /// Whether layout continues reserving the divider gap while its paint and interaction are hidden.
    let reservesDividerSpace: Bool

    /// Optional ratio limits for a split owned by a narrower product policy.
    let splitRatioBounds: ClosedRange<CGFloat>?

    /// Called once when a drag resize begins (for UI state like suppressing overlays)
    let onResizeBegin: (() -> Void)?

    /// Called when a drag resize ends (for persistence)
    let onResizeEnd: (() -> Void)?

    /// The minimum size (in points) of a split
    let minSize: CGFloat = AppPolicies.DragAndDrop.splitMinimumPaneSize

    /// The current fractional width of the split view. 0.5 means L/R are equally sized.
    @Binding var split: CGFloat
    @Environment(\.agentStudioInteractionPerformanceProbe) private var interactionProbe
    @State private var frameMeasurement = DividerFrameMeasurementState()

    /// Gap size between panes (the background color shows through as the separator)
    private let splitterGapSize: CGFloat = SplitViewRegionLayout.dividerGapSize
    /// Total hit area for resize dragging (extends beyond the visible gap)
    private let splitterHitSize: CGFloat = 6

    package var body: some View {
        GeometryReader { geo in
            let regions = self.regions(for: geo.size)
            let leftRect = regions.left
            let rightRect = regions.right
            let splitterPoint = self.splitterPoint(for: geo.size, leftRect: leftRect)

            ZStack(alignment: .topLeading) {
                left
                    .frame(width: leftRect.size.width, height: leftRect.size.height)
                    .offset(x: leftRect.origin.x, y: leftRect.origin.y)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(leftPaneLabel)
                right
                    .frame(width: rightRect.size.width, height: rightRect.size.height)
                    .offset(x: rightRect.origin.x, y: rightRect.origin.y)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(rightPaneLabel)
                if showsDivider {
                    Divider(
                        direction: direction,
                        gapSize: splitterGapSize,
                        hitSize: splitterHitSize,
                        split: $split,
                        splitRatioBounds: splitRatioBounds
                    )
                    .position(splitterPoint)
                    .gesture(dragGesture(geo.size, splitterPoint: splitterPoint))
                    .onTapGesture(count: 2) {
                        onEqualize()
                    }
                    .transition(.identity)
                }
            }
            .clipped()
            .preference(key: SplitViewLayoutPublicationKey.self, value: split)
            .onPreferenceChange(SplitViewLayoutPublicationKey.self) { _ in
                frameMeasurement.layoutDidPublish(using: interactionProbe)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(splitViewLabel)
        }
    }

    /// Initialize a split view that can be resized by manually dragging the divider.
    package init(
        _ direction: SplitViewDirection,
        _ split: Binding<CGFloat>,
        resizeIncrements: NSSize = .init(width: 1, height: 1),
        @ViewBuilder left: (() -> L),
        @ViewBuilder right: (() -> R),
        onEqualize: @escaping () -> Void,
        showsDivider: Bool = true,
        reservesDividerSpace: Bool? = nil,
        onResizeBegin: (() -> Void)? = nil,
        onResizeEnd: (() -> Void)? = nil,
        splitRatioBounds: ClosedRange<CGFloat>? = nil
    ) {
        self.direction = direction
        self._split = split
        self.resizeIncrements = resizeIncrements
        self.left = left()
        self.right = right()
        self.onEqualize = onEqualize
        self.showsDivider = showsDivider
        self.reservesDividerSpace = reservesDividerSpace ?? showsDivider
        self.onResizeBegin = onResizeBegin
        self.onResizeEnd = onResizeEnd
        self.splitRatioBounds = splitRatioBounds
    }

    @State private var hasStartedResize = false

    private func dragGesture(_ size: CGSize, splitterPoint: CGPoint) -> some Gesture {
        DragGesture()
            .onChanged { gesture in
                if !hasStartedResize {
                    hasStartedResize = true
                    RestoreTrace.log(
                        "SplitView.dragBegin direction=\(String(describing: direction)) size=\(NSStringFromSize(size)) splitterPoint=\(NSStringFromPoint(splitterPoint)) split(before)=\(split)"
                    )
                    onResizeBegin?()
                }
                switch direction {
                case .horizontal:
                    guard
                        let resizedSplit = boundedSplitRatio(
                            at: gesture.location.x,
                            extent: size.width
                        )
                    else { return }
                    RestoreTrace.log(
                        "SplitView.dragChanged direction=horizontal location=\(NSStringFromPoint(gesture.location)) size=\(NSStringFromSize(size)) split(before)=\(split) split(after)=\(resizedSplit)"
                    )
                    guard resizedSplit != split else { return }
                    split = resizedSplit
                    frameMeasurement.admitSample(using: interactionProbe)

                case .vertical:
                    guard
                        let resizedSplit = boundedSplitRatio(
                            at: gesture.location.y,
                            extent: size.height
                        )
                    else { return }
                    RestoreTrace.log(
                        "SplitView.dragChanged direction=vertical location=\(NSStringFromPoint(gesture.location)) size=\(NSStringFromSize(size)) split(before)=\(split) split(after)=\(resizedSplit)"
                    )
                    guard resizedSplit != split else { return }
                    split = resizedSplit
                    frameMeasurement.admitSample(using: interactionProbe)
                }
            }
            .onEnded { _ in
                RestoreTrace.log(
                    "SplitView.dragEnd direction=\(String(describing: direction)) split(final)=\(split)"
                )
                frameMeasurement.gestureDidEnd(using: interactionProbe)
                hasStartedResize = false
                onResizeEnd?()
            }
    }

    private func boundedSplitRatio(at location: CGFloat, extent: CGFloat) -> CGFloat? {
        guard extent.isFinite, extent > 0 else { return nil }
        let minimumPaneExtent = min(minSize, extent / 2)
        let minimumPosition = max(
            minimumPaneExtent,
            extent * (splitRatioBounds?.lowerBound ?? 0)
        )
        let maximumPosition = max(
            minimumPosition,
            min(extent - minimumPaneExtent, extent * (splitRatioBounds?.upperBound ?? 1))
        )
        let clampedPosition = min(max(location, minimumPosition), maximumPosition)
        guard let splitRatioBounds else { return clampedPosition / extent }
        // `(extent * bound) / extent` can misround (1714 * 0.3 / 1714 == 0.29999999999999993)
        // and owners validate bounds exactly, so a drag held at a bound emits the bound itself
        // and any other ratio is clamped after the division.
        if clampedPosition <= extent * splitRatioBounds.lowerBound { return splitRatioBounds.lowerBound }
        if clampedPosition >= extent * splitRatioBounds.upperBound { return splitRatioBounds.upperBound }
        return min(max(clampedPosition / extent, splitRatioBounds.lowerBound), splitRatioBounds.upperBound)
    }

    /// Calculates the bounding rects for the left and right views.
    private func regions(for size: CGSize) -> SplitViewRegions {
        SplitViewRegionLayout.regions(
            direction: direction,
            size: size,
            split: split,
            reservesDividerSpace: reservesDividerSpace,
            resizeIncrements: resizeIncrements
        )
    }

    /// Calculates the point at which the splitter should be rendered.
    private func splitterPoint(for size: CGSize, leftRect: CGRect) -> CGPoint {
        switch direction {
        case .horizontal:
            return CGPoint(x: leftRect.size.width, y: size.height / 2)

        case .vertical:
            return CGPoint(x: size.width / 2, y: leftRect.size.height)
        }
    }

    // MARK: Accessibility

    private var splitViewLabel: String {
        switch direction {
        case .horizontal: return "Horizontal split view"
        case .vertical: return "Vertical split view"
        }
    }

    private var leftPaneLabel: String {
        switch direction {
        case .horizontal: return "Left pane"
        case .vertical: return "Top pane"
        }
    }

    private var rightPaneLabel: String {
        switch direction {
        case .horizontal: return "Right pane"
        case .vertical: return "Bottom pane"
        }
    }
}

// MARK: - Divider

extension SplitView {
    /// The split divider rendered as a gap that reveals the app background color.
    /// The visible gap is subtle (2pt) while the hit area for dragging is larger.
    struct Divider: View {
        let direction: SplitViewDirection
        let gapSize: CGFloat
        let hitSize: CGFloat
        @Binding var split: CGFloat
        let splitRatioBounds: ClosedRange<CGFloat>?

        private var hitWidth: CGFloat? {
            switch direction {
            case .horizontal: return hitSize
            case .vertical: return nil
            }
        }

        private var hitHeight: CGFloat? {
            switch direction {
            case .horizontal: return nil
            case .vertical: return hitSize
            }
        }

        private var pointerStyle: BackportPointerStyle {
            switch direction {
            case .horizontal: return .resizeLeftRight
            case .vertical: return .resizeUpDown
            }
        }

        var body: some View {
            ZStack {
                // Hit area (invisible, extends beyond the visible gap)
                Color.clear
                    .frame(width: hitWidth, height: hitHeight)
                    .contentShape(Rectangle())
            }
            .backport.pointerStyle(pointerStyle)
            .onHover { isHovered in
                // macOS 15+ we use the pointerStyle helper
                if #available(macOS 15, *) {
                    return
                }

                if isHovered {
                    switch direction {
                    case .horizontal:
                        NSCursor.resizeLeftRight.push()
                    case .vertical:
                        NSCursor.resizeUpDown.push()
                    }
                } else {
                    NSCursor.pop()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(axLabel)
            .accessibilityValue("\(Int(split * 100))%")
            .accessibilityHint(axHint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAdjustableAction { direction in
                let adjustment: CGFloat = 0.025
                let bounds = splitRatioBounds ?? 0.1...0.9
                switch direction {
                case .increment:
                    split = min(split + adjustment, bounds.upperBound)
                case .decrement:
                    split = max(split - adjustment, bounds.lowerBound)
                @unknown default:
                    break
                }
            }
        }

        private var axLabel: String {
            switch direction {
            case .horizontal: return "Horizontal split divider"
            case .vertical: return "Vertical split divider"
            }
        }

        private var axHint: String {
            switch direction {
            case .horizontal: return "Drag to resize the left and right panes"
            case .vertical: return "Drag to resize the top and bottom panes"
            }
        }
    }
}
