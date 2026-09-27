import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@MainActor
struct BridgePaneRevealActorFixture {
    let navigation: BridgeNavigationHandlerFixture
    let actor: BridgePaneRevealActor
    let storage: BridgeRevealRetentionTestPort
    let presentation: RecordingReceiverPresentation
    let target: BridgeRevealFileTarget
    let location: BridgeDocumentLocation
    let requester: BridgeLinkContributor

    init(
        existingDocument: Bool = false,
        eligibility: any BridgeAgentRevealEligibility = BridgeFailClosedAgentRevealEligibility(),
        interlock: any BridgeRevealPublicationInterlock = BridgeImmediateRevealPublicationInterlock()
    ) throws {
        navigation = try BridgeNavigationHandlerFixture(
            root: FileManager.default.temporaryDirectory.appending(
                path: "bridge-reveal-\(UUIDv7.generate().uuidString)", directoryHint: .isDirectory
            )
        )
        target = try BridgeRevealFileTarget(
            worktree: navigation.worktree.id, relativePath: "src/main.swift", line: 12
        )
        location = try #require(
            BridgeDocumentLocation(
                canonicalPath:
                    DarwinFSEventPathCanonicalizer.canonicalURL(
                        navigation.worktree.path.appending(path: target.relativePath)
                    ).path))
        requester = .agent(
            BridgeAgentContributorIdentity(
                provider: try BridgeAgentProviderName("codex"),
                sessionRef: try BridgeAgentSessionRef("reveal-session")
            ))
        if existingDocument, let record = navigation.handler.record(for: navigation.receiver) {
            navigation.store.bridgeNavigationAtom.setRecord(
                BridgeNavigationRules.admitting(
                    BridgeOpenedDocument(location: location, provenance: nil), into: record
                ).record,
                for: navigation.receiver
            )
        }
        presentation = RecordingReceiverPresentation()
        navigation.install(presentation)
        storage = BridgeRevealRetentionTestPort(
            record: navigation.handler.record(for: navigation.receiver) ?? .empty
        )
        actor = BridgePaneRevealActor(
            workspaceID: navigation.store.identityAtom.workspaceId,
            handler: navigation.handler, commitPort: storage,
            eligibility: eligibility, publicationInterlock: interlock
        )
        navigation.handler.paneRevealActor = actor
    }

    func admit() async throws -> UUID {
        let result = try await actor.admitAgentReveal(
            receiver: PaneId(existingUUID: navigation.receiver.paneId),
            target: target, requestedBy: requester
        )
        guard case .admitted(let operationID) = result else {
            Issue.record("Expected a validated agent reveal admission, got \(result)")
            throw BridgeLinkPortFailure.unavailable
        }
        return operationID
    }

    func awaitSettlement(_ operationID: UUID) async throws -> BridgeAgentRevealSettlement {
        try await actor.awaitAgentRevealSettlement(
            receiver: PaneId(existingUUID: navigation.receiver.paneId), operationId: operationID
        )
    }
}

