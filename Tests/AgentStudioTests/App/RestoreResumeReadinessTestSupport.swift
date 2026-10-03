import AgentStudioInfrastructure
import AgentStudioTestHarness
import Foundation
import Synchronization
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

actor HeldLifecycleReportIntake: LifecycleReportIntaking {
    let boundary: LifecycleReportBoundary
    let hold = HeldStep<LifecycleReportBoundary>(
        "historical lifecycle intake before readiness publication", cancellation: .holdThroughCancellation)
    private(set) var capturedBoundaries = 0
    private(set) var takenBoundaries: [LifecycleReportBoundary] = []
    private let arrivalSink: @Sendable (LifecycleReportBoundary) -> Void
    init(
        boundary: LifecycleReportBoundary = .noStore,
        arrivalSink: @escaping @Sendable (LifecycleReportBoundary) -> Void = { _ in }
    ) {
        self.boundary = boundary
        self.arrivalSink = arrivalSink
    }
    func captureListenerReadyBoundary() async throws -> LifecycleReportBoundary {
        capturedBoundaries += 1
        return boundary
    }
    func takeIn(through boundary: LifecycleReportBoundary) async throws {
        takenBoundaries.append(boundary)
        arrivalSink(boundary)
        try await hold.arrive(boundary)
    }
}

enum ResumeIntakeOperationFact: Equatable, Sendable {
    case arrived(LifecycleReportBoundary)
    case initializationFinished
}

enum ResumeClassificationOperationFact: Equatable, Sendable { case publishedKinds, mountFinished }

struct ResumeClassificationProbe: Sendable {
    private let scope = UUIDv7.generate()
    private let source: LocalFactSource<UUID, ResumeClassificationOperationFact>
    private let facts: FactRecorder<UUID, ResumeClassificationOperationFact>
    private let held = HeldStep<Void>("classification after ready kind publication")

    init() throws {
        source = LocalFactSource(
            vocabulary: .init(
                describeScope: { $0.uuidString }, describeFact: { String(describing: $0) },
                isClosing: { _, fact in fact == .mountFinished }))
        facts = try source.attach()
    }

    func holdAfterPublication() async throws {
        source.sink(scope, .publishedKinds)
        try await held.arrive(())
    }
    func mountCompleted() { source.sink(scope, .mountFinished) }
    func expectPublishedKinds() async throws -> ResumeClassificationOperationFact {
        let fact = try await facts.expectNext(in: scope, where: { $0 == .publishedKinds }, "classified kinds published")
        _ = try await held.firstArrival()
        return fact
    }
    func release() { held.release() }
    func retire() { held.retire() }
    func finish() async throws { try await facts.finish() }
}

struct ResumeReadinessFixture: Sendable {
    let launchId = UUIDv7.generate()
    let clock = TestPushClock()
    let facts: FactRecorder<UUID, RestoreResumeReadinessFact>
    let readiness: RestoreResumeReadiness<TestPushClock>
    let intake: HeldLifecycleReportIntake
    let events: ResumeReadinessEventLedger
    private let intakeOperationSource: LocalFactSource<UUID, ResumeIntakeOperationFact>
    private let intakeOperationFacts: FactRecorder<UUID, ResumeIntakeOperationFact>

    init(boundary: LifecycleReportBoundary = .noStore) throws {
        let events = ResumeReadinessEventLedger()
        self.events = events
        let source = LocalFactSource(
            vocabulary: FactVocabulary<UUID, RestoreResumeReadinessFact>(
                describeScope: { $0.uuidString }, describeFact: { String(describing: $0) },
                isClosing: { _, fact in
                    switch fact {
                    case .published, .decided: true
                    default: false
                    }
                }))
        facts = try source.attach()
        readiness = RestoreResumeReadiness(
            clock: clock, deadline: .seconds(2), launchId: launchId,
            factSink: { scope, fact in
                events.record(fact)
                source.sink(scope, fact)
            })
        let intakeSource = LocalFactSource<UUID, ResumeIntakeOperationFact>(
            vocabulary: .init(
                describeScope: { $0.uuidString }, describeFact: { String(describing: $0) },
                isClosing: { _, fact in fact == .initializationFinished }))
        intakeOperationSource = intakeSource
        intakeOperationFacts = try intakeSource.attach()
        let launch = launchId
        intake = HeldLifecycleReportIntake(
            boundary: boundary, arrivalSink: { intakeSource.sink(launch, .arrived($0)) })
    }

