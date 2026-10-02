import AgentStudioCLIStore
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import AgentStudioSessions
import AgentStudioTestHarness
import AgentStudioTestSupport
import Foundation
import Synchronization
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTerminal

/// One real store, Sessions transaction owner, zmx terminal and native observer.
/// The provider executable is the external stand-in; its actual argv is recorded.
struct ResumeEvidenceZmxProof: Sendable {
    let environment: ResumeEvidenceZmxEnvironment
    let data: LifecycleIntakeFileFixture
    let foreground: ZmxForegroundFixture
    let backend: ZmxBackend
    let provider: String
    let sessionID: String
    let liveIntake: CLILifecycleReportIntake
    let projector: TerminalActivityProjector
    let ingressFacts: FactRecorder<UUID, ResumeEvidenceIngressFact>
    let ingressSource: LocalFactSource<UUID, ResumeEvidenceIngressFact>
    let ingressScope: ResumeEvidenceIngressScope
    let surfaceID: UUID
    private let ownsDatastore: Bool

    static func make(
        environment: ResumeEvidenceZmxEnvironment, provider: String,
        historical: Bool = false, unordered: Bool = false, successor: Bool = false,
        exitWatcher: (any ProcessExitWatching)? = nil,
        sharedData: LifecycleIntakeFileFixture? = nil
    ) async throws -> Self {
        let data: LifecycleIntakeFileFixture
        if let sharedData {
            data = sharedData.sharingStore(for: UUIDv7.generate())
        } else {
            data = try await LifecycleIntakeFileFixture.make()
        }
        let harness = environment.harness
        let backend = environment.backend
        let projector = TerminalActivityProjector()
        let source = LocalFactSource<UUID, ResumeEvidenceIngressFact>(
            vocabulary: .init(
                describeScope: { $0.uuidString }, describeFact: { String(describing: $0) },
                isClosing: { _, fact in fact == .reply }))
        let facts = try source.attach()
        let scope = ResumeEvidenceIngressScope()
        let surfaceID = UUIDv7.generate()
        let admission = makeAdmission(
            data: data, projector: projector, source: source,
            scope: scope, surfaceID: surfaceID)
        let members = data.members
        let live = CLILifecycleReportIntake(
            storeURL: unordered ? data.rootURL : data.storeURL,
            expectedChannel: .debug, admission: admission, sqliteAccess: data.access, workspaceID: data.workspaceID,
            paneExists: { paneID, _ in members.contains(paneID) })
        data.intakes.record(live)
        do {
            let record = data.record(provider: provider)
            if unordered {
                let result = try await live.recordLive(paneId: data.paneID, params: data.params(record))
                try #require(result.disposition == .admitted)
            } else {
                if !historical { _ = try await live.captureListenerReadyBoundary() }
                let row = try await store(record, data: data)
                if !historical {
                    let result = try await live.recordLive(
                        paneId: data.paneID,
                        params: data.params(row.record, sequence: row.sequence))
                    try #require(result.disposition == .admitted)
                }
            }
            if historical {
                let intake = makeIntake(data: data, admission: admission)
                try await prepare(data: data, intake: intake)
            }
            let fetchedBinding = try await data.binding()
            let binding = try #require(fetchedBinding)
            let foreground = try await ZmxForegroundFixture.make(
                harness: harness, backend: backend,
                provider: provider == "codex" ? "codex" : "claude", successorProgram: successor,
                bindingContext: .init(
                    paneID: data.paneID, generationID: binding.bindingGenerationId,
                    database: data.access.queue, ownership: environment), exitWatcher: exitWatcher)
            return Self(
                environment: environment, data: data, foreground: foreground, backend: backend, provider: provider,
                sessionID: record.conversationID, liveIntake: live, projector: projector,
                ingressFacts: facts, ingressSource: source, ingressScope: scope, surfaceID: surfaceID,
                ownsDatastore: sharedData == nil)
        } catch {
            await projector.reset()
            try? await facts.finish()
            if sharedData == nil {
                await data.close()
                data.remove()
            }
            throw error
        }
    }

