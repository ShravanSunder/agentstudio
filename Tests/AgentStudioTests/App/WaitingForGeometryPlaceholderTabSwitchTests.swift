import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

/// S8's tab-switch claim (SPEC R5 presentation): split from
/// `WorkspaceSurfaceCoordinatorTerminalRestoreIntegrationTests` into its own
/// suite since that file was already at the repo's file-length gate. This is
/// a pure `activeTabHasMissingVisibleView` integration test — it needs only
/// the already-shared, non-private `makeWorkspaceSurfaceCoordinatorViewFactoryHarness()`
/// from `WorkspaceSurfaceCoordinatorViewFactoryTestSupport.swift`.
@MainActor
@Suite("Workspace surface coordinator waiting-for-geometry placeholder", .serialized)
struct WaitingForGeometryPlaceholderTabSwitchTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("a tab switch does not re-enter restore for a waitingForGeometry pane")
    func aTabSwitchDoesNotReEnterRestoreForAWaitingForGeometryPane() throws {
        // Arrange
        let harness = makeWorkspaceSurfaceCoordinatorViewFactoryHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let pane = harness.store.createPane()
        let tab = Tab(paneId: pane.id, name: "Waiting")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        // Sanity: a `.preparing` placeholder for this same visible pane IS
        // treated as missing — proving the harness genuinely discriminates
        // by mode rather than always reporting nothing missing.
        harness.coordinator.registerTerminalPlaceholderIfNeeded(for: pane, mode: .preparing)
        #expect(harness.coordinator.activeTabHasMissingVisibleView(tab) == true)

        // Act: the settlement transition (S8) reconfigures the same host to
        // `.waitingForGeometry`.
        harness.coordinator.registerTerminalPlaceholderIfNeeded(for: pane, mode: .waitingForGeometry)

        // Assert: a tab switch's missing-view check no longer treats this
        // pane as needing restore, so it neither creates a surface nor
        // re-enters restore for it.
        #expect(harness.coordinator.activeTabHasMissingVisibleView(tab) == false)
    }
}
