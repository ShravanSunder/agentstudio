import SwiftUI

enum HoverTooltipPlacement {
    static let defaultEdgeInset: CGFloat = 6
    static let defaultVerticalOffset: CGFloat = -28

    static func clampedLeadingX(
        anchorFrame: CGRect,
        tooltipSize: CGSize,
        availableWidth: CGFloat,
        edgeInset: CGFloat = defaultEdgeInset
    ) -> CGFloat {
        let proposedLeadingX = anchorFrame.midX - (tooltipSize.width / 2)
        let maxLeadingX = max(edgeInset, availableWidth - tooltipSize.width - edgeInset)
        return min(max(edgeInset, proposedLeadingX), maxLeadingX)
    }
}

struct HoverTooltipBubble: View {
    let text: String

    var body: some View {
        Text(text)
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

struct HoverTooltipAnchorPreferenceKey<Target: Hashable>: PreferenceKey {
    static var defaultValue: [Target: CGRect] { [:] }

    static func reduce(value: inout [Target: CGRect], nextValue: () -> [Target: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct HoverTooltipSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

extension View {
    func hoverTooltipAnchor<Target: Hashable>(_ target: Target, in coordinateSpaceName: String) -> some View {
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

struct FloatingHoverTooltipPresenter<Target: Hashable>: View {
    let activeTarget: Target?
    let anchorFrames: [Target: CGRect]
    let availableWidth: CGFloat
    let tooltipText: (Target) -> String?
    let verticalOffset: CGFloat
    let edgeInset: CGFloat

    @State private var tooltipSize: CGSize = .zero

    init(
        activeTarget: Target?,
        anchorFrames: [Target: CGRect],
        availableWidth: CGFloat,
        verticalOffset: CGFloat = HoverTooltipPlacement.defaultVerticalOffset,
        edgeInset: CGFloat = HoverTooltipPlacement.defaultEdgeInset,
        tooltipText: @escaping (Target) -> String?
    ) {
        self.activeTarget = activeTarget
        self.anchorFrames = anchorFrames
        self.availableWidth = availableWidth
        self.verticalOffset = verticalOffset
        self.edgeInset = edgeInset
        self.tooltipText = tooltipText
    }

    var body: some View {
        if let activeTarget,
            let text = tooltipText(activeTarget),
            let anchorFrame = anchorFrames[activeTarget]
        {
            HoverTooltipBubble(text: text)
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
                    y: verticalOffset
                )
                .onPreferenceChange(HoverTooltipSizePreferenceKey.self) { tooltipSize = $0 }
        }
    }
}
