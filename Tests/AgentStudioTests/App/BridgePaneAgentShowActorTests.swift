import AgentStudioInfrastructure
import AgentStudioTestHarness
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("Bridge agent show", .serialized)
struct BridgePaneAgentShowActorTests {
    init() { installTestCoreAtomsIfNeeded() }

    @Test("background opens without a mounted page and keeps the latest line at one sort key")
    func backgroundOpening() async throws {
        let fixture = try AgentShowFixture()
        let first = try await fixture.actor.openInBackground(
            receiver: fixture.paneID, target: fixture.target(line: 12))
        let intervening = try #require(BridgeDocumentLocation(canonicalPath: "/tmp/intervening.swift"))
        let afterFirst = try #require(fixture.navigation.handler.record(for: fixture.navigation.receiver))
        let firstEntry = try #require(afterFirst.openedDocument(at: fixture.location))
        let interveningKey = mintOpenedDocumentSortKey(
            wallMillis: 1_700_000_000_000,
            floorMillis: try #require(openedDocumentSortKeyMillis(firstEntry.sortKey))
        ).key
        fixture.navigation.store.bridgeNavigationAtom.setRecord(
            BridgeNavigationRules.openingInBackground(
                .init(provenance: nil, sortKey: interveningKey),
                at: intervening, in: afterFirst),
            for: fixture.navigation.receiver)
        let second = try await fixture.actor.openInBackground(
            receiver: fixture.paneID, target: fixture.target(line: 23))

        #expect(first == .opened)
        #expect(second == .opened)
        let record = try #require(fixture.navigation.handler.record(for: fixture.navigation.receiver))
        let initialLoose = try #require(fixture.navigation.loosePlan)
        #expect(Set(record.openedDocuments.keys) == Set([initialLoose, fixture.location, intervening]))
        #expect(record.openedDocument(at: fixture.location)?.sortKey == firstEntry.sortKey)
        #expect(record.openedDocument(at: fixture.location)?.openedLine == 23)
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

    @Test("a close during show preparation permits the show to restore its captured sort key")
    func closeDuringPreparationKeepsCapturedKey() async throws {
        let fixture = try AgentShowFixture()
        #expect(
            try await fixture.actor.openInBackground(
                receiver: fixture.paneID, target: fixture.target(line: 4)) == .opened)
        let before = try #require(
            fixture.navigation.handler.record(for: fixture.navigation.receiver)?
                .openedDocument(at: fixture.location))
        let heldPreparation = HeldStep<Void>("agent show preparation before close")
        await fixture.preparation.holdNextPreparation(heldPreparation)
        let show = Task {
            try await fixture.actor.openInBackground(
                receiver: fixture.paneID, target: fixture.target(line: 8))
        }
        try await heldPreparation.firstArrival()

        let closed = await fixture.navigation.handler.closeFile(
            fixture.location, in: fixture.navigation.receiver)
        heldPreparation.release()
        let result = try await show.value

        #expect(closed == .applied)
        #expect(result == .opened)
        let after = try #require(
            fixture.navigation.handler.record(for: fixture.navigation.receiver)?
                .openedDocument(at: fixture.location))
        #expect(after.sortKey == before.sortKey)
        #expect(after.openedLine == 8)
    }

    @Test("a sequential reopen after close receives a newer sort key")
    func sequentialReopenMovesToEnd() async throws {
        let fixture = try AgentShowFixture()
        #expect(
            try await fixture.actor.openInBackground(
                receiver: fixture.paneID, target: fixture.target(line: 4)) == .opened)
        let before = try #require(
            fixture.navigation.handler.record(for: fixture.navigation.receiver)?
                .openedDocument(at: fixture.location))
        #expect(
            await fixture.navigation.handler.closeFile(
                fixture.location, in: fixture.navigation.receiver) == .applied)

        #expect(
            try await fixture.actor.openInBackground(
                receiver: fixture.paneID, target: fixture.target(line: 8)) == .opened)
        let after = try #require(
            fixture.navigation.handler.record(for: fixture.navigation.receiver)?
                .openedDocument(at: fixture.location))
        #expect(after.sortKey.uuidString > before.sortKey.uuidString)
        #expect(after.openedLine == 8)
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
        let existingFloor =
            navigation.handler.record(for: navigation.receiver)?
            .openedDocuments.values.compactMap { openedDocumentSortKeyMillis($0.sortKey) }.max() ?? 0
        preparation = AgentShowPreparationStub(
            .prepared(
                location: location,
                entry: .init(
                    provenance: nil, openedLine: 1,
                    sortKey: mintOpenedDocumentSortKey(
                        wallMillis: 1_700_000_000_000, floorMillis: existingFloor
                    ).key)))
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
    private var nextPreparationHold: HeldStep<Void>?
    private var floorMillis: UInt64 = 0

    init(_ result: BridgeAgentShowPreparation) {
        self.result = result
        if case .prepared(_, let entry) = result {
            floorMillis = openedDocumentSortKeyMillis(entry.sortKey) ?? 0
        }
    }
    func setResult(_ result: BridgeAgentShowPreparation) { self.result = result }
    func setThrowsUnavailable(_ value: Bool) { throwsUnavailable = value }
    func holdNextPreparation(_ step: HeldStep<Void>) { nextPreparationHold = step }
    func prepareAgentShow(
        workspaceID _: UUID, receiver _: BridgeReceiver, target: BridgeAgentShowTarget,
        topologySnapshot _: BridgeReceiverTopologySnapshot,
        currentEntries: [BridgeDocumentLocation: BridgeOpenedDocumentEntry]
    ) async throws -> BridgeAgentShowPreparation {
        if let hold = nextPreparationHold {
            nextPreparationHold = nil
            try await hold.arrive(())
        }
        if throwsUnavailable { throw BridgeLinkPortFailure.unavailable }
        switch result {
        case .prepared(let location, let entry):
            let sortKey: UUID
            if let existing = currentEntries[location] {
                sortKey = existing.sortKey
            } else {
                let capturedFloor =
                    currentEntries.values.compactMap {
                        openedDocumentSortKeyMillis($0.sortKey)
                    }.max() ?? 0
                let minted = mintOpenedDocumentSortKey(
                    wallMillis: 1_700_000_000_000,
                    floorMillis: max(floorMillis, capturedFloor))
                floorMillis = minted.newFloorMillis
                sortKey = minted.key
            }
            return .prepared(
                location: location,
                entry: .init(
                    provenance: entry.provenance, openedLine: target.line,
                    sortKey: sortKey))
        case .notFound: return .notFound
        case .paneUnavailable: return .paneUnavailable
        }
    }
}
