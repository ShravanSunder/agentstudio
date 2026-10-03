import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioTerminal

@Suite("Terminal resume restore phase")
struct TerminalResumeRestorePhaseTests {
    @Test("a matching resumed provider start supplies the current generation for ordered phase end")
    func matchingStartEndsThroughOrderedIngress() async throws {
        let projector = TerminalActivityProjector()
        let paneId = UUIDv7.generate()
        let surfaceId = UUIDv7.generate()
        let generation = RestoreGeneration(rawValue: 1)
        let id = UUIDv7.generate().uuidString
        let invocation = ResumeInvocation(provider: .codex, sessionId: try ProviderSessionId(rawValue: id))
        await projector.armRestorePhase(paneID: paneId, generation: generation, resumeInvocation: invocation)
        let matching = try #require(
            await projector.matchingResumeRestoreGeneration(
                paneID: paneId, providerIdentifier: "codex", providerSessionId: id))
        #expect(matching == generation)
        #expect(await projector.isRestorePhaseActive(paneID: paneId))
        await projector.applyOrderedControl(
            surfaceID: surfaceId, paneID: paneId, precedingAggregate: nil,
            control: .restorePhaseEnded(matching))
        #expect(await projector.isRestorePhaseActive(paneID: paneId) == false)
        #expect(
            await projector.matchingResumeRestoreGeneration(
                paneID: paneId,
                providerIdentifier: "codex", providerSessionId: id) == nil)
        await projector.reset()
    }

    @Test(
        "a start for another provider, session or pane cannot end the resume phase",
        arguments: ["provider", "session", "pane"])
    func foreignStartCannotMatch(difference: String) async throws {
        let projector = TerminalActivityProjector()
        let paneId = UUIDv7.generate()
        let id = UUIDv7.generate().uuidString
        let invocation = ResumeInvocation(provider: .codex, sessionId: try ProviderSessionId(rawValue: id))
        await projector.armRestorePhase(paneID: paneId, generation: .init(rawValue: 1), resumeInvocation: invocation)
        #expect(
            await projector.matchingResumeRestoreGeneration(
                paneID: difference == "pane" ? UUIDv7.generate() : paneId,
                providerIdentifier: difference == "provider" ? "claude-code" : "codex",
                providerSessionId: difference == "session" ? UUIDv7.generate().uuidString : id) == nil)
        #expect(await projector.isRestorePhaseActive(paneID: paneId))
        await projector.reset()
    }

    @Test("a replacement generation forgets the old resume id and only its own start matches")
    func newGenerationOwnsItsSessionId() async throws {
        let projector = TerminalActivityProjector()
        let paneId = UUIDv7.generate()
        let oldId = UUIDv7.generate().uuidString
        let newId = UUIDv7.generate().uuidString
        await projector.armRestorePhase(
            paneID: paneId, generation: .init(rawValue: 1),
            resumeInvocation: .init(provider: .codex, sessionId: try ProviderSessionId(rawValue: oldId)))
        await projector.armRestorePhase(
            paneID: paneId, generation: .init(rawValue: 2),
            resumeInvocation: .init(provider: .codex, sessionId: try ProviderSessionId(rawValue: newId)))
        #expect(
            await projector.matchingResumeRestoreGeneration(
                paneID: paneId, providerIdentifier: "codex", providerSessionId: oldId) == nil)
        #expect(
            await projector.matchingResumeRestoreGeneration(
                paneID: paneId,
                providerIdentifier: "codex", providerSessionId: newId) == RestoreGeneration(rawValue: 2))
        await projector.reset()
    }

    @Test("a plain shell restore has no matching resume start even for a valid provider id")
    func shellPhaseHasNoResumeMatch() async {
        let projector = TerminalActivityProjector()
        let paneId = UUIDv7.generate()
        await projector.armRestorePhase(paneID: paneId, generation: .init(rawValue: 1))
        #expect(
            await projector.matchingResumeRestoreGeneration(
                paneID: paneId,
                providerIdentifier: "codex", providerSessionId: UUIDv7.generate().uuidString) == nil)
        #expect(await projector.isRestorePhaseActive(paneID: paneId))
        await projector.reset()
    }
}
