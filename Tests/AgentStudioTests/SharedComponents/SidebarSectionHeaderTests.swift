import SwiftUI
import Testing

@testable import AgentStudio

@Suite("SidebarSectionHeader")
struct SidebarSectionHeaderTests {
    @Test("empty trailing initializer builds")
    @MainActor
    func emptyTrailingInitializerBuilds() {
        let header = SidebarSectionHeader(
            title: "askluna",
            isExpanded: true,
            onToggle: {}
        )

        #expect(String(describing: type(of: header)).contains("SidebarSectionHeader"))
    }
}
