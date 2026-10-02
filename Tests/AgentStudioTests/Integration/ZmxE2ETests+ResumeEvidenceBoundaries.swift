import AgentStudioInfrastructure
import AgentStudioTestHarness
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTerminal

extension E2ESerializedTests.ZmxE2ETests {
    @Test(
        "a resumed start creates a new run; its duplicate cannot end a later armed generation",
        arguments: ["claude-code", "codex"])
    func resumeEvidenceResumedStartAndDuplicate(provider: String) async throws {
        try await withResumeEvidenceProof(provider: provider) { proof in
            _ = try await proof.foreground.initialLook()
            let fetchedOriginal = try await proof.data.binding()
            let original = try #require(fetchedOriginal)
            let look = try await proof.foreground.observer.takePreRestoreObservation(paneId: proof.data.paneID)
            await proof.foreground.observer.shutdown()
            try await proof.foreground.killOwnedSession()
            try await proof.prepareReadiness()
            let candidate = try proof.candidate()
            guard case .interruptedCandidate(let invocation) = candidate else { throw POSIXError(.EPROTO) }
            await proof.projector.armRestorePhase(
                paneID: proof.data.paneID, generation: .init(rawValue: 1), resumeInvocation: invocation)
            let decided = try await proof.decision(observation: look)
            try await proof.invoke(
                decided, expected: candidate,
                beforeRelease: {
                    let scope = proof.ingressScope.replace()
                    let row = try await proof.report(event: .sessionStart)
                    proof.ingressSource.sink(scope, .reply)
                    try await proof.ingressFacts.expectNext(in: scope, .phaseEnded)
                    try await proof.ingressFacts.expectNext(in: scope, .reply)
                    #expect(!(await proof.projector.isRestorePhaseActive(paneID: proof.data.paneID)))
                    let fetchedBinding = try await proof.data.binding()
                    let binding = try #require(fetchedBinding)
                    #expect(binding.bindingGenerationId != original.bindingGenerationId)
                    #expect(binding.providerConversationId == proof.sessionID)
                    #expect(!binding.startedFromHistoricalReport)
                    await proof.projector.armRestorePhase(
                        paneID: proof.data.paneID, generation: .init(rawValue: 2), resumeInvocation: invocation)
                    let duplicateScope = proof.ingressScope.replace()
                    let opening = await proof.ingressFacts.mark(duplicateScope)
                    _ = try await proof.liveIntake.recordLive(
                        paneId: proof.data.paneID,
                        params: proof.data.params(row.record, sequence: row.sequence))
                    proof.ingressSource.sink(duplicateScope, .reply)
                    try await proof.ingressFacts.expectNone(
                        of: { $0 == .phaseEnded }, "duplicate resumed start",
                        from: opening, closedBy: { $0 == .reply })
                    #expect(await proof.projector.isRestorePhaseActive(paneID: proof.data.paneID))
                    #expect(try await proof.data.binding()?.bindingGenerationId == binding.bindingGenerationId)
                    let replay = proof.data.intake()
                    try await replay.takeIn(through: .stored(storeId: proof.data.storeID, sequence: row.sequence))
                    #expect(try await proof.data.binding()?.bindingGenerationId == binding.bindingGenerationId)
                })
        }
    }

