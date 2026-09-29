import AgentStudioInfrastructure
import SwiftUI

package struct SidebarChip: View {
    package enum Icon: Equatable {
        case octicon(String)
        case system(String)
    }

    package enum Style {
        case neutral
        case info
        case success
        case warning
        case danger
        case accent(Color)

        package var foreground: Color {
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
                Image(systemName: symbol)
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
        .frame(height: AppStyles.Shell.Sidebar.chipLineHeight)
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
