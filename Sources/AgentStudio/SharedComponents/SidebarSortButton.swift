import SwiftUI

enum SidebarToolbarNoTooltipTarget: Hashable {}

struct SidebarToolbarIcon<Icon: View>: View {
    @ViewBuilder let icon: () -> Icon
    var isActive = false

    var body: some View {
        icon()
            .frame(
                width: AppStyles.General.Button.compact,
                height: AppStyles.General.Button.compact
            )
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .contentShape(Rectangle())
    }
}

enum SidebarToolbarControlVisualState: Equatable {
    case idle
    case hovered
    case pressed
    case active
    case open
    case disabled

    static func resolve(
        isEnabled: Bool,
        isHovered: Bool,
        isPressed: Bool,
        isActive: Bool,
        isOpen: Bool
    ) -> Self {
        guard isEnabled else { return .disabled }
        if isPressed { return .pressed }
        if isOpen { return .open }
        if isActive { return .active }
        if isHovered { return .hovered }
        return .idle
    }

    var fillOpacity: CGFloat {
        switch self {
        case .idle, .disabled:
            return 0
        case .hovered:
            return AppStyles.Shell.Sidebar.ToolbarControl.hoverFillOpacity
        case .pressed:
            return AppStyles.Shell.Sidebar.ToolbarControl.pressedFillOpacity
        case .active, .open:
            return AppStyles.Shell.Sidebar.ToolbarControl.activeFillOpacity
        }
    }
}

struct SidebarToolbarButtonStyle: ButtonStyle {
    var isActive = false
    var isOpen = false

    func makeBody(configuration: Configuration) -> some View {
        SidebarToolbarButtonStyleBody(
            configuration: configuration,
            isActive: isActive,
            isOpen: isOpen
        )
    }
}

private struct SidebarToolbarButtonStyleBody: View {
    let configuration: ButtonStyle.Configuration
    let isActive: Bool
    let isOpen: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        let visualState = SidebarToolbarControlVisualState.resolve(
            isEnabled: isEnabled,
            isHovered: isHovered,
            isPressed: configuration.isPressed,
            isActive: isActive,
            isOpen: isOpen
        )
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: AppStyles.Shell.Sidebar.ToolbarControl.cornerRadius)
                    .fill(Color.primary.opacity(visualState.fillOpacity))
            )
            .opacity(isEnabled ? 1 : AppStyles.Shell.Sidebar.ToolbarControl.disabledOpacity)
            .onHover { isHovered = $0 }
    }
}

struct SidebarToolbarMenuLabel<Icon: View>: View {
    @ViewBuilder let icon: () -> Icon
    @State private var isHovered = false

    var body: some View {
        SidebarToolbarIcon(icon: icon)
            .background(
                RoundedRectangle(cornerRadius: AppStyles.Shell.Sidebar.ToolbarControl.cornerRadius)
                    .fill(
                        Color.primary.opacity(
                            isHovered ? AppStyles.Shell.Sidebar.ToolbarControl.hoverFillOpacity : 0
                        )
                    )
            )
            .onHover { isHovered = $0 }
    }
}

struct SidebarToolbarMenuButton<Icon: View, MenuContent: View>: View {
    let label: String
    @ViewBuilder let icon: () -> Icon
    @ViewBuilder let menuContent: () -> MenuContent

    var body: some View {
        Menu {
            menuContent()
        } label: {
            SidebarToolbarMenuLabel(icon: icon)
        }
        .accessibilityLabel(label)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(Color.secondary)
    }
}

struct SidebarToolbarDivider: View {
    var body: some View {
        Divider()
            .frame(height: AppStyles.Shell.Sidebar.ToolbarControl.dividerHeight)
    }
}

