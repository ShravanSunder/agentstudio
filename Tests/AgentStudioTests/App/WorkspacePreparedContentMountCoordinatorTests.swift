import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace prepared content mount coordinator")
struct WorkspacePreparedContentMountCoordinatorTests {
    @Test("empty accepted cohort settles both lanes and completes initial restore")
    func emptyCohortCompletesInitialRestore() async throws {
        // Arrange
        let generation = try makePreparedContentCoordinatorGeneration()
        let cohort = WorkspacePreparedContentMountCohort(
            generation: generation,
            terminalActivationInput: TerminalActivationInput(entries: []),
            nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
        )
        let registry = ViewRegistry()
        registry.beginInitialRestore()
        let terminalPort = RecordingPreparedContentTerminalPort()
        let nonterminalPort = RecordingPreparedContentNonterminalPort()
        let coordinator = WorkspacePreparedContentMountCoordinator(
            cohort: cohort,
            viewRegistry: registry,
            terminalAdmissionPort: terminalPort,
            nonterminalAdmissionPort: nonterminalPort
        )

        // Act
        let settlement = await coordinator.mount()

        // Assert
        #expect(settlement.generation == generation)
        #expect(settlement.terminal.outcomesByPaneID.isEmpty)
        #expect(settlement.nonterminal.outcomesByPaneID.isEmpty)
        #expect(registry.isInitialRestorePending == false)
        #expect(terminalPort.admissions.isEmpty)
        #expect(nonterminalPort.descriptors.isEmpty)
    }

    @Test("concurrent mount callers share one lane execution and cached settlement")
    func concurrentMountCallersShareOneExecution() async throws {
        // Arrange
        let generation = try makePreparedContentCoordinatorGeneration()
        let descriptor = makePreparedContentCoordinatorTerminalDescriptor()
        let cohort = WorkspacePreparedContentMountCohort(
            generation: generation,
            terminalActivationInput: TerminalActivationInput(entries: [descriptor]),
            nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
        )
        let registry = ViewRegistry()
        registry.beginInitialRestore()
        let terminalPort = SuspendedPreparedContentTerminalPort()
        let coordinator = WorkspacePreparedContentMountCoordinator(
            cohort: cohort,
            viewRegistry: registry,
            terminalAdmissionPort: terminalPort,
            nonterminalAdmissionPort: RecordingPreparedContentNonterminalPort()
        )
        let firstMount = Task { @MainActor in
            await coordinator.mount()
        }
        await terminalPort.waitUntilAdmissionStarts()
        let secondCallerStarted = AsyncStream<Void>.makeStream()
        let secondMount = Task { @MainActor in
            secondCallerStarted.continuation.yield()
            return await coordinator.mount()
        }
        var secondCallerIterator = secondCallerStarted.stream.makeAsyncIterator()
        _ = await secondCallerIterator.next()
        let surfaceID = UUIDv7.generate()

        // Act
        terminalPort.finish(with: .ready(surfaceID: surfaceID))
        let firstSettlement = await firstMount.value
        let secondSettlement = await secondMount.value
        let cachedSettlement = await coordinator.mount()

        // Assert
        #expect(terminalPort.admissions.count == 1)
        #expect(firstSettlement == secondSettlement)
        #expect(secondSettlement == cachedSettlement)
        #expect(
            cachedSettlement.terminal.outcomesByPaneID[descriptor.paneID]
                == .ready(surfaceID: surfaceID)
        )
        #expect(registry.isInitialRestorePending == false)
    }

    @Test("failed member visibility intent waits for aggregate settlement before repair")
    func failedMemberVisibilityIntentWaitsForAggregateSettlement() async throws {
        // Arrange
        let generation = try makePreparedContentCoordinatorGeneration()
        let failedDescriptor = makePreparedContentCoordinatorTerminalDescriptor(title: "Failed")
        let blockingDescriptor = makePreparedContentCoordinatorTerminalDescriptor(title: "Blocking")
        let cohort = WorkspacePreparedContentMountCohort(
            generation: generation,
            terminalActivationInput: TerminalActivationInput(
                entries: [failedDescriptor, blockingDescriptor]
            ),
            nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
        )
        let registry = ViewRegistry()
        registry.beginInitialRestore()
        let terminalPort = FailedAndSuspendedPreparedContentTerminalPort(
            failedPaneID: failedDescriptor.paneID,
            suspendedPaneID: blockingDescriptor.paneID
        )
        let coordinator = WorkspacePreparedContentMountCoordinator(
            cohort: cohort,
            viewRegistry: registry,
            terminalAdmissionPort: terminalPort,
            nonterminalAdmissionPort: RecordingPreparedContentNonterminalPort()
        )
        let mountTask = Task { @MainActor in
            await coordinator.mount()
        }
        await terminalPort.waitUntilFailureReturns()
        await terminalPort.waitUntilSuspendedAdmissionStarts()

        // Act
        let handledPaneIDs = coordinator.handleVisibilitySignals(for: [failedDescriptor.paneID])
        terminalPort.finishSuspendedAdmission()
        _ = await mountTask.value
        let deferredAfterSettlement = coordinator.takeDeferredSteadyStateRepairPaneIDs()

        // Assert
        #expect(handledPaneIDs == [failedDescriptor.paneID])
        #expect(deferredAfterSettlement == [failedDescriptor.paneID])
        #expect(terminalPort.admissions.filter { $0.descriptor.paneID == failedDescriptor.paneID }.count == 1)
        #expect(registry.isInitialRestorePending == false)
    }
}

