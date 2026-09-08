import AgentStudioInfrastructure
import SwiftUI

/// A quiet subgroup label with a rule that fills the remaining row width.
package struct SidebarSubgroupHeading: View {
    private let title: String

    package init(_ title: String) {
        self.title = title
    }

    package var body: some View {
        HStack(spacing: AppStyles.General.Spacing.standard) {
            SectionSubheadingLabel(title, isSecondary: true, casing: .initialSmallCaps)
                .layoutPriority(1)
            VStack(spacing: 0) {
                Divider()
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
        }
        .padding(.trailing, AppStyles.Components.SectionSubheading.horizontalPadding)
    }
}
