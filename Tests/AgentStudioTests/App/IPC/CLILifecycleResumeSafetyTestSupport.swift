import AgentStudioInfrastructure
import AgentStudioSessions
import AgentStudioTerminal
import AgentStudioTestHarness
import AgentStudioTestSupport
import Foundation
import GRDB
import Testing

@testable import AgentStudio
@testable import AgentStudioCLIStore
@testable import AgentStudioCore

func persistLifecycleSafetyLook(_ fixture: LifecycleIntakeFileFixture) async throws -> PaneForegroundObservation {
    let fetched = try await fixture.binding()
    let binding = try #require(fetched)
    let identity = try ZmxSessionIdentity(
        version: 1, bootID: "earlier-boot", daemon: .init(pid: 50, startSeconds: 1, startMicroseconds: 0),
        terminalLeader: .init(pid: 51, startSeconds: 1, startMicroseconds: 0), processGroupID: 51, sessionCreatedAt: 1
    ).encoded()
    let launchID = UUIDv7.generate()
    let look = PaneForegroundObservation(
        paneId: fixture.paneID, zmxSessionId: .generateUUIDv7(), sessionIdentity: identity,
        bindingGenerationId: binding.bindingGenerationId, program: .codex, observerLaunchId: launchID,
        sequence: 1, observedAt: fixture.now)
    let repository = SQLitePaneForegroundObservationRepository(
        access: TestForegroundSQLiteAccess(databaseQueue: fixture.access.queue), observerLaunchId: launchID)
    let admission = try await repository.admit(look)
    #expect(admission == .admitted)
    return look
}

func storedLifecycleSafetyVerdict(_ fixture: LifecycleIntakeFileFixture, sessionID: ZmxSessionID) async throws
    -> ResumeEvidence
{
    let repository = SQLitePaneForegroundObservationRepository(
        access: TestForegroundSQLiteAccess(databaseQueue: fixture.access.queue), observerLaunchId: UUIDv7.generate())
    let look = try await repository.load(paneId: fixture.paneID)
    return await SessionsResumeResolver(repository: fixture.repository).resumeEvidence(
        for: .init(
            paneId: fixture.paneID, zmxSessionId: sessionID, observation: look,
            launchBootId: "current-boot", inventory: .complete([:])))
}

func closeLifecycleSafetyFiles(_ fixture: LifecycleIntakeFileFixture) async throws {
    await fixture.close()
    try await valueFromDedicatedThread { try fixture.access.queue.close() }
}

/// Reopens local history and reads an existing store identity without creating or migrating a CLI store.
func reopenLifecycleSafetyFiles(_ previous: LifecycleIntakeFileFixture) async throws -> LifecycleIntakeFileFixture {
    let prepared = try await valueFromDedicatedThread {
        let storeID: UUID
        if FileManager.default.fileExists(atPath: previous.storeURL.path) {
            let reader = try CLIStore.openReader(url: previous.storeURL, expectedChannel: .debug).get()
            storeID = reader.identity.storeID
            try reader.databaseQueue.close()
        } else {
            storeID = previous.storeID
        }
        return (storeID, try DatabaseQueue(path: previous.rootURL.appending(path: "local.sqlite").path))
    }
    let access = LifecycleTestSQLiteAccess(queue: prepared.1)
    let repository = SessionsRepository(sqliteAccess: access)
    let ingestion = SessionsIngestion(
        repository: repository, limits: .init(maximumPendingPerPane: 32, maximumPendingGlobal: 128), probe: { _ in })
    return LifecycleIntakeFileFixture(
        rootURL: previous.rootURL, storeURL: previous.storeURL, workspaceID: previous.workspaceID,
        paneID: previous.paneID, storeID: prepared.0, access: access, repository: repository, ingestion: ingestion,
        members: LifecyclePaneMembership([previous.paneID]), refusals: LifecycleRefusalLedger(),
        intakes: LifecycleIntakeOwnerLedger())
}