    @Test(
        "historical starts cannot end a current resume attempt, and remain unknown for the next restart",
        arguments: ["claude-code", "codex"])
    func resumeEvidenceHistoricalStartCannotEndPhase(provider: String) async throws {
        try await withResumeEvidenceProof(provider: provider) { proof in
            _ = try await proof.foreground.initialLook()
            let look = try await proof.foreground.observer.takePreRestoreObservation(paneId: proof.data.paneID)
            await proof.foreground.observer.shutdown()
            try await proof.foreground.killOwnedSession()
            try await proof.prepareReadiness()
            let expected = try proof.candidate()
            guard case .interruptedCandidate(let invocation) = expected else { throw POSIXError(.EPROTO) }
            await proof.projector.armRestorePhase(
                paneID: proof.data.paneID, generation: .init(rawValue: 1), resumeInvocation: invocation)
            let decided = try await proof.decision(observation: look)
            try await proof.invoke(
                decided, expected: expected,
                beforeRelease: {
                    let scope = proof.ingressScope.replace()
                    let opening = await proof.ingressFacts.mark(scope)
                    _ = try await proof.report(event: .sessionStart, live: false)
                    try await proof.prepareReadiness()
                    proof.ingressSource.sink(scope, .reply)
                    try await proof.ingressFacts.expectNone(
                        of: { $0 == .phaseEnded }, "historical resumed start",
                        from: opening, closedBy: { $0 == .reply })
                    #expect(await proof.projector.isRestorePhaseActive(paneID: proof.data.paneID))
                    #expect(try await proof.data.binding()?.startedFromHistoricalReport == true)
                })
            let next = try await proof.decision(observation: look, reboot: true)
            try await proof.invoke(next, expected: .unknown(.startedFromHistoricalReport))
        }
    }

    @Test(
        "SR13: an in-flight end of the same UUID ends the resumed run; the next restart misses rather than resumes wrong",
        arguments: ["claude-code", "codex"])
    func resumeEvidenceLateEndLimitation(provider: String) async throws {
        try await withResumeEvidenceProof(provider: provider) { proof in
            _ = try await proof.foreground.initialLook()
            let fetchedOldBinding = try await proof.data.binding()
            let oldBinding = try #require(fetchedOldBinding)
            let look = try await proof.foreground.observer.takePreRestoreObservation(paneId: proof.data.paneID)
            await proof.foreground.observer.shutdown()
            try await proof.foreground.killOwnedSession()
            try await proof.prepareReadiness()
            let expected = try proof.candidate()
            guard case .interruptedCandidate(let invocation) = expected else { throw POSIXError(.EPROTO) }
            await proof.projector.armRestorePhase(
                paneID: proof.data.paneID, generation: .init(rawValue: 1), resumeInvocation: invocation)
            let decided = try await proof.decision(observation: look)
            try await proof.invoke(
                decided, expected: expected,
                beforeRelease: {
                    let scope = proof.ingressScope.replace()
                    _ = try await proof.report(event: .sessionStart)
                    proof.ingressSource.sink(scope, .reply)
                    try await proof.ingressFacts.expectNext(in: scope, .phaseEnded)
                    try await proof.ingressFacts.expectNext(in: scope, .reply)
                    let fetchedResumed = try await proof.data.binding()
                    let resumed = try #require(fetchedResumed)
                    #expect(resumed.bindingGenerationId != oldBinding.bindingGenerationId)
                    _ = try await proof.report(event: .sessionEnd(reason: "other"))
                    let fetchedEnded = try await proof.data.binding()
                    let ended = try #require(fetchedEnded)
                    #expect(ended.bindingGenerationId == resumed.bindingGenerationId)
                    #expect(ended.providerEndedAt != nil)
                })
            try await proof.prepareReadiness()
            let next = try await proof.decision(observation: look)
            try await proof.invoke(next, expected: .knownExited(.providerOther))
        }
    }

    @Test(
        "clear changes the exact UUID; the old conversation's delayed end cannot veto the new one",
        arguments: ["claude-code", "codex"])
    func resumeEvidenceEndPrecedenceIsBindingScoped(provider: String) async throws {
        try await withResumeEvidenceProof(provider: provider) { proof in
            _ = try await proof.foreground.initialLook()
            _ = try await proof.report(event: .sessionEnd(reason: "other"))
            let nextID = UUIDv7.generate().uuidString
            _ = try await proof.report(event: .sessionStart, sessionID: nextID)
            _ = try await proof.report(event: .sessionEnd(reason: "other"))
            try await proof.foreground.requestLook(.relaunched)
            let scope = try await proof.foreground.nextLook(sequence: 2)
            try await proof.foreground.facts.expectNext(in: scope, .observation(.admitted))
            _ = try await proof.foreground.facts.expectNext(
                in: scope,
                where: {
                    if case .watchRegistered = $0 { true } else { false }
                }, "new binding native watch")
            try await proof.foreground.facts.expectNext(in: scope, .closed(.looked))
            let look = try await proof.foreground.observer.takePreRestoreObservation(paneId: proof.data.paneID)
            await proof.foreground.observer.shutdown()
            try await proof.foreground.killOwnedSession()
            try await proof.prepareReadiness()
            let decided = try await proof.decision(observation: look, reboot: true)
            try await proof.invoke(decided, expected: proof.candidate(sessionID: nextID))
        }
    }

