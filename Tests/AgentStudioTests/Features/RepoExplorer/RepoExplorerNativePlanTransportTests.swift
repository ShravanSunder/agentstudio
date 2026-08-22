import AppKit
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
private final class NativePlanTransportRecordingTarget:
    RepoExplorerNativeTableTransactionTarget
{
    private(set) var operations: [String] = []

    func beginUpdates() { operations.append("begin") }
    func removeRows(_ indexes: IndexSet) { operations.append("remove:\(Array(indexes))") }
    func moveRow(from oldIndex: Int, to newIndex: Int) {
        operations.append("move:\(oldIndex)->\(newIndex)")
    }
    func insertRows(_ indexes: IndexSet) { operations.append("insert:\(Array(indexes))") }
    func reloadRows(_ indexes: IndexSet) { operations.append("reload:\(Array(indexes))") }
    func noteHeightChanges(_ indexes: IndexSet) { operations.append("height:\(Array(indexes))") }
    func endUpdates() { operations.append("end") }
}

@MainActor
private final class NativePlanTransportContentChild:
    RepoExplorerMaterializationContentChild
{
    let view = NSView()
    let target = NativePlanTransportRecordingTarget()
    private(set) var candidates: [RepoExplorerMaterializationContentCandidate] = []
    private(set) var applierCallCount = 0
    var onBeforeCompletion: (() -> Void)?

    func apply(
        _ candidate: RepoExplorerMaterializationContentCandidate,
        completion: @escaping (RepoExplorerMaterializationChildDisposition) -> Void
    ) {
        candidates.append(candidate)
        applierCallCount += 1
        let applied = RepoExplorerNativeTransactionApplier.apply(
            tablePlan: candidate.tableUpdatePlan,
            to: target
        )
        onBeforeCompletion?()
        completion(applied ? .accepted : .rejected)
    }

    func prepareForRemoval(
        visibleGeneration: UInt64,
        completion: @escaping (RepoExplorerMaterializationChildDisposition) -> Void
    ) {
        completion(.accepted)
    }

    func detach() {}
}

@MainActor
@Suite("Repo Explorer native plan transport", .serialized)
struct RepoExplorerNativePlanTransportTests {
    @Test("host forwards the exact empty-to-content and content update plans to the sole applier")
    func hostForwardsExactPlansToSoleApplier() throws {
        let child = NativePlanTransportContentChild()
        let host = makeTransportHost(child: child)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 480),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.layoutIfNeeded()
        defer { window.close() }
        let firstSnapshot = nativePlanSnapshot(["A", "B"])
        let firstCandidate = try makeTransportCandidate(
            host: host,
            id: 1,
            generation: 1,
            presentation: nativePlanContent(firstSnapshot)
        )

        guard case .accepted = host.apply(firstCandidate) else {
            Issue.record("Expected empty-to-content candidate acceptance")
            return
        }
        let firstEnvelope = try #require(child.candidates.first)
        #expect(firstEnvelope.candidateID == firstCandidate.id)
        #expect(firstEnvelope.requestGeneration == firstCandidate.requestGeneration)
        #expect(firstEnvelope.visibleGeneration == firstCandidate.visibleGeneration)
        #expect(firstEnvelope.snapshot == firstSnapshot)
        #expect(host.window === window)
        #expect(host.presentedChildView === child.view)
        guard case .changed(let firstChanged) = firstCandidate.nativeUpdatePlan.kind,
            case .emptyToContent(let firstTablePlan) = firstChanged.presentation
        else {
            Issue.record("Expected exact empty-to-content plan")
            return
        }
        #expect(firstEnvelope.tableUpdatePlan == firstTablePlan)
        #expect(child.target.operations == ["begin", "insert:[0, 1]", "end"])

        let secondSnapshot = nativePlanSnapshot(["A", "B"], changedTitles: ["B"])
        let secondCandidate = try makeTransportCandidate(
            host: host,
            id: 2,
            generation: 2,
            presentation: nativePlanContent(secondSnapshot)
        )
        child.onBeforeCompletion = {
            #expect(host.acceptedBaseline?.revision == 1)
        }

