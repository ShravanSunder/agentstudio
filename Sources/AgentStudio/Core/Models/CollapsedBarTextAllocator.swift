import AppKit
import CoreGraphics
import Foundation

struct CollapsedBarTextAllocator {
    static let segmentSpacing: CGFloat = AppStyle.spacingStandard

    static func allocatedTextWidths(
        for parts: [CollapsedBarLabelPart],
        availableLabelWidth: CGFloat
    ) -> [CGFloat] {
        guard !parts.isEmpty else { return [] }

        let separatorCount = max(parts.count - 1, 0)
        let fixedWidth =
            CGFloat(parts.count) * iconWidth
            + CGFloat(separatorCount) * separatorWidth
            + CGFloat(max(parts.count * 3 - 2, 0)) * segmentSpacing
        let availableTextWidth = max(availableLabelWidth - fixedWidth, 0)

        let intrinsicWidths = parts.map(intrinsicTextWidth(for:))
        let intrinsicTotal = intrinsicWidths.reduce(0, +)
        guard intrinsicTotal > availableTextWidth else { return intrinsicWidths }

        var allocatedWidths = Array(repeating: CGFloat.zero, count: parts.count)
        var unresolved = Set(parts.indices)
        var remainingWidth = availableTextWidth

        while !unresolved.isEmpty {
            let equalShare = remainingWidth / CGFloat(unresolved.count)
            let fitting = unresolved.filter { intrinsicWidths[$0] <= equalShare }

            guard !fitting.isEmpty else {
                for index in unresolved {
                    allocatedWidths[index] = max(equalShare, 0)
                }
                break
            }

            for index in fitting {
                allocatedWidths[index] = intrinsicWidths[index]
                remainingWidth -= intrinsicWidths[index]
                unresolved.remove(index)
            }
        }

        return allocatedWidths
    }

    private static var iconWidth: CGFloat {
        AppStyle.textBase
    }

    private static var separatorWidth: CGFloat {
        measuredWidth(
            for: "·",
            font: .systemFont(ofSize: AppStyle.textSm, weight: .regular)
        )
    }

    private static func intrinsicTextWidth(for part: CollapsedBarLabelPart) -> CGFloat {
        measuredWidth(
            for: part.text,
            font: .systemFont(ofSize: AppStyle.textBase, weight: fontWeight(for: part.weight))
        )
    }

    private static func measuredWidth(for text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func fontWeight(for weight: CollapsedBarLabelPart.TextWeight) -> NSFont.Weight {
        switch weight {
        case .semibold:
            .semibold
        case .regular:
            .regular
        }
    }
}