func removeLifecycleSafetyStore(_ fixture: LifecycleIntakeFileFixture, replace: Bool) async throws -> UUID? {
    try await valueFromDedicatedThread {
        // All prior intake/CLI operations have joined. Close a final writer to checkpoint its own WAL.
        let oldWriter = try CLIStore.openWriter(url: fixture.storeURL, channel: .debug).get()
        try oldWriter.databaseQueue.close()
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: fixture.storeURL.path + suffix)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        guard replace else { return nil }
        let writer = try CLIStore.openWriter(url: fixture.storeURL, channel: .debug).get()
        let identity = writer.identity.storeID
        try writer.databaseQueue.close()
        return identity
    }
}

@MainActor
func productionLifecycleSafetyColdPlan(_ fixture: LifecycleIntakeFileFixture, look: PaneForegroundObservation)
    async throws -> (plan: TerminalColdRestorePlan, readiness: RestoreResumeReadinessResult)
{
    let prepared = try await valueFromDedicatedThread {
        let coreQueue = try DatabaseQueue(path: fixture.rootURL.appending(path: "core.sqlite").path)
        let core = WorkspaceCoreRepository(databaseWriter: coreQueue)
        try core.migrate()
        let local = WorkspaceLocalRepository(workspaceId: fixture.workspaceID, databaseWriter: fixture.access.queue)
        return (core, local)
    }
    let datastore = try await preparedWorkspaceSQLiteDatastore(
        coreRepository: prepared.0, preparedApplicationLocalRepository: prepared.1)
    let observations = SQLitePaneForegroundObservationRepository(
        access: WorkspaceForegroundObservationSQLiteAccess(datastore: datastore), observerLaunchId: UUIDv7.generate())
    let observer = PaneForegroundObserver(
        clock: ContinuousClock(),
        policy: .init(lookSettleDelay: .seconds(5), lookMaxDelay: .seconds(60), quitLookDeadline: .seconds(1)),
        repository: observations,
        probe: DarwinTerminalForegroundProbe(sessionDirectory: fixture.rootURL.path, bootId: "current-boot"),
        exitWatcher: DarwinProcessExitWatcher(), observerLaunchId: UUIDv7.generate(), factSink: { _, _ in })
    let controlledReadiness = RestoreResumeReadiness(
        clock: TestPushClock(), deadline: .seconds(2), launchId: UUIDv7.generate(), factSink: { _, _ in })
    await AppIPCDeferredInitialization.prepareResumeReadiness(
        readiness: controlledReadiness, intake: fixture.intake(),
        prepareForLaunch: { _ = try await fixture.ingestion.prepareForLaunch(at: fixture.now) })
    let state = await controlledReadiness.wait(paneId: fixture.paneID)
    // App's concrete clock owner consumes the same immutable result; no elapsed-time deadline decides this test.
    let appReadiness = RestoreResumeReadiness(
        clock: ContinuousClock(), deadline: .seconds(2), launchId: UUIDv7.generate(), factSink: { _, _ in })
    await appReadiness.publish(state)
    let delegate = AppDelegate()
    delegate.workspaceSQLiteDatastore = datastore
    delegate.restoreForegroundObserver = observer
    delegate.restoreResumeReadiness = appReadiness
    delegate.restoreLaunchBootId = "current-boot"
    let base = TerminalColdRestorePlan(
        zmxExecutable: URL(fileURLWithPath: "/unused/zmx"), zmxDirectory: fixture.rootURL,
        sessionID: look.zmxSessionId, loginShell: URL(fileURLWithPath: "/bin/zsh"),
        folderCandidates: [fixture.rootURL], notice: .init(linesByCandidateIndex: ["Restored after restart"]),
        replayFile: nil, resume: nil, attemptID: .generate())
    let plan = await delegate.makeColdResumePlanResolver()(PaneId(existingUUID: fixture.paneID), base)
    await observer.shutdown()
    await controlledReadiness.shutdown()
    await appReadiness.shutdown()
    return (plan, state)
}
