import AgentStudioInfrastructure

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

/// Controlled selection semantics shared by sidebar toggle renderers. No UI or state-owner dependency.
package struct SidebarToggleModel<Value: Hashable> {
    package enum Content {
        case icons
        case selectedLabel
        case labels
    }

    package let segments: [SidebarToolbarSegment<Value>]
    package let selection: Value?
    package let content: Content

    package init(segments: [SidebarToolbarSegment<Value>], selection: Value?, content: Content) {
        self.segments = segments
        self.selection = selection
        self.content = content
    }

    package func isSelected(_ value: Value) -> Bool { value == selection }

    package func showsLabel(for value: Value) -> Bool {
        switch content {
        case .icons: false
        case .selectedLabel: isSelected(value)
        case .labels: true
        }
    }

    package var showsIcons: Bool { content != .labels }

    package func selectionRequest(for value: Value) -> Value? {
        segments.first { $0.value == value && $0.isEnabled }?.value
    }
}