        guard case .accepted = host.apply(secondCandidate) else {
            Issue.record("Expected content-to-content candidate acceptance")
            return
        }
        let secondEnvelope = try #require(child.candidates.last)
        guard case .changed(let secondChanged) = secondCandidate.nativeUpdatePlan.kind,
            case .contentToContent(let secondTablePlan) = secondChanged.presentation
        else {
            Issue.record("Expected exact content-to-content plan")
            return
        }
        #expect(secondEnvelope.snapshot == secondSnapshot)
        #expect(secondEnvelope.tableUpdatePlan == secondTablePlan)
        #expect(child.applierCallCount == 2)
        #expect(child.target.operations.suffix(3) == ["begin", "reload:[1]", "end"])
        #expect(host.acceptedBaseline?.revision == 2)
    }

    @Test("presentation and plan mismatch rejects before child entry and retains acknowledged R")
    func mismatchedPresentationAndPlanRejectBeforeChild() throws {
        let child = NativePlanTransportContentChild()
        let host = makeTransportHost(child: child)
        let plannedPresentation = nativePlanContent(nativePlanSnapshot(["A", "B"]))
        let exactCandidate = try makeTransportCandidate(
            host: host,
            id: 1,
            generation: 1,
            presentation: plannedPresentation
        )
        let mismatchedPresentation = nativePlanContent(nativePlanSnapshot(["A", "C"]))
        let mismatchedCandidate = RepoExplorerMaterializationCandidate(
            id: exactCandidate.id,
            lifetimeID: exactCandidate.lifetimeID,
            demandEpoch: exactCandidate.demandEpoch,
            requestGeneration: exactCandidate.requestGeneration,
            visibleGeneration: exactCandidate.visibleGeneration,
            expectedRevision: exactCandidate.expectedRevision,
            proposedRevision: exactCandidate.proposedRevision,
            presentation: mismatchedPresentation,
            nativeUpdatePlan: exactCandidate.nativeUpdatePlan
        )
        let baseline = host.acceptedBaseline

        #expect(host.apply(mismatchedCandidate) == .rejected(.nativePlanMismatch))
        #expect(child.candidates.isEmpty)
        #expect(child.applierCallCount == 0)
        #expect(host.acceptedBaseline == baseline)
    }

    @Test("changed rowless transition preserves its exact plan without entering content child")
    func changedRowlessPlanStaysInCandidateAndSkipsContentChild() throws {
        let child = NativePlanTransportContentChild()
        let host = makeTransportHost(child: child)
        let candidate = try makeTransportCandidate(
            host: host,
            id: 7,
            generation: 3,
            presentation: .rowless(.noTabs)
        )

        guard case .changed(let changed) = candidate.nativeUpdatePlan.kind,
            case .changedEmptyToEmpty(.noTabs) = changed.presentation
        else {
            Issue.record("Expected exact typed changed-empty plan")
            return
        }
        #expect(host.apply(candidate) == .accepted(host.acceptedBaseline!))
        #expect(child.candidates.isEmpty)
        #expect(child.applierCallCount == 0)
        #expect(host.acceptedBaseline?.revision == 1)
    }

    @Test("template instances traverse the unchanged host and sole applier")
    func templateInstancesUseOrdinaryHostAndApplierPath() throws {
        let child = NativePlanTransportContentChild()
        let host = makeTransportHost(child: child)
        let source = nativePlanContent(nativePlanSnapshot(["A", "B"]))
        let target = nativePlanContent(nativePlanSnapshot(["B", "C", "A"]))
        let sourceCandidate = try makeTransportCandidate(
            host: host,
            id: 1,
            generation: 1,
            presentation: source
        )
        guard case .accepted = host.apply(sourceCandidate) else {
            Issue.record("Expected source candidate acceptance")
            return
        }
        let templates = try RepoExplorerProjectionWorker.sealNativeUpdatePlanTemplates(
            source: source,
            target: target
        ).get()
        let forward = try templates.forward.instantiate(
            baseline: #require(host.acceptedBaseline),
            candidateID: RepoExplorerMaterializationCandidateID(rawValue: 2),
            requestGeneration: 2,
            visibleGeneration: 2
        ).get()
        #expect(host.apply(forward) == .accepted(host.acceptedBaseline!))
        let reverse = try templates.reverse.instantiate(
            baseline: #require(host.acceptedBaseline),
            candidateID: RepoExplorerMaterializationCandidateID(rawValue: 3),
            requestGeneration: 3,
            visibleGeneration: 3
        ).get()
        #expect(host.apply(reverse) == .accepted(host.acceptedBaseline!))

        #expect(child.applierCallCount == 3)
        #expect(child.candidates.map(\.candidateID.rawValue) == [1, 2, 3])
        #expect(host.acceptedBaseline?.presentation == source)
        #expect(host.acceptedBaseline?.revision == 3)
    }
}

@MainActor
private func makeTransportHost(
    child: NativePlanTransportContentChild
) -> RepoExplorerMaterializationHost {
    RepoExplorerMaterializationHost(
        lifetimeID: nativePlanLifetime(),
        initialDemandEpoch: 7,
        initialPresentation: .noRepositories,
        makeContentChild: { child },
        onFeedback: { _ in }
    )
}

@MainActor
private func makeTransportCandidate(
    host: RepoExplorerMaterializationHost,
    id: UInt64,
    generation: UInt64,
    presentation: RepoExplorerMaterializationPresentation
) throws -> RepoExplorerMaterializationCandidate {
    let baseline = try #require(host.acceptedBaseline)
    let plan = try RepoExplorerNativeUpdatePlan.validating(
        baseline: baseline,
        candidate: presentation,
        requestGeneration: generation
    ).get()
    let proposedRevision: UInt64
    switch plan.kind {
    case .equal(let equal): proposedRevision = equal.newRevision
    case .changed(let changed): proposedRevision = changed.proposedRevision
    }
    return RepoExplorerMaterializationCandidate(
        id: RepoExplorerMaterializationCandidateID(rawValue: id),
        lifetimeID: baseline.lifetimeID,
        demandEpoch: baseline.demandEpoch,
        requestGeneration: generation,
        visibleGeneration: generation,
        expectedRevision: baseline.revision,
        proposedRevision: proposedRevision,
        presentation: presentation,
        nativeUpdatePlan: plan
    )
}
