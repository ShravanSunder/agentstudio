import Foundation
import Testing

@testable import AgentStudioTestSupport

@Suite("TabClickHotPathArchitectureTests")
struct TabClickHotPathArchitectureTests {
    @Test("tab selection observation excludes repository and fleet pane facts")
    func tabSelectionObservationIsKeyedToTabFacts() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Panes/PaneTabViewController.swift"),
            encoding: .utf8
        )
        let observation = try #require(
            source.tabClickArchitectureSlice(
                from: "private func observeForTabSelectionState()",
                to: "private func observeForEmptyState()"
            )
        )

        #expect(observation.contains("tabShellAtom.orderedTabIds"))
        #expect(observation.contains("tabShellAtom.activeTabId"))
        #expect(observation.contains("tabLayoutAtom.tab(activeTabId)"))
        #expect(!observation.contains("repositoryTopologyAtom"))
        #expect(!observation.contains("tabLayoutAtom.tabs"))
        #expect(!observation.contains("paneIDs"))
        #expect(!observation.contains("await"))
    }

    @Test("active tab restore evaluates only the selected tab's pane and geometry facts")
    func activeTabRestoreAvoidsFleetEvaluation() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ActiveTabRestore.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("activeTab.allPaneIds"))
        #expect(source.contains("resolveInitialFrames(for: activeTab"))
        #expect(!source.contains("graphAtom.paneIDs"))
        #expect(!source.contains("resolveInitialFramesByTabId"))
        #expect(!source.contains("tabLayoutAtom.tabs"))
        #expect(!source.contains("await"))

        let placeholderSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+TerminalPlaceholders.swift"
            ),
            encoding: .utf8
        )
        let missingVisibleViewCheck = try #require(
            placeholderSource.tabClickArchitectureSlice(
                from: "func activeTabHasMissingVisibleView(",
                to: "return false"
            )
        )
        #expect(missingVisibleViewCheck.contains("activeTab.allPaneIds"))
        #expect(!missingVisibleViewCheck.contains("graphAtom.paneIDs"))
    }
}

extension String {
    fileprivate func tabClickArchitectureSlice(from startMarker: String, to endMarker: String) -> String? {
        guard let start = range(of: startMarker)?.lowerBound,
            let end = range(of: endMarker, range: start..<endIndex)?.lowerBound
        else {
            return nil
        }
        return String(self[start..<end])
    }
}
