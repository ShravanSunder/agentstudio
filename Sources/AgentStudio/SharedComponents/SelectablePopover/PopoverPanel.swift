import AgentStudioInfrastructure
import SwiftUI

/// Shared content shell for compact configuration popovers.
package struct PopoverPanel<Content: View>: View {
    private let content: Content

    package init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: AppStyles.Components.PopoverPanel.sectionSpacing) {
            content
        }
        .padding(AppStyles.Components.PopoverPanel.contentPadding)
    }
}

package struct PopoverOptionLabel<Icon: View>: View {
    private let title: String
    private let icon: Icon

    package init(_ title: String, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.icon = icon()
    }

    package var body: some View {
        HStack(spacing: AppStyles.General.Spacing.standard) {
            icon
                .frame(width: AppStyles.General.Icon.compact, height: AppStyles.General.Icon.compact)
                .accessibilityHidden(true)
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

package struct PopoverOptionVisualStyle: Equatable {
    package let isSelected: Bool
    package let isHighlighted: Bool
    package let isPressed: Bool

    package init(isSelected: Bool, isHighlighted: Bool, isPressed: Bool) {
        self.isSelected = isSelected
        self.isHighlighted = isHighlighted
        self.isPressed = isPressed
    }

    package var backgroundOpacity: CGFloat {
        if isPressed { return AppStyles.General.Fill.pressed }
        if isSelected { return AppStyles.General.Fill.active }
        if isHighlighted { return AppStyles.General.Fill.hover }
        return AppStyles.General.Fill.subtle
    }

    package var foregroundIsPrimary: Bool {
        isSelected || isHighlighted || isPressed
    }
}

/// Also applies to compound controls such as an arrangement chip with a rename button.
package struct PopoverOptionSurface: ViewModifier {
    private let visualStyle: PopoverOptionVisualStyle
    private let isUnavailable: Bool

    package init(
        isSelected: Bool,
        isHighlighted: Bool,
        isPressed: Bool = false,
        isUnavailable: Bool = false
    ) {
        visualStyle = PopoverOptionVisualStyle(
            isSelected: isSelected, isHighlighted: isHighlighted, isPressed: isPressed
        )
        self.isUnavailable = isUnavailable
    }

    package func body(content: Content) -> some View {
        content
            .font(
                .system(
                    size: AppStyles.General.Typography.textXs, weight: visualStyle.isSelected ? .semibold : .regular)
            )
            .foregroundStyle(isUnavailable ? .tertiary : visualStyle.foregroundIsPrimary ? .primary : .secondary)
            .padding(.horizontal, AppStyles.General.Spacing.loose)
            .padding(.vertical, AppStyles.General.Spacing.tight)
            .background(
                RoundedRectangle(cornerRadius: AppStyles.General.CornerRadius.bar)
                    .fill(Color.white.opacity(isUnavailable ? 0 : visualStyle.backgroundOpacity))
            )
            .contentShape(Rectangle())
    }
}

package struct PopoverOptionButtonStyle: ButtonStyle {
    private let isSelected: Bool
    private let isHighlighted: Bool

    package init(isSelected: Bool, isHighlighted: Bool) {
        self.isSelected = isSelected
        self.isHighlighted = isHighlighted
    }

    package func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(
            PopoverOptionSurface(
                isSelected: isSelected,
                isHighlighted: isHighlighted,
                isPressed: configuration.isPressed
            )
        )
    }
}

/// Keeps one painted surface around multiple independently actionable buttons.
package struct PopoverCompoundOptionSurface: ViewModifier {
    private let isSelected: Bool
    private let isHighlighted: Bool
    @State private var isPressed = false

    package init(isSelected: Bool, isHighlighted: Bool) {
        self.isSelected = isSelected
        self.isHighlighted = isHighlighted
    }

    package func body(content: Content) -> some View {
        content
            .buttonStyle(PopoverPressReportingButtonStyle())
            .modifier(
                PopoverOptionSurface(
                    isSelected: isSelected, isHighlighted: isHighlighted, isPressed: isPressed
                )
            )
            .onPreferenceChange(PopoverPressedPreferenceKey.self) { isPressed = $0 }
    }
}

private struct PopoverPressReportingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.preference(key: PopoverPressedPreferenceKey.self, value: configuration.isPressed)
    }
}

private struct PopoverPressedPreferenceKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        let nextPressed = nextValue()
        value = value || nextPressed
    }
}
