import AgentStudioInfrastructure
import SwiftUI

package struct SidebarMetadataLine: View {
    /// Where the line's leading glyph comes from. SF Symbols and octicons render through
    /// different SwiftUI image paths, so the source is a distinct case rather than a second
    /// optional string parameter.
    package enum IconSource {
        case systemName(String)
        case octicon(name: String, loader: OcticonLoader)
    }

    package let icon: IconSource?
    package let reservesIconColumn: Bool
    package let text: String
    package let prominence: SidebarMetadataProminence

    static var reservedIconPlaceholderHeight: CGFloat {
        AppStyles.Shell.Sidebar.branchIconSize
    }

    package init(
        icon: IconSource? = nil,
        reservesIconColumn: Bool = true,
        text: String,
        prominence: SidebarMetadataProminence = .secondary
    ) {
        self.icon = icon
        self.reservesIconColumn = reservesIconColumn
        self.text = text
        self.prominence = prominence
    }

    package var body: some View {
        HStack(spacing: AppStyles.Shell.Sidebar.groupIconTitleSpacing) {
            switch icon {
            case .systemName(let systemName):
                Image(systemName: systemName)
                    .font(.system(size: AppStyles.Shell.Sidebar.branchIconSize, weight: .medium))
                    .foregroundStyle(prominence.foregroundStyle)
                    .frame(width: AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth, alignment: .leading)
            case .octicon(let name, let loader):
                OcticonImage(name: name, size: AppStyles.Shell.Sidebar.branchIconSize, loader: loader)
                    .foregroundStyle(prominence.foregroundStyle)
                    .frame(width: AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth, alignment: .leading)
            case nil:
                if reservesIconColumn {
                    Color.clear
                        .frame(
                            width: AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth,
                            height: Self.reservedIconPlaceholderHeight
                        )
                }
            }

            Text(text)
                .font(.system(size: AppStyles.Shell.Sidebar.branchFontSize, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
                .foregroundStyle(prominence.foregroundStyle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

package enum SidebarMetadataProminence: Equatable {
    case primary
    case secondary
    case tertiary

    var foregroundStyle: Color {
        switch self {
        case .primary:
            Color.primary
        case .secondary:
            Color.secondary
        case .tertiary:
            Color.secondary.opacity(AppStyles.General.Fill.muted)
        }
    }
}
