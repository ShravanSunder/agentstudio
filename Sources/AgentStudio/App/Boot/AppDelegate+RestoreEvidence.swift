import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSessions
import AgentStudioTerminal
import Foundation

extension AppDelegate {
    /// Composition captures capabilities once; subsequent gathering and trigger
    /// consumption run on their off-main owners, never through the atom store.
    func installRestoreEvidenceOwners(datastore: WorkspaceSQLiteDatastoreActor, sessionDirectory: String) async {
        let launchId = UUIDv7.generate()
        let workspaceId = store.identityAtom.workspaceId
        let bootId = try? await WorkspaceUndoJournalClock.current().bootID
        restoreLaunchBootId = bootId
        let readiness = RestoreResumeReadiness(
            clock: ContinuousClock(), deadline: AppPolicies.Restore.resumeReadinessDeadline,
            launchId: launchId, factSink: { _, _ in })
        restoreResumeReadiness = readiness
        guard let bootId else {
            await readiness.publish(.unavailable)
            return
        }
        let repository = SQLitePaneForegroundObservationRepository(
            access: WorkspaceForegroundObservationSQLiteAccess(datastore: datastore), observerLaunchId: launchId,
            paneSessions: { try await datastore.liveZmxSessionsByPane(workspaceId: workspaceId) })
        let watcher = DarwinProcessExitWatcher()
        let observer = PaneForegroundObserver(
            clock: ContinuousClock(),
            policy: .init(
                lookSettleDelay: AppPolicies.Restore.lookSettleDelay,
                lookMaxDelay: AppPolicies.Restore.lookMaxDelay, quitLookDeadline: AppPolicies.Restore.quitLookDeadline),
            repository: repository,
            probe: DarwinTerminalForegroundProbe(sessionDirectory: sessionDirectory, bootId: bootId),
            exitWatcher: watcher, observerLaunchId: launchId, factSink: { _, _ in })
        restoreForegroundObserver = observer
        restoreForegroundExitWatcher = watcher
        let (stream, continuation) = AsyncStream.makeStream(
            of: ForegroundLookTrigger.self, bufferingPolicy: .unbounded)
        restoreForegroundLifecycleContinuation = continuation
        restoreForegroundTriggerSink = { continuation.yield($0) }
        restoreForegroundLifecycleTask = Task { await consumeRestoreLifecycle(stream, observer: observer) }
    }

    func makeRestoreForegroundLookSink() -> (@Sendable (ForegroundLookTrigger, UUID) async -> Void)? {
        guard let observer = restoreForegroundObserver else { return nil }
        return { trigger, paneId in await observer.note(trigger, pane: paneId) }
    }

    func makeColdResumePlanResolver() -> @Sendable (PaneId, TerminalColdRestorePlan) async -> TerminalColdRestorePlan {
        let observer = restoreForegroundObserver
        let readiness = restoreResumeReadiness
        let bootId = restoreLaunchBootId
        let repository = workspaceSQLiteDatastore.map {
            SessionsRepository(sqliteAccess: WorkspaceSessionsSQLiteAccess(datastore: $0))
        }
        return { paneId, plan in
            // Take the old evidence before waiting, and before native activation
            // can admit this restored session's first foreground look.
            let observation = try? await observer?.takePreRestoreObservation(paneId: paneId.uuid)
            let state = await readiness?.wait(paneId: paneId.uuid) ?? .unavailable
            let snapshot = try? await repository?.snapshot(.pane(paneId.uuid, page: .init(limit: 1, after: nil)))
            let binding = snapshot?.currentBinding
            let evidence: ResumeEvidence
            if state == .ready, let repository, let bootId {
                // Only positively cold classifications reach this resolver:
                // the complete inventory already proved this session dead.
                evidence = await SessionsResumeResolver(repository: repository).resumeEvidence(
                    for: .init(
                        paneId: paneId.uuid, zmxSessionId: plan.sessionID, observation: observation,
                        launchBootId: bootId, inventory: .complete([:])))
            } else {
                evidence = .unknown(.reportsNotTakenIn)
            }
            return TerminalColdRestorePlanBuilder.applyingResumeEvidence(
                evidence,
                providerIdentifier: binding?.providerIdentifier ?? "agent",
                providerSessionId: binding?.providerConversationId ?? "unknown", to: plan)
        }
    }

    func shutdownRestoreEvidenceOwners() async {
        restoreForegroundLifecycleContinuation?.finish()
        await restoreForegroundLifecycleTask?.value
        restoreForegroundLifecycleTask = nil
        restoreForegroundLifecycleContinuation = nil
        restoreForegroundTriggerSink = nil
        await restoreForegroundObserver?.shutdown()
        restoreForegroundExitWatcher?.shutdown()
        await restoreResumeReadiness?.shutdown()
    }
}

@concurrent nonisolated private func consumeRestoreLifecycle(
    _ stream: AsyncStream<ForegroundLookTrigger>, observer: PaneForegroundObserver<ContinuousClock>
) async {
    for await trigger in stream { await observer.noteLifecycle(trigger) }
}
