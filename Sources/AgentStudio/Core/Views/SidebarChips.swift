import SwiftUI

struct SidebarChip: View {
    enum Style {
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

    let iconAsset: String
    let text: String?
    let style: Style

    var body: some View {
        HStack(spacing: AppStyles.Shell.Sidebar.chipContentSpacing) {
            OcticonImage(name: iconAsset, size: AppStyles.Shell.Sidebar.chipIconSize)
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

struct SidebarStatusSyncChip: View {
    let aheadText: String
    let behindText: String
    let hasSyncSignal: Bool

    private var effectiveStyle: SidebarChip.Style {
        hasSyncSignal ? .info : .neutral
    }

    var body: some View {
        HStack(spacing: AppStyles.Shell.Sidebar.chipContentSpacing) {
            HStack(spacing: AppStyles.Shell.Sidebar.syncClusterSpacing) {
                OcticonImage(name: "octicon-arrow-up", size: AppStyles.Shell.Sidebar.syncChipIconSize)
                Text(aheadText)
            }
            HStack(spacing: AppStyles.Shell.Sidebar.syncClusterSpacing) {
                OcticonImage(name: "octicon-arrow-down", size: AppStyles.Shell.Sidebar.syncChipIconSize)
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

struct SidebarDiffChip: View {
    let linesAdded: Int
    let linesDeleted: Int
    let showsDirtyIndicator: Bool
    let isMuted: Bool

    private var plusColor: Color {
        if isMuted {
            return SidebarChip.Style.neutral.foreground.opacity(AppStyles.Shell.Sidebar.chipForegroundOpacity)
        }
        return AppStyles.Shell.Sidebar.chipSuccessColor.opacity(AppStyles.Shell.Sidebar.chipForegroundOpacity)
    }

    private var minusColor: Color {
        if isMuted {
            return SidebarChip.Style.neutral.foreground.opacity(AppStyles.Shell.Sidebar.chipForegroundOpacity)
        }
        return AppStyles.Shell.Sidebar.chipDangerColor.opacity(AppStyles.Shell.Sidebar.chipForegroundOpacity)
    }

    var body: some View {
        HStack(spacing: AppStyles.Shell.Sidebar.chipContentSpacing) {
            if showsDirtyIndicator {
                OcticonImage(name: "octicon-dot-fill", size: AppStyles.Shell.Sidebar.chipIconSize)
                    .foregroundStyle(
                        SidebarChip.Style.danger.foreground.opacity(AppStyles.Shell.Sidebar.chipForegroundOpacity))
            }

            HStack(spacing: AppStyles.General.Spacing.tight) {
                Text("+\(linesAdded)")
                    .foregroundStyle(plusColor)
                Text("-\(linesDeleted)")
                    .foregroundStyle(minusColor)
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
