import SwiftUI

/// App-wide visual style constants.
///
/// Centralizes icon sizes, button dimensions, and spacing so all UI components
/// share a consistent visual hierarchy. Individual components may define
/// additional local constants but should reference these for shared values.
///
/// ## Icon Size Hierarchy
/// ```
/// 22pt  — Pane action buttons (minimize, close)
/// 16pt  — Toolbar actions (management mode toggle, window controls)
/// 14pt  — Split "+" half-moon button
/// 12pt  — Compact bars (tab bar, drawer icon bar, arrangement bar)
/// ```
///
/// ## Button Frame Derivation
/// All standard buttons use the same `iconPadding` so the chrome around
/// icons is visually consistent. Pane controls use a separate larger padding
/// for easier in-pane targeting.
/// ```
/// compact:     12 + 2×6 = 24pt frame
/// toolbar:     16 + 2×6 = 28pt frame
/// paneSplit:   14 + 2×8 = 30pt frame  (half-moon "+")
/// paneAction:  22 + 2×8 = 38pt frame  (minimize, close)
/// ```
enum AppStyle {

    // MARK: - Icon Sizes

    /// Icons in compact bars: tab bar, drawer icon bar, arrangement bar.
    static let compactIconSize: CGFloat = 12

    /// Icons in the main toolbar: management mode toggle, window-level actions.
    static let toolbarIconSize: CGFloat = 16

    /// Icons for pane action buttons: minimize (−), close (×).
    /// Larger than the split button for easy targeting.
    static let paneActionIconSize: CGFloat = 22

    /// Icon for the split "+" half-moon button (top-right of pane).
    static let paneSplitIconSize: CGFloat = 14

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

    /// Frame for pane action buttons (minimize, close): paneActionIconSize + 2 × paneControlIconPadding.
    static let paneActionButtonSize: CGFloat = paneActionIconSize + paneControlIconPadding * 2

    /// Frame for the split half-moon button: paneSplitIconSize + 2 × paneControlIconPadding.
    static let paneSplitButtonSize: CGFloat = paneSplitIconSize + paneControlIconPadding * 2

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

    // MARK: - Sidebar Metrics

    /// Vertical gap between a repo group header and its first checkout row.
    static let sidebarGroupChildrenSpacing: CGFloat = 2

    /// Internal vertical spacing between checkout title and chip row.
    static let sidebarRowContentSpacing: CGFloat = 4

    /// Vertical inset around each checkout row container.
    static let sidebarRowVerticalInset: CGFloat = 6

    /// Reduces default DisclosureGroup child indentation to keep tree rows tighter.
    static let sidebarGroupChildLeadingReduction: CGFloat = 10

    /// Leading inset used for sidebar list rows.
    static let sidebarListRowLeadingInset: CGFloat = 2

    /// Group (repo) icon size in sidebar rows.
    static let sidebarGroupIconSize: CGFloat = 14

    /// Shared icon column width for checkout/branch rows so text alignment is consistent.
    static let sidebarRowLeadingIconColumnWidth: CGFloat = textBase

    /// Font size for organization text in sidebar group titles.
    static let sidebarGroupOrganizationFontSize: CGFloat = textSm

    /// Spacing between repo title and organization title in sidebar group rows.
    static let sidebarGroupTitleSpacing: CGFloat = spacingTight

    /// Max width for organization text so repo and org truncate independently.
    static let sidebarGroupOrganizationMaxWidth: CGFloat = 120

    /// Worktree icon size in sidebar rows.
    static let sidebarWorktreeIconSize: CGFloat = 11

    /// Branch icon size in the checkout branch row.
    static let sidebarBranchIconSize: CGFloat = 10

    /// Leading inset for status chips so they align with checkout/branch text after the leading icon.
    static let sidebarStatusRowLeadingIndent: CGFloat = sidebarRowLeadingIconColumnWidth + spacingTight

    /// Font size for the branch name row under each checkout title.
    static let sidebarBranchFontSize: CGFloat = textSm

    /// Vertical padding for sidebar group rows.
    static let sidebarGroupRowVerticalPadding: CGFloat = 2

    /// Horizontal padding for sidebar group checkout-count badges.
    static let sidebarCountBadgeHorizontalPadding: CGFloat = 6

    /// Vertical padding for sidebar group checkout-count badges.
    static let sidebarCountBadgeVerticalPadding: CGFloat = 2

    /// Background opacity for sidebar group checkout-count badges.
    static let sidebarCountBadgeBackgroundOpacity: CGFloat = 0.15

    /// Horizontal spacing between chips in checkout rows.
    static let sidebarChipRowSpacing: CGFloat = 4

    /// Spacing between icon and text inside a chip.
    static let sidebarChipContentSpacing: CGFloat = 2

