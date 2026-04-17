import SwiftUI

enum AppStyles {
    enum General {
        enum Icon {
            static let compact: CGFloat = 12
            static let toolbar: CGFloat = 16
            static let paneAction: CGFloat = 22
            static let paneSplit: CGFloat = 14
        }

        enum Padding {
            static let icon: CGFloat = 6
            static let paneControl: CGFloat = 8
        }

        enum Button {
            static let compact: CGFloat = Icon.compact + (Padding.icon * 2)
            static let toolbar: CGFloat = Icon.toolbar + (Padding.icon * 2)
            static let paneAction: CGFloat = Icon.paneAction + (Padding.paneControl * 2)
            static let paneSplit: CGFloat = Icon.paneSplit + (Padding.paneControl * 2)
        }

        enum Fill {
            static let subtle: CGFloat = 0.04
            static let muted: CGFloat = 0.06
            static let hover: CGFloat = 0.08
            static let pressed: CGFloat = 0.10
            static let active: CGFloat = 0.12
        }

        enum CornerRadius {
            static let bar: CGFloat = 6
            static let button: CGFloat = 4
            static let panel: CGFloat = 8
            static let pill: CGFloat = 14
        }

        enum Spacing {
            static let tight: CGFloat = 4
            static let standard: CGFloat = 6
            static let loose: CGFloat = 8
        }

        enum Typography {
            static let textXs: CGFloat = 11
            static let textSm: CGFloat = 12
            static let textBase: CGFloat = 13
            static let textLg: CGFloat = 14
            static let textXl: CGFloat = 16
            static let text2xl: CGFloat = 24
            static let text5xl: CGFloat = 48
        }

        enum Foreground {
            static let dim: CGFloat = 0.5
            static let muted: CGFloat = 0.6
            static let secondary: CGFloat = 0.7
        }

        enum Stroke {
            static let subtle: CGFloat = 0.10
            static let muted: CGFloat = 0.15
            static let hover: CGFloat = 0.20
            static let visible: CGFloat = 0.25
        }

        enum Animation {
            static let fast: Double = 0.12
            static let standard: Double = 0.20
        }

        enum Layout {
            static let paneGap: CGFloat = 1
            static let splitMinimumPaneSize: CGFloat = 10
            static let dropTargetMarkerWidth: CGFloat = 8
            static let dropTargetPreviewMinimumWidth: CGFloat = 34
            static let dropTargetPreviewMaxFraction: CGFloat = 0.22
        }
    }

    enum Shell {
        enum Sidebar {
            static let rowContentSpacing: CGFloat = 4
            static let rowVerticalInset: CGFloat = 6
            static let listRowLeadingInset: CGFloat = 2
            static let groupIconSize: CGFloat = 14
            static let rowLeadingIconColumnWidth: CGFloat = AppStyles.General.Typography.textBase
            static let groupOrganizationFontSize: CGFloat = AppStyles.General.Typography.textSm
            static let groupTitleSpacing: CGFloat = AppStyles.General.Spacing.tight
            static let groupOrganizationMaxWidth: CGFloat = 120
            static let worktreeIconSize: CGFloat = 11
            static let branchIconSize: CGFloat = 10
            static let branchFontSize: CGFloat = AppStyles.General.Typography.textSm
            static let groupRowVerticalPadding: CGFloat = 2
            static let countBadgeHorizontalPadding: CGFloat = 6
            static let countBadgeVerticalPadding: CGFloat = 2
            static let countBadgeBackgroundOpacity: CGFloat = 0.15
            static let chipRowSpacing: CGFloat = 4
            static let chipContentSpacing: CGFloat = 2
            static let syncClusterSpacing: CGFloat = 1
            static let chipHorizontalPadding: CGFloat = 4
            static let chipIconOnlyHorizontalPadding: CGFloat = 3
            static let chipVerticalPadding: CGFloat = 2
            static let chipFontSize: CGFloat = AppStyles.General.Typography.textXs
            static let chipIconSize: CGFloat = 8
            static let syncChipIconSize: CGFloat = 7
            static let chipBackgroundOpacity: CGFloat = AppStyles.General.Fill.hover
            static let chipBorderOpacity: CGFloat = AppStyles.General.Fill.muted
            static let chipForegroundOpacity: CGFloat = 0.82
            static let chipMuteOverlayOpacity: CGFloat = 0.16
            static let rowHoverOpacity: CGFloat = AppStyles.General.Fill.pressed

            static let groupChildRowLeadingInset: CGFloat =
                listRowLeadingInset
                + AppStyles.General.Typography.textBase
                + AppStyles.General.Spacing.tight

