import AgentStudioInfrastructure
import AgentStudioTestHarness
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

@MainActor
@Suite("Restore resume readiness", .serialized)
struct RestoreResumeReadinessTests {
    init() { installTestCoreAtomsIfNeeded() }

    @Test("ready is published only after listener boundary, launch preparation and historical intake")
    func allThreeReadinessFactsAreRequired() async throws {
        let boundary = LifecycleReportBoundary.stored(storeId: UUIDv7.generate(), sequence: 42)
        let fixture = try ResumeReadinessFixture(boundary: boundary)
        let initialization = fixture.beginResumeReadiness()
        let paneId = UUIDv7.generate()
        let waiting = Task { await fixture.readiness.wait(paneId: paneId) }
        do {
            try await fixture.expectIntakeHeld()
            try await fixture.facts.expectNext(in: paneId, .waiting)
            #expect(await fixture.intake.capturedBoundaries == 1)
            #expect(await fixture.intake.takenBoundaries == [boundary])
            #expect(!fixture.events.snapshot().contains(.published(.ready)))
            await fixture.releaseIntake()
            await initialization.value
            try await fixture.facts.expectNext(in: fixture.launchId, .reportsTakenIn(boundary))
            try await fixture.facts.expectNext(in: fixture.launchId, .published(.ready))
            #expect(await waiting.value == .ready)
            try await fixture.facts.expectNext(in: paneId, .decided(.ready))
            try await fixture.close(initialization: initialization)
        } catch {
            fixture.intake.hold.retire()
            await fixture.readiness.shutdown()
            _ = await waiting.value
            try? await fixture.close(initialization: initialization)
            throw error
        }
    }

    @Test("a no-store stand-in has no rows but still obeys the three-fact readiness boundary")
    func noStoreStandInClosesTheBoundary() async throws {
        let fixture = try ResumeReadinessFixture()
        let initialization = fixture.beginResumeReadiness()
        do {
            let boundary = try await fixture.expectIntakeHeld()
            #expect(boundary == .noStore)
            await fixture.releaseIntake()
            await initialization.value
            try await fixture.facts.expectNext(in: fixture.launchId, .reportsTakenIn(.noStore))
            try await fixture.facts.expectNext(in: fixture.launchId, .published(.ready))
            try await fixture.close(initialization: initialization)
        } catch {
            try? await fixture.close(initialization: initialization)
            throw error
        }
    }

    @Test("the controlled readiness deadline is final and late intake cannot publish ready")
    func deadlineCannotBeRevivedByLateIntake() async throws {
        let fixture = try ResumeReadinessFixture()
        let initialization = fixture.beginResumeReadiness()
        let paneId = UUIDv7.generate()
        let waiting = Task { await fixture.readiness.wait(paneId: paneId) }
        do {
            try await fixture.expectIntakeHeld()
            try await fixture.facts.expectNext(in: paneId, .waiting)
            let opening = await fixture.facts.mark(fixture.launchId)
            await fixture.clock.waitForPendingSleepCount(atLeast: 1)
            fixture.clock.advance(by: .seconds(2))
            try await fixture.facts.expectNone(
                of: { $0 == .published(.ready) }, "ready while historical intake is held", from: opening,
                closedBy: { $0 == .published(.unavailable) })
            #expect(await waiting.value == .unavailable)
            try await fixture.facts.expectNext(in: paneId, .decided(.unavailable))
            await fixture.releaseIntake()
            await initialization.value
            let latePane = UUIDv7.generate()
            #expect(await fixture.readiness.wait(paneId: latePane) == .unavailable)
            #expect(!fixture.events.snapshot().contains(.published(.ready)))
            #expect(fixture.events.snapshot().filter { if case .published = $0 { true } else { false } }.count == 1)
            try await fixture.close(initialization: initialization)
        } catch {
            fixture.intake.hold.retire()
            await fixture.readiness.shutdown()
            _ = await waiting.value
            try? await fixture.close(initialization: initialization)
            throw error
        }
    }