    /// Internal spacing between direction cluster icon and count in sync chip.
    static let sidebarSyncClusterSpacing: CGFloat = 1

    /// Horizontal padding for chips with icon + text.
    static let sidebarChipHorizontalPadding: CGFloat = 4

    /// Horizontal padding for icon-only chips.
    static let sidebarChipIconOnlyHorizontalPadding: CGFloat = 3

    /// Vertical padding for chips.
    static let sidebarChipVerticalPadding: CGFloat = 2

    /// Font size for compact sidebar chips.
    static let sidebarChipFontSize: CGFloat = textXs

    /// Icon size used in standard sidebar chips.
    static let sidebarChipIconSize: CGFloat = 8

    /// Icon size used in the compact sync chip.
    static let sidebarSyncChipIconSize: CGFloat = 7

    /// Chip background opacity for sidebar pills.
    static let sidebarChipBackgroundOpacity: CGFloat = fillHover

    /// Chip border opacity for sidebar pills.
    static let sidebarChipBorderOpacity: CGFloat = fillMuted

    /// Foreground opacity for sidebar chip labels/icons to keep chips visually muted.
    static let sidebarChipForegroundOpacity: CGFloat = 0.82

    /// Dark overlay opacity applied on top of chip fills to reduce color intensity.
    static let sidebarChipMuteOverlayOpacity: CGFloat = 0.16

    /// Hover fill opacity for sidebar checkout rows.
    static let sidebarRowHoverOpacity: CGFloat = fillPressed

    // Legacy aliases — prefer the spacing* names above.
    static let barPadding: CGFloat = spacingTight
    static let barHorizontalPadding: CGFloat = spacingStandard

    // MARK: - Typography
    //
    // Tailwind-style text scale for app typography tokens.
    // We use these as a single source of truth across views:
    // text-xs, text-sm, text-base, text-lg, text-xl.
    //
    // Dynamic text roadmap:
    // These are currently fixed point sizes. We will migrate these tokens
    // to Dynamic Type-aware semantics (SwiftUI text styles) in AppStyle
    // so scaling behavior can be enabled app-wide from one layer.

    /// Tailwind `text-xs`
    static let textXs: CGFloat = 11

    /// Tailwind `text-sm`
    static let textSm: CGFloat = 12

    /// Tailwind `text-base`
    static let textBase: CGFloat = 13

    /// Tailwind `text-lg`
    static let textLg: CGFloat = 14

    /// Tailwind `text-xl`
    static let textXl: CGFloat = 16

    /// Tailwind `text-2xl` for section/empty-state emphasis.
    static let text2xl: CGFloat = 24

    /// Tailwind `text-5xl` for large status overlays.
    static let text5xl: CGFloat = 48

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

    /// Management mode dimming overlay on pane content.
    static let managementModeDimming: CGFloat = 0.35

    /// Fill opacity for management mode control backgrounds (action circles, half-moon, drag handle).
    /// Darker than the dimming overlay so controls stand out against the dimmed pane content.
    static let managementControlFill: CGFloat = 0.60

    /// Hover delta added to managementControlFill for interactive feedback.
    static let managementControlHoverDelta: CGFloat = 0.05

    // MARK: - Management Mode Controls
    //
    // Sizes for the four management mode control elements. Each element has
    // its own natural shape; these constants set visually harmonious proportions
    // while allowing independent customization.
    //
    // ```
    // action circles:   28pt circle, 13pt icon  (minimize, close)
    // split half-moon:  30×42pt pill, 14pt icon  (reuses paneSplitButtonSize/paneSplitIconSize)
    // drag handle:      60×100pt pill, 16pt icon (reuses toolbarIconSize)
    // ```

    /// Diameter of management mode action circles (minimize, close).
    static let managementActionSize: CGFloat = 28

    /// Icon font size inside management mode action circles.
    static let managementActionIconSize: CGFloat = 13

    /// Drag handle pill width.
    static let managementDragHandleWidth: CGFloat = 60

    /// Drag handle pill height.
    static let managementDragHandleHeight: CGFloat = 100

    /// Drag handle corner radius.
    static let managementDragHandleCornerRadius: CGFloat = 20

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

    /// Minimum pane size enforced while dragging split dividers.
    static let splitMinimumPaneSize: CGFloat = 10

    /// Width of the edge insertion marker shown while dragging panes.
    static let dropTargetMarkerWidth: CGFloat = 8

    /// Minimum preview width for split insertion affordance.
    static let dropTargetPreviewMinimumWidth: CGFloat = 34

    /// Maximum preview width as a fraction of the destination pane width.
    static let dropTargetPreviewMaxFraction: CGFloat = 0.22
}
