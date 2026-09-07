import AgentStudioInfrastructure
import SwiftUI

package struct SectionSubheadingLabel: View {
    private let title: String
    private let isSecondary: Bool

    package init(_ title: String, isSecondary: Bool = false) {
        self.title = title
        self.isSecondary = isSecondary
    }

    package static func displayTitle(for title: String) -> String {
        title.lowercased()
    }

    package var body: some View {
        Text(Self.displayTitle(for: title))
            .font(
                Font.system(size: AppStyles.Components.SectionSubheading.fontSize, weight: .semibold)
                    .smallCaps()
            )
            .foregroundStyle(
                isSecondary
                    ? Color.secondary
                    : AppStyles.General.Accent.primaryColor.opacity(
                        AppStyles.Components.SectionSubheading.foregroundOpacity)
            )
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
