import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import AgentStudioTestHarness
import Foundation

@testable import AgentStudio

enum PopoverReadFact: Sendable, Equatable {
    case started(PaneContextReadRequest)
    case finished
}
enum PopoverSettlementFact: Sendable, Equatable {
    case awaiting
}

enum PopoverReleaseFact: Sendable, Equatable {
    case released
}

actor PaneContextPopoverTestPorts: PaneContextDetailReading, PaneContextPersonActing, PaneLinkMembershipPort {
    let reads = FactRecorder<Int, PopoverReadFact>(
        vocabulary: .init(
            describeScope: { "read \($0)" }, describeFact: { String(describing: $0) },
            isClosing: { _, fact in fact == .finished }))
    let releases = FactRecorder<Int, PopoverReleaseFact>(
        vocabulary: .init(
            describeScope: { "release \($0)" }, describeFact: { String(describing: $0) },
            isClosing: { _, _ in true }))
    let settlements = FactRecorder<Int, PopoverSettlementFact>(
        vocabulary: .init(
            describeScope: { "settlement \($0)" }, describeFact: { String(describing: $0) },
            isClosing: { _, _ in false }
        ))
    let settlementReleases = FactRecorder<Int, PopoverReleaseFact>(
        vocabulary: .init(
            describeScope: { "settlement release \($0)" }, describeFact: { String(describing: $0) },
            isClosing: { _, _ in true }))
    private var holdSettlement = false
    private var results: [PaneContextReadResult]
    private var fallback: PaneContextDetail
    private let heldReads: Set<Int>
    private var readNumber = 0
    private(set) var requests: [PaneContextReadRequest] = []
    private(set) var answers: [AnswerAskRequest] = []
    private(set) var dismissals: [(AgentMessageId, PaneId)] = []
    private(set) var readsMarked: [(AgentMessageId, PaneId)] = []
    private(set) var actions: [MessageActionRequest] = []
    private(set) var removals: [BridgeLinkContributor] = []
    private(set) var pendingOperations: [UUID] = []
    private var answerResults: [AnswerAskResult] = []
    var answerResult: AnswerAskResult = .answered
    var dismissResult: DismissResult = .done
    var markReadResult: MarkReadResult = .done
    var actionResult: MessageActionResult = .notFound
    var memberResult: BridgeMemberRemoveResult = .alreadyAbsent
    var settlement: BridgePendingMemberRemovalSettlement = .alreadyAbsent
    var referenceResult: BridgePullRequestReferenceRemoveResult = .alreadyAbsent
    var linkFailure: BridgeLinkPortFailure?

    init(_ detail: PaneContextDetail, results: [PaneContextReadResult] = [], heldReads: Set<Int> = []) {
        fallback = detail
        self.results = results
        self.heldReads = heldReads
    }
    func setDetail(_ detail: PaneContextDetail) { fallback = detail }
    func enqueue(_ result: PaneContextReadResult) { results.append(result) }
    func configureAnswers(_ results: [AnswerAskResult]) { answerResults = results }
    func configureAnswer(_ result: AnswerAskResult) { answerResult = result }
    func configureDismiss(_ result: DismissResult) { dismissResult = result }
    func configureMarkRead(_ result: MarkReadResult) { markReadResult = result }
    func configureAction(_ result: MessageActionResult) { actionResult = result }
    func configureMember(
        _ result: BridgeMemberRemoveResult, settlement: BridgePendingMemberRemovalSettlement = .alreadyAbsent
    ) {
        memberResult = result
        self.settlement = settlement
    }
    func holdPendingSettlement() { holdSettlement = true }
    func releasePendingSettlement() { settlementReleases.append(scope: 0, fact: .released) }
    func configureReference(_ result: BridgePullRequestReferenceRemoveResult) { referenceResult = result }
    func configureLinkFailure(_ failure: BridgeLinkPortFailure?) { linkFailure = failure }
    func release(_ number: Int) { releases.append(scope: number, fact: .released) }

    func readDetail(_ request: PaneContextReadRequest) async -> PaneContextReadResult {
        let number = readNumber
        readNumber += 1
        requests.append(request)
        let result = results.isEmpty ? .detail(fallback) : results.removeFirst()
        reads.append(scope: number, fact: .started(request))
        if heldReads.contains(number) {
            do { try await releases.expectNext(in: number, .released) } catch {
                reads.append(scope: number, fact: .finished)
                return .unavailable(.databaseUnavailable)
            }
        }
        reads.append(scope: number, fact: .finished)
        return result
    }
    func answer(_ request: AnswerAskRequest) async -> AnswerAskResult {
        answers.append(request)
        return answerResults.isEmpty ? answerResult : answerResults.removeFirst()
    }
    func dismiss(messageId: AgentMessageId, paneId: PaneId) async -> DismissResult {
        dismissals.append((messageId, paneId))
        return dismissResult
    }
    func markRead(messageId: AgentMessageId, paneId: PaneId) async -> MarkReadResult {
        readsMarked.append((messageId, paneId))
        return markReadResult
    }
    func runAction(_ request: MessageActionRequest) async -> MessageActionResult {
        actions.append(request)
        return actionResult
    }
    func removeMember(receiver _: PaneId, worktree _: WorktreeId, contributor: BridgeLinkContributor) async throws
        -> BridgeMemberRemoveResult
    {
        removals.append(contributor)
        if let linkFailure { throw linkFailure }
        return memberResult
    }
    func awaitPendingMemberRemoval(receiver _: PaneId, operationId: UUID) async throws
        -> BridgePendingMemberRemovalSettlement
    {
        pendingOperations.append(operationId)
        if holdSettlement {
            settlements.append(scope: 0, fact: .awaiting)
            try await settlementReleases.expectNext(in: 0, .released)
        }
        if let linkFailure { throw linkFailure }
        return settlement
    }
    func removePullRequestReference(
        receiver _: PaneId, reference _: ForgePullRequestIdentity, contributor: BridgeLinkContributor
    ) async throws -> BridgePullRequestReferenceRemoveResult {
        removals.append(contributor)
        if let linkFailure { throw linkFailure }
        return referenceResult
    }
    func addMember(receiver _: PaneId, worktree _: WorktreeId, contributor _: BridgeLinkContributor) async throws
        -> BridgeMemberAddResult
    { .alreadyPresent }
    func addPullRequestReference(
        receiver _: PaneId, reference _: ForgePullRequestIdentity, contributor _: BridgeLinkContributor
    ) async throws -> BridgePullRequestReferenceAddResult { .alreadyPresent }
    func membershipFacts() async -> AsyncStream<BridgeLinkContributionsRemoved> {
        let stream = AsyncStream.makeStream(of: BridgeLinkContributionsRemoved.self, bufferingPolicy: .unbounded)
        stream.continuation.finish()
        return stream.stream
    }
    func finish() async throws {
        try await settlements.finish()
        try await settlementReleases.finish()
        try await reads.finish()
        try await releases.finish()
    }
}

@MainActor
func makePopoverController(
    ports: PaneContextPopoverTestPorts, location: PaneContextPopoverLocation = .pane,
    titleForPane: @escaping @MainActor (PaneId) -> String? = { _ in nil },
    revisionForPane: @escaping @MainActor (PaneId) -> PaneContextRevision? = { _ in nil }
) -> PaneContextPopoverController {
    PaneContextPopoverController(
        reader: ports, person: ports, membership: ports, contributor: .person, location: location,
        titleForPane: titleForPane, revisionForPane: revisionForPane)
}
