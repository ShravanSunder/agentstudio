import Foundation
import Testing

@Suite("PaneTabManagementHotPathTests")
struct PaneTabManagementHotPathTests {
    @Test("management layer observation is separated from broad AppKit state observation")
    func managementLayerObservationIsSeparatedFromBroadAppKitStateObservation() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Panes/PaneTabViewController.swift"),
            encoding: .utf8
        )

        let appKitObservation = try #require(
            source.architectureSlice(
                from: "private func observeForAppKitState()",
                to: "private func observeForManagementLayerState()"
            )
        )
        let managementObservation = try #require(
            source.architectureSlice(
                from: "private func observeForManagementLayerState()",
                to: "private func handleAppKitStateChange()"
            )
        )
        let managementHandler = try #require(
            source.architectureSlice(
                from: "private func handleManagementLayerStateChange()",
                to: "private func prunePaneInboxPresentationState()"
            )
        )

        #expect(!appKitObservation.contains("managementLayer"))
        #expect(managementObservation.contains("atom(\\.managementLayer).isActive"))
        #expect(!managementObservation.contains("repositoryTopologyAtom.repos"))
        #expect(!managementObservation.contains("recentTargets"))
        #expect(!managementObservation.contains("welcome"))

        #expect(!managementHandler.contains("syncTabContentHosts()"))
        #expect(!managementHandler.contains("updateVisibleTabHost()"))
        #expect(!managementHandler.contains("rebuildEmptyStateView()"))
        #expect(!managementHandler.contains("updateEmptyState()"))
        #expect(!managementHandler.contains("prunePaneInboxPresentationState()"))
        #expect(!managementHandler.contains("restoreVisibleViewsForActiveTabIfNeeded"))
    }
}

extension String {
    fileprivate func architectureSlice(from startMarker: String, to endMarker: String) -> String? {
        guard let start = range(of: startMarker)?.lowerBound,
            let end = range(of: endMarker, range: start..<endIndex)?.lowerBound
        else {
            return nil
        }
        return String(self[start..<end])
    }
}
