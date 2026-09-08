import AgentStudioInfrastructure
import SwiftUI

/// A controlled selector using the sidebar toggle's existing chrome and selectable popover.
@MainActor
package struct SidebarDropdownSelector<Value: Hashable, Icon: View>: View {
    let options: [SidebarToolbarSegment<Value>]
    let selection: Value
    let label: String
    let tooltip: ControlTooltipRenderValue
    let appearance: SidebarToolbarSelectionAppearance
    @Binding var isOpen: Bool
    @ViewBuilder let icon: (Value) -> Icon
    let onSelect: (Value) -> Void

    package init(
        options: [SidebarToolbarSegment<Value>], selection: Value,
        label: String, tooltip: ControlTooltipRenderValue,
        appearance: SidebarToolbarSelectionAppearance = .accent,
        isOpen: Binding<Bool>, @ViewBuilder icon: @escaping (Value) -> Icon,
        onSelect: @escaping (Value) -> Void
    ) {
        self.options = options
        self.selection = selection
        self.label = label
        self.tooltip = tooltip
        self.appearance = appearance
        self._isOpen = isOpen
        self.icon = icon
        self.onSelect = onSelect
    }

    package var body: some View {
        let model = SidebarToggleModel(segments: options, selection: selection, content: .selectedLabel)
        Button {
            withAnimation(.easeInOut(duration: AppStyles.General.Animation.standard)) {
                isOpen.toggle()
            }
        } label: {
            HStack(spacing: AppStyles.Shell.Sidebar.ToolbarControl.groupingContentSpacing) {
                icon(selection)
                    .frame(width: AppStyles.General.Button.compact, height: AppStyles.General.Button.compact)
                Text(options.first { $0.value == selection }?.label ?? "")
                    .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: AppStyles.Shell.Sidebar.ToolbarControl.groupingChevronSize, weight: .semibold))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .animation(.easeInOut(duration: AppStyles.General.Animation.standard), value: isOpen)
                    .padding(.trailing, AppStyles.Shell.Sidebar.ToolbarControl.groupingHorizontalPadding)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(
            SidebarToolbarSegmentButtonStyle(
                isSelected: appearance != .unhighlighted, appearance: appearance
            )
        )
        .accessibilityLabel(label)
        .controlHelp(tooltip)
        .popover(isPresented: $isOpen, arrowEdge: .top) {
            SidebarDropdownReveal {
                SidebarGroupingPopover(
                    items: options.filter(\.isEnabled).map(\.value), selectedItem: selection,
                    icon: icon,
                    label: { value in options.first { $0.value == value }?.label ?? "" },
                    onSelect: { value in
                        guard let request = model.selectionRequest(for: value) else { return }
                        onSelect(request)
                        isOpen = false
                    },
                    onDismiss: { isOpen = false }
                )
            }
        }
        .onDisappear { isOpen = false }
    }
}

private struct SidebarDropdownReveal<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var isVisible = false

    var body: some View {
        content()
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : -AppStyles.General.Spacing.tight)
            .onAppear {
                withAnimation(.easeOut(duration: AppStyles.General.Animation.fast)) {
                    isVisible = true
                }
            }
    }
}

package struct SidebarGroupingConnector: View {
    package init() {}

    package var body: some View {
        Image(systemName: "arrow.left")
            .font(.system(size: AppStyles.General.Icon.compact))
            .foregroundStyle(.secondary)
            .frame(width: AppStyles.General.Icon.compact)
            .accessibilityHidden(true)
    }
}
