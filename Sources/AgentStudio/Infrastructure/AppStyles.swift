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
}
