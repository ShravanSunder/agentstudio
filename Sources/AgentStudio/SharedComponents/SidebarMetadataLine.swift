import AgentStudioInfrastructure
import SwiftUI

package struct SidebarMetadataLine: View {
    let iconSystemName: String?
    let reservesIconColumn: Bool
    let text: String
    let prominence: SidebarMetadataProminence

    static var reservedIconPlaceholderHeight: CGFloat {
        AppStyles.Shell.Sidebar.branchIconSize
    }

    package init(
        iconSystemName: String? = nil,
        reservesIconColumn: Bool = true,
        text: String,
        prominence: SidebarMetadataProminence = .secondary
    ) {
        self.iconSystemName = iconSystemName
        self.reservesIconColumn = reservesIconColumn
        self.text = text
        self.prominence = prominence
    }

    package var body: some View {
        HStack(spacing: AppStyles.General.Spacing.tight) {
            if let iconSystemName {
                Image(systemName: iconSystemName)
                    .font(.system(size: AppStyles.Shell.Sidebar.branchIconSize, weight: .medium))
                    .frame(width: AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth, alignment: .leading)
            } else if reservesIconColumn {
                Color.clear
                    .frame(
                        width: AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth,
                        height: Self.reservedIconPlaceholderHeight
                    )
            }

            Text(text)
                .font(.system(size: AppStyles.Shell.Sidebar.branchFontSize, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
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
