import AgentStudioInfrastructure
import SwiftUI

package struct SidebarChip: View {
    package enum Icon: Equatable {
        case octicon(String)
        case system(SystemSymbol)
    }

    package enum Style {
        case neutral
        case info
        case success
        case warning
        case danger
        case accent(Color)

        var foreground: Color {
            switch self {
            case .neutral: return .secondary
            case .info: return AppStyles.Shell.Sidebar.chipInfoColor
            case .success: return AppStyles.Shell.Sidebar.chipSuccessColor
            case .warning: return AppStyles.Shell.Sidebar.chipWarningColor
            case .danger: return AppStyles.Shell.Sidebar.chipDangerColor
            case .accent(let color): return color
            }
        }
    }

    let icon: Icon
    let octiconLoader: OcticonLoader
    let text: String?
    let style: Style

    package init(
        icon: Icon,
        octiconLoader: OcticonLoader,
        text: String?,
        style: Style
    ) {
        self.icon = icon
        self.octiconLoader = octiconLoader
        self.text = text
        self.style = style
    }

    package var body: some View {
        HStack(spacing: AppStyles.Shell.Sidebar.chipContentSpacing) {
            switch icon {
            case .octicon(let assetName):
                OcticonImage(
                    name: assetName,
                    size: AppStyles.Shell.Sidebar.chipIconSize,
                    loader: octiconLoader
                )
            case .system(let symbol):
                Image(systemName: symbol.rawValue)
                    .font(.system(size: AppStyles.Shell.Sidebar.chipIconSize, weight: .medium))
            }
            if let text {
                Text(text)
                    .font(.system(size: AppStyles.Shell.Sidebar.chipFontSize, weight: .medium).monospacedDigit())
                    .lineLimit(1)
            }
        }
        .padding(
            .horizontal,
            text == nil
                ? AppStyles.Shell.Sidebar.chipIconOnlyHorizontalPadding : AppStyles.Shell.Sidebar.chipHorizontalPadding
        )
        .padding(.vertical, AppStyles.Shell.Sidebar.chipVerticalPadding)
        .background(
            Capsule()
                .fill(Color.white.opacity(AppStyles.Shell.Sidebar.chipBackgroundOpacity))
                .overlay(
                    Capsule()
                        .fill(Color.black.opacity(AppStyles.Shell.Sidebar.chipMuteOverlayOpacity))
                )
        )
        .foregroundStyle(style.foreground.opacity(AppStyles.Shell.Sidebar.chipForegroundOpacity))
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(AppStyles.Shell.Sidebar.chipBorderOpacity), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: true)
    }
}

package struct SidebarStatusSyncChip: View {
    let octiconLoader: OcticonLoader
    let aheadText: String
    let behindText: String
    let hasSyncSignal: Bool

    private var effectiveStyle: SidebarChip.Style {
        hasSyncSignal ? .info : .neutral
    }

    package init(
        octiconLoader: OcticonLoader,
        aheadText: String,
        behindText: String,
        hasSyncSignal: Bool
    ) {
        self.octiconLoader = octiconLoader
        self.aheadText = aheadText
        self.behindText = behindText
        self.hasSyncSignal = hasSyncSignal
    }

    package var body: some View {
        HStack(spacing: AppStyles.Shell.Sidebar.chipContentSpacing) {
            HStack(spacing: AppStyles.Shell.Sidebar.syncClusterSpacing) {
                OcticonImage(
                    name: "octicon-arrow-up",
                    size: AppStyles.Shell.Sidebar.syncChipIconSize,
                    loader: octiconLoader
                )
                Text(aheadText)
            }
            HStack(spacing: AppStyles.Shell.Sidebar.syncClusterSpacing) {
                OcticonImage(
                    name: "octicon-arrow-down",
                    size: AppStyles.Shell.Sidebar.syncChipIconSize,
                    loader: octiconLoader
                )
                Text(behindText)
            }
        }
        .font(.system(size: AppStyles.Shell.Sidebar.chipFontSize, weight: .medium).monospacedDigit())
        .lineLimit(1)
        .padding(.horizontal, AppStyles.Shell.Sidebar.chipHorizontalPadding)
        .padding(.vertical, AppStyles.Shell.Sidebar.chipVerticalPadding)
        .background(
            Capsule()
                .fill(Color.white.opacity(AppStyles.Shell.Sidebar.chipBackgroundOpacity))
                .overlay(
                    Capsule()
                        .fill(Color.black.opacity(AppStyles.Shell.Sidebar.chipMuteOverlayOpacity))
                )
        )
        .foregroundStyle(effectiveStyle.foreground.opacity(AppStyles.Shell.Sidebar.chipForegroundOpacity))
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(AppStyles.Shell.Sidebar.chipBorderOpacity), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: true)
    }
}