            static let statusRowLeadingIndent: CGFloat = rowLeadingIconColumnWidth + AppStyles.General.Spacing.tight

            static let chipInfoColor = Color(red: 0.47, green: 0.69, blue: 0.96)
            static let chipSuccessColor = Color(red: 0.42, green: 0.84, blue: 0.50)
            static let chipWarningColor = Color(red: 0.93, green: 0.71, blue: 0.34)
            static let chipDangerColor = Color(red: 0.93, green: 0.41, blue: 0.41)

            static let accentPaletteHexes: [String] = [
                "#F5C451",
                "#58C4FF",
                "#A78BFA",
                "#4ADE80",
                "#FB923C",
                "#F472B6",
            ]
        }

        enum TabBar {
            static let height: CGFloat = 36
            static let titlebarBackground = NSColor(white: 0.12, alpha: 1.0)
        }

        enum PaneChrome {
            static let inactivePaneDimmingOpacity: CGFloat = 0.30
            static let inactivePaneDimmingDepth: CGFloat = 120
            static let paneSplitIconSize: CGFloat = AppStyles.General.Icon.paneSplit
            static let paneSplitButtonSize: CGFloat = AppStyles.General.Button.paneSplit
            static let maskFadeWidth: CGFloat = 14
            static let background = Color(nsColor: NSColor(white: 0.09, alpha: 1.0))
        }

        enum ManagementLayer {
            static let modeDimmingOpacity: CGFloat = 0.35
            static let controlFillOpacity: CGFloat = 0.70
            static let controlHoverDelta: CGFloat = 0.05
            static let actionSize: CGFloat = 28
            static let actionIconSize: CGFloat = 13
            static let dragHandleWidth: CGFloat = 60
            static let dragHandleHeight: CGFloat = 100
            static let dragHandleCornerRadius: CGFloat = 20
        }
    }

    enum WorkspaceFocus {
        enum Terminal {
            static let startupOverlayPadding: CGFloat = 28
            static let startupOverlaySpacing: CGFloat = 16
            static let errorOverlayCornerRadius: CGFloat = 12
            static let errorOverlayContentPadding: CGFloat = 32
            static let errorOverlayContentSpacing: CGFloat = 24
            static let errorOverlaySectionSpacing: CGFloat = 16
            static let errorOverlayActionTopPadding: CGFloat = 8
        }

        enum Webview {
            static let navigationBarHorizontalPadding: CGFloat = 8
            static let navigationBarHeight: CGFloat = 36
            static let navigationControlsSpacing: CGFloat = 8
            static let navigationFieldHorizontalPadding: CGFloat = 8
            static let navigationFieldVerticalPadding: CGFloat = 4
            static let navigationFieldCornerRadius: CGFloat = 6
        }

        enum Bridge {}

        enum CodeViewer {}
    }

    enum CommandBar {
        enum Panel {
            static let cornerRadius: CGFloat = 12
            static let horizontalPadding: CGFloat = 12
            static let nestedDividerOpacity: Double = 0.3
            static let rootDividerOpacity: Double = 0.15
        }

        enum Rows {
            static let iconSpacing: CGFloat = 10
            static let iconSize: CGFloat = 16
            static let worktreeOpenIndicatorSize: CGFloat = 6
            static let rowHeight: CGFloat = 36
            static let shortcutSpacing: CGFloat = 4
            static let chevronOpacity: Double = 0.3
            static let selectedRowCornerRadius: CGFloat = 6
            static let horizontalPadding: CGFloat = 12
            static let selectedRowHorizontalInset: CGFloat = 4
        }

        enum Footer {
            static let primaryOpacity: Double = 0.40
            static let secondaryOpacity: Double = 0.25
            static let separatorOpacity: Double = 0.15
            static let rowHeight: CGFloat = 16
            static let separatorHorizontalPadding: CGFloat = 6
            static let rowSpacing: CGFloat = 6
            static let bottomRowSpacing: CGFloat = 14
            static let hintSpacing: CGFloat = 4
            static let topPadding: CGFloat = 6
            static let bottomPadding: CGFloat = 8
            static let horizontalPadding: CGFloat = 12
        }
    }

    enum Welcome {
        static let pageHorizontalPadding: CGFloat = 56
        static let pageVerticalPadding: CGFloat = 48
        static let contentColumnsGap: CGFloat = 72
        static let headerMaxWidth: CGFloat = 720
        static let headerToContentGap: CGFloat = 40

