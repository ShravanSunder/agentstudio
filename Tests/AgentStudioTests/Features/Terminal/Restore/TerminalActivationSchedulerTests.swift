import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioTerminal

@MainActor
@Suite("Terminal activation scheduler", .serialized)
struct TerminalActivationSchedulerTests {
    enum ReferenceVersusGatedCase: CaseIterable, CustomTestStringConvertible {
        case ready
        case createFailure
        case attachFailure
        case retryReady

        var testDescription: String { String(describing: self) }

        func results(surfaceID: UUID) -> [TerminalActivationAttemptResult] {
            switch self {
            case .ready:
                return [.ready(surfaceID: surfaceID)]
            case .createFailure:
                return [
                    .failed(
                        failure: .surfaceCreationFailed(code: "surface-unavailable"),
                        retry: .doNotRetry
                    )
                ]
            case .attachFailure:
                return [
                    .failed(
                        failure: .surfaceAttachmentFailed(code: "exact-attach-rejected"),
                        retry: .doNotRetry
                    )
                ]
            case .retryReady:
                return [
                    .failed(
                        failure: .surfaceCreationFailed(code: "transient-create"),
                        retry: .retry
                    ),
                    .ready(surfaceID: surfaceID),
                ]
            }
        }
    }

    @Test("empty cohort settles without admission")
    func emptyCohortSettlesWithoutAdmission() async throws {
        let port = ImmediateTerminalActivationAdmissionPort()
        let scheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(
                generation: try makeCompositionGeneration(),
                input: TerminalActivationInput(entries: [])
            ),
            admissionPort: port
        )

        let settlement = await scheduler.activate()
        let diagnostics = await scheduler.diagnostics()

