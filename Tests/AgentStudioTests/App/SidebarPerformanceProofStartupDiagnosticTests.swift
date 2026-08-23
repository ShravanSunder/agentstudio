import Foundation
import Testing

struct SidebarPerformanceProofStartupDiagnosticTests {
    @Test("sidebar performance search driver uses native key events and policy cadence")
    func sidebarPerformanceSearchDriverUsesNativeKeyEventsAndPolicyCadence() throws {
        let source = try String(
            contentsOfFile:
                "Sources/AgentStudio/App/Boot/AppDelegate+SidebarPerformanceProofStartupDiagnostics.swift",
            encoding: .utf8
        )

        #expect(source.contains("window.firstResponder is NSTextView"))
        #expect(source.contains("NSEvent.keyEvent("))
        #expect(source.contains("window.sendEvent(event)"))
        #expect(source.contains("searchCharacterInterval"))
        #expect(source.contains("modifierFlags: modifiers"))
        #expect(source.contains("modifiers: [.command]"))
        #expect(source.contains("keyCode: 51"))
        #expect(!source.contains("setFilterText"))
        #expect(!source.contains("filterText ="))
        #expect(!source.contains("uiState."))
        #expect(!source.contains("AppCommandIPC"))
    }
}
