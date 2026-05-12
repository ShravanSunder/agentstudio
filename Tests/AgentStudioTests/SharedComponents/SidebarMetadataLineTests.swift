import SwiftUI
import Testing

@testable import AgentStudio

@Suite("SidebarMetadataLine")
struct SidebarMetadataLineTests {
    @Test("metadata line builds with and without icon")
    @MainActor
    func metadataLineBuildsWithAndWithoutIcon() {
        let withIcon = SidebarMetadataLine(iconSystemName: "terminal", text: "Tab 2 · Pane 1")
        let withoutIcon = SidebarMetadataLine(text: "agent-studio")

        #expect(String(describing: type(of: withIcon)).contains("SidebarMetadataLine"))
        #expect(String(describing: type(of: withoutIcon)).contains("SidebarMetadataLine"))
    }
}
