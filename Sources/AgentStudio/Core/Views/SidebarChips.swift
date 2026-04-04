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
            case .info: return AppStyle.chipInfoColor
            case .success: return AppStyle.chipSuccessColor
            case .warning: return AppStyle.chipWarningColor
            case .danger: return AppStyle.chipDangerColor
            case .accent(let color): return color
            }
        }
    }

    let iconAsset: String
    let text: String?
    let style: Style

    var body: some View {
        HStack(spacing: AppStyle.sidebarChipContentSpacing) {
            OcticonImage(name: iconAsset, size: AppStyle.sidebarChipIconSize)
            if let text {
                Text(text)
                    .font(.system(size: AppStyle.sidebarChipFontSize, weight: .medium).monospacedDigit())
                    .lineLimit(1)
            }
        }
        .padding(
            .horizontal,
            text == nil ? AppStyle.sidebarChipIconOnlyHorizontalPadding : AppStyle.sidebarChipHorizontalPadding
        )
        .padding(.vertical, AppStyle.sidebarChipVerticalPadding)
        .background(
            Capsule()
                .fill(Color.white.opacity(AppStyle.sidebarChipBackgroundOpacity))
                .overlay(
                    Capsule()
                        .fill(Color.black.opacity(AppStyle.sidebarChipMuteOverlayOpacity))
                )
        )
        .foregroundStyle(style.foreground.opacity(AppStyle.sidebarChipForegroundOpacity))
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(AppStyle.sidebarChipBorderOpacity), lineWidth: 1)
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
        HStack(spacing: AppStyle.sidebarChipContentSpacing) {
            HStack(spacing: AppStyle.sidebarSyncClusterSpacing) {
                OcticonImage(name: "octicon-arrow-up", size: AppStyle.sidebarSyncChipIconSize)
                Text(aheadText)
            }
            HStack(spacing: AppStyle.sidebarSyncClusterSpacing) {
                OcticonImage(name: "octicon-arrow-down", size: AppStyle.sidebarSyncChipIconSize)
                Text(behindText)
            }
        }
        .font(.system(size: AppStyle.sidebarChipFontSize, weight: .medium).monospacedDigit())
        .lineLimit(1)
        .padding(.horizontal, AppStyle.sidebarChipHorizontalPadding)
        .padding(.vertical, AppStyle.sidebarChipVerticalPadding)
        .background(
            Capsule()
                .fill(Color.white.opacity(AppStyle.sidebarChipBackgroundOpacity))
                .overlay(
                    Capsule()
                        .fill(Color.black.opacity(AppStyle.sidebarChipMuteOverlayOpacity))
                )
        )
        .foregroundStyle(effectiveStyle.foreground.opacity(AppStyle.sidebarChipForegroundOpacity))
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(AppStyle.sidebarChipBorderOpacity), lineWidth: 1)
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
            return SidebarChip.Style.neutral.foreground.opacity(AppStyle.sidebarChipForegroundOpacity)
        }
        return AppStyle.chipSuccessColor.opacity(AppStyle.sidebarChipForegroundOpacity)
    }

    private var minusColor: Color {
        if isMuted {
            return SidebarChip.Style.neutral.foreground.opacity(AppStyle.sidebarChipForegroundOpacity)
        }
        return AppStyle.chipDangerColor.opacity(AppStyle.sidebarChipForegroundOpacity)
    }

    var body: some View {
        HStack(spacing: AppStyle.sidebarChipContentSpacing) {
            if showsDirtyIndicator {
                OcticonImage(name: "octicon-dot-fill", size: AppStyle.sidebarChipIconSize)
                    .foregroundStyle(SidebarChip.Style.danger.foreground.opacity(AppStyle.sidebarChipForegroundOpacity))
            }

            HStack(spacing: AppStyle.spacingTight) {
                Text("+\(linesAdded)")
                    .foregroundStyle(plusColor)
                Text("-\(linesDeleted)")
                    .foregroundStyle(minusColor)
            }
        }
        .font(.system(size: AppStyle.sidebarChipFontSize, weight: .medium).monospacedDigit())
        .lineLimit(1)
        .padding(.horizontal, AppStyle.sidebarChipHorizontalPadding)
        .padding(.vertical, AppStyle.sidebarChipVerticalPadding)
        .background(
            Capsule()
                .fill(Color.white.opacity(AppStyle.sidebarChipBackgroundOpacity))
                .overlay(
                    Capsule()
                        .fill(Color.black.opacity(AppStyle.sidebarChipMuteOverlayOpacity))
                )
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(AppStyle.sidebarChipBorderOpacity), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: true)
    }
}
