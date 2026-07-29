import AgentStudioInfrastructure
import SwiftUI

package enum HoverTooltipPlacement {
    package static let defaultEdgeInset: CGFloat = 6
    package static let defaultVerticalOffset: CGFloat = -28
    package static let aboveAnchorVerticalOffset: CGFloat = -34
    package static let belowAnchorVerticalOffset: CGFloat = 6

    package enum VerticalAnchor {
        case containerTop
        case aboveAnchor
        case belowAnchor
    }

    package static func clampedLeadingX(
        anchorFrame: CGRect,
        tooltipSize: CGSize,
        availableWidth: CGFloat,
        edgeInset: CGFloat = defaultEdgeInset
    ) -> CGFloat {
        let proposedLeadingX = anchorFrame.midX - (tooltipSize.width / 2)
        let maxLeadingX = max(edgeInset, availableWidth - tooltipSize.width - edgeInset)
        return min(max(edgeInset, proposedLeadingX), maxLeadingX)
    }

    package static func positionedY(
        anchorFrame: CGRect,
        verticalAnchor: VerticalAnchor,
        verticalOffset: CGFloat
    ) -> CGFloat {
        switch verticalAnchor {
        case .containerTop:
            return verticalOffset
        case .aboveAnchor:
            return max(0, anchorFrame.minY + verticalOffset)
        case .belowAnchor:
            return anchorFrame.maxY + verticalOffset
        }
    }
}

struct HoverTooltipBubble: View {
    let renderValue: ControlTooltipRenderValue

    var body: some View {
        Text(renderValue.text)
            .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(AppStyles.General.Fill.active), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            .fixedSize()
    }
}

package struct HoverTooltipAnchorPreferenceKey<Target: Hashable>: PreferenceKey {
    package static var defaultValue: [Target: CGRect] { [:] }

    package static func reduce(value: inout [Target: CGRect], nextValue: () -> [Target: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct HoverTooltipSizePreferenceKey: PreferenceKey {
    package static let defaultValue: CGSize = .zero

    package static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

extension View {
    package func hoverTooltipAnchor<Target: Hashable>(_ target: Target, in coordinateSpaceName: String) -> some View {
        background(
            GeometryReader { geometryProxy in
                Color.clear.preference(
                    key: HoverTooltipAnchorPreferenceKey<Target>.self,
                    value: [target: geometryProxy.frame(in: .named(coordinateSpaceName))]
                )
            }
        )
    }
}

package struct FloatingHoverTooltipPresenter<Target: Hashable>: View {
    let activeTarget: Target?
    let anchorFrames: [Target: CGRect]
    let availableWidth: CGFloat
    let tooltipValue: (Target) -> ControlTooltipRenderValue?
    let verticalAnchor: HoverTooltipPlacement.VerticalAnchor
    let verticalOffset: CGFloat
    let edgeInset: CGFloat

    @State private var tooltipSize: CGSize = .zero

    package init(
        activeTarget: Target?,
        anchorFrames: [Target: CGRect],
        availableWidth: CGFloat,
        verticalAnchor: HoverTooltipPlacement.VerticalAnchor = .containerTop,
        verticalOffset: CGFloat = HoverTooltipPlacement.defaultVerticalOffset,
        edgeInset: CGFloat = HoverTooltipPlacement.defaultEdgeInset,
        tooltipValue: @escaping (Target) -> ControlTooltipRenderValue?
    ) {
        self.activeTarget = activeTarget
        self.anchorFrames = anchorFrames
        self.availableWidth = availableWidth
        self.verticalAnchor = verticalAnchor
        self.verticalOffset = verticalOffset
        self.edgeInset = edgeInset
        self.tooltipValue = tooltipValue
    }

    package var body: some View {
        if let activeTarget,
            let renderValue = tooltipValue(activeTarget),
            let anchorFrame = anchorFrames[activeTarget]
        {
            HoverTooltipBubble(renderValue: renderValue)
                .background(
                    GeometryReader { tooltipGeometryProxy in
                        Color.clear.preference(
                            key: HoverTooltipSizePreferenceKey.self,
                            value: tooltipGeometryProxy.size
                        )
                    }
                )
                .offset(
                    x: HoverTooltipPlacement.clampedLeadingX(
                        anchorFrame: anchorFrame,
                        tooltipSize: tooltipSize,
                        availableWidth: availableWidth,
                        edgeInset: edgeInset
                    ),
                    y: HoverTooltipPlacement.positionedY(
                        anchorFrame: anchorFrame,
                        verticalAnchor: verticalAnchor,
                        verticalOffset: verticalOffset
                    )
                )
                .onPreferenceChange(HoverTooltipSizePreferenceKey.self) { tooltipSize = $0 }
        }
    }
}