package struct SidebarDiffChip: View {
    /// The one working-tree fact the chip describes. The dirty dot is never rendered on its own, so
    /// every case here carries a label the reader can act on.
    package enum WorkingTreeDetail: Equatable {
        case lineCounts(added: Int, deleted: Int)
        case untrackedOnly
        case changesWithoutLineCounts
    }

    let octiconLoader: OcticonLoader
    let detail: WorkingTreeDetail

    private var plusColor: Color {
        AppStyles.Shell.Sidebar.chipSuccessColor.opacity(AppStyles.Shell.Sidebar.chipForegroundOpacity)
    }

    private var minusColor: Color {
        AppStyles.Shell.Sidebar.chipDangerColor.opacity(AppStyles.Shell.Sidebar.chipForegroundOpacity)
    }

    private var neutralColor: Color {
        SidebarChip.Style.neutral.foreground.opacity(AppStyles.Shell.Sidebar.chipForegroundOpacity)
    }

    package init(octiconLoader: OcticonLoader, detail: WorkingTreeDetail) {
        self.octiconLoader = octiconLoader
        self.detail = detail
    }

    /// Resolves the chip for a branch status, or `nil` when the checkout is clean and the row shows no
    /// diff chip at all.
    package static func workingTreeDetail(
        isDirty: Bool,
        linesAdded: Int,
        linesDeleted: Int,
        untrackedFileCount: Int
    ) -> WorkingTreeDetail? {
        if linesAdded > 0 || linesDeleted > 0 {
            return .lineCounts(added: linesAdded, deleted: linesDeleted)
        }
        if untrackedFileCount > 0 {
            return .untrackedOnly
        }
        return isDirty ? .changesWithoutLineCounts : nil
    }

    package var body: some View {
        HStack(spacing: AppStyles.Shell.Sidebar.chipContentSpacing) {
            OcticonImage(
                name: "octicon-dot-fill",
                size: AppStyles.Shell.Sidebar.chipIconSize,
                loader: octiconLoader
            )
            .foregroundStyle(
                SidebarChip.Style.danger.foreground.opacity(AppStyles.Shell.Sidebar.chipForegroundOpacity))

            switch detail {
            case .lineCounts(let added, let deleted):
                HStack(spacing: AppStyles.General.Spacing.tight) {
                    Text("+\(added)")
                        .foregroundStyle(plusColor)
                    Text("-\(deleted)")
                        .foregroundStyle(minusColor)
                }
            case .untrackedOnly:
                Text("untracked")
                    .foregroundStyle(neutralColor)
            case .changesWithoutLineCounts:
                Text("changes")
                    .foregroundStyle(neutralColor)
            }
        }
        .font(.system(size: AppStyles.Shell.Sidebar.chipFontSize, weight: .medium).monospacedDigit())
        .lineLimit(1)
        .padding(.horizontal, AppStyles.Shell.Sidebar.chipHorizontalPadding)
        .padding(.vertical, AppStyles.Shell.Sidebar.chipVerticalPadding)
        .background(
            Capsule()
                .fill(Color.white.opacity(AppStyles.Shell.Sidebar.chipBackgroundOpacity))
                .overlay(
                    Capsule()
                        .fill(Color.black.opacity(AppStyles.Shell.Sidebar.chipMuteOverlayOpacity))
                )
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(AppStyles.Shell.Sidebar.chipBorderOpacity), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: true)
    }
}
