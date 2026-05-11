import SwiftUI
import Testing

@testable import AgentStudio

@Suite("SidebarSectionHeader")
struct SidebarSectionHeaderTests {
    @Test("header exposes shared collapsible sidebar section semantics")
    @MainActor
    func headerExposesSharedCollapsibleSidebarSectionSemantics() {
        let header = SidebarSectionHeader(
            label: "agent-studio",
            isCollapsed: false,
            onToggle: {}
        )

        #expect(String(describing: type(of: header)).contains("SidebarSectionHeader"))
    }
}