    @Test(
        "held post-frame intake leaves the first frame and warm or unverified admission independent of the cold plan",
        arguments: [false, true])
    func firstFrameAndWarmPaneNeverWaitForColdIntake(unverified: Bool) async throws {
        let fixture = try ResumeReadinessFixture()
        let cold = makePreparedContentCoordinatorTerminalDescriptor(title: "cold", visibilityPriority: .activeVisible)
        let warm = makePreparedContentCoordinatorTerminalDescriptor(title: "warm", visibilityPriority: .hidden)
        let entries = [cold, warm]
        let base = try resumeAppBasePlan(cold)
        let warmPlan = try resumeAppBasePlan(warm)
        let readyKind: TerminalRestoreKind =
            unverified
            ? .unverified(.sessionUnresponsive, fallback: warmPlan)
            : .warm(identity: Data("warm".utf8), fallback: warmPlan)
        let classification = try ResumeClassificationProbe()
        defer { classification.retire() }
        let window = WindowLifecycleAtom()
        let invocation = ResumeInvocation(
            provider: .codex, sessionId: try ProviderSessionId(rawValue: UUIDv7.generate().uuidString))
        let port = try ResumeAppAdmissionPort(entries: entries)
        let cohort = WorkspacePreparedContentMountCohort(
            generation: .init(), terminalActivationInput: .init(entries: entries),
            nonterminalContentMountInput: .init(entries: []))
        let registry = ViewRegistry()
        registry.beginInitialRestore()
        let coordinator = WorkspacePreparedContentMountCoordinator(
            cohort: cohort, viewRegistry: registry,
            terminalAdmissionPort: port, nonterminalAdmissionPort: RecordingPreparedContentNonterminalPort(),
            classifyTerminalRestoreKinds: { _, publish in
                await publish(cold.paneID, .cold(base))
                await publish(warm.paneID, readyKind)
                try? await classification.holdAfterPublication()
            },
            resolveColdResumePlan: { paneId, plan in
                let ready = await fixture.readiness.wait(paneId: paneId.uuid)
                return TerminalColdRestorePlanBuilder.applyingResumeEvidence(
                    ready == .ready ? .interruptedCandidate(invocation) : .unknown(.reportsNotTakenIn),
                    providerIdentifier: "codex", providerSessionId: invocation.sessionId.rawValue, to: plan)
            })
        await coordinator.installTerminalGeometryAvailability(Set(entries.map(\.paneID)))
        await coordinator.holdTerminalActivationUntilReleased()
        let mount = Task {
            defer { classification.mountCompleted() }
            return await coordinator.mount()
        }
        let initialization = Task {
            defer { fixture.initializationCompleted() }
            _ = await AppIPCDeferredInitialization.run(windowLifecycleStore: window) {
                await AppIPCDeferredInitialization.prepareResumeReadiness(
                    readiness: fixture.readiness, intake: fixture.intake, prepareForLaunch: {})
            }
        }
        do {
            window.recordFirstInteractiveFramePublished(source: .presented)
            #expect(await window.waitUntilFirstInteractiveFramePublished() == .completed)
            await coordinator.releaseTerminalActivation()
            _ = try await classification.expectPublishedKinds()
            try await fixture.facts.expectNext(in: cold.paneID.uuid, .waiting)
            try await fixture.expectIntakeHeld()
            try await port.expectStartAndFinish(warm.paneID)
            let admittedPaneIds = port.admissions.map { $0.descriptor.paneID }
            #expect(admittedPaneIds == [warm.paneID])
            #expect(!fixture.events.snapshot().contains(.published(.ready)))
            classification.release()
            await fixture.releaseIntake()
            _ = await initialization.value
            try await port.expectStartAndFinish(cold.paneID)
            _ = await mount.value
            #expect(port.admissions.first?.restoreKind == readyKind)
            let kind = try #require(port.admissions.last?.restoreKind)
            if case .cold(let plan) = kind {
                #expect(plan.resume == invocation)
            } else {
                Issue.record("expected the decided cold plan after readiness")
            }
            try await fixture.close(initialization: initialization)
            try await classification.finish()
            try await port.facts.finish()
        } catch {
            classification.retire()
            fixture.intake.hold.retire()
            initialization.cancel()
            await fixture.readiness.shutdown()
            window.recordFirstInteractiveFramePublished(source: .presented)
            await coordinator.releaseTerminalActivation()
            _ = await initialization.value
            _ = await mount.value
            try? await fixture.close(initialization: initialization)
            try? await classification.finish()
            try? await port.facts.finish()
            throw error
        }
    }
}
