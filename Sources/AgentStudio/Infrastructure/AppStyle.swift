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
    static let pillCornerRadius: CGFloat = 14

    // MARK: - Spacing
    //
    // Three-tier scale used for padding and gaps. Components pick the tier
    // that matches their context: tight for element-to-element gaps, standard
    // for content inset inside interactive elements, loose for container edges.
    //
    // ```
    // tight      4pt — between sibling elements (tab-to-tab, button-to-button)
    // standard   6pt — content inset inside interactive elements (pills, bars)
    // loose      8pt — container / section boundaries
    // ```

    /// Tight spacing: gaps between sibling elements.
    static let spacingTight: CGFloat = 4

    /// Standard spacing: content inset inside interactive elements.
    static let spacingStandard: CGFloat = 6

    /// Loose spacing: container and section boundary padding.
    static let spacingLoose: CGFloat = 8

    // Legacy aliases — prefer the spacing* names above.
    static let barPadding: CGFloat = spacingTight
    static let barHorizontalPadding: CGFloat = spacingStandard

    // MARK: - Font Sizes
    //
    // Five-step scale for system font sizes. Components pick the step
    // that matches their text hierarchy: caption for tiny labels,
    // body for standard content.
    //
    // ```
    // caption     9pt — close buttons, tiny labels
    // small      10pt — compact labels, badge counts, zoom badge
    // secondary  11pt — secondary text, collapsed bar titles
    // body       12pt — tab titles, main body text
    // primary    13pt — command bar input, prominent text
    // ```

    /// Tiny labels: close buttons, minimal annotations.
    static let fontCaption: CGFloat = 9

    /// Compact labels: badge counts, zoom indicators, arrangement labels.
    static let fontSmall: CGFloat = 10

    /// Secondary text: collapsed bar titles, arrangement panel text.
    static let fontSecondary: CGFloat = 11

    /// Standard body text: tab titles, empty state text.
    static let fontBody: CGFloat = 12

    /// Prominent text: command bar input, search fields.
    static let fontPrimary: CGFloat = 13

    // MARK: - Foreground Opacities (text & icon overlays)
    //
    // Three-step scale for text and icon foreground colors on dark backgrounds.
    // Separate from the fill* surface scale — these apply to `.foregroundStyle`
    // and icon tints where `.secondary` / `.tertiary` semantic colors are
    // too coarse-grained.
    //
    // ```
    // dim        0.5 — menu icons, secondary controls
    // muted      0.6 — pane control icons, de-emphasized actions
    // secondary  0.7 — expand arrows, collapsed bar text, zoom badge
    // ```

    /// Dim foreground: menu icons, de-emphasized secondary controls.
    static let foregroundDim: CGFloat = 0.5

    /// Muted foreground: pane control icons, in-pane action icons.
    static let foregroundMuted: CGFloat = 0.6

    /// Secondary foreground: expand arrows, collapsed bar text, zoom badge.
    static let foregroundSecondary: CGFloat = 0.7

    // MARK: - Stroke Opacities (borders & outlines)
    //
    // Four-step scale for border and outline opacities on dark backgrounds.
    // Used with `Color.white.opacity(...)` for theme-neutral borders.
    //
    // ```
    // subtle    0.10 — resting borders (collapsed pane bars)
    // muted     0.15 — gentle borders (arrangement panel, pane dimming)
    // hover     0.20 — hover feedback borders
    // visible   0.25 — prominent borders (active hover, pane leaf borders)
    // ```

    /// Resting border: collapsed pane bars at rest.
    static let strokeSubtle: CGFloat = 0.10

    /// Gentle border: arrangement panel borders, pane dimming.
    static let strokeMuted: CGFloat = 0.15

    /// Hover border feedback.
    static let strokeHover: CGFloat = 0.20

    /// Prominent border: active hover states, pane leaf borders.
    static let strokeVisible: CGFloat = 0.25

    // MARK: - Animation Durations
    //
    // Two-step scale for transition and hover animations.
    //
    // ```
    // fast       0.12s — hover feedback, icon bar transitions
    // standard   0.20s — tab scroll, general transitions
    // ```

    /// Fast animation: hover feedback, icon bar transitions.
    static let animationFast: Double = 0.12

    /// Standard animation: tab scroll, general transitions.
    static let animationStandard: Double = 0.20

    // MARK: - Mask

    /// Standard gradient width for text fade masks (clear ↔ opaque transition).
    static let maskFadeWidth: CGFloat = 14

    // MARK: - Layout

    /// Tab bar height in points.
    static let tabBarHeight: CGFloat = 36

    /// Inter-pane gap (padding around each pane leaf).
    static let paneGap: CGFloat = 2
}
