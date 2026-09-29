import AgentStudioInfrastructure
import AgentStudioTestHarness
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

/// A navigation handler over a real workspace store, with scripted presentation
/// ports: persistence outcome, the owner's known CWD, and recorded effects.
@MainActor
final class BridgeNavigationHandlerFixture {
    let store: WorkspaceStore
    let handler: BridgeNavigationCommandHandler
    let linkCommitPort: BridgePaneLinkCommitTestPort
    let linkMembershipActor: BridgePaneLinkMembershipActor
    private let displayedSelectionPreparationPort = TestDisplayedSelectionPreparationPort()
    let repo: Repo
    let worktree: Worktree
    let receiver: BridgeReceiver
    let loosePlan: BridgeDocumentLocation?
    let root: URL
    var persistenceSucceeds = true
    var persistCount = 0
    var refreshedFilesReceivers: [BridgeReceiver] = []
    var replacedReviewReceivers: [BridgeReceiver] = []
    var knownCWDWorktreeId: UUID?
    var resolvedReceiverForSourcePane: BridgeReceiver?

    init(root: URL, terminalReceiver: Bool = false, failInitialAppCommit: Bool = false) throws {
        self.root = root
        store = WorkspaceStore(startsObserving: false)
        repo = store.addRepo(at: root.appending(path: "repo", directoryHint: .isDirectory))
        worktree = try #require(store.repo(repo.id)?.worktrees.first)
        linkCommitPort = BridgePaneLinkCommitTestPort(
            navigationAtom: store.bridgeNavigationAtom,
            failInitialCommit: failInitialAppCommit
        )
        handler = BridgeNavigationCommandHandler(
            navigationAtom: store.bridgeNavigationAtom,
            paneAtom: store.paneAtom,
            panePresentationAtom: store.panePresentationAtom,
            repositoryTopologyAtom: store.repositoryTopologyAtom,
            writeSequencer: store.bridgeWriteSequencer,
            linkCommitPort: linkCommitPort,
            displayedSelectionPreparationPort: displayedSelectionPreparationPort,
            workspaceID: store.identityAtom.workspaceId
        )
        receiver = terminalReceiver ? .terminal(UUIDv7.generate()) : .standalone(UUIDv7.generate())
        let receiverContent: PaneContent =
            terminalReceiver
            ? .terminal(
                TerminalState(
                    provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7()
                ))
            : .bridgePanel(BridgePaneState(panelKind: .fileViewer))
        store.paneAtom.addPane(
            Pane(
                id: receiver.paneId,
                content: receiverContent,
                metadata: PaneMetadata(title: "Receiver")
            ))
        resolvedReceiverForSourcePane = receiver
        loosePlan = BridgeDocumentLocation(canonicalPath: "/tmp/notes/plan.md")
        linkMembershipActor = BridgePaneLinkMembershipActor(
            workspaceID: store.identityAtom.workspaceId,
            handler: handler,
            commitPort: linkCommitPort
        )
        handler.linkMembershipActor = linkMembershipActor
        if terminalReceiver {
            handler.ensureRecord(for: receiver, seedingKnownWorktreeId: worktree.id)
        } else {
            // Standalone fixtures start with an already committed app member.
            // Only terminal CWD membership may use the live derived overlay.
            seedCommittedMember(worktree.id, for: receiver)
        }
        if let loosePlan, let record = handler.record(for: receiver) {
            let entry = BridgeOpenedDocumentEntry(provenance: nil, sortKey: UUIDv7.generate())
            let admitted = BridgeNavigationRules.admitting(entry, at: loosePlan, into: record)
            store.bridgeNavigationAtom.setRecord(
                admitted.record, for: receiver,
                openedDocumentUpdates: [.set(loosePlan, entry)])
        }
    }

    func setCurrentCWDWorktree(_ worktree: Worktree) {
        guard var pane = store.paneAtom.pane(receiver.paneId) else { return }
        pane.metadata.updateFacets(
            PaneContextFacets(
                repoId: worktree.repoId, worktreeId: worktree.id, cwd: worktree.path
            ))
        store.paneAtom.addPane(pane)
        knownCWDWorktreeId = worktree.id
    }

    func seedCommittedMember(_ worktreeID: UUID, for receiver: BridgeReceiver) {
        store.bridgeNavigationAtom.setRecord(
            BridgeNavigationRecord(
                committedMemberLinks: [
                    BridgeMemberLink(
                        worktreeId: worktreeID,
                        contributions: [
                            BridgeLinkContribution(
                                addedBy: .app, addedAt: Date(timeIntervalSince1970: 1_700_000_000)
                            )
                        ]
                    )
                ],
                reviewSelection: .member(worktreeId: worktreeID)
            ),
            for: receiver
        )
    }

    func install(_ presentation: any BridgeReceiverPresentation) {
        handler.presentationPorts = BridgeReceiverPresentationPorts(
            mountedPresentation: { [receiver] requested in
                requested == receiver ? presentation : nil
            },
            replaceReviewSource: { [weak self] replaced, _ in
                self?.replacedReviewReceivers.append(replaced)
                return true
            },
            knownCWDWorktreeId: { [weak self] _ in self?.knownCWDWorktreeId },
            receiverForCommandPaneId: { [weak self] paneId in
                guard let self, paneId == self.receiver.paneId else { return nil }
                return self.resolvedReceiverForSourcePane
            },
            refreshFilesSource: { [weak self] refreshed in
                self?.refreshedFilesReceivers.append(refreshed)
            },
            persistNavigation: { [weak self] in
                guard let self else { return false }
                self.persistCount += 1
                return self.persistenceSucceeds
            }
        )
    }

