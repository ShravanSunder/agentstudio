import AgentStudioInfrastructure
import AgentStudioTestHarness
import Foundation
import GRDB
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioSessions
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

@MainActor
@Suite("Restore resume observation handoff", .serialized)
struct RestoreResumeObservationHandoffTests {
    init() { installTestCoreAtomsIfNeeded() }

    @Test("live zmx membership follows persisted additions and removals, excluding other ownership")
    func persistedLiveMembershipIsCurrentAndScoped() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "live-zmx-membership-\(UUIDv7.generate())")
        defer { try? FileManager.default.removeItem(at: root) }
        let prepared = try await prepareForegroundFiles(root: root)
        let workspaceId = UUIDv7.generate()
        let otherWorkspace = UUIDv7.generate()
        let paneId = UUIDv7.generate()
        let sessionId = ZmxSessionID.generateUUIDv7()
        let undoPaneId = UUIDv7.generate()
        let undoSessionId = ZmxSessionID.generateUUIDv7()
        try await prepared.coreQueue.write { database in
            for workspace in [workspaceId, otherWorkspace] {
                try database.execute(
                    sql: "INSERT INTO workspace VALUES (?, 'Membership proof', 1, 1)",
                    arguments: [workspace.uuidString])
            }
            try insertLiveMembershipPane(database, workspaceId: workspaceId, paneId: paneId, sessionId: sessionId)
            try insertLiveMembershipPane(
                database, workspaceId: otherWorkspace, paneId: UUIDv7.generate(),
                sessionId: .generateUUIDv7())
            try insertLiveMembershipPane(
                database, workspaceId: workspaceId, paneId: UUIDv7.generate(),
                sessionId: .generateUUIDv7(), provider: "ghostty")
            let closeId = UUIDv7.generate()
            try database.execute(
                sql: "INSERT INTO workspace_terminal_session_ownership(session_id) VALUES (?)",
                arguments: [undoSessionId.rawValue])
            try database.execute(
                sql: """
                    INSERT INTO workspace_undo_close(close_id, workspace_id, close_sequence, close_kind,
                        closed_at, expires_at, state, snapshot_version, snapshot_payload, deadline_boot_id, deadline_uptime_ns)
                    VALUES (?, ?, 1, 'pane', 100, 400, 'available', 1, ?, 'proof-boot', 400000000000)
                    """, arguments: [closeId.uuidString, workspaceId.uuidString, Data("{}".utf8)])
            try database.execute(
                sql: "INSERT INTO workspace_undo_close_member VALUES (?, ?, ?)",
                arguments: [closeId.uuidString, undoPaneId.uuidString, undoSessionId.rawValue])
        }
        #expect(try await prepared.datastore.liveZmxSessionsByPane(workspaceId: workspaceId) == [paneId: sessionId])
        let addedPaneId = UUIDv7.generate()
        let addedSessionId = ZmxSessionID.generateUUIDv7()
        try await prepared.coreQueue.write {
            try insertLiveMembershipPane($0, workspaceId: workspaceId, paneId: addedPaneId, sessionId: addedSessionId)
        }
        #expect(
            try await prepared.datastore.liveZmxSessionsByPane(workspaceId: workspaceId)
                == [paneId: sessionId, addedPaneId: addedSessionId])
        try await prepared.coreQueue.write {
            try $0.execute(sql: "DELETE FROM pane WHERE id = ?", arguments: [paneId.uuidString])
        }
        #expect(
            try await prepared.datastore.liveZmxSessionsByPane(workspaceId: workspaceId)
                == [addedPaneId: addedSessionId])
    }

    @Test("foreground transactions use the real App adapter over prepared Core files")
    func preparedDatastoreOwnsObservationTransactions() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "foreground-access-\(UUIDv7.generate())")
        defer { try? FileManager.default.removeItem(at: root) }
        let datastore = try await prepareForegroundDatastore(root: root)
        let paneId = UUIDv7.generate()
        let sessionId = ZmxSessionID.generateUUIDv7()
        let launchId = UUIDv7.generate()
        let membership = [paneId: sessionId]
        let repository = SQLitePaneForegroundObservationRepository(
            access: WorkspaceForegroundObservationSQLiteAccess(datastore: datastore),
            observerLaunchId: launchId, paneSessions: { membership })
        let observation = PaneForegroundObservation(
            paneId: paneId, zmxSessionId: sessionId,
            sessionIdentity: try handoffIdentity(bootId: "adapter-proof", daemonPid: 8300),
            bindingGenerationId: nil, program: .codex, observerLaunchId: launchId,
            sequence: 1, observedAt: Date(timeIntervalSince1970: 1))
        #expect(try await repository.admit(observation) == .admitted)
        #expect(try await repository.load(paneId: paneId) == observation)
        let storedSequence = try await datastore.performApplicationLocalRead {
            try Int64.fetchOne(
                $0, sql: "SELECT sequence FROM terminal_pane_foreground_observation WHERE pane_id = ?",
                arguments: [paneId.uuidString])
        }
        #expect(storedSequence == 1)
        try await repository.retire(paneId: paneId)
        #expect(try await repository.load(paneId: paneId) == nil)
        let retainedRows = try await datastore.performApplicationLocalRead {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM terminal_pane_foreground_observation")
        }
        #expect(retainedRows == 0)
    }

    @Test("the old stored look reaches the verdict before native admission can replace it with a new-session look")
    func preRestoreLookIsHandedOffBeforeFirstNewLook() async throws {
        let sessions = try AppResumeSessionsFixture()
        let ingestion = sessions.makeIngestion()
        let start = try sessions.event(.sessionStart)
        let adapter = resumeProducerAdapter(
            ingestion: ingestion, fixture: sessions, ledger: RestoreSessionsTriggerLedger())
        _ = try await adapter.recordProviderEvent(paneId: sessions.paneId, params: start, provenance: .matchingPane)
        let snapshot = try await sessions.snapshot()
        let binding = try #require(snapshot.currentBinding)
        let observationFixture = try await HandoffObservationFixture.make(sessions: sessions, binding: binding)
        let repository = observationFixture.repository
        let observer = observationFixture.observer
        let facts = observationFixture.facts
        let launch = observationFixture.launch
        let readiness = try ResumeReadinessFixture()
        let descriptor = TerminalActivationDescriptor(
            pane: Pane(
                id: sessions.paneId,
                content: .terminal(
                    TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: sessions.zmxSessionId)),
                metadata: .init(launchDirectory: URL(filePath: "/tmp/handoff-proof"), title: "handoff")),
            visibilityPriority: .activeVisible, hostPlacement: .tab(tabID: UUIDv7.generate()))
        let base = try resumeAppBasePlan(descriptor)
        let resolver = SessionsResumeResolver(repository: sessions.repository)
        let port = try ResumeAppAdmissionPort(entries: [descriptor])
        port.beforeStart = { _ in
            do {
                _ = try await observationFixture.expectNewSessionLook(paneId: sessions.paneId)
            } catch { Issue.record("new-session foreground look did not finish with admission") }
        }
        let registry = ViewRegistry()
        registry.beginInitialRestore()
        let coordinator = WorkspacePreparedContentMountCoordinator(
            cohort: .init(
                generation: .init(), terminalActivationInput: .init(entries: [descriptor]),
                nonterminalContentMountInput: .init(entries: [])),
            viewRegistry: registry,
            terminalAdmissionPort: port, nonterminalAdmissionPort: RecordingPreparedContentNonterminalPort(),
            classifyTerminalRestoreKinds: { _, publish in await publish(descriptor.paneID, .cold(base)) },
            resolveColdResumePlan: { pane, plan in
                let taken = try? await observer.takePreRestoreObservation(paneId: pane.uuid)
                let state = await readiness.readiness.wait(paneId: pane.uuid)
                let evidence =
                    state == .ready
                    ? await resolver.resumeEvidence(
                        for: ResumeEvidenceInput(
                            paneId: pane.uuid, zmxSessionId: sessions.zmxSessionId, observation: taken,
                            launchBootId: "current-boot", inventory: .complete([:]))) : .unknown(.reportsNotTakenIn)
                return TerminalColdRestorePlanBuilder.applyingResumeEvidence(
                    evidence,
                    providerIdentifier: "codex", providerSessionId: sessions.sessionId, to: plan)
            })
        await coordinator.installTerminalGeometryAvailability([descriptor.paneID])
        let initialization = readiness.beginResumeReadiness {
            _ = try await ingestion.prepareForLaunch(at: Date(timeIntervalSince1970: 2))
        }
        let mount = Task { await coordinator.mount() }
        do {
            try await readiness.expectIntakeHeld()
            await readiness.releaseIntake()
            await initialization.value
            try await port.expectStartAndFinish(descriptor.paneID)
            _ = await mount.value
            let kind = try #require(port.admissions.first?.restoreKind)
            if case .cold(let plan) = kind {
                #expect(
                    plan.resume
                        == ResumeInvocation(
                            provider: .codex, sessionId: try ProviderSessionId(rawValue: sessions.sessionId)))
            } else {
                Issue.record("expected decided cold plan")
            }
            #expect(try await repository.load(paneId: sessions.paneId)?.program == .shell)
            #expect(try await repository.load(paneId: sessions.paneId)?.observerLaunchId == launch)
            #expect(try await observer.takePreRestoreObservation(paneId: sessions.paneId) == nil)
            await observer.shutdown()
            await ingestion.finish()
            try await readiness.close(initialization: initialization)
            try await facts.finish()
            try await port.facts.finish()
        } catch {
            readiness.intake.hold.retire()
            await readiness.readiness.shutdown()
            _ = await mount.value
            await observer.shutdown()
            await ingestion.finish()
            try? await readiness.close(initialization: initialization)
            try? await facts.finish()
            try? await port.facts.finish()
            throw error
        }
    }
}