    static func makeAdmission(
        data: LifecycleIntakeFileFixture, projector: TerminalActivityProjector,
        source: LocalFactSource<UUID, ResumeEvidenceIngressFact>, scope: ResumeEvidenceIngressScope, surfaceID: UUID
    )
        -> AgentStudioIPCSessionsAdapter
    {
        AgentStudioIPCSessionsAdapter(
            ingestion: data.ingestion,
            providerRegistry: .init(profiles: [
                .codexCommandLine,
                .init(
                    providerIdentifier: "claude-code",
                    exactVersion: "2.1.274", operatingMode: "cli", qualifiedCapabilities: [.sessionStart, .sessionEnd]),
            ]),
            now: { data.now },
            resumedSessionStartSink: { paneID, provider, sessionID in
                if let generation = await projector.matchingResumeRestoreGeneration(
                    paneID: paneID,
                    providerIdentifier: provider, providerSessionId: sessionID)
                {
                    await projector.applyOrderedControl(
                        surfaceID: surfaceID, paneID: paneID,
                        precedingAggregate: nil, control: .restorePhaseEnded(generation))
                    source.sink(scope.current(), .phaseEnded)
                }
            })
    }

    private static func makeIntake(data: LifecycleIntakeFileFixture, admission: AgentStudioIPCSessionsAdapter)
        -> CLILifecycleReportIntake
    {
        let members = data.members
        let intake = CLILifecycleReportIntake(
            storeURL: data.storeURL, expectedChannel: .debug,
            admission: admission, sqliteAccess: data.access, workspaceID: data.workspaceID,
            paneExists: { paneID, _ in members.contains(paneID) })
        data.intakes.record(intake)
        return intake
    }

    func prepareReadiness() async throws {
        let admission = Self.makeAdmission(
            data: data, projector: projector, source: ingressSource,
            scope: ingressScope, surfaceID: surfaceID)
        try await Self.prepare(data: data, intake: Self.makeIntake(data: data, admission: admission))
    }

    private static func prepare(data: LifecycleIntakeFileFixture, intake: CLILifecycleReportIntake) async throws {
        let readiness = RestoreResumeReadiness(
            clock: TestPushClock(), deadline: .seconds(2),
            launchId: UUIDv7.generate(), factSink: { _, _ in })
        await AppIPCDeferredInitialization.prepareResumeReadiness(
            readiness: readiness, intake: intake,
            prepareForLaunch: { _ = try await data.ingestion.prepareForLaunch(at: data.now) })
        let status = await readiness.wait(paneId: data.paneID)
        await readiness.shutdown()
        try #require(status == .ready, "real historical intake must finish before deciding")
    }

    static func store(_ record: CLILifecycleReportRecord, data: LifecycleIntakeFileFixture) async throws
        -> CLILifecycleReport
    {
        try await valueFromDedicatedThread {
            let writer = try CLIStore.openWriter(url: data.storeURL, channel: .debug).get()
            return try writer.appendLifecycleReport(record).get()
        }
    }

    func report(event: CLILifecycleEvent, sessionID: String? = nil, live: Bool = true) async throws
        -> CLILifecycleReport
    {
        let row = try await Self.store(
            data.record(sessionID: sessionID ?? self.sessionID, event: event, provider: provider), data: data)
        if live {
            let result = try await liveIntake.recordLive(
                paneId: data.paneID,
                params: data.params(row.record, sequence: row.sequence))
            try #require(result.disposition == .admitted)
        }
        return row
    }

    func decision(observation: PaneForegroundObservation?, reboot: Bool = false) async throws -> ResumeEvidence {
        let bootID = try ZmxSessionIdentity.decode(foreground.identity).bootID
        return await SessionsResumeResolver(repository: data.repository).resumeEvidence(
            for: .init(
                paneId: data.paneID, zmxSessionId: foreground.sessionId, observation: observation,
                launchBootId: reboot ? UUIDv7.generate().uuidString : bootID,
                inventory: await backend.discoverSessionInventory()))
    }

