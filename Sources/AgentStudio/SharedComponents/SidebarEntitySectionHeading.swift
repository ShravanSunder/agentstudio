import AgentStudioInfrastructure
import SwiftUI

/// A section identifies its contents; collapsible group headers remain separate.
package struct SidebarEntitySectionHeading: View {
    private let title: String
    private let icon: AppEntityIcon
    private let octiconLoader: OcticonLoader

    package init(_ title: String, icon: AppEntityIcon, octiconLoader: OcticonLoader) {
        self.title = title
        self.icon = icon
        self.octiconLoader = octiconLoader
    }

    package var body: some View {
        HStack(alignment: .center, spacing: AppStyles.Shell.Sidebar.groupIconTitleSpacing) {
            icon.swiftUIImage(
                loader: octiconLoader,
                size: AppStyles.Shell.Sidebar.groupIconSize,
                foregroundOverride: AppStyles.General.Accent.primaryColor.opacity(
                    AppStyles.Components.SectionSubheading.foregroundOpacity
                )
            )
            .frame(width: AppStyles.Shell.Sidebar.groupIconColumnWidth)
            .accessibilityHidden(true)
            SectionSubheadingLabel(title, casing: .initialSmallCaps)
        }
    }
}