private func handoffIdentity(bootId: String, daemonPid: Int32) throws -> Data {
    try ZmxSessionIdentity(
        version: 1, bootID: bootId,
        daemon: .init(pid: daemonPid, startSeconds: 1, startMicroseconds: 1),
        terminalLeader: .init(pid: daemonPid + 1, startSeconds: 1, startMicroseconds: 2),
        processGroupID: daemonPid + 1, sessionCreatedAt: 1
    ).encoded()
}
private struct HandoffNewSessionProbe: TerminalForegroundProbing {
    let sessionId: ZmxSessionID
    let identity: Data
    func probeForeground(of sessions: [ZmxSessionID]) -> [ZmxSessionID: ForegroundSnapshot] {
        [sessionId: .init(sessionIdentity: identity, foregroundProcess: nil, program: .shell)]
    }
}
private struct HandoffNoExitWatcher: ProcessExitWatching {
    func watchExit(of process: ProcessIncarnation, watchId: UUID) -> ProcessExitWatch {
        Issue.record("a shell look must not acquire a process-exit watch")
        return .init(events: AsyncStream { $0.finish() }, cancel: {})
    }
}

private struct HandoffObservationFixture: Sendable {
    let repository: SQLitePaneForegroundObservationRepository
    let observer: PaneForegroundObserver<TestPushClock>
    let facts: FactRecorder<ForegroundObserverFactScope, ForegroundObserverFact>
    let launch: UUID

