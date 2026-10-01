import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import AgentStudioTestHarness
import Foundation
import Synchronization
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioSessions
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

@MainActor
@Suite("Restore resume decision boundary", .serialized)
struct RestoreResumeDecisionBoundaryTests {
    init() { installTestCoreAtomsIfNeeded() }

    @Test("the readiness deadline releases a cold member with unknown and late ready changes no plan")
    func deadlineUnknownPlanIsFinal() async throws {
        let fixture = try ResumeReadinessFixture()
        let descriptor = makePreparedContentCoordinatorTerminalDescriptor()
        let base = try resumeAppBasePlan(descriptor)
        let providerId = UUIDv7.generate().uuidString
        let candidate = ResumeInvocation(provider: .codex, sessionId: try ProviderSessionId(rawValue: providerId))
        let decisions = ResumePlanDecisionLedger()
        let port = try ResumeAppAdmissionPort(entries: [descriptor])
        let registry = ViewRegistry()
        registry.beginInitialRestore()
        let coordinator = WorkspacePreparedContentMountCoordinator(
            cohort: .init(
                generation: .init(), terminalActivationInput: .init(entries: [descriptor]),
                nonterminalContentMountInput: .init(entries: [])),
            viewRegistry: registry,
            terminalAdmissionPort: port, nonterminalAdmissionPort: RecordingPreparedContentNonterminalPort(),
            classifyTerminalRestoreKinds: { _, publish in await publish(descriptor.paneID, .cold(base)) },
            resolveColdResumePlan: { paneId, plan in
                let ready = await fixture.readiness.wait(paneId: paneId.uuid)
                let evidence: ResumeEvidence =
                    ready == .ready
                    ? .interruptedCandidate(candidate)
                    : .unknown(.reportsNotTakenIn)
                decisions.record(evidence)
                return TerminalColdRestorePlanBuilder.applyingResumeEvidence(
                    evidence,
                    providerIdentifier: "codex", providerSessionId: providerId, to: plan)
            })
        await coordinator.installTerminalGeometryAvailability([descriptor.paneID])
        let initialization = fixture.beginResumeReadiness()
        let mount = Task { await coordinator.mount() }
        do {
            try await fixture.expectIntakeHeld()
            try await fixture.facts.expectNext(in: descriptor.paneID.uuid, .waiting)
            #expect(port.admissions.isEmpty)
            await fixture.clock.waitForPendingSleepCount(atLeast: 1)
            fixture.clock.advance(by: .seconds(2))
            try await fixture.facts.expectNext(in: fixture.launchId, .published(.unavailable))
            try await port.expectStartAndFinish(descriptor.paneID)
            _ = await mount.value
            let admission = try #require(port.admissions.first)
            let kind = try #require(admission.restoreKind)
            guard case .cold(let decided) = kind else {
                Issue.record("expected cold deadline plan")
                throw ResumeDecisionTestError.notCold
            }
            #expect(decided.resume == nil)
            #expect(decisions.snapshot() == [.unknown(.reportsNotTakenIn)])
            #expect(
                decided.notice.linesByCandidateIndex.allSatisfy {
                    $0.contains("Codex") && $0.contains(String(providerId.prefix(8)))
                })
            await fixture.releaseIntake()
            await initialization.value
            #expect(port.admissions.count == 1)
            #expect(port.admissions.first?.restoreKind == .cold(decided))
            #expect(decisions.snapshot() == [.unknown(.reportsNotTakenIn)])
            try await fixture.close(initialization: initialization)
            try await port.facts.finish()
        } catch {
            fixture.intake.hold.retire()
            await fixture.readiness.shutdown()
            _ = await mount.value
            try? await fixture.close(initialization: initialization)
            try? await port.facts.finish()
            throw error
        }
    }

    @Test("a real provider end held across readiness cannot change the plan already sent to admission")
    func lateHookCannotRedecidePlan() async throws {
        let sessions = try AppResumeSessionsFixture()
        let ingestion = sessions.makeIngestion()
        let signals = RestoreSessionsTriggerLedger()
        let adapter = resumeProducerAdapter(ingestion: ingestion, fixture: sessions, ledger: signals)
        let fixture = try ResumeReadinessFixture()
        let held = HeldStep<IPCSessionEventParams>("old run end before live delivery across readiness")
        defer { held.retire() }
        let start = try sessions.event(.sessionStart)
        _ = try await adapter.recordProviderEvent(paneId: sessions.paneId, params: start, provenance: .matchingPane)
        let snapshot = try await sessions.snapshot()
        let binding = try #require(snapshot.currentBinding)
        let pane = Pane(
            id: sessions.paneId,
            content: .terminal(
                TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: sessions.zmxSessionId)),
            metadata: PaneMetadata(launchDirectory: URL(filePath: "/tmp/resume-boundary"), title: "cold"))
        let descriptor = TerminalActivationDescriptor(
            pane: pane, visibilityPriority: .activeVisible, hostPlacement: .tab(tabID: UUIDv7.generate()))
        let base = try resumeAppBasePlan(descriptor)
        let identity = ZmxSessionIdentity(
            version: 1, bootID: "older-boot",
            daemon: .init(pid: 7000, startSeconds: 1, startMicroseconds: 1),
            terminalLeader: .init(pid: 7001, startSeconds: 1, startMicroseconds: 2), processGroupID: 7001,
            sessionCreatedAt: 1)
        let observation = PaneForegroundObservation(
            paneId: sessions.paneId, zmxSessionId: sessions.zmxSessionId,
            sessionIdentity: try identity.encoded(), bindingGenerationId: binding.bindingGenerationId,
            program: .codex, observerLaunchId: UUIDv7.generate(), sequence: 1,
            observedAt: Date(timeIntervalSince1970: 1))
        let input = ResumeEvidenceInput(
            paneId: sessions.paneId, zmxSessionId: sessions.zmxSessionId,
            observation: observation, launchBootId: "current-boot", inventory: .complete([:]))
        let resolver = SessionsResumeResolver(repository: sessions.repository)
        let decisions = ResumePlanDecisionLedger()
        let port = try ResumeAppAdmissionPort(entries: [descriptor])
        let registry = ViewRegistry()
        registry.beginInitialRestore()
        let coordinator = WorkspacePreparedContentMountCoordinator(
            cohort: .init(
                generation: .init(), terminalActivationInput: .init(entries: [descriptor]),
                nonterminalContentMountInput: .init(entries: [])),
            viewRegistry: registry,
            terminalAdmissionPort: port, nonterminalAdmissionPort: RecordingPreparedContentNonterminalPort(),
            classifyTerminalRestoreKinds: { _, publish in await publish(descriptor.paneID, .cold(base)) },
            resolveColdResumePlan: { paneId, plan in
                let ready = await fixture.readiness.wait(paneId: paneId.uuid)
                let evidence =
                    ready == .ready ? await resolver.resumeEvidence(for: input) : .unknown(.reportsNotTakenIn)
                decisions.record(evidence)
                return TerminalColdRestorePlanBuilder.applyingResumeEvidence(
                    evidence,
                    providerIdentifier: "codex", providerSessionId: sessions.sessionId, to: plan)
            })
        await coordinator.installTerminalGeometryAvailability([descriptor.paneID])
        let end = try sessions.event(.sessionEnd)
        let hook = Task {
            try await held.arrive(end)
            return try await adapter.recordProviderEvent(
                paneId: sessions.paneId, params: end, provenance: .matchingPane)
        }
        let initialization = fixture.beginResumeReadiness {
            _ = try await ingestion.prepareForLaunch(at: Date(timeIntervalSince1970: 2))
        }
        let mount = Task { await coordinator.mount() }
        do {
            _ = try await held.firstArrival()
            try await fixture.expectIntakeHeld()
            try await fixture.facts.expectNext(in: sessions.paneId, .waiting)
            await fixture.releaseIntake()
            await initialization.value
            try await port.expectStartAndFinish(descriptor.paneID)
            _ = await mount.value
            let invocation = ResumeInvocation(
                provider: .codex, sessionId: try ProviderSessionId(rawValue: sessions.sessionId))
            #expect(decisions.snapshot() == [.interruptedCandidate(invocation)])
            let decided = try #require(port.admissions.first?.restoreKind)
            held.release()
            #expect(try await hook.value.disposition == .admitted)
            let ended = try await sessions.snapshot()
            #expect(ended.currentBinding?.providerEndedAt != nil)
            #expect(port.admissions.first?.restoreKind == decided)
            #expect(port.admissions.count == 1)
            #expect(decisions.snapshot() == [.interruptedCandidate(invocation)])
            await ingestion.finish()
            try await fixture.close(initialization: initialization)
            try await port.facts.finish()
        } catch {
            held.retire()
            fixture.intake.hold.retire()
            await fixture.readiness.shutdown()
            _ = try? await hook.value
            _ = await mount.value
            await ingestion.finish()
            try? await fixture.close(initialization: initialization)
            try? await port.facts.finish()
            throw error
        }
    }
}

private enum ResumeDecisionTestError: Error { case notCold }
final class ResumePlanDecisionLedger: Sendable {
    private let decisions = Mutex<[ResumeEvidence]>([])
    func record(_ evidence: ResumeEvidence) { decisions.withLock { $0.append(evidence) } }
    func snapshot() -> [ResumeEvidence] { decisions.withLock { $0 } }
}
