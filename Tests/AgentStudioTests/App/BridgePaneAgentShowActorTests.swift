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
        let first = try await fixture.actor.show(
            receiver: fixture.paneID, target: fixture.target(line: 12), mode: .background)
        let second = try await fixture.actor.show(
            receiver: fixture.paneID, target: fixture.target(line: 23), mode: .background)

        #expect(first == .opened)
        #expect(second == .opened)
        let record = try #require(fixture.navigation.handler.record(for: fixture.navigation.receiver))
        #expect(record.openedDocuments.count == 2)  // Fixture begins with a loose Open file.
        #expect(record.openedDocuments.last?.location == fixture.location)
        #expect(record.openedDocuments.last?.openedLine == 23)
        #expect(record.selectedFilesDocument == nil)
        #expect(await fixture.notifications.postedCount == 2)
    }

    @Test("notification failure does not change a successful background result")
    func notificationFailure() async throws {
        let fixture = try AgentShowFixture(notificationFails: true)
        let result = try await fixture.actor.show(
            receiver: fixture.paneID, target: fixture.target(line: 5), mode: .background)

        #expect(result == .opened)
        #expect(
            fixture.navigation.handler.record(for: fixture.navigation.receiver)?
                .openedDocument(at: fixture.location)?.openedLine == 5)
        #expect(await fixture.notifications.postedCount == 1)
    }

    @Test("already approved take-over reports display and forwards the stored line")
    func takeOverDisplayed() async throws {
        let fixture = try AgentShowFixture()
        let presentation = RecordingReceiverPresentation()
        fixture.navigation.install(presentation)

        let result = try await fixture.actor.show(
            receiver: fixture.paneID, target: fixture.target(line: 42), mode: .takeOver)

        #expect(result == .shown)
        #expect(presentation.activatedLocations == [fixture.location])
        #expect(presentation.activatedLines == [42])
        #expect(await fixture.notifications.postedCount == 1)
    }

    @Test("an approved take-over kept by a draft remains opened")
    func takeOverDraftRefusal() async throws {
        let fixture = try AgentShowFixture()
        let presentation = RecordingReceiverPresentation()
        presentation.activationArrival = .refused
        fixture.navigation.install(presentation)

        let result = try await fixture.actor.show(
            receiver: fixture.paneID, target: fixture.target(line: 18), mode: .takeOver)

        #expect(result == .opened)
        #expect(
            fixture.navigation.handler.record(for: fixture.navigation.receiver)?
                .openedDocument(at: fixture.location)?.openedLine == 18)
    }

    @Test("missing file and retired pane do not change the inventory")
    func rejectedPreparation() async throws {
        let fixture = try AgentShowFixture()
        let before = fixture.navigation.handler.record(for: fixture.navigation.receiver)
        await fixture.preparation.setResult(.notFound)
        #expect(
            try await fixture.actor.show(
                receiver: fixture.paneID, target: fixture.target(line: 1), mode: .background) == .notFound)
        await fixture.preparation.setResult(.paneUnavailable)
        #expect(
            try await fixture.actor.show(
                receiver: fixture.paneID, target: fixture.target(line: 1), mode: .background) == .paneUnavailable)
        #expect(fixture.navigation.handler.record(for: fixture.navigation.receiver) == before)
        #expect(await fixture.notifications.postedCount == 0)
    }
}

@MainActor
private struct AgentShowFixture {
    let navigation: BridgeNavigationHandlerFixture
    let location: BridgeDocumentLocation
    let preparation: AgentShowPreparationStub
    let notifications: AgentShowNotificationRecorder
    let actor: BridgePaneAgentShowActor

    var paneID: PaneId { PaneId(existingUUID: navigation.receiver.paneId) }

    init(notificationFails: Bool = false) throws {
        navigation = try BridgeNavigationHandlerFixture(
            root: FileManager.default.temporaryDirectory.appending(
                path: "bridge-agent-show-\(UUIDv7.generate().uuidString)", directoryHint: .isDirectory))
        location = try #require(BridgeDocumentLocation(canonicalPath: "/tmp/bridge-agent-show.swift"))
        preparation = AgentShowPreparationStub(
            .prepared(
                .init(location: location, provenance: nil, openedLine: 1)))
        notifications = AgentShowNotificationRecorder(fails: notificationFails)
        actor = BridgePaneAgentShowActor(
            workspaceID: navigation.store.identityAtom.workspaceId,
            handler: navigation.handler, preparationPort: preparation,
            notificationPort: notifications)
    }

    func target(line: Int) throws -> BridgeRevealFileTarget {
        try BridgeRevealFileTarget(
            worktree: navigation.worktree.id, relativePath: "src/main.swift", line: line)
    }
}

private actor AgentShowPreparationStub: BridgeAgentShowPreparationPort {
    private var result: BridgeAgentShowPreparation

    init(_ result: BridgeAgentShowPreparation) { self.result = result }
    func setResult(_ result: BridgeAgentShowPreparation) { self.result = result }
    func prepareAgentShow(
        workspaceID _: UUID, receiver _: BridgeReceiver, target: BridgeRevealFileTarget,
        topologySnapshot _: BridgeReceiverTopologySnapshot
    ) async throws -> BridgeAgentShowPreparation {
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

private actor AgentShowNotificationRecorder: BridgeBackgroundOpenNotificationPosting {
    private(set) var postedCount = 0
    let fails: Bool

    init(fails: Bool) { self.fails = fails }
    func postBackgroundOpenNotification(
        receiver _: BridgeReceiver, location _: BridgeDocumentLocation
    ) async throws {
        postedCount += 1
        if fails { throw BridgeLinkPortFailure.unavailable }
    }
}
