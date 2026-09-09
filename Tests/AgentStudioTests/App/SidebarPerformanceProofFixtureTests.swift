import AgentStudioInfrastructure
import AgentStudioTestSupport
import AppKit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

extension SidebarPerformanceProofStartupDiagnosticTests {
    @Test("strict fixture refreshes two real roots plus one isolated control root")
    func strictFixtureRefreshesTwoRealRootsPlusOneIsolatedControlRoot() throws {
        let fixtureSource = try String(
            contentsOfFile: "Sources/AgentStudio/App/Boot/SidebarPerformanceProofFixture+RealSize.swift",
            encoding: .utf8
        )
        let diagnosticSource = try String(
            contentsOfFile:
                "Sources/AgentStudio/App/Boot/AppDelegate+SidebarPerformanceProofStartupDiagnostics.swift",
            encoding: .utf8
        )
        let combinedSource = fixtureSource + diagnosticSource

        let requiredRoots = try #require(
            combinedSource.range(of: "strictWatchedRootURLs")
        )
        let addWatchedPath = try #require(
            combinedSource.range(of: "mutationCoordinator.addWatchedPath")
        )
        let refreshWatchedFolders = try #require(
            diagnosticSource.range(of: "commands.refreshWatchedFolders")
        )
        let completedSummary = try #require(
            diagnosticSource.range(of: "WatchedFolderRefreshSummary")
        )
        #expect(requiredRoots.lowerBound < addWatchedPath.lowerBound)
        #expect(completedSummary.lowerBound < refreshWatchedFolders.lowerBound)
        #expect(fixtureSource.contains("controlRootURL: URL"))
        #expect(fixtureSource.contains("rootURLs + [controlRootURL]"))
        #expect(combinedSource.contains("summary.repoPaths(in: rootURL).isEmpty"))
        #expect(combinedSource.contains("summary.repoPaths(in: controlRootURL) == [controlRootURL]"))
        #expect(combinedSource.contains("controlRootPresent: true"))
        #expect(combinedSource.contains("control_root_present"))
        #expect(combinedSource.contains("unknownRepositoryCount"))
        #expect(combinedSource.contains("unknownWorktreeCount"))
        #expect(combinedSource.contains("unknown_repository_count"))
        #expect(combinedSource.contains("unknown_worktree_count"))
        #expect(!diagnosticSource.contains("unclassifiedRepositoryCount"))
        #expect(!diagnosticSource.contains("populateRealSizeTopology"))

        let preparationStart = try #require(
            diagnosticSource.range(of: "private func prepareStrictSidebarPerformanceProofFixture(")
        )
        let preparationEnd = try #require(
            diagnosticSource.range(of: "private struct StrictColdRepositoryProof")
        )
        let preparation = diagnosticSource[preparationStart.lowerBound..<preparationEnd.lowerBound]
        let controlPreparation = try #require(
            preparation.range(of: "await prepareStrictSidebarControl(action: action)"))
        let fleetRegistration = try #require(
            preparation.range(of: "SidebarPerformanceProofFixture.registerStrictWatchedRoots("))
        let fleetScan = try #require(
            preparation.range(of: "refreshStrictWatchedRootsAndAwaitZeroLogicalDebt(watchedPaths)"))
        #expect(controlPreparation.lowerBound < fleetRegistration.lowerBound)
        #expect(fleetRegistration.lowerBound < fleetScan.lowerBound)
        let controlStart = try #require(diagnosticSource.range(of: "private func prepareStrictSidebarControl("))
        let controlPreparationSource = diagnosticSource[controlStart.lowerBound...]
        let controlScan = try #require(
            controlPreparationSource.range(of: "controlSummary.repoPaths(in: controlRootURL)"))
        let coldProof = try #require(
            controlPreparationSource.range(of: "await proveStrictColdRepositoryControl(controlRootURL)"))
        #expect(controlScan.lowerBound < coldProof.lowerBound)
    }

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

    @Test("strict cold control accepts only completed remote refresh settlement")
    func strictColdControlAcceptsOnlyCompletedRemoteRefreshSettlement() {
        let repositoryID = UUIDv7.generate()
        let attemptID = UUIDv7.generate()
        let accepted = RepositoryFactUpdateProgress.admitted(
            repoId: repositoryID,
            attemptId: attemptID,
            applicableSources: [.remoteReferences],
            terminalResultsBySource: [:]
        ).settled([.remoteReferences: .completed])
        #expect(AppDelegate.strictRemoteRepositoryUpdateCompleted(accepted))

        let noApplicable = RepositoryFactUpdateProgress.admitted(
            repoId: repositoryID,
            attemptId: attemptID,
            applicableSources: [],
            terminalResultsBySource: [.remoteReferences: .notApplicable]
        )
        #expect(!AppDelegate.strictRemoteRepositoryUpdateCompleted(noApplicable))

        let threeSources = RepositoryFactUpdateProgress.admitted(
            repoId: repositoryID,
            attemptId: attemptID,
            applicableSources: Set(RepositoryFactSource.allCases),
            terminalResultsBySource: [:]
        ).settled(
            Dictionary(
                uniqueKeysWithValues: RepositoryFactSource.allCases.map { ($0, .completed) }
            )
        )
        #expect(!AppDelegate.strictRemoteRepositoryUpdateCompleted(threeSources))

        let failedRemote = RepositoryFactUpdateProgress.admitted(
            repoId: repositoryID,
            attemptId: attemptID,
            applicableSources: [.remoteReferences],
            terminalResultsBySource: [:]
        ).settled([.remoteReferences: .failed])
        #expect(!AppDelegate.strictRemoteRepositoryUpdateCompleted(failedRemote))
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
