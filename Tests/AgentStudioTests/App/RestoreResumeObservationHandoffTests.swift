import AgentStudioInfrastructure
import AgentStudioTestHarness
import Foundation
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
            await observer.note(.bindingChanged, pane: sessions.paneId)
            let pane = sessions.paneId
            do {
                let look = try await facts.expectNextOperation(
                    matching: { $0.paneId == pane },
                    opening: { $0 == .snapshotStarted(sequence: 1) }, "first new-session foreground look")
                try await facts.expectNext(in: look, .snapshotStarted(sequence: 1))
                try await facts.expectNext(in: look, .observation(.admitted))
                try await facts.expectNext(in: look, .closed(.looked))
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
        let initialization = readiness.start {
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

    static func make(sessions: AppResumeSessionsFixture, binding: SessionsBindingRecord) async throws -> Self {
        let oldLaunch = UUIDv7.generate()
        let oldIdentity = try handoffIdentity(bootId: "old-boot", daemonPid: 8000)
        let oldObservation = PaneForegroundObservation(
            paneId: sessions.paneId, zmxSessionId: sessions.zmxSessionId,
            sessionIdentity: oldIdentity, bindingGenerationId: binding.bindingGenerationId, program: .codex,
            observerLaunchId: oldLaunch, sequence: 10, observedAt: Date(timeIntervalSince1970: 1))
        let oldRepository = SQLitePaneForegroundObservationRepository(
            databaseWriter: sessions.database, observerLaunchId: oldLaunch)
        #expect(try await oldRepository.admit(oldObservation) == .admitted)
        let launch = UUIDv7.generate()
        let membership = [sessions.paneId: sessions.zmxSessionId]
        let repository = SQLitePaneForegroundObservationRepository(
            databaseWriter: sessions.database, observerLaunchId: launch,
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
