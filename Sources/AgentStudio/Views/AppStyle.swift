import SwiftUI

/// App-wide visual style constants.
///
/// Centralizes icon sizes, button dimensions, and spacing so all UI components
/// share a consistent visual hierarchy. Individual components may define
/// additional local constants but should reference these for shared values.
///
/// ## Icon Size Hierarchy
/// ```
/// 18pt  — In-pane controls (minimize, close, split "+")
/// 16pt  — Toolbar actions (edit mode toggle, window controls)
/// 12pt  — Compact bars (tab bar, drawer icon bar, arrangement bar)
/// ```
///
/// ## Button Frame Derivation
/// All standard buttons use the same `iconPadding` so the chrome around
/// icons is visually consistent. Pane controls use a separate larger padding
/// for easier in-pane targeting.
/// ```
/// compact:  12 + 2×6 = 24pt frame
/// toolbar:  16 + 2×6 = 28pt frame
/// pane:     18 + 2×8 = 34pt frame  (larger hit target over content)
/// ```
enum AppStyle {

    // MARK: - Icon Sizes

    /// Icons in compact bars: tab bar, drawer icon bar, arrangement bar.
    static let compactIconSize: CGFloat = 12

    /// Icons in the main toolbar: edit mode toggle, window-level actions.
    static let toolbarIconSize: CGFloat = 16

    /// Icons for in-pane controls: minimize, close, split "+".
    static let paneControlIconSize: CGFloat = 18

    // MARK: - Icon Padding

    /// Standard padding around icons in buttons (same for compact and toolbar).
    /// Button frame = icon size + 2 × iconPadding.
    static let iconPadding: CGFloat = 6

    /// Padding around pane control icons (larger for in-pane hit targets).
    static let paneControlIconPadding: CGFloat = 8

    // MARK: - Button Frames (Derived)

    /// Frame for compact bar buttons: compactIconSize + 2 × iconPadding.
    static let compactButtonSize: CGFloat = compactIconSize + iconPadding * 2

    /// Frame for toolbar buttons: toolbarIconSize + 2 × iconPadding.
    static let toolbarButtonSize: CGFloat = toolbarIconSize + iconPadding * 2

    /// Frame for in-pane control buttons: paneControlIconSize + 2 × paneControlIconPadding.
    static let paneControlButtonSize: CGFloat = paneControlIconSize + paneControlIconPadding * 2

    // MARK: - Fill Opacities (white overlays on dark backgrounds)
    //
    // Five-step scale for interactive surfaces. Components pick the steps
    // that match their state (resting, hover, active). Using `Color.white`
    // at these opacities keeps the palette neutral and theme-independent.
    //
    // ```
    // subtle   0.04 — barely visible resting state (inactive tabs)
    // muted    0.06 — gentle resting state (standalone icon buttons)
    // hover    0.08 — standard hover feedback
    // pressed  0.10 — emphasized hover / pressed feedback
    // active   0.12 — selected / active state (active tab, toggled-on)
    // ```

    /// Barely visible surface — inactive tabs, deemphasized elements.
    static let fillSubtle: CGFloat = 0.04

    /// Gentle resting state — standalone icon buttons at rest.
    static let fillMuted: CGFloat = 0.06

    /// Standard hover feedback.
    static let fillHover: CGFloat = 0.08

    /// Emphasized hover or pressed state.
    static let fillPressed: CGFloat = 0.10

    /// Selected / active state — active tab, toggled-on controls.
    static let fillActive: CGFloat = 0.12

    // MARK: - Corner Radii

    /// Standard corner radius for bar backgrounds (icon bars, chip groups).
    static let barCornerRadius: CGFloat = 6

    /// Standard corner radius for individual buttons within bars.
    static let buttonCornerRadius: CGFloat = 4

    /// Standard corner radius for panel containers (drawer panel, popovers).
    static let panelCornerRadius: CGFloat = 8

    /// Corner radius for pill-shaped elements (tabs, capsule buttons).
    static let pillCornerRadius: CGFloat = 12

    // MARK: - Spacing

    /// Standard vertical padding around bar contents.
    static let barPadding: CGFloat = 4

    /// Standard horizontal padding for bar contents.
    static let barHorizontalPadding: CGFloat = 6
}
