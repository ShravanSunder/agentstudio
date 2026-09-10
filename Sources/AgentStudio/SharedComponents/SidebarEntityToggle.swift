import AgentStudioInfrastructure
import SwiftUI

/// The sidebar's original entity toggle: entity glyphs, muted idle icons and accent selection.
@MainActor
package struct SidebarEntityToggle<Value: Hashable>: View {
    private let segments: [SidebarToolbarSegment<Value>]
    private let selection: Value
    private let octiconLoader: OcticonLoader
    private let entityIcon: (Value) -> AppEntityIcon
    private let onSelect: (Value) -> Void

    package init(
        segments: [SidebarToolbarSegment<Value>],
        selection: Value,
        octiconLoader: OcticonLoader,
        entityIcon: @escaping (Value) -> AppEntityIcon,
        onSelect: @escaping (Value) -> Void
    ) {
        self.segments = segments
        self.selection = selection
        self.octiconLoader = octiconLoader
        self.entityIcon = entityIcon
        self.onSelect = onSelect
    }

    package var body: some View {
        SidebarToolbarSegmentedControl(
            segments: segments,
            selection: selection,
            content: .selectedLabel,
            icon: { value in
                entityIcon(value).swiftUIImage(
                    loader: octiconLoader,
                    size: AppStyles.General.Icon.compact,
                    foregroundOverride: value == selection ? AppStyles.General.Accent.primaryColor : nil
                )
            },
            onSelect: onSelect
        )
    }
}
