import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("Bridge agent show", .serialized)
struct BridgePaneAgentShowActorTests {
    init() { installTestCoreAtomsIfNeeded() }

    @Test("background opens without a mounted page and keeps the latest line at one ordinal")
    func backgroundOpening() async throws {
        let fixture = try AgentShowFixture()
        let first = try await fixture.actor.openInBackground(
            receiver: fixture.paneID, target: fixture.target(line: 12))
        let intervening = try #require(BridgeDocumentLocation(canonicalPath: "/tmp/intervening.swift"))
        let afterFirst = try #require(fixture.navigation.handler.record(for: fixture.navigation.receiver))
        fixture.navigation.store.bridgeNavigationAtom.setRecord(
            BridgeNavigationRules.openingInBackground(
                .init(location: intervening, provenance: nil), in: afterFirst),
            for: fixture.navigation.receiver)
        let second = try await fixture.actor.openInBackground(
            receiver: fixture.paneID, target: fixture.target(line: 23))

        #expect(first == .opened)
        #expect(second == .opened)
        let record = try #require(fixture.navigation.handler.record(for: fixture.navigation.receiver))
        let initialLoose = try #require(fixture.navigation.loosePlan)
        #expect(record.openedDocuments.map(\.location) == [initialLoose, fixture.location, intervening])
        #expect(record.openedDocuments[1].openedLine == 23)
        #expect(record.selectedFilesDocument == nil)
        #expect(fixture.navigation.persistCount == 2)
    }

    @Test("already approved take-over reports display and forwards the stored line")
    func takeOverDisplayed() async throws {
        let fixture = try AgentShowFixture()
        let presentation = RecordingReceiverPresentation()
        fixture.navigation.install(presentation)

        let result = try await fixture.actor.takeOver(
            receiver: fixture.paneID, target: fixture.target(line: 42))

        #expect(result == .shown)
        #expect(presentation.activatedLocations == [fixture.location])
        #expect(presentation.activatedLines == [42])
        #expect(fixture.navigation.persistCount == 2)
    }

    @Test("an approved take-over kept by a draft remains opened")
    func takeOverDraftRefusal() async throws {
        let fixture = try AgentShowFixture()
        let presentation = RecordingReceiverPresentation()
        presentation.activationArrival = .refused
        fixture.navigation.install(presentation)

        let result = try await fixture.actor.takeOver(
            receiver: fixture.paneID, target: fixture.target(line: 18))

        #expect(result == .opened)
        #expect(
            fixture.navigation.handler.record(for: fixture.navigation.receiver)?
                .openedDocument(at: fixture.location)?.openedLine == 18)
    }

    @Test("scripted preparation refusals do not change the inventory")
    func rejectedPreparation() async throws {
        let fixture = try AgentShowFixture()
        let before = fixture.navigation.handler.record(for: fixture.navigation.receiver)
        await fixture.preparation.setResult(.notFound)
        #expect(
            try await fixture.actor.openInBackground(
                receiver: fixture.paneID, target: fixture.target(line: 1)) == .notFound)
        await fixture.preparation.setResult(.paneUnavailable)
        #expect(
            try await fixture.actor.openInBackground(
                receiver: fixture.paneID, target: fixture.target(line: 1)) == .paneUnavailable)
        #expect(fixture.navigation.handler.record(for: fixture.navigation.receiver) == before)
        #expect(fixture.navigation.persistCount == 0)
    }

    @Test("take-over of a missing receiver has no inventory or activation effect")
    func takeOverUnavailableReceiver() async throws {
        let fixture = try AgentShowFixture()
        let presentation = RecordingReceiverPresentation()
        fixture.navigation.install(presentation)
        let unknownPane = PaneId.generateUUIDv7()

        let result = try await fixture.actor.takeOver(
            receiver: unknownPane, target: fixture.target(line: 3))

        #expect(result == .paneUnavailable)
        #expect(presentation.activatedLocations.isEmpty)
        #expect(fixture.navigation.persistCount == 0)
    }

    @Test("preparation failure reports unavailable before an inventory effect")
    func preparationFailure() async throws {
        let fixture = try AgentShowFixture()
        let before = fixture.navigation.handler.record(for: fixture.navigation.receiver)
        await fixture.preparation.setThrowsUnavailable(true)

        do {
            _ = try await fixture.actor.openInBackground(
                receiver: fixture.paneID, target: fixture.target(line: 3))
            Issue.record("Expected a pre-dispatch unavailable failure")
        } catch let failure as BridgeLinkPortFailure {
            #expect(failure == .unavailable)
        }
        #expect(fixture.navigation.handler.record(for: fixture.navigation.receiver) == before)
        #expect(fixture.navigation.persistCount == 0)
    }

    @Test("failed inventory save reports an uncertain outcome")
    func failedSave() async throws {
        let fixture = try AgentShowFixture()
        fixture.navigation.persistenceSucceeds = false

        do {
            _ = try await fixture.actor.openInBackground(
                receiver: fixture.paneID, target: fixture.target(line: 4))
            Issue.record("Expected outcomeUnknown after the atom entry was applied")
        } catch let failure as BridgeLinkPortFailure {
            #expect(failure == .outcomeUnknown)
        }
        #expect(
            fixture.navigation.handler.record(for: fixture.navigation.receiver)?
                .openedDocument(at: fixture.location)?.openedLine == 4)
        #expect(fixture.navigation.persistCount == 1)
    }

    @Test("conversion-unavailable receiver is not reseeded by agent show")
    func conversionUnavailable() async throws {
        let fixture = try AgentShowFixture()
        fixture.navigation.store.bridgeNavigationAtom.removeRecord(for: fixture.navigation.receiver)
        fixture.navigation.store.bridgeNavigationAtom.replaceConversionUnavailablePaneIds(
            [fixture.navigation.receiver.paneId])

        let result = try await fixture.actor.openInBackground(
            receiver: fixture.paneID, target: fixture.target(line: 7))

        #expect(result == .paneUnavailable)
        #expect(fixture.navigation.handler.record(for: fixture.navigation.receiver) == nil)
        #expect(fixture.navigation.persistCount == 0)
    }

    @Test("first agent show of a terminal receiver seeds its known current worktree")
    func firstTerminalShowSeedsCurrentWorktree() async throws {
        let fixture = try AgentShowFixture(terminalReceiver: true)
        await fixture.navigation.linkMembershipActor.awaitReceiverIdle(fixture.navigation.receiver)
        fixture.navigation.setCurrentCWDWorktree(fixture.navigation.worktree)
        fixture.navigation.store.bridgeNavigationAtom.removeRecord(for: fixture.navigation.receiver)

        let result = try await fixture.actor.openInBackground(
            receiver: fixture.paneID, target: fixture.target(line: 6))

        #expect(result == .opened)
        let record = try #require(fixture.navigation.handler.record(for: fixture.navigation.receiver))
        #expect(record.derivedCurrentCWDWorktreeId == fixture.navigation.worktree.id)
        #expect(record.effectiveMemberWorktreeIds.contains(fixture.navigation.worktree.id))
        #expect(record.openedDocument(at: fixture.location)?.openedLine == 6)
    }
}