    @Test(
        "a last look at an older binding cannot authorize the replacement's UUID",
        arguments: ["claude-code", "codex"])
    func resumeEvidenceOlderBindingLookIsUnknown(provider: String) async throws {
        try await withResumeEvidenceProof(provider: provider) { proof in
            _ = try await proof.foreground.initialLook()
            let look = try await proof.foreground.observer.takePreRestoreObservation(paneId: proof.data.paneID)
            let replacement = UUIDv7.generate().uuidString
            _ = try await proof.report(event: .sessionStart, sessionID: replacement)
            await proof.foreground.observer.shutdown()
            try await proof.foreground.killOwnedSession()
            try await proof.prepareReadiness()
            let decided = try await proof.decision(observation: look, reboot: true)
            try await proof.invoke(decided, expected: .unknown(.observationMismatch))
        }
    }

    @Test(
        "an older launch's late look cannot replace an admitted look in the new observer launch",
        arguments: ["claude-code", "codex"])
    func resumeEvidenceOlderLaunchLookIsRefused(provider: String) async throws {
        try await withResumeEvidenceProof(provider: provider) { proof in
            _ = try await proof.foreground.initialLook()
            let fetchedOld = try await proof.foreground.repository.load(paneId: proof.data.paneID)
            let old = try #require(fetchedOld)
            await proof.foreground.observer.shutdown()
            let paneID = proof.data.paneID
            let sessionID = proof.foreground.sessionId
            // Native sample and identity are unchanged; only the writer's equality scope is new.
            let fetchedSample = try await proof.foreground.probe.probeForeground(of: [sessionID])[sessionID]
            let sample = try #require(fetchedSample)
            let fresh = PaneForegroundObservation(
                paneId: paneID, zmxSessionId: sessionID, sessionIdentity: sample.sessionIdentity,
                bindingGenerationId: old.bindingGenerationId, program: sample.program,
                observerLaunchId: UUIDv7.generate(), sequence: 1, observedAt: proof.data.now)
            // Use a repository composed with the actual fresh writer scope.
            let writer = SQLitePaneForegroundObservationRepository(
                access: TestForegroundSQLiteAccess(databaseQueue: proof.data.access.queue),
                observerLaunchId: fresh.observerLaunchId, paneSessions: { [paneID: sessionID] })
            #expect(try await writer.admit(fresh) == .admitted)
            #expect(try await writer.admit(old) == .olderLook)
            #expect(try await writer.load(paneId: paneID) == fresh)
            try await proof.foreground.killOwnedSession()
            try await proof.prepareReadiness()
            let decided = try await proof.decision(observation: fresh, reboot: true)
            try await proof.invoke(decided, expected: proof.candidate())
        }
    }