    func expectNewSessionLook(paneId: UUID) async throws -> ForegroundObserverFactScope {
        await observer.note(.bindingChanged, pane: paneId)
        let demand = try await facts.expectNextOperation(
            matching: { $0.paneId == paneId }, opening: { $0 == .scheduled }, "new-session foreground demand")
        try await facts.expectNext(in: demand, .scheduled)
        try await facts.expectNext(in: demand, .closed(.scheduled))
        let look = try await facts.expectNextOperation(
            matching: { $0.paneId == paneId },
            opening: { $0 == .snapshotStarted(sequence: 1) }, "first new-session foreground look")
        try await facts.expectNext(in: look, .snapshotStarted(sequence: 1))
        try await facts.expectNext(in: look, .observation(.admitted))
        try await facts.expectNext(in: look, .closed(.looked))
        return look
    }

    static func make(sessions: AppResumeSessionsFixture, binding: SessionsBindingRecord) async throws -> Self {
        let oldLaunch = UUIDv7.generate()
        let oldIdentity = try handoffIdentity(bootId: "old-boot", daemonPid: 8000)
        let oldObservation = PaneForegroundObservation(
            paneId: sessions.paneId, zmxSessionId: sessions.zmxSessionId,
            sessionIdentity: oldIdentity, bindingGenerationId: binding.bindingGenerationId, program: .codex,
            observerLaunchId: oldLaunch, sequence: 10, observedAt: Date(timeIntervalSince1970: 1))
        let oldRepository = SQLitePaneForegroundObservationRepository(
            access: TestForegroundSQLiteAccess(databaseQueue: sessions.database), observerLaunchId: oldLaunch)
        #expect(try await oldRepository.admit(oldObservation) == .admitted)
        let launch = UUIDv7.generate()
        let membership = [sessions.paneId: sessions.zmxSessionId]
        let repository = SQLitePaneForegroundObservationRepository(
            access: TestForegroundSQLiteAccess(databaseQueue: sessions.database), observerLaunchId: launch,
            paneSessions: { membership })
        let source = LocalFactSource(
            vocabulary: FactVocabulary<ForegroundObserverFactScope, ForegroundObserverFact>(
                describeScope: { "\($0.paneId)/\($0.operationId)" }, describeFact: { String(describing: $0) },
                isClosing: { _, fact in if case .closed = fact { true } else { false } }))
        let facts = try source.attach()
        let observer = PaneForegroundObserver(
            clock: TestPushClock(),
            policy: .init(lookSettleDelay: .seconds(5), lookMaxDelay: .seconds(60), quitLookDeadline: .seconds(1)),
            repository: repository,
            probe: HandoffNewSessionProbe(
                sessionId: sessions.zmxSessionId,
                identity: try handoffIdentity(bootId: "current-boot", daemonPid: 8100)),
            exitWatcher: HandoffNoExitWatcher(), observerLaunchId: launch, factSink: source.sink)
        return Self(repository: repository, observer: observer, facts: facts, launch: launch)
    }
}

