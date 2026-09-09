import AgentStudioCore
import Foundation

#if DEBUG
    @MainActor
    extension AppDelegate {
        func prepareStrictSidebarHistoricalInactiveActivity(
            action: AgentStudioStartupDiagnosticAction,
            summary: WatchedFolderRefreshSummary,
            rootURLs: [URL]
        ) async -> Int? {
            let topology = store.repositoryTopologyAtom
            let repositoryPathsByID = Dictionary(
                uniqueKeysWithValues: topology.repositoryIdsInOrder.compactMap { repositoryID in
                    topology.repo(repositoryID).map { (repositoryID, $0.repoPath) }
                }
            )
            let classificationInput = captureStrictSidebarRepositoryActivityInput(
                referenceDate: Date()
            )
            guard
                let seed = await SidebarPerformanceProofFixture.makeHistoricalInactiveActivitySeed(
                    classificationInput: classificationInput,
                    repositoryPathsByID: repositoryPathsByID,
                    watchedRootSummary: summary,
                    rootURLs: rootURLs
                ),
                !seed.repositoryIDs.isEmpty
            else {
                recordIncompleteHistoricalActivityDiagnostic(action)
                return nil
            }
            do {
                _ = try await repositoryLocalActivityStore.commitAsync(seed.commit)
            } catch {
                recordIncompleteHistoricalActivityDiagnostic(action)
                return nil
            }
            await workspaceSurfaceCoordinator.settleRepositoryFactDemandAdmissionForPerformanceProof()
            return seed.repositoryIDs.count
        }

        private func recordIncompleteHistoricalActivityDiagnostic(
            _ action: AgentStudioStartupDiagnosticAction
        ) {
            recordBlockedSidebarPerformanceProofDiagnostic(
                action: action,
                reason: "historical_inactive_activity_fixture_incomplete"
            )
        }
    }
#endif
