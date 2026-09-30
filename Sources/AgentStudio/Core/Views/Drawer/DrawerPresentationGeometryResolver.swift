import CoreGraphics
import Foundation

/// Where the drawer presents and which region frames it may use.
///
/// Normal owner frames include the owner's own toolbar at their bottom, so
/// the resolver subtracts it once. Zoom regions already exclude the shared
/// bottom toolbar, so no footer is subtracted.
package enum DrawerPresentationPlacement: Equatable, Sendable {
    case normal(ownerFrame: CGRect, ownerToolbarHeight: CGFloat, liveHeight: CGFloat?)
    case zoom(terminalRegion: CGRect, visibleBridgeRegion: CGRect?)
}

package struct DrawerPresentationGeometryInput: Equatable, Sendable {
    /// Container bounds in the `tabContainer` coordinate space.
    package let containerBounds: CGRect
    package let preference: DrawerPresentationPreference
    package let placement: DrawerPresentationPlacement

    package init(
        containerBounds: CGRect,
        preference: DrawerPresentationPreference,
        placement: DrawerPresentationPlacement
    ) {
        self.containerBounds = containerBounds
        self.preference = preference
        self.placement = placement
    }
}

/// Horizontal insets that shape the connector between the panel and its anchor.
package struct DrawerConnectorInsets: Equatable, Sendable {
    package let junctionLeft: CGFloat
    package let junctionRight: CGFloat
    package let bottomLeft: CGFloat
    package let bottomRight: CGFloat
}

/// Every drawer rectangle for one presentation, in container coordinates.
/// Paint, child layout, and hit/dismissal testing all read this one value.
package struct DrawerPresentationGeometry: Equatable, Sendable {
    package enum Mode: Equatable, Sendable {
        case normal
        case zoom(effectiveSide: DrawerZoomSide)
    }

    package let mode: Mode
    /// Panel plus connector.
    package let outlineFrame: CGRect
    package let panelFrame: CGRect
    package let connectorFrame: CGRect
    /// Rectangle the drawer child layout partitions.
    package let childContentFrame: CGRect
    /// Region that does not dismiss the drawer on click.
    package let dismissalFrame: CGRect
    /// Top-edge resize target. Absent in Pane Zoom, which has no resize input.
    package let resizeHandleFrame: CGRect?
    package let connectorInsets: DrawerConnectorInsets
}