        #expect(settlement.outcomesByPaneID.isEmpty)
        #expect(port.admissions.isEmpty)
        #expect(diagnostics.maximumSimultaneousAdmissions == 0)
    }

    @Test("single member forwards exact opaque zmx identity")
    func singleMemberForwardsExactOpaqueZmxIdentity() async throws {
        let storedText = "opaque existing zmx identity ! '$`\\"
        let storedSessionID = try makeRestoredZmxSessionID(storedText)
        let descriptor = makeDescriptor(zmxSessionID: storedSessionID)
        let surfaceID = UUIDv7.generate()
        let port = ImmediateTerminalActivationAdmissionPort(
            resultsByPaneID: [descriptor.paneID: [.ready(surfaceID: surfaceID)]]
        )
        let scheduler = try makeScheduler(entries: [descriptor], port: port)

        let settlement = await scheduler.activate()
        let admittedPane = try #require(port.admissions.first?.descriptor.pane)
        guard case .terminal(let admittedTerminalState) = admittedPane.content else {
            Issue.record("expected admitted descriptor to retain terminal content")
            return
        }

        #expect(admittedTerminalState.zmxSessionID == storedSessionID)
        #expect(admittedTerminalState.zmxSessionID.rawValue == storedText)
        #expect(await scheduler.memberState(for: descriptor.paneID) == .ready(surfaceID: surfaceID))
        #expect(settlement.outcomesByPaneID[descriptor.paneID] == .ready(surfaceID: surfaceID))
    }

    @Test("active visible then visible then hidden cohorts are admitted in priority order")
    func cohortPriorityOrderIsStable() async throws {
        let active = makeDescriptors(count: 4, priority: .activeVisible)
        let visible = makeDescriptors(count: 4, priority: .visible)
        let hidden = makeDescriptors(count: 4, priority: .hidden)
        let port = ImmediateTerminalActivationAdmissionPort()
        let scheduler = try makeScheduler(entries: hidden + visible + active, port: port)

        let settlement = await scheduler.activate()

        #expect(
            port.admissions.map(\.descriptor.visibilityPriority)
                == Array(repeating: .activeVisible, count: 4)
                + Array(repeating: .visible, count: 4)
                + Array(repeating: .hidden, count: 4)
        )
        #expect(settlement.outcomesByPaneID.count == 12)
    }

    @Test("closed restore gate admits nothing before release and preserves stable priority order")
    func closedRestoreGatePreservesOrderUntilRelease() async throws {
        let active = makeDescriptor(priority: .activeVisible)
        let firstHidden = makeDescriptor(priority: .hidden)
        let secondHidden = makeDescriptor(priority: .hidden)
        let port = ImmediateTerminalActivationAdmissionPort()
        let releaseSignal = ControlledTerminalActivationReleaseSignal()
        let scheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(
                generation: try makeCompositionGeneration(),
                input: TerminalActivationInput(entries: [firstHidden, active, secondHidden])
            ),
            admissionPort: port,
            releaseSignal: releaseSignal
        )
        let activation = Task { await scheduler.activate() }
        await releaseSignal.waitUntilSchedulerIsWaiting()

        #expect(port.admissions.isEmpty)

        await releaseSignal.release()
        let settlement = await activation.value

        #expect(
            port.admissions.map(\.descriptor.paneID)
                == [active.paneID, firstHidden.paneID, secondHidden.paneID]
        )
        #expect(settlement.outcomesByPaneID.count == 3)
    }

    @Test("restore admissions are serial with a yield after every completed attempt")
    func restoreAdmissionsAreSerialAndYielded() async throws {
        let descriptors = makeDescriptors(count: 3, priority: .activeVisible)
        let port = ImmediateTerminalActivationAdmissionPort()
        let scheduler = try makeScheduler(entries: descriptors, port: port)

        _ = await scheduler.activate()
        let diagnostics = await scheduler.diagnostics()

        #expect(diagnostics.maximumSimultaneousAdmissions == 1)
        #expect(diagnostics.workerCount == 1)
        #expect(diagnostics.yieldCount == descriptors.count)
        #expect(port.admissions.map(\.descriptor.paneID) == descriptors.map(\.paneID))
    }

    @Test("replacement while gated settles without admitting stale members")
    func replacementWhileGatedSettlesWithoutAdmission() async throws {
        let originalGeneration = nextCompositionGeneration()
        let replacementGeneration = nextCompositionGeneration()
        let descriptors = makeDescriptors(count: 3, priority: .hidden)
        let port = ImmediateTerminalActivationAdmissionPort()
        let releaseSignal = ControlledTerminalActivationReleaseSignal()
        let scheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(
                generation: originalGeneration,
                input: TerminalActivationInput(entries: descriptors)
            ),
            admissionPort: port,
            releaseSignal: releaseSignal
        )
        let activation = Task { await scheduler.activate() }
        await releaseSignal.waitUntilSchedulerIsWaiting()

        await scheduler.cancelAndReplace(with: replacementGeneration)
        await releaseSignal.release()
        let settlement = await activation.value

        #expect(port.admissions.isEmpty)
        #expect(
            settlement.outcomesByPaneID.values.allSatisfy {
                $0 == .cancelledReplaced(replacement: replacementGeneration)
            }
        )
    }

    @Test(
        "gated restore is lossless against the reference scheduler",
        arguments: ReferenceVersusGatedCase.allCases
    )
    func gatedRestoreMatchesReference(testCase: ReferenceVersusGatedCase) async throws {
        let storedText = "opaque restored zmx identity ! '$`\\"
        let storedSessionID = try makeRestoredZmxSessionID(storedText)
        let descriptor = makeDescriptor(zmxSessionID: storedSessionID)
        let surfaceID = UUIDv7.generate()
        let results = testCase.results(surfaceID: surfaceID)
        let referencePort = ImmediateTerminalActivationAdmissionPort(
            resultsByPaneID: [descriptor.paneID: results]
        )
        let gatedPort = ImmediateTerminalActivationAdmissionPort(
            resultsByPaneID: [descriptor.paneID: results]
        )
        let referenceScheduler = try makeScheduler(entries: [descriptor], port: referencePort)
        let releaseSignal = ControlledTerminalActivationReleaseSignal()
        let gatedScheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(
                generation: try makeCompositionGeneration(),
                input: TerminalActivationInput(entries: [descriptor])
            ),
            admissionPort: gatedPort,
            releaseSignal: releaseSignal
        )
        let gatedActivation = Task { await gatedScheduler.activate() }
        await releaseSignal.waitUntilSchedulerIsWaiting()

        let referenceSettlement = await referenceScheduler.activate()
        #expect(gatedPort.admissions.isEmpty)
        await releaseSignal.release()
        let gatedSettlement = await gatedActivation.value

        #expect(
            gatedSettlement.outcomesByPaneID[descriptor.paneID]
                == referenceSettlement.outcomesByPaneID[descriptor.paneID]
        )
        #expect(gatedPort.admissions.map(\.attempt) == referencePort.admissions.map(\.attempt))
        for admission in gatedPort.admissions {
            #expect(admission.descriptor.pane.terminalState?.zmxSessionID == storedSessionID)
            #expect(admission.descriptor.pane.terminalState?.zmxSessionID.rawValue == storedText)
        }
    }

    @Test("slot bound holds while queued work remains")
    func slotBoundHoldsWhileQueuedWorkRemains() async throws {
        let descriptors = makeDescriptors(count: 100, priority: .activeVisible)
        let port = ControlledTerminalActivationAdmissionPort()
        let scheduler = try makeScheduler(entries: descriptors, port: port)
        let activation = Task { await scheduler.activate() }

        await port.waitUntilStartedCount(AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions)

        #expect(port.admissions.count == AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions)
        #expect(
            await scheduler.diagnostics().currentSimultaneousAdmissions
                == AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions)

        port.releaseFirstPendingAsReady()
        await port.waitUntilStartedCount(AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions + 1)

        #expect(
            await scheduler.diagnostics().maximumSimultaneousAdmissions
                == AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions)

        while port.admissions.count < descriptors.count {
            port.releaseAllPendingAsReady()
            await port.waitUntilStartedCount(
                min(
                    port.admissions.count + AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions,
                    descriptors.count))
        }
        port.releaseAllPendingAsReady()
        let settlement = await activation.value
        #expect(settlement.outcomesByPaneID.count == descriptors.count)
    }

    @Test("large cohorts settle with a fleet-sized worker bound", arguments: [100, 300])
    func largeCohortsSettleWithFleetSizedWorkerBound(memberCount: Int) async throws {
        let descriptors = makeDescriptors(count: memberCount, priority: .hidden)
        let port = ImmediateTerminalActivationAdmissionPort()
        let scheduler = try makeScheduler(entries: descriptors, port: port)

        let settlement = await scheduler.activate()
        let diagnostics = await scheduler.diagnostics()

        #expect(settlement.outcomesByPaneID.count == memberCount)
        #expect(port.admissions.count == memberCount)
        #expect(
            diagnostics.maximumSimultaneousAdmissions
                <= AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions
        )
        #expect(diagnostics.workerCount <= AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions)
    }

    @Test("one requested retry requeues the same member and can become ready")
    func requestedRetryRequeuesSameMemberAndCanBecomeReady() async throws {
        let descriptor = makeDescriptor()
        let failure = TerminalActivationFailure.attachmentRejected(code: "transient-attach")
        let surfaceID = UUIDv7.generate()
        let port = ImmediateTerminalActivationAdmissionPort(
            resultsByPaneID: [
                descriptor.paneID: [
                    .failed(failure: failure, retry: .retry),
                    .ready(surfaceID: surfaceID),
                ]
            ]
        )
        let scheduler = try makeScheduler(entries: [descriptor], port: port)

        let settlement = await scheduler.activate()

        #expect(port.admissions.map(\.attempt) == [1, 2])
        #expect(port.admissions.map(\.descriptor.paneID) == [descriptor.paneID, descriptor.paneID])
        #expect(settlement.outcomesByPaneID[descriptor.paneID] == .ready(surfaceID: surfaceID))
    }

    @Test("non-retryable failure exposes strict terminal failure state")
    func nonRetryableFailureExposesStrictTerminalFailureState() async throws {
        let descriptor = makeDescriptor()
        let failure = TerminalActivationFailure.surfaceCreationFailed(code: "surface-unavailable")
        let port = ImmediateTerminalActivationAdmissionPort(
            resultsByPaneID: [
                descriptor.paneID: [.failed(failure: failure, retry: .doNotRetry)]
            ]
        )
        let scheduler = try makeScheduler(entries: [descriptor], port: port)

        let settlement = await scheduler.activate()
        let expectedRetry = TerminalActivationRetry.notRequested(attemptCount: 1)

        #expect(
            await scheduler.memberState(for: descriptor.paneID)
                == .failedTerminal(failure: failure, retry: expectedRetry)
        )
        #expect(
            settlement.outcomesByPaneID[descriptor.paneID]
                == .failedTerminal(failure: failure, retry: expectedRetry)
        )
    }

    @Test("replacement cancels queued and attaching members without accepting stale completions")
    func replacementCancelsQueuedAndAttachingMembers() async throws {
        let originalGeneration = nextCompositionGeneration()
        let replacementGeneration = nextCompositionGeneration()
        let descriptors = makeDescriptors(count: 8, priority: .hidden)
        let port = ControlledTerminalActivationAdmissionPort()
        let scheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(
                generation: originalGeneration,
                input: TerminalActivationInput(entries: descriptors)
            ),
            admissionPort: port
        )
        let activation = Task { await scheduler.activate() }

        await port.waitUntilStartedCount(AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions)
        await scheduler.cancelAndReplace(with: replacementGeneration)
        port.releaseAllPendingAsReady()
        let settlement = await activation.value

        #expect(port.admissions.count == AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions)
        #expect(
            settlement.outcomesByPaneID.values.allSatisfy {
                $0 == .cancelledReplaced(replacement: replacementGeneration)
            }
        )
    }

    @Test("aggregate settlement waits for every member outcome")
    func aggregateSettlementWaitsForEveryMemberOutcome() async throws {
        let descriptors = makeDescriptors(
            count: AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions + 1,
            priority: .activeVisible
        )
        let port = ControlledTerminalActivationAdmissionPort()
        let completionProbe = TerminalActivationCompletionProbe()
        let scheduler = try makeScheduler(entries: descriptors, port: port)
        let activation = Task {
            let settlement = await scheduler.activate()
            await completionProbe.record(settlement)
            return settlement
        }

        await port.waitUntilStartedCount(AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions)
        let releasedAdmission = try #require(port.releaseFirstPendingAsReady())
        await port.waitUntilStartedCount(
            AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions + 1
        )
        let newlyStartedAdmission = try #require(port.admissions.last)

        #expect(!(await completionProbe.isCompleted))
        #expect(await scheduler.memberState(for: releasedAdmission.descriptor.paneID)?.isTerminal == true)
        #expect(await scheduler.memberState(for: newlyStartedAdmission.descriptor.paneID) == .attaching)

        port.releaseAllPendingAsReady()
        let settlement = await activation.value
        #expect(settlement.outcomesByPaneID.count == descriptors.count)
        #expect(await completionProbe.isCompleted)
    }

    @Test("priority promotion preempts queued hidden work")
    func priorityPromotionPreemptsQueuedHiddenWork() async throws {
        let active = makeDescriptors(
            count: AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions,
            priority: .activeVisible
        )
        let firstHidden = makeDescriptor(priority: .hidden)
        let promotedHidden = makeDescriptor(priority: .hidden)
        let port = ControlledTerminalActivationAdmissionPort()
        let scheduler = try makeScheduler(entries: active + [firstHidden, promotedHidden], port: port)
        let activation = Task { await scheduler.activate() }

        await port.waitUntilStartedCount(AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions)
        let promotion = await scheduler.promote(
            paneID: promotedHidden.paneID,
            to: .activeVisible
        )
        port.releaseFirstPendingAsReady()
        await port.waitUntilStartedCount(AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions + 1)

        #expect(promotion == .promoted(from: .hidden, to: .activeVisible))
        #expect(
            port.admissions[AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions].descriptor.paneID
                == promotedHidden.paneID)

        port.releaseAllPendingAsReady()
        await port.waitUntilStartedCount(active.count + 2)
        port.releaseAllPendingAsReady()
        _ = await activation.value
    }

    private func makeScheduler(
        entries: [TerminalActivationDescriptor],
        port: some TerminalActivationAdmissionPort
    ) throws -> TerminalActivationScheduler {
        TerminalActivationScheduler(
            cohort: TerminalActivationCohort(
                generation: try makeCompositionGeneration(),
                input: TerminalActivationInput(entries: entries)
            ),
            admissionPort: port
        )
    }

    private func makeCompositionGeneration() throws -> WorkspaceContentMountGeneration {
        nextCompositionGeneration()
    }

    private func nextCompositionGeneration() -> WorkspaceContentMountGeneration {
        WorkspaceContentMountGeneration()
    }

    private func makeDescriptors(
        count: Int,
        priority: TerminalActivationVisibilityPriority
    ) -> [TerminalActivationDescriptor] {
        (0..<count).map { _ in
            makeDescriptor(
                zmxSessionID: .generateUUIDv7(),
                priority: priority
            )
        }
    }

    private func makeDescriptor(
        zmxSessionID: ZmxSessionID = .generateUUIDv7(),
        priority: TerminalActivationVisibilityPriority = .activeVisible
    ) -> TerminalActivationDescriptor {
        let pane = Pane(
            id: UUIDv7.generate(),
            content: .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionID: zmxSessionID
                )
            ),
            metadata: PaneMetadata(
                launchDirectory: URL(filePath: "/tmp/terminal-activation"),
                title: "Activation test"
            )
        )
        return TerminalActivationDescriptor(
            pane: pane,
            visibilityPriority: priority,
            hostPlacement: .tab(tabID: UUIDv7.generate())
        )
    }
}

