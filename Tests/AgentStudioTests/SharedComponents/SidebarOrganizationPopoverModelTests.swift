import AgentStudioInfrastructure
import Testing

@testable import AgentStudioSharedComponents

@Suite("Sidebar organization popover model")
struct SidebarOrganizationPopoverModelTests {
    @Test("one keyboard sequence spans group then enabled subgroup options")
    func keyboardItemsSpanBothSections() {
        let model = SidebarOrganizationPopoverModel(
            group: section(title: "Group", values: [1, 2], selection: 1),
            subgroup: section(title: "Subgroup", values: [3, 4], selection: 3, disabled: [4])
        )

        #expect(
            model.keyboardItems.map(\.id) == [
                SidebarOrganizationPopoverItem(level: .group, value: 1),
                SidebarOrganizationPopoverItem(level: .group, value: 2),
                SidebarOrganizationPopoverItem(level: .subgroup, value: 3),
            ]
        )
    }

    @Test("absent and disabled subgroup rows cannot emit selection requests")
    func rejectsUnavailableSubgroupSelection() {
        let disabledSubgroup = SidebarOrganizationPopoverItem(level: .subgroup, value: 4)
        let configured = SidebarOrganizationPopoverModel(
            group: section(title: "Group", values: [1, 2], selection: 1),
            subgroup: section(title: "Subgroup", values: [3, 4], selection: 3, disabled: [4])
        )
        let withoutSubgroup = SidebarOrganizationPopoverModel(
            group: section(title: "Group", values: [1, 2], selection: 1),
            subgroup: nil
        )

        #expect(configured.selectionRequest(for: disabledSubgroup) == nil)
        #expect(
            withoutSubgroup.selectionRequest(
                for: SidebarOrganizationPopoverItem(level: .subgroup, value: 3)
            ) == nil
        )
        #expect(
            configured.selectionRequest(
                for: SidebarOrganizationPopoverItem(level: .group, value: 2)
            ) == SidebarOrganizationPopoverItem(level: .group, value: 2)
        )
    }

    private func section(
        title: String,
        values: [Int],
        selection: Int,
        disabled: Set<Int> = []
    ) -> SidebarOrganizationPopoverSection<Int> {
        SidebarOrganizationPopoverSection(
            title: title,
            options: values.map { value in
                SidebarToolbarSegment(
                    value: value,
                    label: "Option \(value)",
                    accessibilityIdentifier: "option-\(value)",
                    tooltipValue: ControlTooltipRenderValue(
                        text: "Option \(value)", shortcutDisplayText: nil
                    ),
                    isEnabled: !disabled.contains(value)
                )
            },
            selection: selection
        )
    }
}
