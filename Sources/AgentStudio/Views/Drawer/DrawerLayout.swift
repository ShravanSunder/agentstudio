import SwiftUI

/// Shared layout constants for the drawer system.
///
/// Referenced by DrawerPanelOverlay, DrawerPanel, and DrawerIconBar
/// to keep dimensions consistent across the tab-level overlay and
/// pane-level icon bar components.
///
/// **Dependency chain:** DrawerPanelOverlay positions the overlay using
/// `iconBarFrameHeight`, which is derived from icon bar component dimensions.
/// If any icon bar dimension changes, the derived values update automatically.
enum DrawerLayout {

    // MARK: - Panel

    /// Fraction of tab width used for the drawer panel (0–1).
    static let panelWidthRatio: CGFloat = 0.8

    /// Corner radius for the drawer panel and its glass effect shape.
    static let panelCornerRadius: CGFloat = 14

    /// Minimum panel height in points.
    static let panelMinHeight: CGFloat = 100

    /// Margin from tab bottom edge when computing maximum panel height.
    static let panelBottomMargin: CGFloat = 60

    /// Minimum user-adjustable height ratio.
    static let heightRatioMin: Double = 0.2

    /// Maximum user-adjustable height ratio.
    static let heightRatioMax: Double = 0.8

    /// Padding inside the drawer panel around pane content (left, right, bottom).
    /// Matches `resizeHandleHeight` so the border around content is uniform on all sides.
    static let panelContentPadding: CGFloat = resizeHandleHeight

    // MARK: - Connector

    /// Height of the S-curve connector between the panel and pane icon bar.
    static let overlayConnectorHeight: CGFloat = 40

    /// Corner radius for the bottom corners of the connector bar.
    static let connectorBottomCornerRadius: CGFloat = 6

    // MARK: - Icon Bar

    /// Height of the pane-level connector between pane and icon strip.
    /// Set to 0 since the icon bar is now a standalone rounded bar.
    static let connectorHeight: CGFloat = 0

    /// Width and height of icon bar buttons (derived from AppStyle compact size).
    static let iconButtonSize: CGFloat = AppStyle.compactButtonSize

    /// Corner radius for individual icon bar buttons.
    static let iconButtonCornerRadius: CGFloat = AppStyle.buttonCornerRadius

    /// Vertical padding around the icon bar button strip.
    static let iconBarVerticalPadding: CGFloat = AppStyle.barPadding

    /// Horizontal padding around the icon bar button strip.
    static let iconBarHorizontalPadding: CGFloat = AppStyle.barHorizontalPadding

    /// Corner radius for the icon bar background shape.
    static let iconBarCornerRadius: CGFloat = AppStyle.barCornerRadius

    // MARK: - Resize Handle

    /// Height of the draggable resize handle touch target at the top of the panel.
    static let resizeHandleHeight: CGFloat = 8

    /// Width of the resize handle pill indicator.
    static let resizeHandlePillWidth: CGFloat = 40

    /// Height of the resize handle pill indicator.
    static let resizeHandlePillHeight: CGFloat = 4

    // MARK: - Overlay Positioning

    /// Minimum gap between panel edge and tab edge when clamping horizontal position.
    static let tabEdgeMargin: CGFloat = 4

    // MARK: - Derived

    /// Height of the icon strip (buttons + vertical padding).
    /// = `iconButtonSize` + 2 × `iconBarVerticalPadding`
    static let iconStripHeight: CGFloat = iconButtonSize + iconBarVerticalPadding * 2

    /// Total DrawerIconBar VStack height (connector + icon strip).
    static let iconBarTotalHeight: CGFloat = connectorHeight + iconStripHeight

    /// Icon bar height in pane frame coordinates.
    /// Includes TerminalPaneLeaf's pane gap padding since pane frames
    /// are reported after that padding is applied.
    static let iconBarFrameHeight: CGFloat = iconBarTotalHeight + AppStyle.paneGap
}