@MainActor
private final class ImmediateTerminalActivationAdmissionPort: TerminalActivationAdmissionPort {
    private var resultsByPaneID: [PaneId: [TerminalActivationAttemptResult]]
    private(set) var admissions: [TerminalActivationAdmission] = []

    init(resultsByPaneID: [PaneId: [TerminalActivationAttemptResult]] = [:]) {
        self.resultsByPaneID = resultsByPaneID
    }

    func activate(_ admission: TerminalActivationAdmission) async -> TerminalActivationAttemptResult {
        admissions.append(admission)
        if var results = resultsByPaneID[admission.descriptor.paneID], !results.isEmpty {
            let result = results.removeFirst()
            resultsByPaneID[admission.descriptor.paneID] = results
            return result
        }
        return .ready(surfaceID: UUIDv7.generate())
    }
}

@MainActor
private final class ControlledTerminalActivationAdmissionPort: TerminalActivationAdmissionPort {
    private struct PendingAdmission {
        let admission: TerminalActivationAdmission
        let continuation: CheckedContinuation<TerminalActivationAttemptResult, Never>
    }

    private var pending: [PendingAdmission] = []
    private var startedCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var admissions: [TerminalActivationAdmission] = []

    func activate(_ admission: TerminalActivationAdmission) async -> TerminalActivationAttemptResult {
        admissions.append(admission)
        resumeSatisfiedStartedCountWaiters()
        return await withCheckedContinuation { continuation in
            pending.append(PendingAdmission(admission: admission, continuation: continuation))
        }
    }