/// In-memory stand-in for the native retention port. It revalidates the owner
/// and known worktree, applies a per-location generation floor, and preserves
/// one inventory ordinal while replacing the latest metadata.
actor BridgeRevealRetentionTestPort: BridgeRevealRetentionPort {
    private var record: BridgeNavigationRecord
    private var generationByLocation: [BridgeDocumentLocation: Int] = [:]
    private var sequence: UInt64 = 0
    private var holdNextCommit = false
    private var holdNextPreview = false
    private var previewEnteredTarget: BridgeRevealFileTarget?
    private var previewEnteredWaiter: CheckedContinuation<BridgeRevealFileTarget, Never>?
    private var releasePreviewWaiter: CheckedContinuation<Void, Never>?
    private var commitEnteredTarget: BridgeRevealFileTarget?
    private var commitEnteredWaiter: CheckedContinuation<BridgeRevealFileTarget, Never>?
    private var releaseCommitWaiter: CheckedContinuation<Void, Never>?

    init(record: BridgeNavigationRecord) { self.record = record }

    func holdNextRetention() { holdNextCommit = true }

    func holdNextAdmissionPreview() { holdNextPreview = true }

    func waitForAdmissionPreview() async -> BridgeRevealFileTarget {
        if let previewEnteredTarget { return previewEnteredTarget }
        return await withCheckedContinuation { previewEnteredWaiter = $0 }
    }

    func releaseAdmissionPreview() {
        releasePreviewWaiter?.resume()
        releasePreviewWaiter = nil
    }

    func waitForRetentionDispatch() async -> BridgeRevealFileTarget {
        if let commitEnteredTarget { return commitEnteredTarget }
        return await withCheckedContinuation { commitEnteredWaiter = $0 }
    }

    func releaseRetention() {
        releaseCommitWaiter?.resume()
        releaseCommitWaiter = nil
    }

    func previewAgentReveal(
        workspaceID _: UUID, receiver: BridgeReceiver,
        target: BridgeRevealFileTarget, topologySnapshot: BridgeReceiverTopologySnapshot
    ) async throws -> BridgeRevealAdmissionPreflight {
        if holdNextPreview {
            holdNextPreview = false
            previewEnteredTarget = target
            previewEnteredWaiter?.resume(returning: target)
            previewEnteredWaiter = nil
            await withCheckedContinuation { releasePreviewWaiter = $0 }
        }
        guard
            let resolved = BridgeReceiverResolution.receiver(
                forCommandPaneId: topologySnapshot.sourcePaneId,
                companionEntriesBySourceID: topologySnapshot.companionEntriesBySourceID,
                paneStatesByID: topologySnapshot.paneStatesByID
            )
        else { return .staleReceiver }
        guard resolved == receiver else { return .staleOwner }
        guard target.relativePath == "src/main.swift",
            let worktree = topologySnapshot.repositoryTopology.worktree(target.worktree),
            topologySnapshot.repositoryTopology.validatedAssociation(
                repoId: worktree.repoId, worktreeId: target.worktree
            ) != nil,
            let location = BridgeDocumentLocation(
                canonicalPath:
                    DarwinFSEventPathCanonicalizer.canonicalURL(
                        worktree.path.appending(path: target.relativePath)
                    ).path)
        else { return .unsupportedTarget }
        return .eligible(location: location)
    }

    func retainAgentReveal(
        context: BridgeLinkMutationContext, target: BridgeRevealFileTarget,
        requestedBy: BridgeLinkContributor, retainedAt: Date
    ) async throws -> BridgeRevealRetentionReceipt {
        if holdNextCommit {
            holdNextCommit = false
            commitEnteredTarget = target
            commitEnteredWaiter?.resume(returning: target)
            commitEnteredWaiter = nil
            await withCheckedContinuation { releaseCommitWaiter = $0 }
        }
        let preview = try await previewAgentReveal(
            workspaceID: context.workspaceID, receiver: context.receiver, target: target,
            topologySnapshot: context.topologySnapshot
        )
        switch preview {
        case .eligible(let location):
            guard context.generation >= (generationByLocation[location] ?? 0) else {
                return receipt(.superseded, generation: context.generation)
            }
            let item = BridgeRetainedOpenViewItem(
                target: target, requestedBy: requestedBy, retainedAt: retainedAt
            )
            if let index = record.openedDocuments.firstIndex(where: { $0.location == location }) {
                let existing = record.openedDocuments[index]
                record.openedDocuments[index] = BridgeOpenedDocument(
                    location: location, provenance: existing.provenance, retainedOpenViewItem: item
                )
            } else {
                record.openedDocuments.append(
                    BridgeOpenedDocument(location: location, provenance: nil, retainedOpenViewItem: item)
                )
            }
            generationByLocation[location] = context.generation
            return receipt(.retained(item), generation: context.generation)
        case .unsupportedTarget: return receipt(.unsupportedTarget, generation: context.generation)
        case .staleOwner: return receipt(.staleOwner, generation: context.generation)
        case .staleReceiver: return receipt(.staleReceiver, generation: context.generation)
        }
    }

    func clearRetainedOpenViewItem(
        context: BridgeLinkMutationContext, location: BridgeDocumentLocation
    ) async throws -> BridgeRevealRetentionReceipt {
        guard let index = record.openedDocuments.firstIndex(where: { $0.location == location }) else {
            return receipt(.alreadyAbsent, generation: context.generation)
        }
        let existing = record.openedDocuments[index]
        record.openedDocuments[index] = BridgeOpenedDocument(
            location: location, provenance: existing.provenance
        )
        generationByLocation[location] = context.generation
        return receipt(.cleared, generation: context.generation)
    }

    func retainedOpenViewItems(
        workspaceID _: UUID, receiver _: BridgeReceiver
    ) async throws -> [BridgeRetainedOpenViewItem] {
        record.openedDocuments.compactMap(\.retainedOpenViewItem)
    }

    func simulateUIClose(_ location: BridgeDocumentLocation, generation: Int) {
        guard generation >= (generationByLocation[location] ?? 0) else { return }
        generationByLocation[location] = generation
        record.openedDocuments.removeAll { $0.location == location }
    }

    func retainedGeneration(for location: BridgeDocumentLocation) -> Int? {
        generationByLocation[location]
    }

    private func receipt(
        _ result: BridgeRevealRetentionResult, generation: Int
    ) -> BridgeRevealRetentionReceipt {
        sequence += 1
        return BridgeRevealRetentionReceipt(
            record: record, result: result, commitSequence: sequence, generationFloor: generation
        )
    }
}