    /// Execution follows the decided value. Wrong non-invocation cannot park a FIFO:
    /// these fake providers write regular reports and always finish unless explicitly held.
    func invoke(
        _ evidence: ResumeEvidence, expected: ResumeEvidence, exitCode: Int32 = 0,
        beforeRelease: (@Sendable () async throws -> Void)? = nil
    ) async throws {
        #expect(evidence == expected)
        let fetchedBinding = try await data.binding()
        let binding = try #require(fetchedBinding)
        let fixture = try ResumeZmxFixture(
            harness: foreground.harness, providerIdentifier: provider, exitCode: exitCode,
            providerSessionId: binding.providerConversationId, restoreSessionID: foreground.sessionId,
            reportsToFile: true, holdResume: beforeRelease != nil, ownership: environment)
        let plan = TerminalColdRestorePlanBuilder.applyingResumeEvidence(
            evidence, providerIdentifier: provider,
            providerSessionId: binding.providerConversationId, to: fixture.plan)
        if case .interruptedCandidate(let invocation) = expected {
            try #require(plan.resume == invocation, "candidate must carry the exact expected UUID before launch")
        } else {
            try #require(plan.resume == nil)
        }
        let driver = try await fixture.launch(plan: plan)
        do {
            if case .interruptedCandidate(let invocation) = expected {
                _ = try await driver.expectProviderInvocation()
                let argv = try await fixture.receiveArgv()
                #expect(argv == ["2", provider == "codex" ? "resume" : "--resume", invocation.sessionId.rawValue])
                let folder = try String(contentsOf: fixture.invocationFolderURL, encoding: .utf8)
                #expect(folder == foreground.harness.zmxDir + "\n")
                if let beforeRelease {
                    try await beforeRelease()
                    try await fixture.releaseResume()
                }
            }
            let output = try await driver.expectInteractiveShell()
            if case .interruptedCandidate = expected {
                #expect(try String(contentsOf: fixture.callsURL, encoding: .utf8) == "called\n")
                #expect(output.contains(exitCode == 0 ? "Resumed" : "session-no-longer-exists"))
            } else {
                #expect(!FileManager.default.fileExists(atPath: fixture.callsURL.path))
                if case .unknown = expected { #expect(output.contains("resume it manually")) }
                if case .knownExited = expected {
                    #expect(!output.contains("resume it manually"))
                    #expect(!output.contains("Resumed"))
                }
            }
            try await fixture.killOwnedSession()
            try await driver.stop()
        } catch {
            try? await fixture.killOwnedSession()
            try? await driver.stop()
            throw error
        }
    }

    func warmAttachWithoutInvocation(expectedIdentity: Data? = nil) async throws {
        let before = try await backend.observeSessionIdentity(foreground.sessionId)
        try #require(before == (expectedIdentity ?? foreground.identity))
        let fixture = try ResumeZmxFixture(
            harness: foreground.harness, providerIdentifier: provider, exitCode: 0,
            providerSessionId: sessionID, restoreSessionID: foreground.sessionId, reportsToFile: true,
            holdResume: false,
            ownership: environment
        )
        var environment = ProcessInfo.processInfo.environment
        environment["ZMX_DIR"] = foreground.harness.zmxDir
        environment["ZMX_SESSION"] = ""
        let driver = try await ResumeZmxProcessDriver.launch(
            command: ZmxBackend.buildColdRestoreCommand(fixture.plan), environment: environment)
        self.environment.retainClient(driver)
        do {
            try await driver.sendStartupProbe()
            _ = try await driver.expectStartupGate()
            try await driver.stop()
            #expect(try await backend.observeSessionIdentity(foreground.sessionId) == before)
            #expect(!FileManager.default.fileExists(atPath: fixture.callsURL.path))
        } catch {
            try? await driver.stop()
            throw error
        }
    }

    func candidate(sessionID: String? = nil) throws -> ResumeEvidence {
        let resumeProvider = try #require(ResumeProvider(providerIdentifier: provider))
        return .interruptedCandidate(
            .init(
                provider: resumeProvider,
                sessionId: try ProviderSessionId(rawValue: sessionID ?? self.sessionID)))
    }

    func close() async throws {
        await projector.reset()
        var failure: (any Error)?
        do { try await foreground.closeFixture() } catch { failure = error }
        if ownsDatastore {
            await data.close()
            data.remove()
        }
        do { try await ingressFacts.finish() } catch { if failure == nil { failure = error } }
        if let failure { throw failure }
    }

}

enum ResumeEvidenceIngressFact: Equatable, Sendable { case phaseEnded, reply }

/// Registration refusal is injected at the watch seam; the process/probe/store remain real.
final class ResumeEvidenceFirstRefusalWatch: ProcessExitWatching, Sendable {
    private let refused = Mutex(false)
    private let native = DarwinProcessExitWatcher()
    func watchExit(of process: ProcessIncarnation, watchId: UUID) -> ProcessExitWatch {
        let shouldRefuse = refused.withLock { value in
            defer { value = true }
            return !value
        }
        guard shouldRefuse else { return native.watchExit(of: process, watchId: watchId) }
        let stream = AsyncStream<ProcessExitWatchEvent>.makeStream(bufferingPolicy: .bufferingOldest(1))
        stream.continuation.yield(.unavailable(watchId: watchId, .permissionDenied))
        stream.continuation.finish()
        return .init(events: stream.stream, cancel: {})
    }
}

final class ResumeEvidenceIngressScope: Sendable {
    private let scope = Mutex(UUIDv7.generate())
    func current() -> UUID { scope.withLock { $0 } }
    func replace() -> UUID {
        let identifier = UUIDv7.generate()
        scope.withLock { $0 = identifier }
        return identifier
    }
}
