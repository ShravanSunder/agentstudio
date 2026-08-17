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
                    HStack(spacing: AppStyles.Shell.Sidebar.ToolbarControl.groupingContentSpacing) {
                        icon(segment.value)
                            .frame(
                                width: AppStyles.General.Button.compact,
                                height: AppStyles.General.Button.compact
                            )

                        if isSelected {
                            Text(segment.label)
                                .font(
                                    .system(
                                        size: AppStyles.General.Typography.textXs,
                                        weight: .medium
                                    )
                                )
                                .lineLimit(1)
                                .padding(
                                    .trailing,
                                    AppStyles.Shell.Sidebar.ToolbarControl.groupingHorizontalPadding
                                )
                                .transition(
                                    .asymmetric(
                                        insertion: selectedLabelInsertionTransition,
                                        removal: selectedLabelRemovalTransition
                                    )
                                )
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SidebarToolbarSegmentButtonStyle(isSelected: isSelected))
                .disabled(!segment.isEnabled)
                .accessibilityLabel(segment.label)
                .accessibilityIdentifier(segment.accessibilityIdentifier)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .controlHelp(segment.tooltipValue)
            }
        }
        .animation(
            .easeInOut(
                duration: AppStyles.Shell.Sidebar.ToolbarControl.selectionTransitionDuration
            ),
            value: selection
        )
    }

    private var selectedLabelInsertionTransition: AnyTransition {
        AnyTransition.offset(
            x: -AppStyles.Shell.Sidebar.ToolbarControl.labelSlideDistance,
            y: 0
        )
        .combined(with: .opacity)
        .animation(
            .easeOut(
                duration: AppStyles.Shell.Sidebar.ToolbarControl.labelRevealDuration
            )
            .delay(AppStyles.Shell.Sidebar.ToolbarControl.labelRevealDelay)
        )
    }

    private var selectedLabelRemovalTransition: AnyTransition {
        .opacity.animation(
            .easeOut(duration: AppStyles.General.Animation.fast)
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
        let visualState = SidebarToolbarControlVisualState.resolve(
            isEnabled: isEnabled,
            isHovered: isHovered,
            isPressed: configuration.isPressed,
            isActive: isSelected,
            isOpen: false
        )
        configuration.label
            .foregroundStyle(
                ChromeToolbarControlPalette.foregroundColor(
                    isSelected: isSelected,
                    isHovered: isHovered
                )
            )
            .background(
                RoundedRectangle(cornerRadius: AppStyles.Shell.Sidebar.ToolbarControl.cornerRadius)
                    .fill(Color.primary.opacity(visualState.fillOpacity))
            )
            .opacity(isEnabled ? 1 : AppStyles.Shell.Sidebar.ToolbarControl.disabledOpacity)
            .onHover { isHovered = $0 }
    }
}
