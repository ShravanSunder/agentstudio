import CoreGraphics
import Foundation
import SwiftUI

enum DrawerDropZone: String, Equatable, CaseIterable {
    case left
    case right
    case top
    case bottom

    static func calculate(at point: CGPoint, in size: CGSize) -> Self {
        guard size.width > 0, size.height > 0 else { return .right }

        let distances: [(Self, CGFloat)] = [
            (.left, point.x),
            (.right, size.width - point.x),
            (.top, size.height - point.y),
            (.bottom, point.y),
        ]

        return distances.min { lhs, rhs in
            if lhs.1 != rhs.1 {
                return lhs.1 < rhs.1
            }
            return lhs.0.rawValue < rhs.0.rawValue
        }?.0 ?? .right
    }

    var newDirection: SplitNewDirection {
        switch self {
        case .left:
            return .left
        case .right:
            return .right
        case .top:
            return .up
        case .bottom:
            return .down
        }
    }

    func overlayRect(in paneFrame: CGRect) -> CGRect {
        let inset: CGFloat = 4
        let availableWidth = max(paneFrame.width - (inset * 2), 1)
        let availableHeight = max(paneFrame.height - (inset * 2), 1)
        let minimumPreviewWidth = max(
            AppStyles.General.Layout.dropTargetPreviewMinimumWidth,
            AppStyles.General.Layout.splitMinimumPaneSize + (AppStyles.General.Layout.paneGap * 2)
        )
        let minimumPreviewHeight = max(
            AppStyles.General.Layout.dropTargetPreviewMinimumWidth,
            AppStyles.General.Layout.splitMinimumPaneSize + (AppStyles.General.Layout.paneGap * 2)
        )
        let fractionalPreviewWidth = paneFrame.width * AppStyles.General.Layout.dropTargetPreviewMaxFraction
        let fractionalPreviewHeight = paneFrame.height * AppStyles.General.Layout.dropTargetPreviewMaxFraction
        let previewWidth = min(max(minimumPreviewWidth, fractionalPreviewWidth), availableWidth)
        let previewHeight = min(max(minimumPreviewHeight, fractionalPreviewHeight), availableHeight)

        switch self {
        case .left:
            return CGRect(
                x: paneFrame.minX + inset,
                y: paneFrame.minY + inset,
                width: previewWidth,
                height: availableHeight
            )
        case .right:
            return CGRect(
                x: paneFrame.maxX - inset - previewWidth,
                y: paneFrame.minY + inset,
                width: previewWidth,
                height: availableHeight
            )
        case .top:
            return CGRect(
                x: paneFrame.minX + inset,
                y: paneFrame.maxY - inset - previewHeight,
                width: availableWidth,
                height: previewHeight
            )
        case .bottom:
            return CGRect(
                x: paneFrame.minX + inset,
                y: paneFrame.minY + inset,
                width: availableWidth,
                height: previewHeight
            )
        }
    }

    func markerRect(in paneFrame: CGRect) -> CGRect {
        let previewRect = overlayRect(in: paneFrame)
        let markerThickness = AppStyles.General.Layout.dropTargetMarkerWidth

        switch self {
        case .left:
            return CGRect(
                x: previewRect.minX,
                y: previewRect.minY,
                width: min(markerThickness, previewRect.width),
                height: previewRect.height
            )
        case .right:
            return CGRect(
                x: previewRect.maxX - min(markerThickness, previewRect.width),
                y: previewRect.minY,
                width: min(markerThickness, previewRect.width),
                height: previewRect.height
            )
        case .top:
            return CGRect(
                x: previewRect.minX,
                y: previewRect.maxY - min(markerThickness, previewRect.height),
                width: previewRect.width,
                height: min(markerThickness, previewRect.height)
            )
        case .bottom:
            return CGRect(
                x: previewRect.minX,
                y: previewRect.minY,
                width: previewRect.width,
                height: min(markerThickness, previewRect.height)
            )
        }
    }
}
