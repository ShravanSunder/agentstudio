import SwiftUI

/// A split view shows a left and right (or top and bottom) view with a divider in the middle for resizing.
/// The terminology "left" and "right" is always used but for vertical splits "left" is "top" and "right" is "bottom".
///
/// Adapted from Ghostty's SplitView implementation.
struct SplitView<L: View, R: View>: View {
    /// Direction of the split
    let direction: SplitViewDirection

    /// Minimum increment (in points) that this split can be resized by
    let resizeIncrements: NSSize

    /// The left and right views to render
    let left: L
    let right: R

    /// Called when the divider is double-tapped to equalize splits
    let onEqualize: () -> Void

    /// Called once when a drag resize begins (for UI state like suppressing overlays)
    let onResizeBegin: (() -> Void)?

    /// Called when a drag resize ends (for persistence)
    let onResizeEnd: (() -> Void)?

    /// The minimum size (in points) of a split
    let minSize: CGFloat = 10

    /// The current fractional width of the split view. 0.5 means L/R are equally sized.
    @Binding var split: CGFloat

    /// Gap size between panes (the background color shows through as the separator)
    private let splitterGapSize: CGFloat = 2
    /// Total hit area for resize dragging (extends beyond the visible gap)
    private let splitterHitSize: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let leftRect = self.leftRect(for: geo.size)
            let rightRect = self.rightRect(for: geo.size, leftRect: leftRect)
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
                Divider(
                    direction: direction,
                    gapSize: splitterGapSize,
                    hitSize: splitterHitSize,
                    split: $split
                )
                .position(splitterPoint)
                .gesture(dragGesture(geo.size, splitterPoint: splitterPoint))
                .onTapGesture(count: 2) {
                    onEqualize()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(splitViewLabel)
        }
    }

    /// Initialize a split view that can be resized by manually dragging the divider.
    init(
        _ direction: SplitViewDirection,
        _ split: Binding<CGFloat>,
        resizeIncrements: NSSize = .init(width: 1, height: 1),
        @ViewBuilder left: (() -> L),
        @ViewBuilder right: (() -> R),
        onEqualize: @escaping () -> Void,
        onResizeBegin: (() -> Void)? = nil,
        onResizeEnd: (() -> Void)? = nil
    ) {
        self.direction = direction
        self._split = split
        self.resizeIncrements = resizeIncrements
        self.left = left()
        self.right = right()
        self.onEqualize = onEqualize
        self.onResizeBegin = onResizeBegin
        self.onResizeEnd = onResizeEnd
    }

    @State private var hasStartedResize = false

    private func dragGesture(_ size: CGSize, splitterPoint: CGPoint) -> some Gesture {
        DragGesture()
            .onChanged { gesture in
                if !hasStartedResize {
                    hasStartedResize = true
                    onResizeBegin?()
                }
                switch direction {
                case .horizontal:
                    let new = min(max(minSize, gesture.location.x), size.width - minSize)
                    split = new / size.width

                case .vertical:
                    let new = min(max(minSize, gesture.location.y), size.height - minSize)
                    split = new / size.height
                }
            }
            .onEnded { _ in
                hasStartedResize = false
                onResizeEnd?()
            }
    }

    /// Calculates the bounding rect for the left view.
    private func leftRect(for size: CGSize) -> CGRect {
        var result = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        switch direction {
        case .horizontal:
            result.size.width *= split
            result.size.width -= splitterGapSize / 2
            result.size.width -= result.size.width.truncatingRemainder(dividingBy: resizeIncrements.width)

        case .vertical:
            result.size.height *= split
            result.size.height -= splitterGapSize / 2
            result.size.height -= result.size.height.truncatingRemainder(dividingBy: resizeIncrements.height)
        }
        return result
    }

    /// Calculates the bounding rect for the right view.
    private func rightRect(for size: CGSize, leftRect: CGRect) -> CGRect {
        var result = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        switch direction {
        case .horizontal:
            result.origin.x += leftRect.size.width
            result.origin.x += splitterGapSize / 2
            result.size.width -= result.origin.x

        case .vertical:
            result.origin.y += leftRect.size.height
            result.origin.y += splitterGapSize / 2
            result.size.height -= result.origin.y
        }
        return result
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
                switch direction {
                case .increment:
                    split = min(split + adjustment, 0.9)
                case .decrement:
                    split = max(split - adjustment, 0.1)
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