struct SidebarSortButton<SortValue: Equatable, Icon: View>: View {
    let sortValue: SortValue
    let isReversed: Bool
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let onToggle: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button(action: onToggle) {
            icon()
                .rotationEffect(.degrees(isReversed ? 180 : 0))
                .animation(.easeInOut(duration: AppStyles.General.Animation.standard), value: isReversed)
        }
        .buttonStyle(SidebarToolbarButtonStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct SidebarToolbarSortButton<SortValue: Equatable, TooltipTarget: Hashable, Icon: View>: View {
    let sortValue: SortValue
    let isReversed: Bool
    let label: String
    let accessibilityIdentifier: String
    let tooltipValue: ControlTooltipRenderValue
    @ViewBuilder let icon: () -> Icon
    let tooltipTarget: TooltipTarget?
    let tooltipCoordinateSpaceName: String?
    let frameAccessibilityIdentifier: String?
    let onHover: ((Bool) -> Void)?
    let onToggle: () -> Void

    init(
        sortValue: SortValue,
        isReversed: Bool,
        label: String,
        accessibilityIdentifier: String,
        tooltipValue: ControlTooltipRenderValue,
        @ViewBuilder icon: @escaping () -> Icon,
        tooltipTarget: TooltipTarget,
        tooltipCoordinateSpaceName: String,
        frameAccessibilityIdentifier: String? = nil,
        onHover: ((Bool) -> Void)? = nil,
        onToggle: @escaping () -> Void
    ) {
        self.sortValue = sortValue
        self.isReversed = isReversed
        self.label = label
        self.accessibilityIdentifier = accessibilityIdentifier
        self.tooltipValue = tooltipValue
        self.icon = icon
        self.tooltipTarget = tooltipTarget
        self.tooltipCoordinateSpaceName = tooltipCoordinateSpaceName
        self.frameAccessibilityIdentifier = frameAccessibilityIdentifier
        self.onHover = onHover
        self.onToggle = onToggle
    }

    fileprivate init(
        sortValue: SortValue,
        isReversed: Bool,
        label: String,
        accessibilityIdentifier: String,
        tooltipValue: ControlTooltipRenderValue,
        @ViewBuilder icon: @escaping () -> Icon,
        tooltipTarget: TooltipTarget?,
        tooltipCoordinateSpaceName: String?,
        frameAccessibilityIdentifier: String?,
        onHover: ((Bool) -> Void)?,
        onToggle: @escaping () -> Void
    ) {
        self.sortValue = sortValue
        self.isReversed = isReversed
        self.label = label
        self.accessibilityIdentifier = accessibilityIdentifier
        self.tooltipValue = tooltipValue
        self.icon = icon
        self.tooltipTarget = tooltipTarget
        self.tooltipCoordinateSpaceName = tooltipCoordinateSpaceName
        self.frameAccessibilityIdentifier = frameAccessibilityIdentifier
        self.onHover = onHover
        self.onToggle = onToggle
    }

    var body: some View {
        SidebarSortButton(
            sortValue: sortValue,
            isReversed: isReversed,
            accessibilityLabel: label,
            accessibilityIdentifier: accessibilityIdentifier,
            onToggle: onToggle
        ) {
            SidebarToolbarIcon(icon: icon)
        }
        .modifier(
            SidebarToolbarControlDecoration(
                label: label,
                tooltipValue: tooltipValue,
                tooltipTarget: tooltipTarget,
                tooltipCoordinateSpaceName: tooltipCoordinateSpaceName,
                frameAccessibilityIdentifier: frameAccessibilityIdentifier,
                onHover: onHover
            )
        )
    }
}

extension SidebarToolbarSortButton where TooltipTarget == SidebarToolbarNoTooltipTarget {
    init(
        sortValue: SortValue,
        isReversed: Bool,
        label: String,
        accessibilityIdentifier: String,
        tooltipValue: ControlTooltipRenderValue,
        @ViewBuilder icon: @escaping () -> Icon,
        onToggle: @escaping () -> Void
    ) {
        self.init(
            sortValue: sortValue,
            isReversed: isReversed,
            label: label,
            accessibilityIdentifier: accessibilityIdentifier,
            tooltipValue: tooltipValue,
            icon: icon,
            tooltipTarget: nil,
            tooltipCoordinateSpaceName: nil,
            frameAccessibilityIdentifier: nil,
            onHover: nil,
            onToggle: onToggle
        )
    }
}

struct SidebarToolbarActionButton<TooltipTarget: Hashable, Icon: View>: View {
    let label: String
    let accessibilityIdentifier: String
    let tooltipValue: ControlTooltipRenderValue
    @ViewBuilder let icon: () -> Icon
    let isActive: Bool
    let tooltipTarget: TooltipTarget?
    let tooltipCoordinateSpaceName: String?
    let frameAccessibilityIdentifier: String?
    let onHover: ((Bool) -> Void)?
    let action: () -> Void

    init(
        label: String,
        accessibilityIdentifier: String,
        tooltipValue: ControlTooltipRenderValue,
        @ViewBuilder icon: @escaping () -> Icon,
        isActive: Bool = false,
        tooltipTarget: TooltipTarget,
        tooltipCoordinateSpaceName: String,
        frameAccessibilityIdentifier: String? = nil,
        onHover: ((Bool) -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.accessibilityIdentifier = accessibilityIdentifier
        self.tooltipValue = tooltipValue
        self.icon = icon
        self.isActive = isActive
        self.tooltipTarget = tooltipTarget
        self.tooltipCoordinateSpaceName = tooltipCoordinateSpaceName
        self.frameAccessibilityIdentifier = frameAccessibilityIdentifier
        self.onHover = onHover
        self.action = action
    }

    fileprivate init(
        label: String,
        accessibilityIdentifier: String,
        tooltipValue: ControlTooltipRenderValue,
        @ViewBuilder icon: @escaping () -> Icon,
        isActive: Bool = false,
        tooltipTarget: TooltipTarget?,
        tooltipCoordinateSpaceName: String?,
        frameAccessibilityIdentifier: String?,
        onHover: ((Bool) -> Void)?,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.accessibilityIdentifier = accessibilityIdentifier
        self.tooltipValue = tooltipValue
        self.icon = icon
        self.isActive = isActive
        self.tooltipTarget = tooltipTarget
        self.tooltipCoordinateSpaceName = tooltipCoordinateSpaceName
        self.frameAccessibilityIdentifier = frameAccessibilityIdentifier
        self.onHover = onHover
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            SidebarToolbarIcon(icon: icon, isActive: isActive)
        }
        .buttonStyle(SidebarToolbarButtonStyle(isActive: isActive))
        .accessibilityLabel(label)
        .accessibilityIdentifier(accessibilityIdentifier)
        .modifier(
            SidebarToolbarControlDecoration(
                label: label,
                tooltipValue: tooltipValue,
                tooltipTarget: tooltipTarget,
                tooltipCoordinateSpaceName: tooltipCoordinateSpaceName,
                frameAccessibilityIdentifier: frameAccessibilityIdentifier,
                onHover: onHover
            )
        )
    }
}

struct SidebarToolbarGroupingButton<TooltipTarget: Hashable>: View {
    let label: String
    let selectionLabel: String
    let accessibilityIdentifier: String
    let tooltipValue: ControlTooltipRenderValue
    let isOpen: Bool
    let tooltipTarget: TooltipTarget
    let tooltipCoordinateSpaceName: String
    let frameAccessibilityIdentifier: String?
    let onHover: ((Bool) -> Void)?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppStyles.Shell.Sidebar.ToolbarControl.groupingContentSpacing) {
                Image(systemName: "rectangle.grid.1x3")
                    .font(.system(size: AppStyles.General.Icon.compact, weight: .medium))
                Text(selectionLabel)
                    .font(.system(size: AppStyles.General.Typography.textSm, weight: .medium))
                    .frame(
                        minWidth: AppStyles.Shell.Sidebar.ToolbarControl.groupingLabelMinimumWidth,
                        alignment: .leading
                    )
                Image(systemName: "chevron.down")
                    .font(.system(size: AppStyles.Shell.Sidebar.ToolbarControl.groupingChevronSize, weight: .semibold))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .foregroundStyle(isOpen ? Color.accentColor : Color.secondary)
            .padding(.horizontal, AppStyles.Shell.Sidebar.ToolbarControl.groupingHorizontalPadding)
            .frame(height: AppStyles.General.Button.compact)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarToolbarButtonStyle(isOpen: isOpen))
        .accessibilityLabel("\(label): \(selectionLabel)")
        .accessibilityIdentifier(accessibilityIdentifier)
        .modifier(
            SidebarToolbarControlDecoration(
                label: label,
                tooltipValue: tooltipValue,
                tooltipTarget: tooltipTarget,
                tooltipCoordinateSpaceName: tooltipCoordinateSpaceName,
                frameAccessibilityIdentifier: frameAccessibilityIdentifier,
                onHover: onHover
            )
        )
    }
}

