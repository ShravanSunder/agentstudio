import AgentStudioInfrastructure
import AppKit
import SwiftUI
import Testing

@testable import AgentStudioSharedComponents

@Suite("Sidebar toolbar control visual state")
struct SidebarToolbarControlVisualStateTests {
    @Test("selected segment expands to show its label")
    @MainActor
    func selectedSegmentExpandsToShowItsLabel() {
        let repoWidth = mountedSegmentedControlWidth(selection: 0)
        let allPanesWidth = mountedSegmentedControlWidth(selection: 1)

        #expect(allPanesWidth > repoWidth)
    }

    @Test("selected segment uses accent foreground and accent-tinted fill without borders")
    func selectedSegmentUsesBorderlessAccentPresentation() throws {
        let source = try String(
            contentsOfFile: "Sources/AgentStudio/SharedComponents/SidebarToolbarSegmentedControl.swift",
            encoding: .utf8
        )

        #expect(source.contains("Text(segment.label)"))
        #expect(source.contains("ChromeToolbarControlPalette.foregroundColor"))
        // The selected fill must come from the same shared palette the Zoom pill family uses (an
        // accent-tinted fill), not an ad-hoc Color.primary opacity — that generic grey fill remains
        // only for the unselected/hover/pressed states.
        #expect(source.contains("ChromeToolbarControlPalette.fillColor"))
        #expect(source.contains("visualState.fillOpacity"))
        #expect(!source.contains(".stroke("))
        #expect(!source.contains("ChromeToolbarControlPalette.strokeColor"))
    }

    @Test("selected label reveal follows the segment geometry transition")
    func selectedLabelRevealFollowsSegmentGeometryTransition() throws {
        let source = try String(
            contentsOfFile: "Sources/AgentStudio/SharedComponents/SidebarToolbarSegmentedControl.swift",
            encoding: .utf8
        )

        #expect(source.contains("selectedLabelInsertionTransition"))
        #expect(source.contains("selectedLabelRemovalTransition"))
        #expect(source.contains("labelRevealDelay"))
        #expect(source.contains(".combined(with: .opacity)"))
    }

    @Test("segmented control renders typed mode-name tooltips")
    func segmentedControlRendersTypedModeNameTooltips() throws {
        let controlSource = try String(
            contentsOfFile: "Sources/AgentStudio/SharedComponents/SidebarToolbarSegmentedControl.swift",
            encoding: .utf8
        )
        let repoExplorerSource = try String(
            contentsOfFile: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+CommandToolbar.swift",
            encoding: .utf8
        )

        #expect(controlSource.contains(".controlHelp(segment.tooltipValue)"))
        #expect(repoExplorerSource.contains("textOverride: groupingMode.title"))
    }

    @Test("interaction state precedence is disabled pressed open active hovered idle")
    func interactionStatePrecedence() {
        #expect(resolve(isEnabled: false, isHovered: true, isPressed: true, isActive: true, isOpen: true) == .disabled)
        #expect(resolve(isHovered: true, isPressed: true, isActive: true, isOpen: true) == .pressed)
        #expect(resolve(isHovered: true, isActive: true, isOpen: true) == .open)
        #expect(resolve(isHovered: true, isActive: true) == .active)
        #expect(resolve(isHovered: true) == .hovered)
        #expect(resolve() == .idle)
    }

    @Test("visible interaction states paint stronger fills than idle")
    func visibleInteractionStatesPaintFills() {
        #expect(SidebarToolbarControlVisualState.idle.fillOpacity == 0)
        #expect(SidebarToolbarControlVisualState.hovered.fillOpacity > 0)
        #expect(
            SidebarToolbarControlVisualState.pressed.fillOpacity
                > SidebarToolbarControlVisualState.hovered.fillOpacity
        )
        #expect(
            SidebarToolbarControlVisualState.open.fillOpacity
                >= SidebarToolbarControlVisualState.pressed.fillOpacity
        )
    }

    private func resolve(
        isEnabled: Bool = true,
        isHovered: Bool = false,
        isPressed: Bool = false,
        isActive: Bool = false,
        isOpen: Bool = false
    ) -> SidebarToolbarControlVisualState {
        SidebarToolbarControlVisualState.resolve(
            isEnabled: isEnabled,
            isHovered: isHovered,
            isPressed: isPressed,
            isActive: isActive,
            isOpen: isOpen
        )
    }

    @MainActor
    private func mountedSegmentedControlWidth(selection: Int) -> CGFloat {
        let segments = [
            SidebarToolbarSegment(
                value: 0,
                label: "By Repo",
                accessibilityIdentifier: "byRepo",
                tooltipValue: ControlTooltipRenderValue(text: "By Repo", shortcutDisplayText: nil),
                isEnabled: true
            ),
            SidebarToolbarSegment(
                value: 1,
                label: "All Panes",
                accessibilityIdentifier: "allPanes",
                tooltipValue: ControlTooltipRenderValue(text: "All Panes", shortcutDisplayText: nil),
                isEnabled: true
            ),
            SidebarToolbarSegment(
                value: 2,
                label: "By Tab",
                accessibilityIdentifier: "byTab",
                tooltipValue: ControlTooltipRenderValue(text: "By Tab", shortcutDisplayText: nil),
                isEnabled: true
            ),
        ]
        let hostingView = NSHostingView(
            rootView: SidebarToolbarSegmentedControl(
                segments: segments,
                selection: selection,
                icon: { _ in Image(systemName: "folder") },
                onSelect: { _ in }
            )
        )
        hostingView.frame = CGRect(origin: .zero, size: hostingView.fittingSize)
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize.width
    }
}