@MainActor
private final class RecordingPreparedContentTerminalPort: TerminalActivationAdmissionPort {
    private(set) var admissions: [TerminalActivationAdmission] = []

    func activate(_ admission: TerminalActivationAdmission) async -> TerminalActivationAttemptResult {
        admissions.append(admission)
        return .failed(
            failure: .attachmentRejected(code: "unexpected"),
            retry: .doNotRetry
        )
    }
}

@MainActor
private final class SuspendedPreparedContentTerminalPort: TerminalActivationAdmissionPort {
    private let admissionStarted = AsyncStream<Void>.makeStream()
    private var resultContinuation: CheckedContinuation<TerminalActivationAttemptResult, Never>?
    private(set) var admissions: [TerminalActivationAdmission] = []

    func activate(_ admission: TerminalActivationAdmission) async -> TerminalActivationAttemptResult {
        admissions.append(admission)
        admissionStarted.continuation.yield()
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
    }

    func waitUntilAdmissionStarts() async {
        var iterator = admissionStarted.stream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func finish(with result: TerminalActivationAttemptResult) {
        let continuation = resultContinuation
        resultContinuation = nil
        continuation?.resume(returning: result)
    }
}

@MainActor
private final class FailedAndSuspendedPreparedContentTerminalPort: TerminalActivationAdmissionPort {
    private let failedPaneID: PaneId
    private let suspendedPaneID: PaneId
    private let failureReturned = AsyncStream<Void>.makeStream()
    private let suspendedAdmissionStarted = AsyncStream<Void>.makeStream()
    private var suspendedContinuation: CheckedContinuation<TerminalActivationAttemptResult, Never>?
    private(set) var admissions: [TerminalActivationAdmission] = []

    init(failedPaneID: PaneId, suspendedPaneID: PaneId) {
        self.failedPaneID = failedPaneID
        self.suspendedPaneID = suspendedPaneID
    }

    func activate(_ admission: TerminalActivationAdmission) async -> TerminalActivationAttemptResult {
        admissions.append(admission)
        if admission.descriptor.paneID == failedPaneID {
            failureReturned.continuation.yield()
            return .failed(
                failure: .surfaceCreationFailed(code: "prepared_failure"),
                retry: .doNotRetry
            )
        }
        precondition(admission.descriptor.paneID == suspendedPaneID)
        suspendedAdmissionStarted.continuation.yield()
        return await withCheckedContinuation { continuation in
            suspendedContinuation = continuation
        }
    }

    func waitUntilFailureReturns() async {
        var iterator = failureReturned.stream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func waitUntilSuspendedAdmissionStarts() async {
        var iterator = suspendedAdmissionStarted.stream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func finishSuspendedAdmission() {
        let continuation = suspendedContinuation
        suspendedContinuation = nil
        continuation?.resume(returning: .ready(surfaceID: UUIDv7.generate()))
    }
}

@MainActor
private final class RecordingPreparedContentNonterminalPort: NonterminalContentMountAdmissionPort {
    private(set) var descriptors: [NonterminalContentMountDescriptor] = []

    func mount(_ descriptor: NonterminalContentMountDescriptor) -> NonterminalContentMountAdmissionResult {
        descriptors.append(descriptor)
        return .mounted
    }
}

@MainActor
private func makePreparedContentCoordinatorGeneration() throws -> WorkspaceContentMountGeneration {
    WorkspaceContentMountGeneration()
}

private func makePreparedContentCoordinatorTerminalDescriptor(
    title: String = "Prepared Coordinator Terminal"
) -> TerminalActivationDescriptor {
    let launchDirectory = URL(filePath: "/tmp/prepared-content-coordinator")
    let terminalState = TerminalState(
        provider: .zmx,
        lifetime: .persistent,
        zmxSessionID: .generateUUIDv7()
    )
    let pane = Pane(
        id: UUIDv7.generate(),
        content: .terminal(terminalState),
        metadata: PaneMetadata(
            launchDirectory: launchDirectory,
            title: title
        )
    )
    return TerminalActivationDescriptor(
        pane: pane,
        visibilityPriority: .activeVisible,
        hostPlacement: .tab(tabID: UUIDv7.generate())
    )
}
