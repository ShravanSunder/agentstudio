import AgentStudioInfrastructure
import Testing

@testable import AgentStudioSharedComponents

@Suite("Sidebar headless toggle")
struct SidebarToggleModelTests {
    @Test("icon-only controls never reveal labels after selection changes")
    func iconsNeverRevealLabels() {
        for selection in [0, 1] {
            let model = SidebarToggleModel(segments: segments, selection: selection, content: .icons)
            #expect(model.showsIcons)
            #expect(!model.showsLabel(for: 0))
            #expect(!model.showsLabel(for: 1))
            #expect(model.isSelected(selection))
        }
    }

    @Test("screen labels share the toggle without native Picker styling")
    func screenLabelsStayVisible() {
        let model = SidebarToggleModel(segments: segments, selection: 0, content: .labels)
        #expect(!model.showsIcons)
        #expect(model.showsLabel(for: 0))
        #expect(model.showsLabel(for: 1))
    }

    @Test("disabled and absent options cannot emit a selection request")
    func rejectsUnavailableSelection() {
        let model = SidebarToggleModel(segments: segments, selection: 0, content: .icons)
        #expect(model.selectionRequest(for: 0) == 0)
        #expect(model.selectionRequest(for: 1) == nil)
        #expect(model.selectionRequest(for: 2) == nil)
    }

    private var segments: [SidebarToolbarSegment<Int>] {
        [0, 1].map { value in
            SidebarToolbarSegment(
                value: value, label: "Option", accessibilityIdentifier: "option-\(value)",
                tooltipValue: ControlTooltipRenderValue(text: "Option", shortcutDisplayText: nil), isEnabled: value == 0
            )
        }
    }
}