@MainActor
private struct AgentShowFixture {
    let navigation: BridgeNavigationHandlerFixture
    let location: BridgeDocumentLocation
    let preparation: AgentShowPreparationStub
    let actor: BridgePaneAgentShowActor

    var paneID: PaneId { PaneId(existingUUID: navigation.receiver.paneId) }

    init(terminalReceiver: Bool = false) throws {
        navigation = try BridgeNavigationHandlerFixture(
            root: FileManager.default.temporaryDirectory.appending(
                path: "bridge-agent-show-\(UUIDv7.generate().uuidString)", directoryHint: .isDirectory),
            terminalReceiver: terminalReceiver)
        location = try #require(BridgeDocumentLocation(canonicalPath: "/tmp/bridge-agent-show.swift"))
        preparation = AgentShowPreparationStub(
            .prepared(
                .init(location: location, provenance: nil, openedLine: 1)))
        actor = BridgePaneAgentShowActor(
            workspaceID: navigation.store.identityAtom.workspaceId,
            handler: navigation.handler, preparationPort: preparation)
        navigation.handler.presentationPorts = BridgeReceiverPresentationPorts(
            mountedPresentation: { _ in nil },
            replaceReviewSource: { _, _ in false },
            knownCWDWorktreeId: { [navigation] _ in navigation.knownCWDWorktreeId },
            receiverForCommandPaneId: { [navigation] paneID in
                paneID == navigation.receiver.paneId ? navigation.receiver : nil
            },
            refreshFilesSource: { _ in },
            persistNavigation: { [navigation] in
                navigation.persistCount += 1
                return navigation.persistenceSucceeds
            }
        )
    }

    func target(line: Int) throws -> BridgeAgentShowTarget {
        try BridgeAgentShowTarget(
            worktree: navigation.worktree.id, relativePath: "src/main.swift", line: line)
    }
}

private actor AgentShowPreparationStub: BridgeAgentShowPreparationPort {
    private var result: BridgeAgentShowPreparation
    private var throwsUnavailable = false

    init(_ result: BridgeAgentShowPreparation) { self.result = result }
    func setResult(_ result: BridgeAgentShowPreparation) { self.result = result }
    func setThrowsUnavailable(_ value: Bool) { throwsUnavailable = value }
    func prepareAgentShow(
        workspaceID _: UUID, receiver _: BridgeReceiver, target: BridgeAgentShowTarget,
        topologySnapshot _: BridgeReceiverTopologySnapshot
    ) async throws -> BridgeAgentShowPreparation {
        if throwsUnavailable { throw BridgeLinkPortFailure.unavailable }
        switch result {
        case .prepared(let document):
            return .prepared(
                .init(
                    location: document.location, provenance: document.provenance,
                    openedLine: target.line))
        case .notFound: return .notFound
        case .paneUnavailable: return .paneUnavailable
        }
    }
}
