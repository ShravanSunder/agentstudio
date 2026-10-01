import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioSessions
@testable import AgentStudioTerminal

@Suite("Restore resumed start ingress")
struct RestoreResumedStartIngressTests {
    @Test("only an admitted live matched start ends the armed resume phase", arguments: [false, true])
    func admittedStartUsesExistingOrderedControl(late: Bool) async throws {
        let fixture = try AppResumeSessionsFixture()
        let ingestion = fixture.makeIngestion()
        let projector = TerminalActivityProjector()
        let surfaceId = UUIDv7.generate()
        let invocation = ResumeInvocation(
            provider: .codex, sessionId: try ProviderSessionId(rawValue: fixture.sessionId))
        await projector.armRestorePhase(
            paneID: fixture.paneId, generation: .init(rawValue: 1), resumeInvocation: invocation)
        let adapter = AgentStudioIPCSessionsAdapter(
            ingestion: ingestion,
            providerRegistry: .init(profiles: SessionsProviderProfile.shippedProfiles),
            admissionFreshness: late ? .late : .live,
            resumedSessionStartSink: { pane, provider, session in
                if let generation = await projector.matchingResumeRestoreGeneration(
                    paneID: pane,
                    providerIdentifier: provider, providerSessionId: session)
                {
                    await projector.applyOrderedControl(
                        surfaceID: surfaceId, paneID: pane, precedingAggregate: nil,
                        control: .restorePhaseEnded(generation))
                }
            })
        do {
            let params = try fixture.event(.sessionStart)
            #expect(
                try await adapter.recordProviderEvent(paneId: fixture.paneId, params: params, provenance: .matchingPane)
                    .disposition == .admitted)
            #expect(await projector.isRestorePhaseActive(paneID: fixture.paneId) == late)
            await ingestion.finish()
            await projector.reset()
        } catch {
            await ingestion.finish()
            await projector.reset()
            throw error
        }
    }

    @Test("an unqualified start never reaches the matched resume-phase ingress")
    func refusedStartKeepsRestorePhaseArmed() async throws {
        let fixture = try AppResumeSessionsFixture()
        let ingestion = fixture.makeIngestion()
        let projector = TerminalActivityProjector()
        let invocation = ResumeInvocation(
            provider: .codex, sessionId: try ProviderSessionId(rawValue: fixture.sessionId))
        await projector.armRestorePhase(
            paneID: fixture.paneId, generation: .init(rawValue: 1), resumeInvocation: invocation)
        let adapter = AgentStudioIPCSessionsAdapter(
            ingestion: ingestion,
            providerRegistry: .init(profiles: SessionsProviderProfile.shippedProfiles),
            resumedSessionStartSink: { pane, _, _ in
                _ = await projector.endRestorePhase(paneID: pane, generation: .init(rawValue: 1))
            })
        do {
            let params = try fixture.event(.sessionStart, version: "unqualified")
            #expect(
                try await adapter.recordProviderEvent(paneId: fixture.paneId, params: params, provenance: .matchingPane)
                    .disposition != .admitted)
            #expect(await projector.isRestorePhaseActive(paneID: fixture.paneId))
            await ingestion.finish()
            await projector.reset()
        } catch {
            await ingestion.finish()
            await projector.reset()
            throw error
        }
    }
}
