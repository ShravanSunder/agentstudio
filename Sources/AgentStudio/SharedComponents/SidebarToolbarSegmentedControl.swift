import AgentStudioInfrastructure
import SwiftUI

@MainActor
package struct SidebarToolbarSegmentedControl<Value: Hashable, Icon: View>: View {
    let model: SidebarToggleModel<Value>
    @ViewBuilder let icon: (Value) -> Icon
    let onSelect: (Value) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    HStack(spacing: 0) {
                        if model.showsIcons {
                            icon(segment.value)
                                .frame(
                                    width: AppStyles.General.Button.compact,
                                    height: AppStyles.General.Button.compact
                                )
                        }

                        SidebarToolbarLabelLayout(
                            revealFraction: model.showsLabel(for: segment.value) ? 1 : 0
                        ) {
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
                                .padding(
                                    .leading,
                                    model.showsIcons ? AppStyles.Shell.Sidebar.ToolbarControl.groupingContentSpacing : 0
                                )
                                .opacity(model.showsLabel(for: segment.value) ? 1 : 0)
                                .animation(
                                    reduceMotion
                                        ? nil : labelAnimation(isShowing: model.showsLabel(for: segment.value)),
                                    value: model.selection
                                )
                        }
                        .clipped()
                        .accessibilityHidden(true)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .clipped()
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
        .overlay {
            RoundedRectangle(cornerRadius: AppStyles.Shell.Sidebar.ToolbarControl.cornerRadius)
                .stroke(AppStyles.General.Stroke.controlGroupColor, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .animation(
            reduceMotion
                ? nil
                : .easeInOut(duration: AppStyles.Shell.Sidebar.ToolbarControl.selectionResizeDuration)
                    .delay(AppStyles.Shell.Sidebar.ToolbarControl.selectionResizeDelay),
            value: model.selection
        )
    }

    private func labelAnimation(isShowing: Bool) -> Animation {
        if isShowing {
            return .easeInOut(duration: AppStyles.Shell.Sidebar.ToolbarControl.labelFadeInDuration)
                .delay(AppStyles.Shell.Sidebar.ToolbarControl.labelFadeInDelay)
        }
        return .easeInOut(duration: AppStyles.Shell.Sidebar.ToolbarControl.labelFadeOutDuration)
    }

}

// Keep the label mounted so insertion/removal lifetimes cannot separate the two
// buttons' geometry. SwiftUI interpolates occupied width on their shared transaction.
struct SidebarToolbarLabelLayout: Layout {
    var revealFraction: CGFloat

    var animatableData: CGFloat {
        get { revealFraction }
        set { revealFraction = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let naturalSize = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: naturalSize.width * revealFraction, height: naturalSize.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: .unspecified)
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