    func selectInFiles(_ location: BridgeDocumentLocation) {
        guard let record = handler.record(for: receiver),
            case .activated(let selected) = BridgeNavigationRules.activatingFilesDocument(location, in: record)
        else { return }
        store.bridgeNavigationAtom.setRecord(selected, for: receiver)
    }

    func holdNextDisplayedSelection(_ step: HeldStep<BridgeDocumentLocation>) async {
        await displayedSelectionPreparationPort.holdNext(step)
    }

    func addMember() async throws -> Worktree {
        let otherRepo = store.addRepo(at: root.appending(path: "other", directoryHint: .isDirectory))
        let otherWorktree = try #require(store.repo(otherRepo.id)?.worktrees.first)
        _ = try await linkMembershipActor.addMember(
            receiver: PaneId(existingUUID: receiver.paneId),
            worktree: otherWorktree.id, contributor: .person
        )
        return otherWorktree
    }
}

private actor TestDisplayedSelectionPreparationPort: BridgeDisplayedSelectionPreparationPort {
    private var floorMillis: UInt64 = 1_700_000_000_000
    private var nextHold: HeldStep<BridgeDocumentLocation>?

    func holdNext(_ step: HeldStep<BridgeDocumentLocation>) {
        nextHold = step
    }

    func prepareDisplayedFilesSelection(
        receiver _: BridgeReceiver, location: BridgeDocumentLocation,
        memberWorktreeID: UUID?, memberRelativePath: String?,
        record: BridgeNavigationRecord, topology: BridgeReceiverTopologySnapshot
    ) async -> BridgeNavigationRecord? {
        if let hold = nextHold {
            nextHold = nil
            try? await hold.arrive(location)
        }
        let provenance: BridgeKnownWorktreeProvenance?
        if let memberWorktreeID {
            guard let memberRelativePath, record.containsMember(memberWorktreeID),
                let worktree = topology.knownWorktree(memberWorktreeID)
            else { return nil }
            provenance = .init(
                repoId: worktree.repoId, worktreeId: memberWorktreeID,
                relativePath: memberRelativePath)
        } else {
            provenance = nil
        }
        let entry: BridgeOpenedDocumentEntry
        if let existing = record.openedDocument(at: location) {
            entry = existing
        } else {
            let minted = mintOpenedDocumentSortKey(
                wallMillis: 1_700_000_000_000, floorMillis: floorMillis)
            floorMillis = minted.newFloorMillis
            entry = .init(provenance: provenance, sortKey: minted.key)
        }
        return BridgeNavigationRules.recordingDisplayedFilesSelection(
            entry, at: location, in: record)
    }
}

/// A receiver presentation whose editor barrier and File arrival the test
/// scripts, with an explicit held arrival to order late results.
@MainActor
final class RecordingReceiverPresentation: BridgeReceiverPresentation {
    var preparationOutcome: BridgeEditorPreparationOutcome = .prepared
    var activationArrival: BridgeFileActivationArrival = .displayed
    var holdsNextArrival = false
    private(set) var preparationCount = 0
    private(set) var activatedLocations: [BridgeDocumentLocation] = []
    private(set) var activatedLines: [Int?] = []
    private(set) var requestedSurfaces: [BridgeProductSurface] = []
    var searchOutcome: BridgeFilesSearchOutcome = .unavailable(.noLivePage)
    private(set) var searchedCriteria: [BridgeFilesSearchCriteria] = []
    private let heldActivationStep = HeldStep<BridgeFileActivationArrival>(
        "Bridge file activation arrival",
        cancellation: .holdThroughCancellation
    )

    func prepareActiveEditorsForNavigation() async -> BridgeEditorPreparationOutcome {
        preparationCount += 1
        return preparationOutcome
    }

    func activateFileDocument(_ location: BridgeDocumentLocation, line: Int?) async -> BridgeFileActivationArrival {
        activatedLocations.append(location)
        activatedLines.append(line)
        guard holdsNextArrival else { return activationArrival }
        holdsNextArrival = false
        try? await heldActivationStep.arrive(activationArrival)
        return activationArrival
    }

    func searchFilesCollection(_ criteria: BridgeFilesSearchCriteria) async -> BridgeFilesSearchOutcome {
        searchedCriteria.append(criteria)
        return searchOutcome
    }

    @discardableResult
    func requestViewerSurface(_ surface: BridgeProductSurface) -> Bool {
        requestedSurfaces.append(surface)
        return true
    }

    /// Resumes once an activation is parked on its held arrival.
    func waitForHeldActivation() async throws -> BridgeFileActivationArrival {
        try await heldActivationStep.firstArrival()
    }

    func releaseHeldArrival(_ arrival: BridgeFileActivationArrival) {
        activationArrival = arrival
        heldActivationStep.release()
    }
}
