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

    init(root: URL) throws {
        self.root = root
        store = WorkspaceStore(startsObserving: false)
        repo = store.addRepo(at: root.appending(path: "repo", directoryHint: .isDirectory))
        worktree = try #require(store.repo(repo.id)?.worktrees.first)
        handler = BridgeNavigationCommandHandler(
            navigationAtom: store.bridgeNavigationAtom,
            repositoryTopologyAtom: store.repositoryTopologyAtom
        )
        receiver = .standalone(UUIDv7.generate())
        loosePlan = BridgeDocumentLocation(canonicalPath: "/tmp/notes/plan.md")
        handler.ensureRecord(for: receiver, seedingKnownWorktreeId: worktree.id)
        if let loosePlan, let record = handler.record(for: receiver) {
            store.bridgeNavigationAtom.setRecord(
                BridgeNavigationRules.admitting(
                    BridgeOpenedDocument(location: loosePlan, provenance: nil),
                    into: record
                ).record,
                for: receiver
            )
        }
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

    func addMember() throws -> Worktree {
        let otherRepo = store.addRepo(at: root.appending(path: "other", directoryHint: .isDirectory))
        let otherWorktree = try #require(store.repo(otherRepo.id)?.worktrees.first)
        guard let record = handler.record(for: receiver),
            case .added(let updated) = BridgeNavigationRules.addingMember(otherWorktree.id, to: record)
        else { return otherWorktree }
        store.bridgeNavigationAtom.setRecord(updated, for: receiver)
        return otherWorktree
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

    func activateFileDocument(_ location: BridgeDocumentLocation) async -> BridgeFileActivationArrival {
        activatedLocations.append(location)
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
