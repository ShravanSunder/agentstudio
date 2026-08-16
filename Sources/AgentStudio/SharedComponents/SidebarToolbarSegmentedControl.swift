import AgentStudioInfrastructure
import SwiftUI

package struct SidebarToolbarSegment<Value: Hashable>: Identifiable {
    package let value: Value
    package let label: String
    package let accessibilityIdentifier: String
    package let tooltipValue: ControlTooltipRenderValue
    package let isEnabled: Bool

    package var id: Value { value }

    package init(
        value: Value,
        label: String,
        accessibilityIdentifier: String,
        tooltipValue: ControlTooltipRenderValue,
        isEnabled: Bool
    ) {
        self.value = value
        self.label = label
        self.accessibilityIdentifier = accessibilityIdentifier
        self.tooltipValue = tooltipValue
        self.isEnabled = isEnabled
    }
}

@MainActor
package struct SidebarToolbarSegmentedControl<Value: Hashable, Icon: View>: View {
    let segments: [SidebarToolbarSegment<Value>]
    let selection: Value
    @ViewBuilder let icon: (Value) -> Icon
    let onSelect: (Value) -> Void

    package init(
        segments: [SidebarToolbarSegment<Value>],
        selection: Value,
        @ViewBuilder icon: @escaping (Value) -> Icon,
        onSelect: @escaping (Value) -> Void
    ) {
        self.segments = segments
        self.selection = selection
        self.icon = icon
        self.onSelect = onSelect
    }

    package var body: some View {
        HStack(spacing: AppStyles.Shell.Sidebar.ToolbarControl.segmentedControlSpacing) {
            ForEach(segments) { segment in
                let isSelected = segment.value == selection
                Button {
                    onSelect(segment.value)
                } label: {
                    SidebarToolbarIcon {
                        icon(segment.value)
                    }
                }
                .buttonStyle(SidebarToolbarSegmentButtonStyle(isSelected: isSelected))
                .disabled(!segment.isEnabled)
                .accessibilityLabel(segment.label)
                .accessibilityIdentifier(segment.accessibilityIdentifier)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .controlHelp(segment.tooltipValue)
            }
        }
        .padding(AppStyles.Shell.Sidebar.ToolbarControl.segmentedControlPadding)
        .background(
            RoundedRectangle(cornerRadius: AppStyles.Shell.Sidebar.ToolbarControl.cornerRadius)
                .fill(Color.primary.opacity(AppStyles.Shell.Sidebar.ToolbarControl.hoverFillOpacity))
        )
    }
}

@MainActor
private struct SidebarToolbarSegmentButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        SidebarToolbarSegmentButtonStyleBody(
            configuration: configuration,
            isSelected: isSelected
        )
    }
}

@MainActor
private struct SidebarToolbarSegmentButtonStyleBody: View {
    let configuration: ButtonStyle.Configuration
    let isSelected: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: AppStyles.Shell.Sidebar.ToolbarControl.cornerRadius)
                    .fill(fillColor(isPressed: configuration.isPressed))
            )
            .opacity(isEnabled ? 1 : AppStyles.Shell.Sidebar.ToolbarControl.disabledOpacity)
            .onHover { isHovered = $0 }
    }

    private func fillColor(isPressed: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(
                AppStyles.Shell.Sidebar.ToolbarControl.segmentedControlSelectedFillOpacity
            )
        }
        if isPressed {
            return Color.primary.opacity(AppStyles.Shell.Sidebar.ToolbarControl.pressedFillOpacity)
        }
        return Color.primary.opacity(
            isHovered ? AppStyles.Shell.Sidebar.ToolbarControl.hoverFillOpacity : 0
        )
    }
}