    @Test(
        "the pre-restore value stays the decision even after the new incarnation's first real look",
        arguments: ["claude-code", "codex"])
    func resumeEvidenceUsesPreRestoreLook(provider: String) async throws {
        try await withResumeEvidenceProof(provider: provider) { proof in
            _ = try await proof.foreground.initialLook()
            let fetchedOld = try await proof.foreground.observer.takePreRestoreObservation(paneId: proof.data.paneID)
            let old = try #require(fetchedOld)
            await proof.foreground.observer.shutdown()
            try await proof.foreground.killOwnedSession()
            try await proof.prepareReadiness()
            let expected = try proof.candidate()
            let decided = try await proof.decision(observation: old)
            try await proof.invoke(
                decided, expected: expected,
                beforeRelease: {
                    let samples = try await proof.foreground.probe.probeForeground(of: [proof.foreground.sessionId])
                    let sample = try #require(samples[proof.foreground.sessionId])
                    #expect(sample.sessionIdentity != old.sessionIdentity)
                    let launchID = UUIDv7.generate()
                    let repository = SQLitePaneForegroundObservationRepository(
                        access: TestForegroundSQLiteAccess(databaseQueue: proof.data.access.queue),
                        observerLaunchId: launchID)
                    let fresh = PaneForegroundObservation(
                        paneId: proof.data.paneID, zmxSessionId: proof.foreground.sessionId,
                        sessionIdentity: sample.sessionIdentity, bindingGenerationId: old.bindingGenerationId,
                        program: sample.program, observerLaunchId: launchID, sequence: 1, observedAt: proof.data.now)
                    #expect(try await repository.admit(fresh) == .admitted)
                    #expect(decided == expected)
                    let secondHandoff = try await proof.foreground.observer.takePreRestoreObservation(
                        paneId: proof.data.paneID)
                    #expect(secondHandoff == nil)
                })
        }
    }

    @Test(
        "a replaced same-name incarnation cannot update the old watch's look or authorize resume",
        arguments: ["claude-code", "codex"])
    func resumeEvidenceOlderIncarnationIsUnknown(provider: String) async throws {
        try await withResumeEvidenceProof(provider: provider) { proof in
            _ = try await proof.foreground.initialLook()
            let fetchedOld = try await proof.foreground.repository.load(paneId: proof.data.paneID)
            let old = try #require(fetchedOld)
            let held = HeldStep<[ZmxSessionID]>("old watch pull across same-name replacement")
            defer { held.retire() }
            await proof.foreground.probeGate.holdNext(held)
            try await proof.foreground.killOwnedSession()
            let look = try await proof.foreground.nextLook(sequence: 2)
            let requested = try await held.firstArrival()
            #expect(requested == [proof.foreground.sessionId])
            let replacement = try ResumeZmxFixture(
                harness: proof.foreground.harness, providerIdentifier: provider,
                exitCode: 0, providerSessionId: proof.sessionID, restoreSessionID: proof.foreground.sessionId,
                reportsToFile: true, holdResume: false, ownership: proof.environment)
            let bootstrapPlan = TerminalColdRestorePlanBuilder.applyingResumeEvidence(
                .unknown(.observationMismatch),
                providerIdentifier: provider, providerSessionId: proof.sessionID, to: replacement.plan)
            let driver = try await replacement.launch(plan: bootstrapPlan)
            do {
                _ = try await driver.expectInteractiveShell()
                let fetchedIdentity = try await proof.backend.observeSessionIdentity(proof.foreground.sessionId)
                let newIdentity = try #require(fetchedIdentity)
                #expect(newIdentity != old.sessionIdentity)
                held.release()
                try await proof.foreground.facts.expectNext(in: look, .closed(.looked))
                #expect(try await proof.foreground.repository.load(paneId: proof.data.paneID) == old)
                try await proof.prepareReadiness()
                let verdict = try await proof.decision(observation: old)
                #expect(verdict == .unknown(.observationMismatch))
                try await proof.warmAttachWithoutInvocation(expectedIdentity: newIdentity)
                #expect(!FileManager.default.fileExists(atPath: replacement.callsURL.path))
                try await replacement.killOwnedSession()
                try await driver.stop()
            } catch {
                held.retire()
                try? await replacement.killOwnedSession()
                try? await driver.stop()
                throw error
            }
        }
    }

    private func withResumeEvidenceProof(
        provider: String,
        _ body: @escaping @Sendable (ResumeEvidenceZmxProof) async throws -> Void
    ) async throws {
        try await withResumeEvidenceBackend { environment in
            let proof = try await ResumeEvidenceZmxProof.make(environment: environment, provider: provider)
            do {
                try await body(proof)
                try await proof.close()
            } catch {
                try? await proof.close()
                throw error
            }
        }
    }
}
