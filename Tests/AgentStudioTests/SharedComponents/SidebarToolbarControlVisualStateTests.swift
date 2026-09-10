import AgentStudioInfrastructure
import AppKit
import SwiftUI
import Testing

@testable import AgentStudioSharedComponents

@Suite("Sidebar toolbar control visual state")
struct SidebarToolbarControlVisualStateTests {
    @Test(
        "outgoing and incoming label widths exchange together at intermediate progress",
        arguments: [CGFloat(0), 0.25, 0.5, 0.75, 1])
    @MainActor
    func labelWidthsExchangeTogether(progress: CGFloat) {
        func mountedWidth(fraction: CGFloat) -> CGFloat {
            let host = NSHostingView(
                rootView: SidebarToolbarLabelLayout(revealFraction: fraction) {
                    Color.clear.frame(width: 80, height: 20)
                })
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            return host.fittingSize.width
        }
        let outgoing = mountedWidth(fraction: 1 - progress)
        let incoming = mountedWidth(fraction: progress)
        #expect(abs(outgoing - 80 * (1 - progress)) < 0.5)
        #expect(abs(incoming - 80 * progress) < 0.5)
        #expect(abs(outgoing + incoming - 80) < 0.5)
    }

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

    @Test("selected label fades with segment geometry and stays clipped inside its segment")
    func selectedLabelSharesClippedSegmentTransition() throws {
        let source = try String(
            contentsOfFile: "Sources/AgentStudio/SharedComponents/SidebarToolbarSegmentedControl.swift",
            encoding: .utf8
        )

        #expect(!source.contains("if model.showsLabel(for: segment.value)"))
        #expect(source.contains("SidebarToolbarLabelLayout("))
        #expect(!source.contains(".transition("))
        #expect(source.contains(".clipped()"))
        #expect(source.contains("value: model.selection"))
        #expect(!source.contains(".delay("))
        #expect(!source.contains("AnyTransition.offset"))
    }

    @Test("organization popovers render command-catalog tooltips")
    func organizationPopoversRenderCommandCatalogTooltips() throws {
        let controlSource = try String(
            contentsOfFile: "Sources/AgentStudio/SharedComponents/SidebarToolbarSegmentedControl.swift",
            encoding: .utf8
        )
        let repoExplorerSource = try String(
            contentsOfFile: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+CommandToolbar.swift",
            encoding: .utf8
        )

        #expect(controlSource.contains(".controlHelp(segment.tooltipValue)"))
        #expect(repoExplorerSource.contains("tooltipValue: command.definition.controlTooltipRenderValue("))
        #expect(repoExplorerSource.contains("organizationAction.controlTooltipRenderValue("))
        #expect(repoExplorerSource.contains("selected.definition.controlTooltipRenderValue()"))
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
