import AgentStudioCLIStore
import AgentStudioCore
import AgentStudioSessions
import Foundation

extension AppDelegate {
    var cliStoreChannel: CLIStoreChannel {
        switch appIPCServerChannel {
        case .stable: .stable
        case .beta: .beta
        case .debug: .debug
        }
    }

    func makeCLILifecycleReportIntake(
        ingestion: SessionsIngestion, datastore: WorkspaceSQLiteDatastoreActor, workspaceID: UUID,
        canonicalPaneMembership: @escaping @MainActor @Sendable (UUID, UUID) -> Bool
    )
        -> CLILifecycleReportIntake
    {
        let admission = AgentStudioIPCSessionsAdapter(
            ingestion: ingestion,
            providerRegistry: SessionsProviderAdapterRegistry(profiles: appIPCSessionsProviderProfiles),
            activityClock: paneActivityClock, foregroundLookSink: makeRestoreForegroundLookSink(),
            resumedSessionStartSink: terminalActivityRouter?.resumedSessionStartSink)
        let principalRegistry = appIPCPrincipalRegistry!
        let intake = CLILifecycleReportIntake(
            storeURL: appIPCPaths.cliStoreURL, expectedChannel: cliStoreChannel, admission: admission,
            sqliteAccess: WorkspaceSessionsSQLiteAccess(datastore: datastore),
            workspaceID: workspaceID, paneExists: canonicalPaneMembership,
            finalRevokedPaneIDs: { principalRegistry.finalRevokedPaneIDsSnapshot() },
            awaitsLaunchInitialization: true,
            refusalProbe: { reason in appLogger.info("Lifecycle report refused: \(reason.rawValue, privacy: .public)") }
        )
        appCLILifecycleReportIntake = intake
        return intake
    }

    func initializeLifecycleIntake(_ intake: CLILifecycleReportIntake, ingestion: SessionsIngestion) async {
        let readiness = restoreResumeReadiness
        await intake.initializeForLaunch { launchIntake in
            if let readiness {
                await AppIPCDeferredInitialization.prepareResumeReadiness(readiness: readiness, intake: launchIntake) {
                    _ = try await ingestion.prepareForLaunch(at: Date())
                }
            } else {
                let boundary: LifecycleReportBoundary
                do {
                    boundary = try await launchIntake.captureListenerReadyBoundary()
                } catch {
                    _ = try? await ingestion.prepareForLaunch(at: Date())
                    appLogger.warning("Lifecycle launch intake unavailable")
                    return
                }
                do {
                    _ = try await ingestion.prepareForLaunch(at: Date())
                    try await launchIntake.takeIn(through: boundary)
                } catch {
                    appLogger.warning("Lifecycle launch intake unavailable")
                }
            }
        }
    }

    func finishAppIPCSessionsIngestion() async {
        await appCLILifecycleReportIntake?.finish()
        appCLILifecycleReportIntake = nil
        guard let ingestion = appIPCSessionsIngestion else { return }
        appIPCSessionsIngestion = nil
        await ingestion.finish()
    }

}
