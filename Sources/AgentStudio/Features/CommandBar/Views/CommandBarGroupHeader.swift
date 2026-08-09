import AgentStudioInfrastructure
import AgentStudioSharedComponents
import SwiftUI

// MARK: - CommandBarGroupHeader

struct CommandBarGroupHeader: View {
    let name: String

    var body: some View {
        SectionSubheadingLabel(name)
            .padding(.top, AppStyles.Components.SectionSubheading.topPadding)
            .padding(.bottom, AppStyles.Components.SectionSubheading.bottomPadding)
            .padding(.horizontal, AppStyles.Components.SectionSubheading.horizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
            .background(
                AccessibilityLabelBridge(
                    identifier: "commandBarGroupHeader.\(name)",
                    label: name,
                    role: NSAccessibility.Role(rawValue: "AXHeading")
                )
            )
    }
}