    func beginResumeReadiness(prepareForLaunch: @escaping @Sendable () async throws -> Void = {}) -> Task<Void, Never> {
        Task {
            defer { initializationCompleted() }
            await AppIPCDeferredInitialization.prepareResumeReadiness(
                readiness: readiness, intake: intake, prepareForLaunch: prepareForLaunch)
        }
    }
    func initializationCompleted() { intakeOperationSource.sink(launchId, .initializationFinished) }
    @discardableResult
    func expectIntakeHeld() async throws -> LifecycleReportBoundary {
        _ = try await intakeOperationFacts.expectNext(
            in: launchId, where: { if case .arrived = $0 { true } else { false } }, "historical intake arrival")
        let boundary = try await intake.hold.firstArrival()
        try await facts.expectNext(in: launchId, .listenerReady)
        try await facts.expectNext(in: launchId, .boundaryRead(boundary))
        try await facts.expectNext(in: launchId, .launchPrepared)
        return boundary
    }
    func releaseIntake() async { intake.hold.release() }
    func close(initialization: Task<Void, Never>) async throws {
        intake.hold.retire()
        initialization.cancel()
        await readiness.shutdown()
        await initialization.value
        try await facts.finish()
        try await intakeOperationFacts.finish()
    }
}

final class ResumeReadinessEventLedger: Sendable {
    private let state = Mutex<[RestoreResumeReadinessFact]>([])
    func record(_ fact: RestoreResumeReadinessFact) { state.withLock { $0.append(fact) } }
    func snapshot() -> [RestoreResumeReadinessFact] { state.withLock { $0 } }
}

enum ResumeAppAdmissionFact: Equatable, Sendable { case started, finished }

@MainActor
final class ResumeAppAdmissionPort: TerminalActivationAdmissionPort {
    private let descriptors: [PaneId: TerminalActivationDescriptor]
    private var kinds: [PaneId: TerminalRestoreKind] = [:]
    private(set) var admissions: [TerminalActivationAdmission] = []
    var beforeStart: (@Sendable (TerminalActivationAdmission) async -> Void)?
    let facts: FactRecorder<UUID, ResumeAppAdmissionFact>
    private let source: LocalFactSource<UUID, ResumeAppAdmissionFact>

    init(entries: [TerminalActivationDescriptor]) throws {
        descriptors = Dictionary(uniqueKeysWithValues: entries.map { ($0.paneID, $0) })
        source = LocalFactSource(
            vocabulary: .init(
                describeScope: { $0.uuidString },
                describeFact: { String(describing: $0) }, isClosing: { _, fact in fact == .finished }))
        facts = try source.attach()
    }
    func installRestoreKinds(_ updates: [PaneId: TerminalRestoreKind]) { kinds.merge(updates) { _, latest in latest } }
    func recordCurrentVisibleQueuedTerminals(_ terminals: TerminalVisibleQueuedTerminals) -> TerminalVisibilityRevision
    {
        .init(generation: terminals.generation, ordinal: 0)
    }
    func claimPreparedTerminal(_ proposal: TerminalAdmissionProposal) -> TerminalAdmissionClaimOutcome {
        guard let descriptor = descriptors[proposal.paneID] else { return .rejected(.paneNotInCohort) }
        return .claimed(
            .init(
                claimID: UUIDv7.generate(),
                admission: .init(
                    generation: proposal.generation,
                    descriptor: descriptor, attempt: proposal.attempt, restoreKind: kinds[proposal.paneID]),
                acknowledgedVisibilityRevision: proposal.appliedVisibilityRevision))
    }
    func activateClaimedTerminal(_ claim: ClaimedTerminalAdmission) async -> ClaimedTerminalActivationOutcome {
        admissions.append(claim.admission)
        await beforeStart?(claim.admission)
        source.sink(claim.admission.descriptor.paneID.uuid, .started)
        source.sink(claim.admission.descriptor.paneID.uuid, .finished)
        return .attempted(.ready(surfaceID: UUIDv7.generate()))
    }
    func expectStartAndFinish(_ paneId: PaneId) async throws {
        try await facts.expectNext(in: paneId.uuid, .started)
        try await facts.expectNext(in: paneId.uuid, .finished)
    }
}

func resumeAppBasePlan(_ descriptor: TerminalActivationDescriptor) throws -> TerminalColdRestorePlan {
    let session = try #require(descriptor.pane.terminalState?.zmxSessionID)
    return TerminalColdRestorePlanBuilder.buildPlan(
        pane: descriptor.pane, sessionID: session,
        zmxExecutablePath: "/unused/zmx", zmxDirectoryPath: "/unused/zmx-root", loginShellPath: "/bin/zsh",
        repositoryMainFolder: nil)
}