extension SidebarToolbarActionButton where TooltipTarget == SidebarToolbarNoTooltipTarget {
    init(
        label: String,
        accessibilityIdentifier: String,
        tooltipValue: ControlTooltipRenderValue,
        @ViewBuilder icon: @escaping () -> Icon,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(
            label: label,
            accessibilityIdentifier: accessibilityIdentifier,
            tooltipValue: tooltipValue,
            icon: icon,
            isActive: isActive,
            tooltipTarget: nil,
            tooltipCoordinateSpaceName: nil,
            frameAccessibilityIdentifier: nil,
            onHover: nil,
            action: action
        )
    }
}

private struct SidebarToolbarControlDecoration<TooltipTarget: Hashable>: ViewModifier {
    let label: String
    let tooltipValue: ControlTooltipRenderValue
    let tooltipTarget: TooltipTarget?
    let tooltipCoordinateSpaceName: String?
    let frameAccessibilityIdentifier: String?
    let onHover: ((Bool) -> Void)?

    func body(content: Content) -> some View {
        anchoredContent(content)
            .controlHelp(tooltipValue)
            .onHover { onHover?($0) }
            .background {
                if let frameAccessibilityIdentifier {
                    AccessibilityLabelBridge(
                        identifier: frameAccessibilityIdentifier,
                        label: label,
                        exposesAccessibility: false
                    )
                }
            }
    }

    @ViewBuilder
    private func anchoredContent(_ content: Content) -> some View {
        if let tooltipTarget, let tooltipCoordinateSpaceName {
            content.hoverTooltipAnchor(tooltipTarget, in: tooltipCoordinateSpaceName)
        } else {
            content
        }
    }
}
