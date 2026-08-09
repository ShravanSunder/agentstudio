import AgentStudioInfrastructure
import SwiftUI

package struct SectionSubheadingLabel: View {
    private let title: String

    package init(_ title: String) {
        self.title = title
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
                Color.accentColor.opacity(AppStyles.Components.SectionSubheading.foregroundOpacity)
            )
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