        static let titleFontSize: CGFloat = 30
        static let bodyFontSize: CGFloat = AppStyles.General.Typography.textXl
        static let titleBodyGap: CGFloat = 8

        // Still used by QuickActionsCallout (scanning/scanEmpty states only)
        static let shortcutKeyFontSize: CGFloat = 18
        static let shortcutKeyColumnWidth: CGFloat = 44

        static let sectionSpacing: CGFloat = 32
        static let teachingColumnWidth: CGFloat = 520
        static let recentsColumnWidth: CGFloat = 540

        static let recentCardMinWidth: CGFloat = 260
        static let recentCardGap: CGFloat = 20
        static let recentsColumnCount = 2

        static let previewWidth: CGFloat = 500
        static let previewCornerRadius: CGFloat = 16
        static let previewStatusRowHeight: CGFloat = 28
        static let previewSearchRowHeight: CGFloat = 44
        static let previewResultRowHeight: CGFloat = 36
        static let previewFooterHeight: CGFloat = 28

        static let cardFillOpacity: CGFloat = AppStyles.General.Fill.muted
        static let cardStrokeOpacity: CGFloat = AppStyles.General.Fill.active
        static let cardHoverOpacity: CGFloat = AppStyles.Shell.Sidebar.rowHoverOpacity
        static let interactiveHoverOpacity: CGFloat = AppStyles.General.Fill.hover

        // Responsive breakpoints
        static let launcherWideBreakpoint: CGFloat = 1400
        static let launcherNarrowBreakpoint: CGFloat = 900
        static let recentsColumnCountWide: Int = 3
        static let recentsColumnCountNarrow: Int = 1

        // MARK: - Typographic scale (semantic)
        //
        // Rules:
        //   - h1 appears exactly once per screen (page title).
        //   - h2 appears only when there are ≥2 sections to label.
        //   - h3 is for item/row titles.
        //   - body is page copy; bodySm is row subtitle.
        //   - caption is metadata (chips, footnotes).
        //   - key is keyboard-shortcut glyphs, monospaced and accent-colored.

        enum Typography {
            static let h1: Font = .system(size: 30, weight: .semibold)
            static let h2: Font = .system(size: 15, weight: .semibold)
            static let h3: Font = .system(size: 13, weight: .medium)
            static let body: Font = .system(size: 16)
            static let bodySm: Font = .system(size: 12)
            static let caption: Font = .system(size: 11)
            static let key: Font = .system(size: 13, weight: .semibold, design: .monospaced)
        }

        enum TextColor {
            static let h2Opacity: CGFloat = 0.62
            static let h3Opacity: CGFloat = 0.88
        }

        // Launcher composition (new — supersedes hero/scope geometry)
        // Welcome 2 is a top-aligned page, not a centered splash. Comfortable
        // top padding puts the header below the toolbar without floating.
        //
        // The shortcuts block mirrors Welcome 1: cmd-P chrome on the left
        // (the "real artifact" illustration), ⌘ shortcut rows on the right
        // (the "action column"). ContentMaxWidth accommodates both side-by-side:
        //   previewWidth (500) + columnsGap (40) + shortcuts column (≥320)
        static let launcherContentMaxWidth: CGFloat = 900
        static let launcherPageTopPadding: CGFloat = 72
        static let launcherRowGap: CGFloat = 20
        static let launcherSectionGap: CGFloat = 28
        static let launcherShortcutsColumnsGap: CGFloat = 40
        static let launcherDividerOpacity: CGFloat =
            AppStyles.CommandBar.Panel.nestedDividerOpacity
        static let launcherShortcutKeyColumnWidth: CGFloat = 32
        static let launcherShortcutKeyTitleGap: CGFloat = 12
        static let launcherPreviewSubtitleOpacity: CGFloat = 0.50

        // Embedded cmd-P preview — mirrors the real modal with mock data
        // (five worktrees matching WelcomeSidebarIllustration). Height must
        // fit 3 group headers (~23pt) + 5 result rows (36pt) + internal padding
        // with a small margin for breathing room.
        static let previewResultsHeight: CGFloat = 264
        static let launcherPreviewCalloutGap: CGFloat = 12
        static let scopesCalloutItemGap: CGFloat = 20

        // Shortcut rows in the right column get the same faint-outlined card
        // chrome as the preview + scopes callout, so they read as clickable.
        static let launcherShortcutRowCornerRadius: CGFloat = 10
        static let launcherShortcutRowHorizontalPadding: CGFloat = 16
        static let launcherShortcutRowVerticalPadding: CGFloat = 12
    }
}
