import AgentStudioInfrastructure
import SwiftUI

package struct SectionSubheadingLabel: View {
    package enum Casing {
        case smallCaps
        case sentence
        case initialSmallCaps
    }

    private let casing: Casing
    private let title: String
    private let isSecondary: Bool

    package init(_ title: String, isSecondary: Bool = false, casing: Casing = .smallCaps) {
        self.casing = casing
        self.title = title
        self.isSecondary = isSecondary
    }

    package static func displayTitle(for title: String, casing: Casing = .smallCaps) -> String {
        switch casing {
        case .smallCaps: title.lowercased()
        case .sentence: title.prefix(1).uppercased() + title.dropFirst().lowercased()
        case .initialSmallCaps: title.lowercased().capitalized
        }
    }

    private var labelFont: Font {
        let font = Font.system(size: AppStyles.Components.SectionSubheading.fontSize, weight: .semibold)
        switch casing {
        case .sentence: return font
        case .smallCaps: return font.smallCaps()
        case .initialSmallCaps: return font.lowercaseSmallCaps()
        }
    }

    package var body: some View {
        Text(Self.displayTitle(for: title, casing: casing))
            .font(labelFont)
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
