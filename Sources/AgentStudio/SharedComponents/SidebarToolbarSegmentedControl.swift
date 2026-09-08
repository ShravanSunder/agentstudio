import AgentStudioInfrastructure
import SwiftUI

@MainActor
package struct SidebarToolbarSegmentedControl<Value: Hashable, Icon: View>: View {
    let model: SidebarToggleModel<Value>
    @ViewBuilder let icon: (Value) -> Icon
    let onSelect: (Value) -> Void

    package init(
        segments: [SidebarToolbarSegment<Value>],
        selection: Value?,
        content: SidebarToggleModel<Value>.Content = .selectedLabel,
        @ViewBuilder icon: @escaping (Value) -> Icon,
        onSelect: @escaping (Value) -> Void
    ) {
        self.model = SidebarToggleModel(segments: segments, selection: selection, content: content)
        self.icon = icon
        self.onSelect = onSelect
    }

    package var body: some View {
        HStack(spacing: AppStyles.Shell.Sidebar.ToolbarControl.segmentedControlSpacing) {
            ForEach(model.segments) { segment in
                let isSelected = model.isSelected(segment.value)
                Button {
                    guard let requestedValue = model.selectionRequest(for: segment.value) else { return }
                    onSelect(requestedValue)
                } label: {
                    HStack(spacing: AppStyles.Shell.Sidebar.ToolbarControl.groupingContentSpacing) {
                        if model.showsIcons {
                            icon(segment.value)
                                .frame(
                                    width: AppStyles.General.Button.compact,
                                    height: AppStyles.General.Button.compact
                                )
                        }

                        if model.showsLabel(for: segment.value) {
                            Text(segment.label)
                                .font(
                                    .system(
                                        size: AppStyles.General.Typography.textXs,
                                        weight: .medium
                                    )
                                )
                                .lineLimit(1)
                                .padding(
                                    model.showsIcons ? .trailing : .horizontal,
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
            value: model.selection
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

package enum SidebarToolbarSelectionAppearance {
    case accent
    case neutral
    case unhighlighted
}

@MainActor
struct SidebarToolbarSegmentButtonStyle: ButtonStyle {
    let isSelected: Bool
    var appearance: SidebarToolbarSelectionAppearance = .accent

    func makeBody(configuration: Configuration) -> some View {
        SidebarToolbarSegmentButtonStyleBody(
            configuration: configuration,
            isSelected: isSelected,
            appearance: appearance
        )
    }
}

@MainActor
private struct SidebarToolbarSegmentButtonStyleBody: View {
    let configuration: ButtonStyle.Configuration
    let isSelected: Bool
    let appearance: SidebarToolbarSelectionAppearance
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
                appearance == .unhighlighted
                    ? Color.secondary
                    : ChromeToolbarControlPalette.foregroundColor(
                        isSelected: isSelected, isHovered: isHovered
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: AppStyles.Shell.Sidebar.ToolbarControl.cornerRadius)
                    .fill(
                        isSelected && appearance == .neutral
                            ? Color.primary.opacity(AppStyles.General.Fill.subtle)
                            : isSelected
                                // Selected fill comes from the same shared palette the Zoom pill family
                                // uses, so the two selected-state treatments can never diverge in color.
                                ? ChromeToolbarControlPalette.fillColor(
                                    isSelected: true,
                                    isHovered: isHovered,
                                    isPressed: configuration.isPressed
                                )
                                : Color.primary.opacity(visualState.fillOpacity)
                    )
            )
            .opacity(isEnabled ? 1 : AppStyles.Shell.Sidebar.ToolbarControl.disabledOpacity)
            .onHover { isHovered = $0 }
    }
}
