import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Terminal activation scheduler", .serialized)
struct TerminalActivationSchedulerTests {
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
        let storedSessionID = try #require(ZmxSessionID(restoring: storedText))
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
        let port = ControlledTerminalActivationAdmissionPort()
        let scheduler = try makeScheduler(entries: hidden + visible + active, port: port)
        let activation = Task { await scheduler.activate() }

        await port.waitUntilStartedCount(4)
        #expect(
            port.admissions.prefix(4).map(\.descriptor.visibilityPriority) == Array(repeating: .activeVisible, count: 4)
        )

        port.releaseAllPendingAsReady()
        await port.waitUntilStartedCount(8)
        #expect(port.admissions[4..<8].map(\.descriptor.visibilityPriority) == Array(repeating: .visible, count: 4))

        port.releaseAllPendingAsReady()
        await port.waitUntilStartedCount(12)
        #expect(port.admissions[8..<12].map(\.descriptor.visibilityPriority) == Array(repeating: .hidden, count: 4))

        port.releaseAllPendingAsReady()
        let settlement = await activation.value
        #expect(settlement.outcomesByPaneID.count == 12)
    }

    @Test("slot bound holds while queued work remains")
    func slotBoundHoldsWhileQueuedWorkRemains() async throws {
        let descriptors = makeDescriptors(count: 100, priority: .activeVisible)
        let port = ControlledTerminalActivationAdmissionPort()
        let scheduler = try makeScheduler(entries: descriptors, port: port)
        let activation = Task { await scheduler.activate() }

        await port.waitUntilStartedCount(AppPolicies.TerminalActivation.maximumConcurrentAdmissions)

        #expect(port.admissions.count == AppPolicies.TerminalActivation.maximumConcurrentAdmissions)
        #expect(
            await scheduler.diagnostics().currentSimultaneousAdmissions
                == AppPolicies.TerminalActivation.maximumConcurrentAdmissions)

        port.releaseFirstPendingAsReady()
        await port.waitUntilStartedCount(AppPolicies.TerminalActivation.maximumConcurrentAdmissions + 1)

        #expect(
            await scheduler.diagnostics().maximumSimultaneousAdmissions
                == AppPolicies.TerminalActivation.maximumConcurrentAdmissions)

        while port.admissions.count < descriptors.count {
            port.releaseAllPendingAsReady()
            await port.waitUntilStartedCount(
                min(
                    port.admissions.count + AppPolicies.TerminalActivation.maximumConcurrentAdmissions,
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
        #expect(diagnostics.maximumSimultaneousAdmissions <= AppPolicies.TerminalActivation.maximumConcurrentAdmissions)
        #expect(diagnostics.workerCount <= AppPolicies.TerminalActivation.maximumConcurrentAdmissions)
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

        await port.waitUntilStartedCount(AppPolicies.TerminalActivation.maximumConcurrentAdmissions)
        await scheduler.cancelAndReplace(with: replacementGeneration)
        port.releaseAllPendingAsReady()
        let settlement = await activation.value

        #expect(port.admissions.count == AppPolicies.TerminalActivation.maximumConcurrentAdmissions)
        #expect(
            settlement.outcomesByPaneID.values.allSatisfy {
                $0 == .cancelledReplaced(replacement: replacementGeneration)
            }
        )
    }

    @Test("aggregate settlement waits for every member outcome")
    func aggregateSettlementWaitsForEveryMemberOutcome() async throws {
        let descriptors = makeDescriptors(
            count: AppPolicies.TerminalActivation.maximumConcurrentAdmissions + 1,
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

        await port.waitUntilStartedCount(AppPolicies.TerminalActivation.maximumConcurrentAdmissions)
        let releasedAdmission = try #require(port.releaseFirstPendingAsReady())
        await port.waitUntilStartedCount(
            AppPolicies.TerminalActivation.maximumConcurrentAdmissions + 1
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
            count: AppPolicies.TerminalActivation.maximumConcurrentAdmissions,
            priority: .activeVisible
        )
        let firstHidden = makeDescriptor(priority: .hidden)
        let promotedHidden = makeDescriptor(priority: .hidden)
        let port = ControlledTerminalActivationAdmissionPort()
        let scheduler = try makeScheduler(entries: active + [firstHidden, promotedHidden], port: port)
        let activation = Task { await scheduler.activate() }

        await port.waitUntilStartedCount(AppPolicies.TerminalActivation.maximumConcurrentAdmissions)
        let promotion = await scheduler.promote(
            paneID: promotedHidden.paneID,
            to: .activeVisible
        )
        port.releaseFirstPendingAsReady()
        await port.waitUntilStartedCount(AppPolicies.TerminalActivation.maximumConcurrentAdmissions + 1)

        #expect(promotion == .promoted(from: .hidden, to: .activeVisible))
        #expect(
            port.admissions[AppPolicies.TerminalActivation.maximumConcurrentAdmissions].descriptor.paneID
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
        (0..<count).map { index in
            makeDescriptor(
                zmxSessionID: ZmxSessionID(restoring: "opaque-zmx-\(index)-\(UUIDv7.generate())")!,
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
