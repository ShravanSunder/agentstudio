import AppKit
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@Suite("GhosttyHostConfigSnapshot")
@MainActor
struct GhosttyHostConfigSnapshotTests {
    @Test("ghostty app handle override keeps scrollbar actions enabled")
    func ghosttyAppHandleOverrideKeepsScrollbarActionsEnabled() {
        let overrideContents = Ghostty.AppHandle.overrideContents()

        #expect(overrideContents.contains("scroll-to-bottom = no-keystroke, no-output"))
        #expect(overrideContents.contains("scrollbar = never") == false)
    }

    @Test("nil config falls back to system scrollbar policy and window background color")
    func nilConfigFallsBackToSystemScrollbarPolicyAndWindowBackgroundColor() {
        let snapshot = GhosttyHostConfigSnapshot(configHandle: nil)

        #expect(snapshot.scrollbarPolicy == .system)
        #expect(snapshot.backgroundColor == .windowBackgroundColor)
    }
}