actor BridgeScriptedAgentRevealEligibility: BridgeAgentRevealEligibility {
    enum Mode { case shown, becameIneligible }
    private let mode: Mode
    private(set) var activationCount = 0

    init(mode: Mode) { self.mode = mode }

    func readOnlyState(
        receiver _: BridgeReceiver, target _: BridgeRevealFileTarget
    ) async -> BridgeAgentRevealEligibilityState { .visibleAndDraftFree }

    func showIfStillEligible(
        receiver _: BridgeReceiver, target _: BridgeRevealFileTarget
    ) async -> BridgeAgentRevealActivationResult {
        activationCount += 1
        return switch mode {
        case .shown: .shownAtRequestedLine
        case .becameIneligible: .becameIneligible
        }
    }
}

actor BridgeHeldRevealPublicationInterlock: BridgeRevealPublicationInterlock {
    private var holdNext = true
    private var observedDecision: (receiver: BridgeReceiver, location: BridgeDocumentLocation)?
    private var enteredWaiter: CheckedContinuation<(BridgeReceiver, BridgeDocumentLocation), Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func beforeApply(receiver: BridgeReceiver, location: BridgeDocumentLocation) async {
        guard holdNext else { return }
        holdNext = false
        observedDecision = (receiver, location)
        enteredWaiter?.resume(returning: (receiver, location))
        enteredWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitForDecision() async -> (receiver: BridgeReceiver, location: BridgeDocumentLocation) {
        if let observedDecision { return observedDecision }
        return await withCheckedContinuation { enteredWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

actor BridgeHeldRevealAdmissionTicketInterlock: BridgeRevealPublicationInterlock {
    private var observedTicket: (receiver: BridgeReceiver, location: BridgeDocumentLocation)?
    private var enteredWaiter: CheckedContinuation<(BridgeReceiver, BridgeDocumentLocation), Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func beforeApply(receiver _: BridgeReceiver, location _: BridgeDocumentLocation) async {}

    func afterAdmissionTicket(receiver: BridgeReceiver, location: BridgeDocumentLocation) async {
        observedTicket = (receiver, location)
        enteredWaiter?.resume(returning: (receiver, location))
        enteredWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitForCapturedTicket() async -> (receiver: BridgeReceiver, location: BridgeDocumentLocation) {
        if let observedTicket { return observedTicket }
        return await withCheckedContinuation { enteredWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