@concurrent nonisolated private func prepareForegroundDatastore(root: URL) async throws -> WorkspaceSQLiteDatastoreActor
{
    try await prepareForegroundFiles(root: root).datastore
}

@concurrent nonisolated private func prepareForegroundFiles(root: URL) async throws
    -> (datastore: WorkspaceSQLiteDatastoreActor, coreQueue: DatabaseQueue)
{
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let coreQueue = try DatabaseQueue(path: root.appending(path: "core.sqlite").path)
    let localQueue = try DatabaseQueue(path: root.appending(path: "local.sqlite").path)
    let core = WorkspaceCoreRepository(databaseWriter: coreQueue)
    try core.migrate()
    try WorkspaceLocalMigrations.migrate(localQueue)
    let local = WorkspaceLocalRepository(workspaceId: UUIDv7.generate(), databaseWriter: localQueue)
    let datastore = try await preparedWorkspaceSQLiteDatastore(
        coreRepository: core, preparedApplicationLocalRepository: local)
    return (datastore, coreQueue)
}

private func insertLiveMembershipPane(
    _ database: Database, workspaceId: UUID, paneId: UUID, sessionId: ZmxSessionID, provider: String = "zmx"
) throws {
    try database.execute(
        sql: """
            INSERT INTO pane(id, workspace_id, content_type, execution_backend, title,
                residency_kind, kind, created_at, updated_at)
            VALUES (?, ?, ?, 'local', 'Membership proof', 'active', 'leaf', 1, 1)
            """,
        arguments: [
            paneId.uuidString, workspaceId.uuidString, SQLitePaneContentTypeStorage.storageValue(for: .terminal),
        ])
    try database.execute(
        sql:
            "INSERT INTO pane_content_terminal(pane_id, provider, lifetime, zmx_session_id) VALUES (?, ?, 'persistent', ?)",
        arguments: [paneId.uuidString, provider, sessionId.rawValue])
}