/// Pure drawer rectangle arithmetic for normal and Pane Zoom presentation.
///
/// Owns rectangles only: it creates no state, never requests Bridge, and
/// returns `nil` when the inputs cannot hold a valid drawer so callers keep
/// their existing safe-geometry deferral instead of synthesizing a size.
package enum DrawerPresentationGeometryResolver {
    package static func resolve(_ input: DrawerPresentationGeometryInput) -> DrawerPresentationGeometry? {
        guard isFiniteNonEmpty(input.containerBounds) else { return nil }
        switch input.placement {
        case .normal(let ownerFrame, let ownerToolbarHeight, let liveHeight):
            return resolveNormal(
                containerBounds: input.containerBounds,
                ratio: input.preference.normalHeightRatio,
                ownerFrame: ownerFrame,
                ownerToolbarHeight: ownerToolbarHeight,
                liveHeight: liveHeight
            )
        case .zoom(let terminalRegion, let visibleBridgeRegion):
            return resolveZoom(
                preferredSide: input.preference.zoomSide,
                terminalRegion: terminalRegion,
                visibleBridgeRegion: visibleBridgeRegion
            )
        }
    }

    /// Height range a normal panel may take in a container of this height,
    /// before the owner's physically available space is applied.
    package static func normalPanelHeightBounds(containerHeight: CGFloat) -> ClosedRange<CGFloat> {
        let availableMaximum = containerHeight - DrawerLayout.panelBottomMargin
        let lower = max(
            DrawerLayout.panelMinHeight,
            min(containerHeight * CGFloat(DrawerLayout.heightRatioMin), availableMaximum)
        )
        let upper = max(
            DrawerLayout.panelMinHeight,
            min(containerHeight * CGFloat(DrawerLayout.heightRatioMax), availableMaximum)
        )
        return lower...max(lower, upper)
    }

    /// Terminal and Bridge regions of a Pane Zoom split area.
    ///
    /// `splitArea` already excludes the shared bottom toolbar. Both the live
    /// container and bootstrap derive regions here so they share the split's
    /// divider arithmetic.
    package static func zoomRegions(
        splitArea: CGRect,
        sourceSplitRatio: CGFloat,
        reservesCompanionSpace: Bool,
        isCompanionVisible: Bool
    ) -> (terminal: CGRect, bridge: CGRect?) {
        let regions = SplitViewRegionLayout.regions(
            direction: .horizontal,
            size: splitArea.size,
            split: isCompanionVisible ? sourceSplitRatio : 1,
            reservesDividerSpace: reservesCompanionSpace
        )
        let terminal = regions.left.offsetBy(dx: splitArea.minX, dy: splitArea.minY)
        let bridge = regions.right.offsetBy(dx: splitArea.minX, dy: splitArea.minY)
        return (terminal, isCompanionVisible ? bridge : nil)
    }

    private static func resolveNormal(
        containerBounds: CGRect,
        ratio: Double,
        ownerFrame: CGRect,
        ownerToolbarHeight: CGFloat,
        liveHeight: CGFloat?
    ) -> DrawerPresentationGeometry? {
        guard isFiniteNonEmpty(ownerFrame), ownerToolbarHeight.isFinite, ownerToolbarHeight >= 0 else {
            return nil
        }
        let containerHeight = containerBounds.height
        let requestedHeight: CGFloat =
            if let liveHeight, liveHeight.isFinite {
                liveHeight
            } else {
                containerHeight * CGFloat(ratio)
            }
        let bounds = normalPanelHeightBounds(containerHeight: containerHeight)
        let boundedHeight = min(bounds.upperBound, max(bounds.lowerBound, requestedHeight))

        let connectorHeight = DrawerLayout.overlayConnectorHeight
        let outlineBottom = ownerFrame.maxY - ownerToolbarHeight
        let availablePanelHeight = outlineBottom - containerBounds.minY - connectorHeight
        let panelHeight = min(boundedHeight, availablePanelHeight)

        let panelWidth = containerBounds.width * DrawerLayout.panelWidthRatio
        let halfPanel = panelWidth / 2
        let edgeMargin = DrawerLayout.tabEdgeMargin
        let centerX = max(
            containerBounds.minX + halfPanel + edgeMargin,
            min(containerBounds.maxX - halfPanel - edgeMargin, ownerFrame.midX)
        )
        let outlineFrame = CGRect(
            x: centerX - halfPanel,
            y: outlineBottom - panelHeight - connectorHeight,
            width: panelWidth,
            height: panelHeight + connectorHeight
        )
        return makeGeometry(
            mode: .normal,
            outlineFrame: outlineFrame,
            connectorHeight: connectorHeight,
            connectorAnchor: ownerFrame,
            hasResizeHandle: true
        )
    }

    private static func resolveZoom(
        preferredSide: DrawerZoomSide,
        terminalRegion: CGRect,
        visibleBridgeRegion: CGRect?
    ) -> DrawerPresentationGeometry? {
        let usableBridgeRegion = visibleBridgeRegion.flatMap { isFiniteNonEmpty($0) ? $0 : nil }
        let effectiveSide: DrawerZoomSide = preferredSide == .bridge && usableBridgeRegion != nil ? .bridge : .terminal
        let region: CGRect
        switch effectiveSide {
        case .terminal:
            region = terminalRegion
        case .bridge:
            guard let usableBridgeRegion else { return nil }
            region = usableBridgeRegion
        }
        guard isFiniteNonEmpty(region) else { return nil }

        let outlineWidth = region.width * DrawerLayout.zoomOutlineWidthRatio
        let outlineHeight = region.height * DrawerLayout.zoomOutlineHeightRatio
        let connectorHeight = min(
            DrawerLayout.overlayConnectorHeight,
            max(0, outlineHeight - DrawerLayout.panelMinHeight)
        )
        let outlineFrame = CGRect(
            x: region.midX - outlineWidth / 2,
            y: region.maxY - outlineHeight,
            width: outlineWidth,
            height: outlineHeight
        )
        return makeGeometry(
            mode: .zoom(effectiveSide: effectiveSide),
            outlineFrame: outlineFrame,
            connectorHeight: connectorHeight,
            connectorAnchor: region,
            hasResizeHandle: false
        )
    }

    /// Splits an outline into panel, connector, content, and hit rectangles.
    /// The panel's top band is the resize handle in normal mode and inert
    /// padding of the same thickness in Zoom; content subtracts it once.
    private static func makeGeometry(
        mode: DrawerPresentationGeometry.Mode,
        outlineFrame: CGRect,
        connectorHeight: CGFloat,
        connectorAnchor: CGRect,
        hasResizeHandle: Bool
    ) -> DrawerPresentationGeometry? {
        let panelHeight = outlineFrame.height - connectorHeight
        let panelFrame = CGRect(
            x: outlineFrame.minX,
            y: outlineFrame.minY,
            width: outlineFrame.width,
            height: panelHeight
        )
        let connectorFrame = CGRect(
            x: outlineFrame.minX,
            y: panelFrame.maxY,
            width: outlineFrame.width,
            height: connectorHeight
        )
        let topBand = DrawerLayout.resizeHandleHeight
        let padding = DrawerLayout.panelContentPadding
        let childContentFrame = CGRect(
            x: panelFrame.minX + padding,
            y: panelFrame.minY + topBand,
            width: panelFrame.width - padding * 2,
            height: panelHeight - topBand - padding
        )
        guard isFiniteNonEmpty(childContentFrame) else { return nil }

        let junctionLeft = max(0, connectorAnchor.minX - outlineFrame.minX)
        let junctionRight = max(0, outlineFrame.maxX - connectorAnchor.maxX)
        let anchorInset = connectorAnchor.width / 6
        return DrawerPresentationGeometry(
            mode: mode,
            outlineFrame: outlineFrame,
            panelFrame: panelFrame,
            connectorFrame: connectorFrame,
            childContentFrame: childContentFrame,
            dismissalFrame: outlineFrame,
            resizeHandleFrame: hasResizeHandle
                ? CGRect(x: panelFrame.minX, y: panelFrame.minY, width: panelFrame.width, height: topBand)
                : nil,
            connectorInsets: DrawerConnectorInsets(
                junctionLeft: junctionLeft,
                junctionRight: junctionRight,
                bottomLeft: junctionLeft + anchorInset,
                bottomRight: junctionRight + anchorInset
            )
        )
    }

    private static func isFiniteNonEmpty(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite
            && rect.origin.y.isFinite
            && rect.size.width.isFinite
            && rect.size.height.isFinite
            && rect.size.width > 0
            && rect.size.height > 0
    }
}
