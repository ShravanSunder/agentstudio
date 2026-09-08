import AgentStudioInfrastructure
import AgentStudioTestSupport
import AppKit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

extension SidebarPerformanceProofStartupDiagnosticTests {
    @Test("fresh strict cold control starts unknown before real FSEvent promotion")
    func freshStrictColdControlStartsUnknown() {
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let activity = RepositoryActivityClassifier.classify(
            RepositoryActivityClassificationInput(
                repositories: [
                    RepositoryActivityTopology(
                        repositoryID: repositoryID,
                        repositoryStableKey: "strict-cold-control",
                        worktreeStableKeysByID: [worktreeID: "strict-cold-control"]
                    )
                ],
                openWorktreeIDs: [],
                localActivityHydrationDisposition: .authoritative,
                repositoryLocalActivityByStableKey: [:],
                referenceDate: Date(),
                inactivityHorizon: AppPolicies.EntityRecency.applicationActivityHorizon
            )
        )

        #expect(activity.unknownRepositoryIDs == [repositoryID])
        #expect(
            AppDelegate.strictColdRepositoryControlIsEligible(
                repositoryID: repositoryID,
                activity: activity
            )
        )
    }

    @Test("strict pane fixture creates five tabs and twenty nonterminal pane models")
    func strictPaneFixtureCreatesOnlyNonterminalPaneModels() throws {
        withTestCoreAtoms { _ in
            let store = WorkspaceStore()
            let viewRegistry = ViewRegistry()
            let placeholderFileURL = URL(fileURLWithPath: "/tmp/sidebar-performance-placeholder.txt")

            #expect(
                SidebarPerformanceProofFixture.populateStrictPaneFleet(
                    store: store,
                    viewRegistry: viewRegistry,
                    placeholderFileURL: placeholderFileURL
                )
            )
            #expect(
                store.tabLayoutAtom.tabs.count
                    == AppPolicies.SidebarPerformanceProof.strictTabCount
            )
            let panes = store.paneAtom.paneSnapshot().values
            #expect(panes.count == AppPolicies.SidebarPerformanceProof.strictPaneModelCount)
            #expect(
                panes.allSatisfy { pane in
                    if case .codeViewer(let state) = pane.content {
                        return state.filePath == placeholderFileURL
                    }
                    return false
                }
            )
        }
    }

}
