import SwiftUI

enum SidebarToolbarNoTooltipTarget: Hashable {}

struct SidebarToolbarIcon: View {
    let icon: CommandIcon
    var isActive = false

    var body: some View {
        icon.swiftUIImage(size: AppStyles.General.Icon.compact)
            .frame(
                width: AppStyles.General.Button.compact,
                height: AppStyles.General.Button.compact
            )
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .contentShape(Rectangle())
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
                .animation(.easeInOut(duration: AppStyles.General.Animation.standard), value: sortValue)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct SidebarToolbarSortButton<SortValue: Equatable, TooltipTarget: Hashable>: View {
    let sortValue: SortValue
    let isReversed: Bool
    let label: String
    let accessibilityIdentifier: String
    let tooltipValue: ControlTooltipRenderValue
    let icon: CommandIcon
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
        icon: CommandIcon,
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
        icon: CommandIcon,
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
        icon: CommandIcon,
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

struct SidebarToolbarActionButton<TooltipTarget: Hashable>: View {
    let label: String
    let accessibilityIdentifier: String
    let tooltipValue: ControlTooltipRenderValue
    let icon: CommandIcon
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
        icon: CommandIcon,
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
        icon: CommandIcon,
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
        .buttonStyle(.borderless)
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

extension SidebarToolbarActionButton where TooltipTarget == SidebarToolbarNoTooltipTarget {
    init(
        label: String,
        accessibilityIdentifier: String,
        tooltipValue: ControlTooltipRenderValue,
        icon: CommandIcon,
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