    func waitUntilStartedCount(_ count: Int) async {
        guard admissions.count < count else { return }
        await withCheckedContinuation { continuation in
            startedCountWaiters.append((count, continuation))
        }
    }

    @discardableResult
    func releaseFirstPendingAsReady() -> TerminalActivationAdmission? {
        guard !pending.isEmpty else {
            Issue.record("Expected a pending terminal activation admission")
            return nil
        }
        let pendingAdmission = pending.removeFirst()
        pendingAdmission.continuation.resume(returning: .ready(surfaceID: UUIDv7.generate()))
        return pendingAdmission.admission
    }

    func releaseAllPendingAsReady() {
        let pendingAdmissions = pending
        pending.removeAll()
        for pendingAdmission in pendingAdmissions {
            pendingAdmission.continuation.resume(returning: .ready(surfaceID: UUIDv7.generate()))
        }
    }

    private func resumeSatisfiedStartedCountWaiters() {
        let ready = startedCountWaiters.filter { $0.0 <= admissions.count }
        startedCountWaiters.removeAll { $0.0 <= admissions.count }
        for waiter in ready { waiter.1.resume() }
    }
}

private actor TerminalActivationCompletionProbe {
    private(set) var settlement: TerminalActivationSettlement?

    var isCompleted: Bool { settlement != nil }

    func record(_ settlement: TerminalActivationSettlement) {
        self.settlement = settlement
    }
}

private actor ControlledTerminalActivationReleaseSignal: TerminalActivationReleaseSignal {
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var waitStartedContinuations: [CheckedContinuation<Void, Never>] = []
    private var isSchedulerWaiting = false
    private var isReleased = false

    func waitUntilReleased() async {
        guard !isReleased else { return }
        isSchedulerWaiting = true
        let startedContinuations = waitStartedContinuations
        waitStartedContinuations.removeAll()
        for continuation in startedContinuations {
            continuation.resume()
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilSchedulerIsWaiting() async {
        guard !isSchedulerWaiting else { return }
        await withCheckedContinuation { continuation in
            waitStartedContinuations.append(continuation)
        }
    }

    func release() {
        guard !isReleased else { return }
        isReleased = true
        let continuation = releaseContinuation
        releaseContinuation = nil
        continuation?.resume()
    }
}
